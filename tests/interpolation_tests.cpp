#include "check.hpp"
#include "coop/interpolation.hpp"
#include <cmath>
#include <limits>
using namespace coop;
void Tests() {
    SnapshotBuffer b;
    CHECK(!b.Sample(0));
    CHECK(b.Push(1,100,{{0,0,0},{}},100));
    CHECK(b.Push(2,200,{{1,0,0},{}},200));
    CHECK(std::abs(b.Sample(250)->position.x-0.5f) < 0.001f);
    CHECK(std::abs(b.Sample(350)->position.x-1.5f) < 0.001f);
    CHECK(std::abs(b.Sample(1000)->position.x-2.0f) < 0.001f); // 100 ms extrapolation cap
    CHECK(!b.Push(1,300,{},300)); // old sequence
    CHECK(!b.Push(3,300,{},199)); // old source timestamp despite newer sequence
    CHECK(!b.Push(3,190,{},300)); // local clock regression
    CHECK(!b.Push(3,300,{{NAN,0,0},{}},300));
    CHECK(!b.Sample(std::numeric_limits<double>::infinity()));
    CHECK(b.Push(3,300,{{100,0,0},{}},300)); // large jump discards interpolation across teleport
    CHECK(b.Size() == 1 && b.Sample(300)->position.x == 100);
    b.Clear(); CHECK(!b.Sample(300));
    CHECK(b.Push(0xffffffffu,1,{})); CHECK(b.Push(0,2,{}));
    CHECK(!b.Push(0xffffffffu,3,{}));
    SnapshotBuffer limited({0,100,6,1});
    CHECK(limited.Push(1,0,{})); CHECK(limited.Push(2,100,{{1,0,0},{}}));
    CHECK(std::abs(limited.Sample(200)->position.x-1.1f) < 0.001f);
    SnapshotBuffer rotation({0,100,6,30});
    CHECK(rotation.Push(1,0,{{},{0,0,3.124139f}}));
    CHECK(rotation.Push(2,100,{{},{0,0,-3.124139f}}));
    CHECK(std::abs(std::abs(rotation.Sample(50)->rotation.z)-3.141593f) < 0.001f);
    CHECK(rotation.Push(3,100,{})); CHECK(rotation.Size() == 2); // equal arrival time replaces safely
    for (unsigned i=4;i<300;++i) CHECK(rotation.Push(i,100+i,{}));
    CHECK(rotation.Size() == 128);
    bool rejected=false;
    try { SnapshotBuffer invalid({0,-1,6,30}); } catch(const std::invalid_argument&) { rejected=true; }
    CHECK(rejected);
}
int main() { return Run(Tests); }
