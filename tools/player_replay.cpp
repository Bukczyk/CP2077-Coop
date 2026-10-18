// Local test participant using the production SessionClient. No engine access,
// protocol changes, keyboard injection, HOST impersonation or public endpoint.
#include "coop/client.hpp"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <fstream>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

namespace {
struct Sample { double t; coop::Vec3 p; double yaw; };
std::vector<Sample> ReadRoute(const std::string& path) {
    std::ifstream input(path);
    std::string line;
    if (!std::getline(input,line) || (line!="seconds,x,y,z,yaw" && line!="seconds,x,y,z,yaw\r"))
        throw std::runtime_error("Expected seconds,x,y,z,yaw CSV header");
    std::vector<Sample> route;
    while (std::getline(input,line)) {
        if (line.empty()) continue;
        if (std::count(line.begin(),line.end(),',')!=4)
            throw std::runtime_error("Expected five CSV columns");
        std::replace(line.begin(),line.end(),',',' ');
        std::istringstream fields(line);
        double t,x,y,z,yaw; std::string extra;
        if (!(fields>>t>>x>>y>>z>>yaw) || fields>>extra || !std::isfinite(t)
            || !std::isfinite(x) || !std::isfinite(y) || !std::isfinite(z) || !std::isfinite(yaw)
            || t<0 || t>120 || std::abs(x)>1000000 || std::abs(y)>1000000
            || std::abs(z)>1000000 || std::abs(yaw)>1000 || route.size()>=20000)
            throw std::runtime_error("Invalid or unbounded route sample");
        if (route.empty() ? t!=0 : t<=route.back().t)
            throw std::runtime_error("Route must start at zero and increase strictly");
        if (!route.empty()) {
            const auto& previous=route.back();
            const double dx=x-previous.p.x,dy=y-previous.p.y,dz=z-previous.p.z;
            if (std::sqrt(dx*dx+dy*dy+dz*dz)/(t-previous.t)>30.01)
                throw std::runtime_error("Route exceeds 30 m/s test bound");
        }
        route.push_back({t,{static_cast<float>(x),static_cast<float>(y),static_cast<float>(z)},yaw});
    }
    if (route.size()<2) throw std::runtime_error("Need at least two route samples");
    return route;
}
coop::Transform At(const std::vector<Sample>& route,double t) {
    const auto upper=std::upper_bound(route.begin(),route.end(),t,[](double v,const Sample& s){return v<s.t;});
    const auto& a=upper==route.begin()?route.front():*(upper-1);
    const auto& b=upper==route.end()?route.back():*upper;
    const double u=b.t==a.t?0:std::clamp((t-a.t)/(b.t-a.t),0.0,1.0);
    const auto lerp=[&](float x,float y){return static_cast<float>(x+(y-x)*u);};
    const double yaw=a.yaw+std::remainder(b.yaw-a.yaw,6.283185307179586)*u;
    return {{lerp(a.p.x,b.p.x),lerp(a.p.y,b.p.y),lerp(a.p.z,b.p.z)},
        {0,0,static_cast<float>(yaw)}};
}
}
int main(int argc,char** argv) {
    try {
        std::string path,keyPath,session="first-test"; bool validate=false;
        for (int i=1;i<argc;++i) {
            const std::string arg=argv[i];
            if (arg=="--validate-only") { validate=true; continue; }
            if (i+1>=argc) throw std::runtime_error("Missing option value");
            const std::string value=argv[++i];
            if (arg=="--route") path=value;
            else if (arg=="--key-file") keyPath=value;
            else if (arg=="--session") session=value;
            else throw std::runtime_error("Unknown option");
        }
        const auto route=ReadRoute(path);
        if (validate) { std::cout<<"ROUTE_VALID samples="<<route.size()<<" duration="<<route.back().t<<'\n'; return 0; }
        std::ifstream keyFile(keyPath); std::string key;
        if (!std::getline(keyFile,key)) throw std::runtime_error("Cannot read private key file");
        if (!key.empty() && key.back()=='\r') key.pop_back();
        if (key.size()<32 || key.size()>256) throw std::runtime_error("Invalid key length");
        coop::ClientConfig config; config.server={"127.0.0.1",11779};
        config.accessKey=key; config.sessionName=session; config.host=false;
        config.automaticSnapshots=true; config.playerSnapshotRate=60;
        coop::SessionClient client(config,[](const std::string& line){std::cout<<line<<std::endl;});
        client.SetLocal(At(route,0));
        if (!client.Connect()) throw std::runtime_error("Loopback connect failed");
        const auto admissionDeadline=coop::net::NowMs()+10000;
        while (client.Phase()!=coop::ClientPhase::Active) {
            client.Tick(coop::net::NowMs());
            if (client.Phase()==coop::ClientPhase::Failed || coop::net::NowMs()>=admissionDeadline)
                throw std::runtime_error("Replay admission failed");
            std::this_thread::sleep_for(std::chrono::milliseconds(2));
        }
        std::cout<<"REPLAY_ACTIVE session="<<client.Member().session<<" player="<<client.Member().player<<std::endl;
        const auto start=coop::net::NowMs(); double nextReport=0;
        while (true) {
            const auto now=coop::net::NowMs();
            const double elapsed=static_cast<double>(now-start)/1000.0;
            const double t=std::clamp(elapsed-8.0,0.0,route.back().t);
            const auto pose=At(route,t); client.SetLocal(pose); client.Tick(now);
            if (client.Phase()!=coop::ClientPhase::Active) throw std::runtime_error("Replay disconnected");
            if (elapsed>=nextReport) {
                std::cout<<"REPLAY_SAMPLE elapsed="<<elapsed<<" route="<<t
                    <<" x="<<pose.position.x<<" y="<<pose.position.y<<" z="<<pose.position.z<<std::endl;
                nextReport=elapsed+0.2;
            }
            if (elapsed>=8+route.back().t+5) break;
            std::this_thread::sleep_for(std::chrono::milliseconds(2));
        }
        std::cout<<"REPLAY_DONE sent="<<client.Stats().sent<<" received="<<client.Stats().received<<std::endl;
        client.Disconnect();
        return 0;
    } catch (const std::exception& error) {
        std::cerr<<"REPLAY_ERROR "<<error.what()<<'\n'; return 1;
    }
}
