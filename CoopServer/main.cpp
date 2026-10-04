#include <winsock2.h>
#include <ws2tcpip.h>

#include <iostream>
#include <string>
#include <unordered_map>
#include <chrono>
#include <cstdint>

#pragma comment(lib, "ws2_32.lib")

static constexpr uint16_t kPort = 11778;

struct Client
{
    uint32_t id = 0;
    sockaddr_in address{};
    std::chrono::steady_clock::time_point lastSeen;
};

static std::string EndpointKey(const sockaddr_in& addr)
{
    char ip[INET_ADDRSTRLEN]{};

    inet_ntop(
        AF_INET,
        &addr.sin_addr,
        ip,
        sizeof(ip)
    );

    return std::string(ip) + ":" +
        std::to_string(ntohs(addr.sin_port));
}

int main()
{
    std::cout << "=== CP2077 Coop Server ===\n";
    std::cout << "UDP port: " << kPort << "\n\n";

    WSADATA wsa{};

    if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0)
    {
        std::cerr << "WSAStartup failed\n";
        return 1;
    }

    SOCKET sock = socket(
        AF_INET,
        SOCK_DGRAM,
        IPPROTO_UDP
    );

    if (sock == INVALID_SOCKET)
    {
        std::cerr << "socket() failed: "
                  << WSAGetLastError() << "\n";

        WSACleanup();
        return 1;
    }

    sockaddr_in serverAddr{};
    serverAddr.sin_family = AF_INET;
    serverAddr.sin_addr.s_addr = INADDR_ANY;
    serverAddr.sin_port = htons(kPort);

    if (bind(
        sock,
        reinterpret_cast<sockaddr*>(&serverAddr),
        sizeof(serverAddr)
    ) == SOCKET_ERROR)
    {
        std::cerr << "bind() failed: "
                  << WSAGetLastError() << "\n";

        closesocket(sock);
        WSACleanup();

        return 1;
    }

    std::cout << "Listening on 0.0.0.0:"
              << kPort << "\n\n";

    std::unordered_map<std::string, Client> clients;

    uint32_t nextPlayerId = 1;

    while (true)
    {
        char buffer[1024]{};

        sockaddr_in sender{};
        int senderLen = sizeof(sender);

        int received = recvfrom(
            sock,
            buffer,
            sizeof(buffer) - 1,
            0,
            reinterpret_cast<sockaddr*>(&sender),
            &senderLen
        );

        if (received <= 0)
            continue;

        buffer[received] = '\0';

        const std::string key =
            EndpointKey(sender);

        auto it = clients.find(key);

        if (it == clients.end())
        {
            Client client{};
            client.id = nextPlayerId++;
            client.address = sender;
            client.lastSeen =
                std::chrono::steady_clock::now();

            clients.emplace(key, client);

            it = clients.find(key);

            std::cout
                << "[CONNECT] Player "
                << it->second.id
                << " from "
                << key
                << "\n";

            std::string welcome =
                "WELCOME," +
                std::to_string(it->second.id);

            sendto(
                sock,
                welcome.c_str(),
                static_cast<int>(welcome.size()),
                0,
                reinterpret_cast<sockaddr*>(
                    &it->second.address
                ),
                sizeof(it->second.address)
            );
        }

        Client& senderClient = it->second;

        senderClient.lastSeen =
            std::chrono::steady_clock::now();

        const std::string packet(buffer, received);

        //
        // Na razie klient wysyła:
        //
        // CP1,seq,x,y,z,w
        //
        if (packet.rfind("CP1,", 0) != 0)
            continue;

        std::cout
            << "[P"
            << senderClient.id
            << "] "
            << packet
            << "\n";

        //
        // Serwer zmienia packet na:
        //
        // RP1,playerId,seq,x,y,z,w
        //
        const std::string relay =
            "RP1," +
            std::to_string(senderClient.id) +
            "," +
            packet.substr(4);

        //
        // Wysyłamy wszystkim POZA nadawcą.
        //
        for (auto& [clientKey, client] : clients)
        {
            if (client.id == senderClient.id)
                continue;

            sendto(
                sock,
                relay.c_str(),
                static_cast<int>(relay.size()),
                0,
                reinterpret_cast<sockaddr*>(
                    &client.address
                ),
                sizeof(client.address)
            );
        }
    }

    closesocket(sock);
    WSACleanup();

    return 0;
}