#pragma once
#include "coop/protocol.hpp"
#include <deque>
namespace coop {
struct InterpolationConfig {
    double delayMs = 100, extrapolationMs = 100;
    float snapDistance = 6, maxExtrapolationSpeed = 30;
};
class SnapshotBuffer {
public:
    explicit SnapshotBuffer(InterpolationConfig config = {}) : config_(config) {}
    bool Push(std::uint32_t sequence, double timeMs, Transform value);
    std::optional<Transform> Sample(double nowMs) const;
    void Clear() { samples_.clear(); }
    std::size_t Size() const { return samples_.size(); }
private:
    struct SamplePoint { std::uint32_t sequence; double timeMs; Transform value; };
    InterpolationConfig config_;
    std::deque<SamplePoint> samples_;
};
} // namespace coop
