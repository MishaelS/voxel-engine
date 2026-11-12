# The game's native code (GDExtension): heavy loops moved out of GDScript.
# Built by build.sh into ../bin/ (loaded through bin/voxel_native.gdextension).
cmake_minimum_required(VERSION 3.17)
# Universal (Apple Silicon and Intel): must be set before project().
set(CMAKE_OSX_ARCHITECTURES "arm64;x86_64" CACHE STRING "")
project(voxel_native LANGUAGES CXX)

set(GODOTCPP_TARGET "template_release" CACHE STRING "")
add_subdirectory(godot-cpp)

file(GLOB SOURCES CONFIGURE_DEPENDS src/*.cpp src/*.h)
add_library(voxel_native SHARED ${SOURCES})
target_link_libraries(voxel_native PRIVATE godot-cpp)
# No fused multiply-add: results must round like GDScript's step by step math.
target_compile_options(voxel_native PRIVATE -O3 -ffp-contract=off)
set_target_properties(voxel_native PROPERTIES
	CXX_STANDARD 17
	CXX_VISIBILITY_PRESET hidden
	POSITION_INDEPENDENT_CODE ON
	PREFIX "lib"
	SUFFIX ".dylib"
	LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../bin"
)
