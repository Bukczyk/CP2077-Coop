#ifdef _WIN32
#include <winsock2.h>
#else
#include <sys/socket.h>
#endif
#include "check.hpp"
#include "coop/net.hpp"
#include <thread>
#include <chrono>
using namespace coop;
using namespace std::chrono_literals;
template<class F> void Until(F done) {
    const auto deadline=net::NowMs()+2000;
    while (!done()) { CHECK(net::NowMs()<deadline); std::this_thread::sleep_for(1ms); }
}
void RawSend(const net::Socket& socket, std::span<const std::uint8_t> bytes) {
#ifdef _WIN32
    const auto handle=static_cast<SOCKET>(socket.Handle());
#else
    const auto handle=static_cast<int>(socket.Handle());
#endif
    CHECK(send(handle,reinterpret_cast<const char*>(bytes.data()),static_cast<int>(bytes.size()),0)==static_cast<int>(bytes.size()));
}
void Tests() {
    auto listener=net::Listen("127.0.0.1",0); CHECK(listener);
    auto raw=net::Connect("127.0.0.1",net::LocalPort(listener)); CHECK(raw);
    net::Socket accepted;
    Until([&] { accepted=net::Accept(listener); return static_cast<bool>(accepted); });
    net::Channel server{std::move(accepted)};
    Packet hello{{},Hello{std::string(64,'a')}};
    auto bytes=Encode(hello).value();
    std::vector<std::uint8_t> frame{0,0,0,static_cast<std::uint8_t>(bytes.size())};
    frame.insert(frame.end(),bytes.begin(),bytes.end());
    std::vector<Packet> received;
    // Actual TCP socket, frame split across writes, including the length prefix.
    for (std::size_t i=0;i<frame.size()-1;++i) {
        RawSend(raw,std::span<const std::uint8_t>(frame).subspan(i,1));
        CHECK(server.Pump(received)); CHECK(received.empty());
    }
    RawSend(raw,std::span<const std::uint8_t>(frame).last(1));
    Until([&] { CHECK(server.Pump(received)); return !received.empty(); });
    CHECK(received.size()==1 && received[0]==hello);
    std::vector<std::uint8_t> combined=frame; combined.insert(combined.end(),frame.begin(),frame.end());
    RawSend(raw,combined); received.clear();
    Until([&] { CHECK(server.Pump(received)); return received.size()==2; });
    CHECK(received[1]==hello);
    RawSend(raw,std::array<std::uint8_t,4>{0x7f,0xff,0xff,0xff});
    Until([&] { return !server.Pump(received); }); CHECK(!server.Open());
    auto socket=net::Connect("127.0.0.1",net::LocalPort(listener)); CHECK(socket);
    net::Channel bounded{std::move(socket)};
    for(int i=0;i<128;++i) CHECK(bounded.Queue(hello));
    CHECK(!bounded.Queue(hello)); CHECK(!bounded.Open());
    auto udp=net::BindUdp("127.0.0.1",0), other=net::BindUdp("127.0.0.1",0);
    CHECK(udp && other);
    auto token=net::RandomToken(); CHECK(token!=ConnectionToken{});
    CHECK(net::SendUdp(udp,{"127.0.0.1",net::LocalPort(other)},token,hello));
    std::optional<net::Datagram> datagram;
    Until([&] { datagram=net::ReceiveUdp(other); return datagram.has_value(); });
    CHECK(datagram->sender.port==net::LocalPort(udp));
    CHECK(std::equal(token.begin(),token.end(),datagram->data.begin()));
    CHECK(Decode(std::span<const std::uint8_t>(datagram->data).subspan(16)).packet.value()==hello);
    CHECK(!net::Connect("invalid",1234));
}
int main() { return Run(Tests); }
