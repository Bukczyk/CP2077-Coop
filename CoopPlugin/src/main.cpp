#include <winsock2.h>
#include <ws2tcpip.h>
#include <Windows.h>

#include <RED4ext/RED4ext.hpp>

#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdint>
#include <deque>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <string>
#include <thread>

//
// CP2077 COOP v0.0.25
//
// Existing movement protocol stays CP1/RP1.
//
// Combat MVP deliberately reuses the same native function and packet shape:
//
//   w        = -777.0
//   forwardX = damage
//   forwardY = 9999.0
//
// This avoids adding another REDscript native surface while we are still
// stabilizing RTTI registration.
//

static constexpr float kCombatMarkerW = -777.0f;
static constexpr float kCombatMarkerForwardY = 9999.0f;
static constexpr uint64_t kCombatReceiveHoldMs = 140;

static std::atomic<float> gX{0.0f};
static std::atomic<float> gY{0.0f};
static std::atomic<float> gZ{0.0f};
static std::atomic<float> gW{1.0f};

static std::atomic<float> gForwardX{0.0f};
static std::atomic<float> gForwardY{1.0f};

static std::atomic<uint32_t> gNextSequence{0};
static std::atomic<uint32_t> gMovementSequence{0};
static std::atomic<bool> gHasState{false};

static std::atomic<bool> gHasRemote{false};
static std::atomic<uint32_t> gRemotePlayerId{0};
static std::atomic<uint32_t> gRemoteSequence{0};

static std::atomic<float> gRemoteX{0.0f};
static std::atomic<float> gRemoteY{0.0f};
static std::atomic<float> gRemoteZ{0.0f};
static std::atomic<float> gRemoteForwardX{0.0f};
static std::atomic<float> gRemoteForwardY{1.0f};

static std::atomic<uint64_t> gRemoteCombatHoldUntilMs{0};

static std::atomic<bool> gNetworkRunning{false};
static std::thread gNetworkThread;
static SOCKET gSocket = INVALID_SOCKET;

static std::string gTargetIp = "127.0.0.1";
static uint16_t gTargetPort = 11778;

struct QueuedCombatPacket
{
    uint32_t sequence = 0;
    float x = 0.0f;
    float y = 0.0f;
    float z = 0.0f;
    float damage = 0.0f;
};

static std::mutex gCombatQueueMutex;
static std::deque<QueuedCombatPacket> gCombatQueue;


// ========================================================
// TIME
// ========================================================

static uint64_t NowMs()
{
    return static_cast<uint64_t>(
        std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now().time_since_epoch()
        ).count()
    );
}


// ========================================================
// SERVER CONFIG
// ========================================================

static std::filesystem::path GetGameRoot()
{
    wchar_t exePath[MAX_PATH]{};

    GetModuleFileNameW(
        nullptr,
        exePath,
        MAX_PATH
    );

    std::filesystem::path path(exePath);

    // Cyberpunk 2077\bin\x64\Cyberpunk2077.exe
    path = path.parent_path(); // x64
    path = path.parent_path(); // bin
    path = path.parent_path(); // Cyberpunk 2077

    return path;
}


static void LoadServerConfig()
{
    const auto configPath =
        GetGameRoot()
        / L"red4ext"
        / L"plugins"
        / L"CP2077Coop"
        / L"server.ini";

    std::ifstream file(configPath);

    if (!file.is_open())
        return;

    std::string line;

    while (std::getline(file, line))
    {
        if (!line.empty() && line.back() == '\r')
            line.pop_back();

        if (line.rfind("server_ip=", 0) == 0)
        {
            const std::string value = line.substr(10);

            if (!value.empty())
                gTargetIp = value;
        }
        else if (line.rfind("server_port=", 0) == 0)
        {
            const std::string value = line.substr(12);

            try
            {
                const int port = std::stoi(value);

                if (port > 0 && port <= 65535)
                    gTargetPort = static_cast<uint16_t>(port);
            }
            catch (...)
            {
            }
        }
    }
}


// ========================================================
// CET / REDSCRIPT -> C++
// ========================================================
//
// Normal:
//   x,y,z,w,forwardX,forwardY = player state
//
// Combat hit:
//   x,y,z                  = local target NPC world position
//   w                      = -777
//   forwardX               = damage
//   forwardY               = 9999
//
// Combat is queued separately so a 20 Hz movement update cannot overwrite it
// before the network thread sends it.
//

static void PushPlayerState(
    RED4ext::IScriptable* aContext,
    RED4ext::CStackFrame* aFrame,
    void* aOut,
    int64_t a4)
{
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(aOut);
    RED4EXT_UNUSED_PARAMETER(a4);

    float x = 0.0f;
    float y = 0.0f;
    float z = 0.0f;
    float w = 1.0f;
    float forwardX = 0.0f;
    float forwardY = 1.0f;

    RED4ext::GetParameter(aFrame, &x);
    RED4ext::GetParameter(aFrame, &y);
    RED4ext::GetParameter(aFrame, &z);
    RED4ext::GetParameter(aFrame, &w);
    RED4ext::GetParameter(aFrame, &forwardX);
    RED4ext::GetParameter(aFrame, &forwardY);

    ++aFrame->code;

    const uint32_t sequence =
        gNextSequence.fetch_add(
            1,
            std::memory_order_acq_rel
        ) + 1;

    const bool isCombatHit =
        w <= -700.0f &&
        forwardY >= 9000.0f;

    if (isCombatHit)
    {
        QueuedCombatPacket packet{};

        packet.sequence = sequence;
        packet.x = x;
        packet.y = y;
        packet.z = z;
        packet.damage = forwardX;

        {
            std::lock_guard<std::mutex> lock(
                gCombatQueueMutex
            );

            // Defensive cap. At 256 queued hit events something is already wrong.
            if (gCombatQueue.size() >= 256)
                gCombatQueue.pop_front();

            gCombatQueue.push_back(packet);
        }

        return;
    }

    gX.store(x, std::memory_order_relaxed);
    gY.store(y, std::memory_order_relaxed);
    gZ.store(z, std::memory_order_relaxed);
    gW.store(w, std::memory_order_relaxed);

    gForwardX.store(forwardX, std::memory_order_relaxed);
    gForwardY.store(forwardY, std::memory_order_relaxed);

    gMovementSequence.store(
        sequence,
        std::memory_order_release
    );

    gHasState.store(
        true,
        std::memory_order_release
    );
}


// ========================================================
// REMOTE GETTERS
// ========================================================

static void HasRemotePlayer(
    RED4ext::IScriptable*,
    RED4ext::CStackFrame* aFrame,
    bool* aOut,
    int64_t)
{
    ++aFrame->code;

    *aOut =
        gHasRemote.load(
            std::memory_order_acquire
        );
}


static void GetRemoteX(
    RED4ext::IScriptable*,
    RED4ext::CStackFrame* aFrame,
    float* aOut,
    int64_t)
{
    ++aFrame->code;

    *aOut =
        gRemoteX.load(
            std::memory_order_relaxed
        );
}


static void GetRemoteY(
    RED4ext::IScriptable*,
    RED4ext::CStackFrame* aFrame,
    float* aOut,
    int64_t)
{
    ++aFrame->code;

    *aOut =
        gRemoteY.load(
            std::memory_order_relaxed
        );
}


static void GetRemoteZ(
    RED4ext::IScriptable*,
    RED4ext::CStackFrame* aFrame,
    float* aOut,
    int64_t)
{
    ++aFrame->code;

    *aOut =
        gRemoteZ.load(
            std::memory_order_relaxed
        );
}


static void GetRemoteForwardX(
    RED4ext::IScriptable*,
    RED4ext::CStackFrame* aFrame,
    float* aOut,
    int64_t)
{
    ++aFrame->code;

    *aOut =
        gRemoteForwardX.load(
            std::memory_order_relaxed
        );
}


static void GetRemoteForwardY(
    RED4ext::IScriptable*,
    RED4ext::CStackFrame* aFrame,
    float* aOut,
    int64_t)
{
    ++aFrame->code;

    *aOut =
        gRemoteForwardY.load(
            std::memory_order_relaxed
        );
}


static void GetRemoteSequence(
    RED4ext::IScriptable*,
    RED4ext::CStackFrame* aFrame,
    int32_t* aOut,
    int64_t)
{
    ++aFrame->code;

    *aOut =
        static_cast<int32_t>(
            gRemoteSequence.load(
                std::memory_order_relaxed
            )
        );
}


// ========================================================
// NETWORK PACKETS
// ========================================================

static void StoreRemotePacket(
    uint32_t playerId,
    uint32_t sequence,
    float x,
    float y,
    float z,
    float forwardX,
    float forwardY)
{
    gRemotePlayerId.store(
        playerId,
        std::memory_order_relaxed
    );

    gRemoteX.store(
        x,
        std::memory_order_relaxed
    );

    gRemoteY.store(
        y,
        std::memory_order_relaxed
    );

    gRemoteZ.store(
        z,
        std::memory_order_relaxed
    );

    gRemoteForwardX.store(
        forwardX,
        std::memory_order_relaxed
    );

    gRemoteForwardY.store(
        forwardY,
        std::memory_order_relaxed
    );

    gRemoteSequence.store(
        sequence,
        std::memory_order_release
    );

    gHasRemote.store(
        true,
        std::memory_order_release
    );
}


static void HandlePacket(
    const char* buffer,
    int length)
{
    if (length <= 0)
        return;

    uint32_t playerId = 0;
    uint32_t sequence = 0;

    float x = 0.0f;
    float y = 0.0f;
    float z = 0.0f;
    float w = 1.0f;
    float forwardX = 0.0f;
    float forwardY = 1.0f;

    // RP1,playerId,seq,x,y,z,w,forwardX,forwardY
    const int parsed =
        std::sscanf(
            buffer,
            "RP1,%u,%u,%f,%f,%f,%f,%f,%f",
            &playerId,
            &sequence,
            &x,
            &y,
            &z,
            &w,
            &forwardX,
            &forwardY
        );

    if (parsed != 8)
        return;

    const uint64_t now =
        NowMs();

    const bool isCombatHit =
        w <= -700.0f &&
        forwardY >= 9000.0f;

    if (isCombatHit)
    {
        StoreRemotePacket(
            playerId,
            sequence,
            x,
            y,
            z,
            forwardX,
            forwardY
        );

        // Keep the event visible to CET for a few frames.
        // Normal movement packets arriving immediately afterwards are ignored
        // until this small window expires.
        gRemoteCombatHoldUntilMs.store(
            now + kCombatReceiveHoldMs,
            std::memory_order_release
        );

        return;
    }

    const uint64_t holdUntil =
        gRemoteCombatHoldUntilMs.load(
            std::memory_order_acquire
        );

    if (now < holdUntil)
        return;

    StoreRemotePacket(
        playerId,
        sequence,
        x,
        y,
        z,
        forwardX,
        forwardY
    );
}


// ========================================================
// SEND HELPERS
// ========================================================

static void SendStatePacket(
    const sockaddr_in& target,
    uint32_t sequence,
    float x,
    float y,
    float z,
    float w,
    float forwardX,
    float forwardY)
{
    char buffer[256]{};

    const int packetLength =
        std::snprintf(
            buffer,
            sizeof(buffer),
            "CP1,%u,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f",
            sequence,
            x,
            y,
            z,
            w,
            forwardX,
            forwardY
        );

    if (packetLength <= 0)
        return;

    sendto(
        gSocket,
        buffer,
        packetLength,
        0,
        reinterpret_cast<const sockaddr*>(
            &target
        ),
        sizeof(target)
    );
}


// ========================================================
// NETWORK THREAD
// ========================================================

static void NetworkThread()
{
    sockaddr_in target{};

    target.sin_family = AF_INET;
    target.sin_port = htons(gTargetPort);

    if (
        inet_pton(
            AF_INET,
            gTargetIp.c_str(),
            &target.sin_addr
        ) != 1
    )
    {
        return;
    }

    u_long nonBlocking = 1;

    ioctlsocket(
        gSocket,
        FIONBIO,
        &nonBlocking
    );

    uint32_t lastMovementSequence = 0;

    while (
        gNetworkRunning.load(
            std::memory_order_acquire
        )
    )
    {
        // =================================================
        // SEND QUEUED COMBAT EVENTS FIRST
        // =================================================

        std::deque<QueuedCombatPacket> pendingCombat;

        {
            std::lock_guard<std::mutex> lock(
                gCombatQueueMutex
            );

            pendingCombat.swap(
                gCombatQueue
            );
        }

        for (const auto& event : pendingCombat)
        {
            SendStatePacket(
                target,
                event.sequence,
                event.x,
                event.y,
                event.z,
                kCombatMarkerW,
                event.damage,
                kCombatMarkerForwardY
            );
        }


        // =================================================
        // SEND LOCAL MOVEMENT STATE
        // =================================================

        if (
            gHasState.load(
                std::memory_order_acquire
            )
        )
        {
            const uint32_t sequence =
                gMovementSequence.load(
                    std::memory_order_acquire
                );

            if (
                sequence != 0 &&
                sequence != lastMovementSequence
            )
            {
                lastMovementSequence =
                    sequence;

                SendStatePacket(
                    target,
                    sequence,
                    gX.load(std::memory_order_relaxed),
                    gY.load(std::memory_order_relaxed),
                    gZ.load(std::memory_order_relaxed),
                    gW.load(std::memory_order_relaxed),
                    gForwardX.load(std::memory_order_relaxed),
                    gForwardY.load(std::memory_order_relaxed)
                );
            }
        }


        // =================================================
        // RECEIVE
        // =================================================

        while (true)
        {
            char recvBuffer[1024]{};

            sockaddr_in sender{};
            int senderLength =
                sizeof(sender);

            const int received =
                recvfrom(
                    gSocket,
                    recvBuffer,
                    sizeof(recvBuffer) - 1,
                    0,
                    reinterpret_cast<sockaddr*>(
                        &sender
                    ),
                    &senderLength
                );

            if (received == SOCKET_ERROR)
            {
                const int error =
                    WSAGetLastError();

                if (
                    error ==
                    WSAEWOULDBLOCK
                )
                {
                    break;
                }

                break;
            }

            if (received <= 0)
                break;

            recvBuffer[received] = '\0';

            HandlePacket(
                recvBuffer,
                received
            );
        }

        std::this_thread::sleep_for(
            std::chrono::milliseconds(2)
        );
    }
}


// ========================================================
// NETWORK START / STOP
// ========================================================

static bool StartNetwork()
{
    WSADATA wsaData{};

    if (
        WSAStartup(
            MAKEWORD(2, 2),
            &wsaData
        ) != 0
    )
    {
        return false;
    }

    gSocket =
        socket(
            AF_INET,
            SOCK_DGRAM,
            IPPROTO_UDP
        );

    if (gSocket == INVALID_SOCKET)
    {
        WSACleanup();
        return false;
    }

    gNetworkRunning.store(
        true,
        std::memory_order_release
    );

    gNetworkThread =
        std::thread(NetworkThread);

    return true;
}


static void StopNetwork()
{
    gNetworkRunning.store(
        false,
        std::memory_order_release
    );

    if (gNetworkThread.joinable())
        gNetworkThread.join();

    if (gSocket != INVALID_SOCKET)
    {
        closesocket(gSocket);
        gSocket = INVALID_SOCKET;
    }

    WSACleanup();
}


// ========================================================
// RTTI
// ========================================================

static void RegisterTypes()
{
}


static void PostRegisterTypes()
{
    auto rtti =
        RED4ext::CRTTISystem::Get();

    RED4ext::CBaseFunction::Flags flags{
        .isNative = true,
        .isStatic = true
    };

    {
        auto func =
            RED4ext::CGlobalFunction::Create(
                "CP2077Coop_PushPlayerState",
                "CP2077Coop_PushPlayerState",
                &PushPlayerState
            );

        func->flags = flags;

        func->AddParam("Float", "x");
        func->AddParam("Float", "y");
        func->AddParam("Float", "z");
        func->AddParam("Float", "w");
        func->AddParam("Float", "forwardX");
        func->AddParam("Float", "forwardY");

        rtti->RegisterFunction(func);
    }

    {
        auto func =
            RED4ext::CGlobalFunction::Create(
                "CP2077Coop_HasRemotePlayer",
                "CP2077Coop_HasRemotePlayer",
                &HasRemotePlayer
            );

        func->flags = flags;
        func->SetReturnType("Bool");

        rtti->RegisterFunction(func);
    }

    {
        auto func =
            RED4ext::CGlobalFunction::Create(
                "CP2077Coop_GetRemoteX",
                "CP2077Coop_GetRemoteX",
                &GetRemoteX
            );

        func->flags = flags;
        func->SetReturnType("Float");

        rtti->RegisterFunction(func);
    }

    {
        auto func =
            RED4ext::CGlobalFunction::Create(
                "CP2077Coop_GetRemoteY",
                "CP2077Coop_GetRemoteY",
                &GetRemoteY
            );

        func->flags = flags;
        func->SetReturnType("Float");

        rtti->RegisterFunction(func);
    }

    {
        auto func =
            RED4ext::CGlobalFunction::Create(
                "CP2077Coop_GetRemoteZ",
                "CP2077Coop_GetRemoteZ",
                &GetRemoteZ
            );

        func->flags = flags;
        func->SetReturnType("Float");

        rtti->RegisterFunction(func);
    }

    {
        auto func =
            RED4ext::CGlobalFunction::Create(
                "CP2077Coop_GetRemoteForwardX",
                "CP2077Coop_GetRemoteForwardX",
                &GetRemoteForwardX
            );

        func->flags = flags;
        func->SetReturnType("Float");

        rtti->RegisterFunction(func);
    }

    {
        auto func =
            RED4ext::CGlobalFunction::Create(
                "CP2077Coop_GetRemoteForwardY",
                "CP2077Coop_GetRemoteForwardY",
                &GetRemoteForwardY
            );

        func->flags = flags;
        func->SetReturnType("Float");

        rtti->RegisterFunction(func);
    }

    {
        auto func =
            RED4ext::CGlobalFunction::Create(
                "CP2077Coop_GetRemoteSequence",
                "CP2077Coop_GetRemoteSequence",
                &GetRemoteSequence
            );

        func->flags = flags;
        func->SetReturnType("Int32");

        rtti->RegisterFunction(func);
    }
}


// ========================================================
// RED4EXT ENTRY
// ========================================================

RED4EXT_C_EXPORT bool RED4EXT_CALL Main(
    const RED4ext::v1::PluginHandle aHandle,
    const RED4ext::v1::EMainReason aReason,
    const RED4ext::v1::Sdk* aSdk)
{
    RED4EXT_UNUSED_PARAMETER(aHandle);
    RED4EXT_UNUSED_PARAMETER(aSdk);

    switch (aReason)
    {
    case RED4ext::v1::EMainReason::Load:
    {
        LoadServerConfig();

        auto rtti =
            RED4ext::CRTTISystem::Get();

        rtti->AddRegisterCallback(
            RegisterTypes
        );

        rtti->AddPostRegisterCallback(
            PostRegisterTypes
        );

        StartNetwork();

        break;
    }

    case RED4ext::v1::EMainReason::Unload:
    {
        StopNetwork();
        break;
    }
    }

    return true;
}


RED4EXT_C_EXPORT void RED4EXT_CALL Query(
    RED4ext::v1::PluginInfo* aInfo)
{
    aInfo->name =
        L"CP2077 Coop";

    aInfo->author =
        L"Jakub";

    aInfo->version =
        RED4EXT_V1_SEMVER(0, 0, 25);

    aInfo->runtime =
        RED4EXT_V1_RUNTIME_VERSION_LATEST;

    aInfo->sdk =
        RED4EXT_V1_SDK_VERSION_CURRENT;
}


RED4EXT_C_EXPORT uint32_t RED4EXT_CALL Supports()
{
    return RED4EXT_API_VERSION_1;
}
