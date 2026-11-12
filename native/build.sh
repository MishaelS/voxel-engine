#!/bin/zsh
# Builds the native library (bin/libvoxel_native.dylib) for macOS (arm64 and
# x86_64). The first build compiles godot-cpp and takes a few minutes.
set -e
cd "$(dirname "$0")"
[ -f godot-cpp/CMakeLists.txt ] || git submodule update --init
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release > /dev/null
cmake --build build --config Release -j "$(sysctl -n hw.ncpu)"
