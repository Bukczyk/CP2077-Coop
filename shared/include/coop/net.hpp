#pragma once
#include "coop/protocol.hpp"
#include <deque>
#include <string>

namespace coop::net {
constexpr std::intptr_t kInvalidSocket = -1;
class Socket {
public:
    Socket() = default;
    explicit Socket(std::intptr_t handle) : handle_(handle) {}
    ~Socket();
    Socket(const Socket&) = delete;
    Socket& operator=(const Socket&) = delete;
    Socket(Socket&& other) noexcept;
    Socket& operator=(Socket&& other) noexcept;
    explicit operator bool() const { return handle_ != kInvalidSocket; }
    std::intptr_t Handle() const { return handle_; }
    void Close();
private:
    std::intptr_t handle_ = kInvalidSocket;
};
struct Endpoint { std::string ip; std::uint16_t port = 0; bool operator==(const Endpoint&) const = default; };
struct Datagram { Endpoint sender; std::vector<std::uint8_t> data; };
ConnectionToken RandomToken();
Socket BindUdp(const std::string& ip, std::uint16_t port);
bool SendUdp(const Socket& socket, const Endpoint& target, const ConnectionToken& token, const Packet& packet);
std::optional<Datagram> ReceiveUdp(const Socket& socket);
Socket Listen(const std::string& ipv4, std::uint16_t port);
Socket Accept(const Socket& listener);
Socket Connect(const std::string& ipv4, std::uint16_t port, unsigned timeoutMs = 2000);
std::uint16_t LocalPort(const Socket& socket);
std::uint64_t NowMs();
// TCP length-prefixed CPS1 packets. Bounded buffering; overload disconnects.
class Channel {
public:
    static constexpr std::size_t kMaxQueuedFrames = 128;
    explicit Channel(Socket socket = {}) : socket_(std::move(socket)) {}
    bool Queue(const Packet& packet);
    bool Pump(std::vector<Packet>& received);
    void Close() { socket_.Close(); }
    bool Open() const { return static_cast<bool>(socket_); }
    bool Pending() const { return !out_.empty(); }
    std::size_t PendingCount() const { return out_.size(); }
    bool CanQueue(std::size_t additional=1) const { return Open() && additional<=kMaxQueuedFrames-out_.size(); }
private:
    Socket socket_;
    std::vector<std::uint8_t> input_;
    std::deque<std::vector<std::uint8_t>> out_;
    std::size_t sent_ = 0;
};
} // namespace coop::net
