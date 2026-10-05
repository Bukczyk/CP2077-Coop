#include <Windows.h>
#include <RED4ext/RED4ext.hpp>
#include <RED4ext/Scripting/Natives/entEntityID.hpp>
#include "coop/game_bridge.hpp"
#include <charconv>
#include <filesystem>
#include <fstream>
#include <memory>
#include <unordered_set>
namespace {
namespace g=coop::game;
std::unique_ptr<g::SessionBridge> bridge;
g::EntityRegistry registry;
g::Frame frame;
std::size_t selected=0, selectedNpc=0;
std::uint32_t npcCapacity=128;
float bubbleRadius=100;
bool experimentalStaticNpcProjection=false;
std::unordered_set<coop::EntityId> projections;
std::ofstream logfile;
void Log(const std::string& s) { logfile<<s<<std::endl; }
std::string Trim(std::string s) {
    auto a=s.find_first_not_of(" \t\r\n");
    return a==std::string::npos?"":s.substr(a,s.find_last_not_of(" \t\r\n")-a+1);
}
unsigned Number(const std::string& value) {
    unsigned n=0; auto result=std::from_chars(value.data(),value.data()+value.size(),n);
    if(result.ec!=std::errc{} || result.ptr!=value.data()+value.size()) throw std::runtime_error("Invalid config number");
    return n;
}
coop::ClientConfig Config(const std::filesystem::path& directory) {
    std::ifstream file(directory/"session.ini"); if(!file) throw std::runtime_error("Missing session.ini");
    coop::ClientConfig c; std::unordered_set<std::string> keys; std::string line;
    while(std::getline(file,line)) {
        line=Trim(line); if(line.empty() || line[0]=='#') continue;
        auto split=line.find('='); if(split==std::string::npos) throw std::runtime_error("Expected key=value");
        auto key=Trim(line.substr(0,split)),value=Trim(line.substr(split+1));
        if(!keys.insert(key).second) throw std::runtime_error("Duplicate config key");
        if(key=="role") { if(value!="HOST" && value!="JOINER") throw std::runtime_error("Invalid role"); c.host=value=="HOST"; }
        else if(key=="server_ip") c.server.ip=value;
        else if(key=="server_port") { auto port=Number(value); if(!port || port>65535) throw std::runtime_error("Invalid port"); c.server.port=static_cast<std::uint16_t>(port); }
        else if(key=="session") c.sessionName=value;
        else if(key=="access_key_file") {
            std::ifstream secret(directory/std::filesystem::path(value));
            if(!std::getline(secret,c.accessKey)) throw std::runtime_error("Missing access key"); c.accessKey=Trim(c.accessKey);
        }
        else if(key=="player_snapshot_rate") c.playerSnapshotRate=Number(value);
        else if(key=="vehicle_snapshot_rate") c.vehicleSnapshotRate=Number(value);
        else if(key=="npc_snapshot_rate") c.npcSnapshotRate=Number(value);
        else if(key=="experimental_static_npc_projection") {
            if(value!="0" && value!="1") throw std::runtime_error("Invalid experimental_static_npc_projection flag");
            experimentalStaticNpcProjection=value=="1";
        }
        else if(key=="max_npcs") c.maxNpcs=Number(value);
        else if(key=="bubble_radius") { auto radius=Number(value); if(!radius || radius>500) throw std::runtime_error("Invalid bubble radius"); bubbleRadius=static_cast<float>(radius); }
        else if(key=="interpolation_ms") c.interpolation.delayMs=Number(value);
        else if(key=="extrapolation_ms") c.interpolation.extrapolationMs=Number(value);
        else if(key=="snap_distance") c.interpolation.snapDistance=static_cast<float>(Number(value));
        else if(key=="max_extrapolation_speed") c.interpolation.maxExtrapolationSpeed=static_cast<float>(Number(value));
        else throw std::runtime_error("Unknown config key: "+key);
    }
    if(!keys.contains("role") || !keys.contains("access_key_file")) throw std::runtime_error("Missing role/key configuration");
    npcCapacity=static_cast<std::uint32_t>(c.maxNpcs);
    return c;
}
const g::RenderPlayer* Current() { return selected<frame.players.size()?&frame.players[selected]:nullptr; }
const g::RenderNpc* CurrentNpc() { return selectedNpc<frame.npcs.size()?&frame.npcs[selectedNpc]:nullptr; }
#define NATIVE(name,type) void name(RED4ext::IScriptable*,RED4ext::CStackFrame* f,type* out,int64_t)
NATIVE(SetActive,void) {
    bool active=false; RED4ext::GetParameter(f,&active); ++f->code;
    if(bridge) bridge->SetActive(active);
    if(!active) { frame={}; registry.Reset({},0); projections.clear(); }
}
NATIVE(PushLocal,void) {
    coop::Transform t; RED4ext::GetParameter(f,&t.position.x); RED4ext::GetParameter(f,&t.position.y);
    RED4ext::GetParameter(f,&t.position.z); RED4ext::GetParameter(f,&t.rotation.z); ++f->code;
    if(bridge) bridge->SetLocal(t);
}
NATIVE(BeginFrame,std::uint32_t) {
    ++f->code; auto next=bridge?bridge->ReadFrame(coop::net::NowMs()):g::Frame{};
    if(next.member.session!=frame.member.session || next.member.epoch!=frame.member.epoch || next.generation!=frame.generation) {
        registry.Reset({next.member.session,next.member.epoch},next.host); projections.clear();
    }
    frame=std::move(next); selected=0; selectedNpc=0;
    std::unordered_set<coop::EntityId> live;
    if(frame.member.player) {
        registry.Accept({frame.member.session,frame.member.epoch},{frame.member.player,g::Kind::Player,frame.member.player,frame.host,0},frame.host);
        live.insert(frame.member.player);
    }
    for(const auto& p:frame.players) {
        registry.Accept({frame.member.session,frame.member.epoch},{p.entity,g::Kind::Player,p.player,frame.host,0},frame.host);
        live.insert(p.entity);
    }
    for(const auto& npc:frame.npcs) {
        auto id=npc.descriptor.entity;
        if(registry.Accept({frame.member.session,frame.member.epoch},{id,g::Kind::NPC,frame.host,frame.host,0},frame.host)) {
            if(npc.hostLocal) registry.Bind(id,npc.hostLocal);
            live.insert(id);
        }
    }
    for(auto id:projections) if(!live.contains(id)) registry.Remove(id);
    projections=std::move(live); *out=static_cast<std::uint32_t>(frame.players.size());
}
NATIVE(Select,bool) { std::uint32_t index=0; RED4ext::GetParameter(f,&index); ++f->code; selected=index; *out=Current()!=nullptr; }
NATIVE(Bind,bool) {
    std::uint64_t id=0; RED4ext::ent::EntityID local{};
    RED4ext::GetParameter(f,&id); RED4ext::GetParameter(f,&local); ++f->code;
    *out=registry.Bind(id,local.hash);
}
NATIVE(Phase,std::uint32_t) { ++f->code; *out=static_cast<std::uint32_t>(frame.phase); }
NATIVE(Generation,std::uint64_t) { ++f->code; *out=frame.generation; }
NATIVE(Host,std::uint32_t) { ++f->code; *out=frame.host; }
NATIVE(Self,std::uint32_t) { ++f->code; *out=frame.member.player; }
NATIVE(SelfEntity,std::uint64_t) { ++f->code; *out=frame.member.player; }
NATIVE(Session,std::uint64_t) { ++f->code; *out=frame.member.session; }
NATIVE(Entity,std::uint64_t) { ++f->code; *out=Current()?Current()->entity:0; }
NATIVE(Player,std::uint32_t) { ++f->code; *out=Current()?Current()->player:0; }
NATIVE(X,float) { ++f->code; *out=Current()?Current()->transform.position.x:0; }
NATIVE(Y,float) { ++f->code; *out=Current()?Current()->transform.position.y:0; }
NATIVE(Z,float) { ++f->code; *out=Current()?Current()->transform.position.z:0; }
NATIVE(Yaw,float) { ++f->code; *out=Current()?Current()->transform.rotation.z:0; }
NATIVE(NpcOffer,bool) {
    RED4ext::ent::EntityID local{}; RED4ext::TweakDBID record{}; coop::Transform t;
    RED4ext::GetParameter(f,&local); RED4ext::GetParameter(f,&record);
    RED4ext::GetParameter(f,&t.position.x); RED4ext::GetParameter(f,&t.position.y);
    RED4ext::GetParameter(f,&t.position.z); RED4ext::GetParameter(f,&t.rotation.z); ++f->code;
    *out=bridge && bridge->OfferNpc(local.hash,record.value & 0xffffffffffULL,t);
}
NATIVE(NpcForget,void) {
    RED4ext::ent::EntityID local{}; RED4ext::GetParameter(f,&local); ++f->code;
    if(bridge) bridge->ForgetNpc(local.hash);
}
NATIVE(NpcSelect,bool) { std::uint32_t index=0; RED4ext::GetParameter(f,&index); ++f->code; selectedNpc=index; *out=CurrentNpc()!=nullptr; }
NATIVE(Unbind,bool) { std::uint64_t entity=0; RED4ext::GetParameter(f,&entity); ++f->code; *out=registry.Unbind(entity); }
NATIVE(Resolve,std::uint64_t) { RED4ext::ent::EntityID local{}; RED4ext::GetParameter(f,&local); ++f->code; *out=registry.FromLocal(local.hash).value_or(0); }
NATIVE(Epoch,std::uint32_t) { ++f->code; *out=frame.member.epoch; }
NATIVE(NpcCapacity,std::uint32_t) { ++f->code; *out=npcCapacity; }
NATIVE(BubbleRadius,float) { ++f->code; *out=bubbleRadius; }
NATIVE(ExperimentalStaticNpcProjection,bool) { ++f->code; *out=experimentalStaticNpcProjection; }
NATIVE(NpcCount,std::uint32_t) { ++f->code; *out=static_cast<std::uint32_t>(frame.npcs.size()); }
NATIVE(NpcEntity,std::uint64_t) { ++f->code; *out=CurrentNpc()?CurrentNpc()->descriptor.entity:0; }
NATIVE(NpcRecord,RED4ext::TweakDBID) { ++f->code; *out=RED4ext::TweakDBID{CurrentNpc()?CurrentNpc()->descriptor.record:std::uint64_t{0}}; }
NATIVE(NpcX,float) { ++f->code; *out=CurrentNpc()?CurrentNpc()->transform.position.x:0; }
NATIVE(NpcY,float) { ++f->code; *out=CurrentNpc()?CurrentNpc()->transform.position.y:0; }
NATIVE(NpcZ,float) { ++f->code; *out=CurrentNpc()?CurrentNpc()->transform.position.z:0; }
NATIVE(NpcYaw,float) { ++f->code; *out=CurrentNpc()?CurrentNpc()->transform.rotation.z:0; }
void RegisterTypes() {}
void RegisterFunctions() {
    auto rtti=RED4ext::CRTTISystem::Get();
    { auto fn=RED4ext::CGlobalFunction::Create("CP2077Session_NpcOffer","CP2077Session_NpcOffer",&NpcOffer);
      fn->flags={.isNative=true,.isStatic=true};
      fn->SetReturnType("Bool");
      fn->AddParam("EntityID","local");
      fn->AddParam("TweakDBID","record");
      fn->AddParam("Float","x");
      fn->AddParam("Float","y");
      fn->AddParam("Float","z");
      fn->AddParam("Float","yawRadians");
      rtti->RegisterFunction(fn); }
    { auto fn=RED4ext::CGlobalFunction::Create("CP2077Session_NpcForget","CP2077Session_NpcForget",&NpcForget);
      fn->flags={.isNative=true,.isStatic=true};
      fn->AddParam("EntityID","local");
      rtti->RegisterFunction(fn); }
    { auto fn=RED4ext::CGlobalFunction::Create("CP2077Session_NpcSelect","CP2077Session_NpcSelect",&NpcSelect);
      fn->flags={.isNative=true,.isStatic=true};
      fn->SetReturnType("Bool");
      fn->AddParam("Uint32","index");
      rtti->RegisterFunction(fn); }
    { auto fn=RED4ext::CGlobalFunction::Create("CP2077Session_Unbind","CP2077Session_Unbind",&Unbind);
      fn->flags={.isNative=true,.isStatic=true};
      fn->SetReturnType("Bool");
      fn->AddParam("Uint64","entity");
      rtti->RegisterFunction(fn); }
    { auto fn=RED4ext::CGlobalFunction::Create("CP2077Session_Resolve","CP2077Session_Resolve",&Resolve);
      fn->flags={.isNative=true,.isStatic=true};
      fn->SetReturnType("Uint64");
      fn->AddParam("EntityID","local");
      rtti->RegisterFunction(fn); }
    { auto fn=RED4ext::CGlobalFunction::Create("CP2077Session_Epoch","CP2077Session_Epoch",&Epoch);
      fn->flags={.isNative=true,.isStatic=true};
      fn->SetReturnType("Uint32");
      rtti->RegisterFunction(fn); }
    { auto fn=RED4ext::CGlobalFunction::Create("CP2077Session_NpcCapacity","CP2077Session_NpcCapacity",&NpcCapacity);
      fn->flags={.isNative=true,.isStatic=true};
      fn->SetReturnType("Uint32");
      rtti->RegisterFunction(fn); }
    { auto fn=RED4ext::CGlobalFunction::Create("CP2077Session_BubbleRadius","CP2077Session_BubbleRadius",&BubbleRadius);
      fn->flags={.isNative=true,.isStatic=true};
      fn->SetReturnType("Float");
      rtti->RegisterFunction(fn); }
    { auto fn=RED4ext::CGlobalFunction::Create("CP2077Session_ExperimentalStaticNpcProjection","CP2077Session_ExperimentalStaticNpcProjection",&ExperimentalStaticNpcProjection);
      fn->flags={.isNative=true,.isStatic=true};
      fn->SetReturnType("Bool");
      rtti->RegisterFunction(fn); }
    { auto fn=RED4ext::CGlobalFunction::Create("CP2077Session_NpcCount","CP2077Session_NpcCount",&NpcCount);
      fn->flags={.isNative=true,.isStatic=true};
      fn->SetReturnType("Uint32");
      rtti->RegisterFunction(fn); }
    { auto fn=RED4ext::CGlobalFunction::Create("CP2077Session_NpcEntity","CP2077Session_NpcEntity",&NpcEntity);
      fn->flags={.isNative=true,.isStatic=true};
      fn->SetReturnType("Uint64");
      rtti->RegisterFunction(fn); }
    { auto fn=RED4ext::CGlobalFunction::Create("CP2077Session_NpcRecord","CP2077Session_NpcRecord",&NpcRecord);
      fn->flags={.isNative=true,.isStatic=true};
      fn->SetReturnType("TweakDBID");
      rtti->RegisterFunction(fn); }
    { auto fn=RED4ext::CGlobalFunction::Create("CP2077Session_NpcX","CP2077Session_NpcX",&NpcX);
      fn->flags={.isNative=true,.isStatic=true};
      fn->SetReturnType("Float");
      rtti->RegisterFunction(fn); }
    { auto fn=RED4ext::CGlobalFunction::Create("CP2077Session_NpcY","CP2077Session_NpcY",&NpcY);
      fn->flags={.isNative=true,.isStatic=true};
      fn->SetReturnType("Float");
      rtti->RegisterFunction(fn); }
    { auto fn=RED4ext::CGlobalFunction::Create("CP2077Session_NpcZ","CP2077Session_NpcZ",&NpcZ);
      fn->flags={.isNative=true,.isStatic=true};
      fn->SetReturnType("Float");
      rtti->RegisterFunction(fn); }
    { auto fn=RED4ext::CGlobalFunction::Create("CP2077Session_NpcYaw","CP2077Session_NpcYaw",&NpcYaw);
      fn->flags={.isNative=true,.isStatic=true};
      fn->SetReturnType("Float");
      rtti->RegisterFunction(fn); }

    { auto fn=RED4ext::CGlobalFunction::Create("CP2077Session_SelfEntity","CP2077Session_SelfEntity",&SelfEntity);
      fn->flags={.isNative=true,.isStatic=true}; fn->SetReturnType("Uint64"); rtti->RegisterFunction(fn); }
    { auto fn=RED4ext::CGlobalFunction::Create("CP2077Session_SetActive","CP2077Session_SetActive",&SetActive);
        fn->flags={.isNative=true,.isStatic=true};
        fn->AddParam("Bool","active");
        rtti->RegisterFunction(fn); }
    { auto fn=RED4ext::CGlobalFunction::Create("CP2077Session_PushLocal","CP2077Session_PushLocal",&PushLocal);
        fn->flags={.isNative=true,.isStatic=true};
        fn->AddParam("Float","x");
        fn->AddParam("Float","y");
        fn->AddParam("Float","z");
        fn->AddParam("Float","yawRadians");
        rtti->RegisterFunction(fn); }
    { auto fn=RED4ext::CGlobalFunction::Create("CP2077Session_BeginFrame","CP2077Session_BeginFrame",&BeginFrame);
        fn->flags={.isNative=true,.isStatic=true};
        fn->SetReturnType("Uint32");
        rtti->RegisterFunction(fn); }
    { auto fn=RED4ext::CGlobalFunction::Create("CP2077Session_Select","CP2077Session_Select",&Select);
        fn->flags={.isNative=true,.isStatic=true};
        fn->SetReturnType("Bool");
        fn->AddParam("Uint32","index");
        rtti->RegisterFunction(fn); }
    { auto fn=RED4ext::CGlobalFunction::Create("CP2077Session_Bind","CP2077Session_Bind",&Bind);
        fn->flags={.isNative=true,.isStatic=true};
        fn->SetReturnType("Bool");
        fn->AddParam("Uint64","entity");
        fn->AddParam("EntityID","local");
        rtti->RegisterFunction(fn); }
    { auto fn=RED4ext::CGlobalFunction::Create("CP2077Session_Phase","CP2077Session_Phase",&Phase);
        fn->flags={.isNative=true,.isStatic=true};
        fn->SetReturnType("Uint32");
        rtti->RegisterFunction(fn); }
    { auto fn=RED4ext::CGlobalFunction::Create("CP2077Session_Generation","CP2077Session_Generation",&Generation);
        fn->flags={.isNative=true,.isStatic=true};
        fn->SetReturnType("Uint64");
        rtti->RegisterFunction(fn); }
    { auto fn=RED4ext::CGlobalFunction::Create("CP2077Session_Host","CP2077Session_Host",&Host);
        fn->flags={.isNative=true,.isStatic=true};
        fn->SetReturnType("Uint32");
        rtti->RegisterFunction(fn); }
    { auto fn=RED4ext::CGlobalFunction::Create("CP2077Session_Self","CP2077Session_Self",&Self);
        fn->flags={.isNative=true,.isStatic=true};
        fn->SetReturnType("Uint32");
        rtti->RegisterFunction(fn); }
    { auto fn=RED4ext::CGlobalFunction::Create("CP2077Session_Session","CP2077Session_Session",&Session);
        fn->flags={.isNative=true,.isStatic=true};
        fn->SetReturnType("Uint64");
        rtti->RegisterFunction(fn); }
    { auto fn=RED4ext::CGlobalFunction::Create("CP2077Session_Entity","CP2077Session_Entity",&Entity);
        fn->flags={.isNative=true,.isStatic=true};
        fn->SetReturnType("Uint64");
        rtti->RegisterFunction(fn); }
    { auto fn=RED4ext::CGlobalFunction::Create("CP2077Session_Player","CP2077Session_Player",&Player);
        fn->flags={.isNative=true,.isStatic=true};
        fn->SetReturnType("Uint32");
        rtti->RegisterFunction(fn); }
    { auto fn=RED4ext::CGlobalFunction::Create("CP2077Session_X","CP2077Session_X",&X);
        fn->flags={.isNative=true,.isStatic=true};
        fn->SetReturnType("Float");
        rtti->RegisterFunction(fn); }
    { auto fn=RED4ext::CGlobalFunction::Create("CP2077Session_Y","CP2077Session_Y",&Y);
        fn->flags={.isNative=true,.isStatic=true};
        fn->SetReturnType("Float");
        rtti->RegisterFunction(fn); }
    { auto fn=RED4ext::CGlobalFunction::Create("CP2077Session_Z","CP2077Session_Z",&Z);
        fn->flags={.isNative=true,.isStatic=true};
        fn->SetReturnType("Float");
        rtti->RegisterFunction(fn); }
    { auto fn=RED4ext::CGlobalFunction::Create("CP2077Session_Yaw","CP2077Session_Yaw",&Yaw);
        fn->flags={.isNative=true,.isStatic=true};
        fn->SetReturnType("Float");
        rtti->RegisterFunction(fn); }
}
}
RED4EXT_C_EXPORT bool RED4EXT_CALL Main(RED4ext::v1::PluginHandle handle,RED4ext::v1::EMainReason reason,const RED4ext::v1::Sdk*) {
    if(reason==RED4ext::v1::EMainReason::Load) {
        wchar_t path[32768]{};
        if(!GetModuleFileNameW(handle,path,32768)) return false;
        auto directory=std::filesystem::path(path).parent_path();
        logfile.open(directory/"session.log",std::ios::app);
        try { bridge=std::make_unique<g::SessionBridge>(Config(directory),Log); }
        catch(const std::exception& error) { Log(std::string("CONFIG_ERROR ")+error.what()); return false; }
        auto rtti=RED4ext::CRTTISystem::Get();
        rtti->AddRegisterCallback(RegisterTypes); rtti->AddPostRegisterCallback(RegisterFunctions);
    } else if(reason==RED4ext::v1::EMainReason::Unload) { bridge.reset(); logfile.close(); }
    return true;
}
RED4EXT_C_EXPORT void RED4EXT_CALL Query(RED4ext::v1::PluginInfo* info) {
    info->name=L"CP2077 Coop Session Foundation"; info->author=L"Jakub";
    info->version=RED4EXT_V1_SEMVER(0,1,0);
    info->runtime=RED4EXT_V1_RUNTIME_VERSION_LATEST; info->sdk=RED4EXT_V1_SDK_VERSION_CURRENT;
}
RED4EXT_C_EXPORT uint32_t RED4EXT_CALL Supports() { return RED4EXT_API_VERSION_1; }
