# The game's native code (GDExtension): heavy loops moved out of GDScript.
# Built by tools/build.sh: on macOS into ../bin/libvoxel_native.framework (universal),
# on Linux into ../bin/libvoxel_native.linux.<arch>.so, on Windows into
# ../bin/voxel_native.windows.<arch>.dll (all listed in bin/voxel_native.gdextension).
# Windows and Linux also in Docker, any host: native/docker/ (BUILDING.md);
# Android (arm64) with the Android NDK into ../bin/libvoxel_native.android.arm64.so.
cmake_minimum_required(VERSION 3.17)
# Universal (Apple Silicon and Intel): must be set before project().
if(APPLE)
	set(CMAKE_OSX_ARCHITECTURES "arm64;x86_64" CACHE STRING "")
endif()
project(voxel_native LANGUAGES CXX)

set(GODOTCPP_TARGET "template_release" CACHE STRING "")
add_subdirectory(godot-cpp)

file(GLOB SOURCES CONFIGURE_DEPENDS src/*.cpp src/*.h)
add_library(voxel_native SHARED ${SOURCES})
target_link_libraries(voxel_native PRIVATE godot-cpp)
# No fused multiply-add: results must round like GDScript's step by step math.
if(MSVC)
	# /fp:precise does not contract a*b+c into an FMA (no /fp:contract).
	target_compile_options(voxel_native PRIVATE /O2 /fp:precise)
else()
	target_compile_options(voxel_native PRIVATE -O3 -ffp-contract=off)
endif()
set_target_properties(voxel_native PROPERTIES
	CXX_STANDARD 17
	CXX_VISIBILITY_PRESET hidden
	POSITION_INDEPENDENT_CODE ON
)

# The godot arch name (x86_64, arm64...), as godot-cpp computes it.
get_target_property(VOXEL_ARCH godot-cpp GODOTCPP_ARCH)
set(BIN_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../bin")
if(APPLE)
	# Packed into ../bin/libvoxel_native.framework by tools/build.sh.
	set_target_properties(voxel_native PROPERTIES
		PREFIX "lib"
		SUFFIX ".dylib"
		LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
	)
elseif(WIN32)
	# $<1:...> keeps multi-config generators (Visual Studio) from adding Release/.
	set_target_properties(voxel_native PROPERTIES
		PREFIX ""
		OUTPUT_NAME "voxel_native.windows.${VOXEL_ARCH}"
		SUFFIX ".dll"
		RUNTIME_OUTPUT_DIRECTORY "$<1:${BIN_DIR}>"
		LIBRARY_OUTPUT_DIRECTORY "$<1:${BIN_DIR}>"
		ARCHIVE_OUTPUT_DIRECTORY "$<1:${CMAKE_CURRENT_BINARY_DIR}/lib>"
		PDB_OUTPUT_DIRECTORY "$<1:${CMAKE_CURRENT_BINARY_DIR}/lib>"
	)
elseif(ANDROID)
	# With the Android NDK's toolchain (tools/build.sh android, BUILDING.md).
	set_target_properties(voxel_native PROPERTIES
		PREFIX "lib"
		OUTPUT_NAME "voxel_native.android.${VOXEL_ARCH}"
		SUFFIX ".so"
		LIBRARY_OUTPUT_DIRECTORY "$<1:${BIN_DIR}>"
	)
else()
	set_target_properties(voxel_native PROPERTIES
		PREFIX "lib"
		OUTPUT_NAME "voxel_native.linux.${VOXEL_ARCH}"
		SUFFIX ".so"
		LIBRARY_OUTPUT_DIRECTORY "$<1:${BIN_DIR}>"
	)
endif()
