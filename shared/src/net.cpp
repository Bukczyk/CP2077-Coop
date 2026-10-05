#include "coop/net.hpp"
#include <algorithm>
#include <array>
#include <chrono>
#include <stdexcept>
#include <utility>
#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#include <bcrypt.h>
#else
#include <arpa/inet.h>
#include <cerrno>
#include <fcntl.h>
#include <netinet/tcp.h>
#include <sys/select.h>
#include <sys/random.h>
#include <sys/socket.h>
#include <unistd.h>
#endif
namespace coop::net {
namespace {
#ifdef _WIN32
using Native = SOCKET;
using SockLen = int;
void initialize() {
    struct Runtime {
        Runtime() { WSADATA data{}; if (WSAStartup(MAKEWORD(2,2),&data)) throw std::runtime_error("WSAStartup failed"); }
        ~Runtime() { WSACleanup(); }
    };
    static Runtime runtime;
}
int error() { return WSAGetLastError(); }
bool pending(int e) { return e == WSAEWOULDBLOCK || e == WSAEINPROGRESS; }
#else
using Native = int;
using SockLen = socklen_t;
void initialize() {}
int error() { return errno; }
bool pending(int e) { return e == EAGAIN || e == EWOULDBLOCK || e == EINPROGRESS || e == EINTR; }
#endif
Native native(const Socket& s) { return static_cast<Native>(s.Handle()); }
bool configure(Socket& s, bool stream = true) {
#ifdef _WIN32
    u_long enabled = 1;
    if (ioctlsocket(native(s),FIONBIO,&enabled)) return false;
#else
    const int flags = fcntl(native(s),F_GETFL,0);
    if (flags < 0 || fcntl(native(s),F_SETFL,flags | O_NONBLOCK) < 0) return false;
#endif
    if (!stream) return true;
    int yes = 1;
    setsockopt(native(s),IPPROTO_TCP,TCP_NODELAY,reinterpret_cast<const char*>(&yes),sizeof(yes));
    return true;
}
bool address(const std::string& ip, std::uint16_t port, sockaddr_in& a) {
    a.sin_family = AF_INET; a.sin_port = htons(port);
    return inet_pton(AF_INET,ip.c_str(),&a.sin_addr) == 1;
}
Socket makeSocket() {
    initialize();
    const auto handle = ::socket(AF_INET,SOCK_STREAM,IPPROTO_TCP);
#ifdef _WIN32
    if (handle == INVALID_SOCKET) return {};
#else
    if (handle < 0) return {};
#endif
    Socket s{static_cast<std::intptr_t>(handle)};
    if (!configure(s)) return {};
    return s;
}
} // namespace
std::uint64_t NowMs() {
    return static_cast<std::uint64_t>(std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count());
}
Socket::~Socket() { Close(); }
Socket::Socket(Socket&& other) noexcept : handle_(std::exchange(other.handle_,kInvalidSocket)) {}
Socket& Socket::operator=(Socket&& other) noexcept {
    if (this != &other) { Close(); handle_ = std::exchange(other.handle_,kInvalidSocket); }
    return *this;
}
void Socket::Close() {
    if (!*this) return;
#ifdef _WIN32
    closesocket(native(*this));
#else
    close(native(*this));
#endif
    handle_ = kInvalidSocket;
}
ConnectionToken RandomToken() {
    ConnectionToken token{};
#ifdef _WIN32
    if (BCryptGenRandom(nullptr,token.data(),static_cast<ULONG>(token.size()),BCRYPT_USE_SYSTEM_PREFERRED_RNG) != 0)
        throw std::runtime_error("Secure random failed");
#else
    std::size_t offset = 0;
    while (offset < token.size()) {
        auto count = getrandom(token.data()+offset,token.size()-offset,0);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) throw std::runtime_error("Secure random failed");
        offset += static_cast<std::size_t>(count);
    }
#endif
    return token;
}
Socket BindUdp(const std::string& ip, std::uint16_t port) {
    initialize();
    auto raw = ::socket(AF_INET,SOCK_DGRAM,IPPROTO_UDP);
#ifdef _WIN32
    if (raw == INVALID_SOCKET) return {};
#else
    if (raw < 0) return {};
#endif
    Socket s{static_cast<std::intptr_t>(raw)}; sockaddr_in a{};
    if (!configure(s,false) || !address(ip,port,a) || bind(native(s),reinterpret_cast<sockaddr*>(&a),sizeof(a))) return {};
    return s;
}
bool SendUdp(const Socket& s, const Endpoint& target, const ConnectionToken& token, const Packet& packet) {
    auto bytes = Encode(packet); sockaddr_in a{};
    if (!s || !bytes || !address(target.ip,target.port,a)) return false;
    bytes->insert(bytes->begin(),token.begin(),token.end());
    const auto count = sendto(native(s),reinterpret_cast<const char*>(bytes->data()),static_cast<int>(bytes->size()),0,
        reinterpret_cast<sockaddr*>(&a),sizeof(a));
    return count == static_cast<int>(bytes->size());
}
std::optional<Datagram> ReceiveUdp(const Socket& s) {
    std::array<std::uint8_t,kMaxPacketSize+17> bytes{}; sockaddr_in a{}; SockLen length = sizeof(a);
    const auto count = recvfrom(native(s),reinterpret_cast<char*>(bytes.data()),static_cast<int>(bytes.size()),0,
        reinterpret_cast<sockaddr*>(&a),&length);
    if (count <= 0) return {};
    char ip[INET_ADDRSTRLEN]{}; inet_ntop(AF_INET,&a.sin_addr,ip,sizeof(ip));
    return Datagram{{ip,ntohs(a.sin_port)},{bytes.begin(),bytes.begin()+count}};
}
Socket Listen(const std::string& ip, std::uint16_t port) {
    auto s = makeSocket(); sockaddr_in a{};
    if (!s || !address(ip,port,a)) return {};
#ifndef _WIN32
    int yes = 1; setsockopt(native(s),SOL_SOCKET,SO_REUSEADDR,&yes,sizeof(yes));
#endif
    if (bind(native(s),reinterpret_cast<sockaddr*>(&a),sizeof(a)) || listen(native(s),32)) return {};
    return s;
}
Socket Accept(const Socket& listener) {
    const auto accepted = accept(native(listener),nullptr,nullptr);
#ifdef _WIN32
    if (accepted == INVALID_SOCKET) return {};
#else
    if (accepted < 0) return {};
#endif
    Socket s{static_cast<std::intptr_t>(accepted)};
    if (!configure(s)) return {};
    return s;
}
Socket Connect(const std::string& ip, std::uint16_t port, unsigned timeoutMs) {
    auto s = makeSocket(); sockaddr_in a{};
    if (!s || !address(ip,port,a)) return {};
    if (connect(native(s),reinterpret_cast<sockaddr*>(&a),sizeof(a)) == 0) return s;
    if (!pending(error())) return {};
#ifndef _WIN32
    if (native(s) >= FD_SETSIZE) return {};
#endif
    fd_set writes, errors; FD_ZERO(&writes); FD_ZERO(&errors);
    FD_SET(native(s),&writes); FD_SET(native(s),&errors);
    timeval timeout{static_cast<long>(timeoutMs / 1000),static_cast<long>((timeoutMs % 1000) * 1000)};
#ifdef _WIN32
    const int nfds = 0;
#else
    const int nfds = native(s) + 1;
#endif
    if (select(nfds,nullptr,&writes,&errors,&timeout) <= 0 || FD_ISSET(native(s),&errors)) return {};
    int result = 0; SockLen length = sizeof(result);
    if (getsockopt(native(s),SOL_SOCKET,SO_ERROR,reinterpret_cast<char*>(&result),&length) || result) return {};
    return s;
}
std::uint16_t LocalPort(const Socket& s) {
    sockaddr_in a{}; SockLen length = sizeof(a);
    if (getsockname(native(s),reinterpret_cast<sockaddr*>(&a),&length)) return 0;
    return ntohs(a.sin_port);
}
bool Channel::Queue(const Packet& packet) {
    auto encoded = Encode(packet);
    if (!encoded || !Open() || out_.size() >= 128) { Close(); return false; }
    const auto size = static_cast<std::uint32_t>(encoded->size());
    std::vector<std::uint8_t> framed{static_cast<std::uint8_t>(size >> 24),static_cast<std::uint8_t>(size >> 16),
        static_cast<std::uint8_t>(size >> 8),static_cast<std::uint8_t>(size)};
    framed.insert(framed.end(),encoded->begin(),encoded->end()); out_.push_back(std::move(framed));
    return true;
}
bool Channel::Pump(std::vector<Packet>& received) {
    if (!Open()) return false;
    while (!out_.empty()) {
        const auto& frame = out_.front();
#ifdef _WIN32
        const int flags = 0;
#else
        const int flags = MSG_NOSIGNAL;
#endif
        const auto count = send(native(socket_),reinterpret_cast<const char*>(frame.data()+sent_),static_cast<int>(frame.size()-sent_),flags);
        if (count < 0) { if (pending(error())) break; Close(); return false; }
        if (!count) { Close(); return false; }
        sent_ += static_cast<std::size_t>(count);
        if (sent_ != frame.size()) break;
        out_.pop_front(); sent_ = 0;
    }
    std::array<std::uint8_t,4096> buffer{};
    const auto count = recv(native(socket_),reinterpret_cast<char*>(buffer.data()),static_cast<int>(buffer.size()),0);
    if (count == 0) { Close(); return false; }
    if (count < 0) { if (pending(error())) return true; Close(); return false; }
    input_.insert(input_.end(),buffer.begin(),buffer.begin()+count);
    std::size_t offset = 0;
    while (input_.size()-offset >= 4) {
        std::uint32_t size = 0;
        for (unsigned i = 0; i < 4; ++i) size = (size << 8) | input_[offset+i];
        if (size < kHeaderSize || size > kMaxPacketSize) { Close(); return false; }
        if (input_.size()-offset < size+4) break;
        auto decoded = Decode(std::span<const std::uint8_t>(input_).subspan(offset+4,size));
        if (!decoded) { Close(); return false; }
        received.push_back(std::move(*decoded.packet)); offset += size+4;
    }
    input_.erase(input_.begin(),input_.begin()+static_cast<std::ptrdiff_t>(offset));
    return true;
}
} // namespace coop::net
