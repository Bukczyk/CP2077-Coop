#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="$repo_root/build/linux"
cmake -S "$repo_root" -B "$build_dir" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCOOP_BUILD_PLUGIN=OFF -DCOOP_BUILD_LEGACY_SERVER=OFF
cmake --build "$build_dir" --parallel
ctest --test-dir "$build_dir" --output-on-failure
