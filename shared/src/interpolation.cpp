#include "coop/interpolation.hpp"
#include <algorithm>
#include <cmath>
#include <stdexcept>
namespace coop {
namespace {
float distance(Vec3 a, Vec3 b) {
    return std::sqrt((a.x-b.x)*(a.x-b.x)+(a.y-b.y)*(a.y-b.y)+(a.z-b.z)*(a.z-b.z));
}
float angle(float a, float b, float t) { return a + std::remainder(b-a,6.283185307f)*t; }
Transform mix(const Transform& a, const Transform& b, float t) {
    return {{a.position.x+(b.position.x-a.position.x)*t,a.position.y+(b.position.y-a.position.y)*t,
        a.position.z+(b.position.z-a.position.z)*t},
        {angle(a.rotation.x,b.rotation.x,t),angle(a.rotation.y,b.rotation.y,t),angle(a.rotation.z,b.rotation.z,t)}};
}
}
SnapshotBuffer::SnapshotBuffer(InterpolationConfig config) : config_(config) {
    if (!std::isfinite(config.delayMs) || config.delayMs < 0 || config.delayMs > 2000
        || !std::isfinite(config.extrapolationMs) || config.extrapolationMs < 0 || config.extrapolationMs > 1000
        || !std::isfinite(config.snapDistance) || config.snapDistance <= 0
        || !std::isfinite(config.maxExtrapolationSpeed) || config.maxExtrapolationSpeed <= 0)
        throw std::invalid_argument("Invalid interpolation config");
}
bool SnapshotBuffer::Push(std::uint32_t seq, double time, Transform value, std::uint64_t sourceTime) {
    if (!std::isfinite(time) || !Validate(Packet{{1,1,1,seq,0},PlayerState{1,value}})) return false;
    if (!samples_.empty()) {
        if (!IsNewer(seq,samples_.back().sequence) || time < samples_.back().timeMs
            || (sourceTime && sourceTime <= samples_.back().sourceTimeMs)) return false;
        if (distance(value.position,samples_.back().value.position) > config_.snapDistance) samples_.clear();
        else if (time == samples_.back().timeMs) { samples_.back() = {seq,time,sourceTime,value}; return true; }
    }
    samples_.push_back({seq,time,sourceTime,value});
    if (samples_.size() > 128) samples_.pop_front();
    return true;
}
std::optional<Transform> SnapshotBuffer::Sample(double now) const {
    if (samples_.empty() || !std::isfinite(now)) return {};
    const double target = now-config_.delayMs;
    if (target <= samples_.front().timeMs) return samples_.front().value;
    for (std::size_t i = 1; i < samples_.size(); ++i) {
        const auto& a=samples_[i-1]; const auto& b=samples_[i];
        if (target <= b.timeMs) return mix(a.value,b.value,static_cast<float>((target-a.timeMs)/(b.timeMs-a.timeMs)));
    }
    const auto& last = samples_.back();
    if (samples_.size() < 2) return last.value;
    const auto& previous = samples_[samples_.size()-2];
    const double interval = last.timeMs-previous.timeMs;
    if (interval < 1) return last.value;
    const float span = static_cast<float>(std::clamp(target-last.timeMs,0.0,config_.extrapolationMs)/interval);
    const float travel = distance(last.value.position,previous.value.position);
    const float speed = travel / static_cast<float>(interval/1000.0);
    const float factor = speed > config_.maxExtrapolationSpeed ? config_.maxExtrapolationSpeed/speed : 1;
    return mix(previous.value,last.value,1+span*factor);
}
} // namespace coop
