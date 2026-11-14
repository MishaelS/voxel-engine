# Linux arm64 (on an arm64 host the compiler is the native g++).
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
find_program(_cxx NAMES aarch64-linux-gnu-g++ g++ REQUIRED)
set(CMAKE_CXX_COMPILER "${_cxx}")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
