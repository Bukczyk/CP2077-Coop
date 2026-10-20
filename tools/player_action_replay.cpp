// LOCAL 0x8005 fixture using SessionClient. No engine or keyboard access.
// A synthetic JOINER, never a claimed physical player or production contract.
#include "coop/client.hpp"
#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <thread>

namespace {
using S=coop::PresentationStance;
using W=coop::PresentationWeapon;
using A=coop::PresentationAim;
struct Phase { const char* name; double until; coop::PresentationValues values; bool gap=false; };
constexpr coop::PresentationValues Holstered{S::Standing,W::Holstered,0,A::NotAiming};
constexpr coop::PresentationValues Ready{S::Standing,W::DrawnSupported,coop::kPresentationIglaPimp,A::NotAiming};
constexpr coop::PresentationValues Crouch{S::Crouching,W::DrawnSupported,coop::kPresentationIglaPimp,A::NotAiming};
constexpr coop::PresentationValues CrouchAim{S::Crouching,W::DrawnSupported,coop::kPresentationIglaPimp,A::Aiming};
constexpr coop::PresentationValues Aim{S::Standing,W::DrawnSupported,coop::kPresentationIglaPimp,A::Aiming};
constexpr std::array<Phase,15> Phases{{
    {"holstered",6,Holstered},{"igla_ready",12,Ready},
    {"crouch_ready",18,Crouch},{"crouch_aim",24,CrouchAim},
    {"crouch_walk_aim",30,CrouchAim},{"sprint_ready",36,Ready},
    {"stop_aim",42,Aim},{"action_gap_movement_continues",48,Aim,true},
    {"same_state_repair",54,Aim},{"holster",60,Holstered},
    {"unsupported_overture",66,{S::Standing,W::DrawnUnsupported,0x1c477e6908ULL,A::NotAiming}},
    {"unavailable",72,{}},{"disconnected",78,{}},{"reconnected_crouch_aim",86,CrouchAim},
    {"crouch_walk_unarmed",92,{S::Crouching,W::Holstered,0,A::NotAiming}}
}};
constexpr auto DirectionPhases=[] {
    auto phases=Phases;
    phases[2]={"armed_walk_forward",18,Ready};
    phases[3]={"armed_walk_right_aim",24,Aim};
    phases[4]={"armed_walk_backward_aim",30,Aim};
    phases[5]={"armed_walk_left",36,Ready};
    return phases;
}();
constexpr auto UnarmedDirectionPhases=[] {
    auto phases=DirectionPhases;
    for(std::size_t i=0;i<6;++i)phases[i].values=Holstered;
    phases[2].name="unarmed_walk_forward";phases[3].name="unarmed_walk_right";
    phases[4].name="unarmed_walk_backward";phases[5].name="unarmed_walk_left";
    return phases;
}();
constexpr auto GaitPhases=[] {
    auto phases=Phases;
    phases[1]={"gait_walk_forward",12,Ready};
    phases[2]={"gait_walk_stop",18,Ready};
    phases[3]={"gait_sprint_then_stop",24,Ready};
    phases[4]={"gait_walk_again",30,Ready};
    phases[5]={"gait_second_stop",36,Ready};
    return phases;
}();
constexpr auto CrouchDirectionPhases=[] {
    auto phases=Phases;
    const coop::PresentationValues crouchHolstered{S::Crouching,W::Holstered,0,A::NotAiming};
    phases[0]={"crouch_unarmed_idle",6,crouchHolstered};
    phases[1]={"crouch_armed_forward",12,Crouch};
    phases[2]={"crouch_armed_stop",18,Crouch};
    phases[3]={"crouch_aim_backward",24,CrouchAim};
    phases[4]={"crouch_unarmed_stop",30,crouchHolstered};
    phases[5]={"crouch_unarmed_out_and_back",36,crouchHolstered};
    return phases;
}();
coop::Transform CrouchPose(coop::Transform origin,double t) {
    double distance=0;
    if(t>=6&&t<12)distance=(t-6)*.5;
    else if(t>=12&&t<18)distance=3;
    else if(t>=18&&t<24)distance=3-(t-18)*.5;
    else if(t>=30&&t<36)distance=(t<33?t-30:36-t)*.5;
    const auto yaw=static_cast<double>(origin.rotation.z);
    origin.position.x-=static_cast<float>(std::sin(yaw)*distance);
    origin.position.y+=static_cast<float>(std::cos(yaw)*distance);
    return origin;
}
coop::Transform GaitPose(coop::Transform origin,double t) {
    double distance=0,heading=0;
    if(t>=6&&t<12)distance=t-6;
    else if(t>=12&&t<18)distance=6;
    else if(t>=18&&t<24){distance=std::max(0.0,6-(t-18)*6);heading=3.141592653589793;}
    else if(t>=24&&t<30)distance=t-24;
    else if(t>=30&&t<36)distance=6;
    else return origin;
    const auto yaw=static_cast<double>(origin.rotation.z);
    origin.position.x-=static_cast<float>(std::sin(yaw)*distance);
    origin.position.y+=static_cast<float>(std::cos(yaw)*distance);
    origin.rotation.z+=static_cast<float>(heading);
    return origin;
}
coop::Transform ParseOrigin(std::string value) {
    if(std::count(value.begin(),value.end(),',')!=3)throw std::runtime_error("Origin needs x,y,z,yaw");
    std::replace(value.begin(),value.end(),',',' ');
    std::istringstream fields(value); double x,y,z,yaw;std::string extra;
    if(!(fields>>x>>y>>z>>yaw)||fields>>extra||!std::isfinite(x)||!std::isfinite(y)
        ||!std::isfinite(z)||!std::isfinite(yaw)||std::abs(x)>1000000||std::abs(y)>1000000
        ||std::abs(z)>1000000||std::abs(yaw)>1000)throw std::runtime_error("Invalid bounded origin");
    return {{static_cast<float>(x),static_cast<float>(y),static_cast<float>(z)},
            {0,0,static_cast<float>(yaw)}};
}
double Triangle(double t,double speed) {
    const double distance=std::fmod(std::max(0.0,t)*speed,6.0);
    return distance<=3.0?distance:6.0-distance;
}
void Admit(coop::SessionClient& client,coop::Transform origin) {
    client.SetLocal(origin);
    if(!client.Connect())throw std::runtime_error("Loopback connection failed");
    const auto deadline=coop::net::NowMs()+10000;
    while(client.Phase()!=coop::ClientPhase::Active) {
        client.Tick(coop::net::NowMs());
        if(client.Phase()==coop::ClientPhase::Failed||coop::net::NowMs()>=deadline)
            throw std::runtime_error("Loopback admission failed");
        std::this_thread::sleep_for(std::chrono::milliseconds(2));
    }
    std::cout<<"ACTION_FIXTURE_ACTIVE session="<<client.Member().session<<" player="<<client.Member().player<<std::endl;
}
}
int main(int argc,char** argv) {
    try {
        std::string keyPath,session,originText="-818,821.5,24.393097,-3.141592653589793";
        bool validate=false,directions=false,gaits=false,crouches=false,unarmed=false;
        for(int i=1;i<argc;++i) {
            const std::string arg=argv[i];
            if(arg=="--validate-only"){validate=true;continue;}
            if(arg=="--directions"){directions=true;continue;}
            if(arg=="--gaits"){gaits=true;continue;}
            if(arg=="--crouch-directions"){crouches=true;continue;}
            if(arg=="--unarmed-directions"){unarmed=true;continue;}
            if(i+1>=argc)throw std::runtime_error("Missing option value");
            const std::string value=argv[++i];
            if(arg=="--key-file")keyPath=value;
            else if(arg=="--session")session=value;
            else if(arg=="--origin")originText=value;
            else throw std::runtime_error("Unknown option");
        }
        if(session.empty()||session.size()>64||session.find_first_of("\r\n\0",0,3)!=std::string::npos)
            throw std::runtime_error("Invalid session name");
        if(static_cast<int>(directions)+static_cast<int>(gaits)+static_cast<int>(crouches)+static_cast<int>(unarmed)>1)
            throw std::runtime_error("Choose one fixture trajectory");
        const auto origin=ParseOrigin(originText);
        const auto& phases=unarmed?UnarmedDirectionPhases:crouches?CrouchDirectionPhases:gaits?GaitPhases:directions?DirectionPhases:Phases;
        for(const auto& p:phases)if(!coop::ValidatePresentation(p.values))throw std::runtime_error("Invalid fixture state");
        if(validate) {
            std::cout<<"ACTION_FIXTURE_VALID loopback_only=true duration="<<phases.back().until<<" protocol="<<coop::kProtocolVersion<<'\n';
            double start=0;for(const auto& p:phases){std::cout<<"PHASE start="<<start<<" until="<<p.until<<" name="<<p.name<<" tick_gap="<<p.gap<<'\n';start=p.until;}
            if(gaits)for(const auto t:{6.0,12.0,18.0,18.5,19.0,24.0,30.0,35.0}) {
                const auto p=GaitPose(origin,t);
                std::cout<<"GAIT_POINT t="<<t<<" x="<<p.position.x<<" y="<<p.position.y<<" yaw="<<p.rotation.z<<'\n';
            }
            if(crouches)for(const auto t:{6.0,12.0,18.0,21.0,24.0,30.0,35.0}) {
                const auto p=CrouchPose(origin,t);
                std::cout<<"CROUCH_POINT t="<<t<<" x="<<p.position.x<<" y="<<p.position.y<<" yaw="<<p.rotation.z<<'\n';
            }
            return 0;
        }
        std::ifstream keyFile(keyPath);std::string key;
        if(!std::getline(keyFile,key))throw std::runtime_error("Cannot read private key file");
        if(!key.empty()&&key.back()=='\r')key.pop_back();
        if(key.size()<32||key.size()>256)throw std::runtime_error("Invalid key length");
        coop::ClientConfig config;config.server={"127.0.0.1",11779};config.accessKey=key;
        config.sessionName=session;config.host=false;config.automaticSnapshots=false;
        coop::SessionClient client(config,[](const std::string& line){std::cout<<line<<std::endl;});
        Admit(client,origin);
        std::uint32_t sequence=0;std::uint64_t nextSnapshot=0;
        const auto started=coop::net::NowMs();std::size_t prior=phases.size();double nextReport=0;
        while(true) {
            auto now=coop::net::NowMs();double t=static_cast<double>(now-started)/1000.0;
            if(t>=phases.back().until)break;
            const auto it=std::find_if(phases.begin(),phases.end(),[&](const auto& p){return t<p.until;});
            const auto index=static_cast<std::size_t>(it-phases.begin());
            const auto& phase=*it;
            if(index!=prior) {
                if(index==12)client.Disconnect();
                if(index==13){Admit(client,origin);sequence=0;nextSnapshot=0;now=coop::net::NowMs();t=static_cast<double>(now-started)/1000.0;}
                std::cout<<"ACTION_FIXTURE_PHASE elapsed="<<t<<" monotonic_ms="<<now<<" player="<<client.Member().player<<" name="<<phase.name<<std::endl;
                prior=index;
            }
            if(index!=12) {
                auto pose=origin;
                if(crouches&&index<=5)pose=CrouchPose(origin,t);
                else if(gaits&&index>=1&&index<=5)pose=GaitPose(origin,t);
                else if((directions||unarmed)&&index>=2&&index<=5) {
                    double x=0,y=0;
                    if(index==2)y=t-12;
                    if(index==3){x=t-18;y=6;}
                    if(index==4){x=6;y=6-(t-24);}
                    if(index==5)x=6-(t-30);
                    const auto yaw=static_cast<double>(origin.rotation.z);
                    pose.position.x+=static_cast<float>(std::cos(yaw)*x-std::sin(yaw)*y);
                    pose.position.y+=static_cast<float>(std::sin(yaw)*x+std::cos(yaw)*y);
                } else {
                    if(index==4)pose.position.x+=static_cast<float>(Triangle(t-24,1));
                    if(index==5)pose.position.x+=static_cast<float>(Triangle(t-30,6));
                }
                if(index==7)pose.position.x+=static_cast<float>(Triangle(t-42,1));
                if(index==14)pose.position.x+=static_cast<float>(Triangle(t-86,1));
                if(!phase.gap) {
                    if(!client.SetLocalPresentation(phase.values))throw std::runtime_error("Fixture state rejected");
                    client.Tick(now);
                }
                // During the six-second gap, omit Tick/repairs but keep sending
                // ordinary owned movement through the existing public client API.
                // Gap is below the session's 10s timeout. No forged packet/token.
                if(now>=nextSnapshot) {
                    if(++sequence==0)++sequence;
                    if(!client.SendLocalSnapshot(pose,sequence,now))throw std::runtime_error("Fixture movement rejected");
                    nextSnapshot=now+17;
                }
                if(client.Phase()!=coop::ClientPhase::Active)throw std::runtime_error("Fixture disconnected");
                if(t>=nextReport) {
                    std::cout<<"ACTION_FIXTURE_SAMPLE elapsed="<<t<<" player="<<client.Member().player<<" x="<<pose.position.x<<" y="<<pose.position.y<<" z="<<pose.position.z<<" presentation_tick="<<!phase.gap<<std::endl;
                    nextReport=t+0.2;
                }
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(2));
        }
        client.Disconnect();std::cout<<"ACTION_FIXTURE_DONE duration="<<phases.back().until<<" synthetic_only=true"<<std::endl;
        return 0;
    }catch(const std::exception& e){std::cerr<<"ACTION_FIXTURE_ERROR "<<e.what()<<'\n';return 1;}
}
