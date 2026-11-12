#!/bin/zsh
# Builds the native library for macOS (arm64 and x86_64) and packs it as
# bin/libvoxel_native.framework (loaded through bin/voxel_native.gdextension):
# a framework, like godot-cpp's template, because an exported game finds a
# framework in its Contents/Frameworks but not a bare .dylib in a subfolder.
# The first build compiles godot-cpp and takes a few minutes.
set -e
cd "$(dirname "$0")"
[ -f godot-cpp/CMakeLists.txt ] || git submodule update --init
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release > /dev/null
cmake --build build --config Release -j "$(sysctl -n hw.ncpu)"

framework=../bin/libvoxel_native.framework
mkdir -p "$framework/Resources"
cp build/libvoxel_native.dylib "$framework/libvoxel_native"
install_name_tool -id @rpath/libvoxel_native.framework/libvoxel_native "$framework/libvoxel_native"
cat > "$framework/Resources/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>libvoxel_native</string>
	<key>CFBundleIdentifier</key>
	<string>io.github.mishaels.voxelengine.native</string>
	<key>CFBundleName</key>
	<string>libvoxel_native</string>
	<key>CFBundlePackageType</key>
	<string>FMWK</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleSupportedPlatforms</key>
	<array><string>MacOSX</string></array>
	<key>LSMinimumSystemVersion</key>
	<string>11.0</string>
</dict>
</plist>
PLIST
echo "Built $framework"
