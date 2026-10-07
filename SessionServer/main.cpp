#include "coop/server.hpp"
#include <charconv>
#include <chrono>
#include <csignal>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <thread>
#include <unordered_set>
namespace {
volatile std::sig_atomic_t running=1;
void stop(int) { running=0; }
std::string trim(std::string text) {
    const auto start=text.find_first_not_of(" \t\r\n");
    return start==std::string::npos?std::string{}:text.substr(start,text.find_last_not_of(" \t\r\n")-start+1);
}
std::uint64_t number(const std::string& value,std::uint64_t maximum) {
    std::uint64_t result=0;
    const auto parsed=std::from_chars(value.data(),value.data()+value.size(),result);
    if(parsed.ec!=std::errc{} || parsed.ptr!=value.data()+value.size() || result>maximum)
        throw std::runtime_error("Invalid numeric configuration");
    return result;
}
coop::ServerConfig config(const std::filesystem::path& path) {
    std::ifstream file(path);
    if(!file) throw std::runtime_error("Cannot read config file");
    coop::ServerConfig c;
    std::unordered_set<std::string> seen;
    std::string line;
    while(std::getline(file,line)) {
        line=trim(line); if(line.empty() || line.front()=='#') continue;
        const auto split=line.find('=');
        if(split==std::string::npos) throw std::runtime_error("Expected key=value in config");
        const auto key=trim(line.substr(0,split)), value=trim(line.substr(split+1));
        if(!seen.insert(key).second) throw std::runtime_error("Duplicate config key: "+key);
        if(key=="bind") c.bind=value;
        else if(key=="port") c.port=static_cast<std::uint16_t>(number(value,65535));
        else if(key=="access_key_file") {
            auto secret=std::filesystem::path(value);
            if(secret.is_relative()) secret=path.parent_path()/secret;
            std::ifstream input(secret); if(!input || !std::getline(input,c.accessKey)) throw std::runtime_error("Cannot read access key file");
            c.accessKey=trim(c.accessKey);
        }
        else if(key=="max_players") c.limits.maxMembers=static_cast<std::size_t>(number(value,256));
        else if(key=="max_sessions") c.limits.maxSessions=static_cast<std::size_t>(number(value,1024));
        else if(key=="max_connections") c.maxConnections=static_cast<std::size_t>(number(value,4096));
        else if(key=="max_npcs") c.limits.maxNpcs=static_cast<std::size_t>(number(value,4096));
        else if(key=="max_gameplay_requests") c.gameplayRequestCapacity=static_cast<std::size_t>(number(value,1048576));
        else if(key=="max_gameplay_members") c.gameplayMemberCapacity=static_cast<std::size_t>(number(value,1048576));
        else if(key=="npc_snapshot_rate") c.npcSnapshotRate=static_cast<unsigned>(number(value,20));
        else if(key=="npc_distant_rate") c.npcDistantRate=static_cast<unsigned>(number(value,20));
        else if(key=="snapshot_rate") c.snapshotRate=static_cast<unsigned>(number(value,60));
        else if(key=="distant_rate") c.distantRate=static_cast<unsigned>(number(value,60));
        else if(key=="near_distance") c.nearDistance=static_cast<float>(number(value,1000000));
        else if(key=="interest_distance") c.interestDistance=static_cast<float>(number(value,1000000));
        else throw std::runtime_error("Unknown config key: "+key);
    }
    return c;
}
}
int main(int argc,char** argv) {
    try {
        std::filesystem::path path="server.ini";
        std::uint64_t runFor=0;
        for(int i=1;i<argc;++i) {
            const std::string arg=argv[i];
            if(arg=="--help") {
                std::cout<<"CP2077SessionServer --config server.ini [--run-for-ms duration]\nTCP reliable control + UDP sequenced state, protocol v4\n"; return 0;
            }
            if(i+1>=argc) throw std::runtime_error("Missing argument value");
            if(arg=="--config") path=argv[++i];
            else if(arg=="--run-for-ms") runFor=number(argv[++i],86400000);
            else throw std::runtime_error("Unknown argument");
        }
        coop::SessionServer server(config(path),[](const std::string& message){ std::cout<<message<<std::endl; });
        std::signal(SIGINT,stop); std::signal(SIGTERM,stop);
        const auto start=coop::net::NowMs();
        while(running) {
            const auto now=coop::net::NowMs(); server.Tick(now);
            if(runFor && now-start>=runFor) break;
            std::this_thread::sleep_for(std::chrono::milliseconds(2));
        }
        std::cout<<"STOP accepted_states="<<server.Stats().acceptedStates<<" stale="<<server.Stats().stale<<std::endl;
        return 0;
    } catch(const std::exception& e) { std::cerr<<"SERVER_ERROR "<<e.what()<<'\n'; return 1; }
}
