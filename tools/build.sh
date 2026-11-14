#!/usr/bin/env bash
# Builds the game from the console, without opening the Godot editor: the
# native libraries (native/, C++ GDExtension) when missing - this OS's with
# its own compiler, Linux and Windows in Docker when it runs - the project's
# import, then one export per platform (export_presets.cfg) into
# build/<platform>/, each zipped with the dedicated server's files next to
# the game (BUILDING.md).
#
#   tools/build.sh                     every platform whose export templates are installed
#   tools/build.sh macos linux         only these (macos, windows, linux, linux-arm64)
#   tools/build.sh --debug             debug builds (console wrapper, full F3 screen)
#   tools/build.sh --native            rebuild the native library for this OS first
#   tools/build.sh --docker            rebuild the Linux and Windows libraries in Docker first
#   tools/build.sh --no-docker         never use Docker (a missing library: GDScript fallback)
#   tools/build.sh --no-native         never build native/ (CI puts the libraries in bin/)
#   tools/build.sh --native-only       only build the native libraries (with --docker:
#                                      Linux and Windows in Docker), no export
#   tools/build.sh --no-zip            leave the folders, skip the zips
#   tools/build.sh --open              show build/ in Finder / the file manager when done
#
# Godot: $GODOT, else the editor in /Applications, else `godot` on the PATH.
# It needs the export templates of the same version: Godot editor > Editor >
# Manage Export Templates > Download and Install (once).
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

mode="release"
native="auto"
docker_mode="auto"
native_only=false
zip_it=true
open_after=false
platforms=()
while [ $# -gt 0 ]; do
	case "$1" in
		--debug) mode="debug" ;;
		--release) mode="release" ;;
		--native) native="yes" ;;
		--no-native) native="no"; docker_mode="no" ;;
		--native-only) native_only=true ;;
		--docker) docker_mode="yes" ;;
		--no-docker) docker_mode="no" ;;
		--no-zip|--app) zip_it=false ;;
		--open) open_after=true ;;
		macos|windows|linux|linux-arm64) platforms+=("$1") ;;
		all) platforms=(macos windows linux linux-arm64) ;;
		-h|--help) sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) echo "Unknown option: $1 (see --help)"; exit 1 ;;
	esac
	shift
done
explicit=true
if [ ${#platforms[@]} -eq 0 ]; then
	platforms=(macos windows linux linux-arm64)
	explicit=false
fi

host="$(uname -s)"
case "$host" in
	Darwin) own="macos"; templates_root="$HOME/Library/Application Support/Godot/export_templates" ;;
	Linux) [ "$(uname -m)" = "x86_64" ] && own="linux" || own="linux-arm64"
		templates_root="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates" ;;
	MINGW*|MSYS*|CYGWIN*) own="windows"; templates_root="$APPDATA/Godot/export_templates" ;;
	*) own=""; templates_root="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates" ;;
esac

# preset name, template files, native library and bundled server scripts per platform
preset_of() {
	case "$1" in
		macos) echo "macOS" ;;
		windows) echo "Windows Desktop" ;;
		linux) echo "Linux" ;;
		linux-arm64) echo "Linux ARM64" ;;
	esac
}
template_of() {
	case "$1" in
		macos) echo "macos.zip" ;;
		windows) echo "windows_${mode}_x86_64.exe" ;;
		linux) echo "linux_${mode}.x86_64" ;;
		linux-arm64) echo "linux_${mode}.arm64" ;;
	esac
}
native_of() {
	case "$1" in
		macos) echo "bin/libvoxel_native.framework/libvoxel_native" ;;
		windows) echo "bin/voxel_native.windows.x86_64.dll" ;;
		linux) echo "bin/libvoxel_native.linux.x86_64.so" ;;
		linux-arm64) echo "bin/libvoxel_native.linux.arm64.so" ;;
	esac
}
gdext_key_of() {
	case "$1" in
		macos) echo "macos" ;;
		windows) echo "windows.x86_64" ;;
		linux) echo "linux.x86_64" ;;
		linux-arm64) echo "linux.arm64" ;;
	esac
}
server_files_of() {
	case "$1" in
		macos) echo "start-server.command start-server.sh server.properties.example" ;;
		windows) echo "start-server.bat server.properties.example" ;;
		linux*) echo "start-server.sh server.properties.example" ;;
	esac
}
docker_running() { command -v docker > /dev/null && docker info > /dev/null 2>&1; }

# --- Native library for this OS, with its own compiler ------------------------------
# CMake 3.17+, a C++17 compiler and Python 3 (godot-cpp's binding generator).
# Into bin/, where bin/voxel_native.gdextension finds it:
#   macOS    bin/libvoxel_native.framework (universal: arm64 and x86_64) - a
#            framework, like godot-cpp's template, because an exported game
#            finds a framework in its Contents/Frameworks but not a bare .dylib
#   Linux    bin/libvoxel_native.linux.<arch>.so
#   Windows  bin/voxel_native.windows.<arch>.dll (Git Bash; MSVC or MinGW)
# Build folder native/build; the first build compiles godot-cpp (a few minutes).
build_native_host() {
	local build_dir=native/build jobs framework
	[ -f native/godot-cpp/CMakeLists.txt ] || git submodule update --init native/godot-cpp
	jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
	cmake -S native -B "$build_dir" -DCMAKE_BUILD_TYPE=Release > /dev/null
	cmake --build "$build_dir" --config Release --parallel "$jobs"
	[ "$host" = "Darwin" ] || return 0
	framework=bin/libvoxel_native.framework
	mkdir -p "$framework/Resources"
	cp "$build_dir/libvoxel_native.dylib" "$framework/libvoxel_native"
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
}

# --- Linux and Windows libraries in Docker ------------------------------------------
# On any host with Docker running: the image native/docker/Dockerfile (Ubuntu
# 20.04, glibc 2.31: g++, the cross g++ for the other Linux arch, MinGW-w64)
# is built once and cached by Docker (the first run downloads ~350 MB), then
# a container with the repository mounted, run as this user, builds release
# libraries with the toolchains native/docker/toolchain-*.cmake (libgcc and
# libstdc++ static; winpthread too on Windows) in native/build-docker-<platform>/.
build_native_docker() { # platforms (linux, linux-arm64, windows)
	local image=voxel-native-build
	[ -f native/godot-cpp/CMakeLists.txt ] || git submodule update --init native/godot-cpp
	docker build -q -t "$image" native/docker > /dev/null
	docker run --rm -v "$ROOT":/src -w /src --user "$(id -u):$(id -g)" "$image" bash -c '
		set -e
		for platform in "$@"; do
			case "$platform" in
				linux) toolchain=linux-x86_64 ;;
				linux-arm64) toolchain=linux-arm64 ;;
				windows) toolchain=windows-x86_64 ;;
			esac
			echo "   $platform"
			dir=native/build-docker-$platform
			cmake -S native -B "$dir" -G Ninja -DCMAKE_BUILD_TYPE=Release \
				-DCMAKE_TOOLCHAIN_FILE=/src/native/docker/toolchain-$toolchain.cmake > /dev/null
			# the compiler output (godot-cpp warns a lot) goes to build.log, shown on failure
			if ! cmake --build "$dir" --parallel "$(nproc)" > "$dir/build.log" 2>&1; then
				grep -E "error|Error" -A3 "$dir/build.log" | head -40
				echo "   failed: $dir/build.log"
				exit 1
			fi
		done' docker-build "$@"
}

# What to build: this OS's library when asked (--native, --native-only) or
# missing; with --docker every chosen Linux/Windows platform (this OS's too)
# goes to Docker, by default only the missing ones and only when Docker runs.
$native_only && [ "$native" = "auto" ] && native="yes"
host_build=false
docker_targets=()
for platform in "${platforms[@]}"; do
	case "$platform" in windows|linux|linux-arm64) dockerable=true ;; *) dockerable=false ;; esac
	missing=false
	[ -f "$(native_of "$platform")" ] || missing=true
	if [ "$platform" = "$own" ] && ! { $dockerable && [ "$docker_mode" = "yes" ]; }; then
		if [ "$native" = "yes" ] || { [ "$native" = "auto" ] && $missing; }; then host_build=true; fi
	elif $dockerable; then
		if [ "$docker_mode" = "yes" ] || { [ "$docker_mode" = "auto" ] && $missing; } \
				|| { $native_only && [ "$docker_mode" = "auto" ] && docker_running; }; then
			docker_targets+=("$platform")
		fi
	fi
done
if $host_build; then
	echo "== Native library for $own (native/, this OS's compiler)"
	build_native_host
	echo "   -> $(native_of "$own")"
fi
if [ ${#docker_targets[@]} -gt 0 ]; then
	if docker_running; then
		echo "== Native libraries in Docker: ${docker_targets[*]}"
		build_native_docker "${docker_targets[@]}"
		for platform in "${docker_targets[@]}"; do
			lib="$(native_of "$platform")"
			[ -f "$lib" ] || { echo "Missing $lib after the Docker build"; exit 1; }
			echo "   -> $lib ($(du -h "$lib" | cut -f1))"
		done
	elif [ "$docker_mode" = "yes" ]; then
		echo "Docker is not running (start Docker Desktop): --docker needs it"
		exit 1
	else
		echo "== Docker is not running: no native library for ${docker_targets[*]} (start Docker to build them)"
	fi
fi
$native_only && exit 0

# --- Godot ------------------------------------------------------------------
if [ -z "$GODOT" ]; then
	for candidate in "/Applications/Разработка/Godot.app/Contents/MacOS/Godot" \
			"/Applications/Godot.app/Contents/MacOS/Godot" "$(command -v godot 2>/dev/null)"; do
		if [ -n "$candidate" ] && [ -x "$candidate" ]; then
			GODOT="$candidate"
			break
		fi
	done
fi
if [ -z "$GODOT" ] || [ ! -x "$GODOT" ]; then
	echo "Godot not found: set GODOT=/path/to/Godot (the editor binary)"
	exit 1
fi
godot_version="$("$GODOT" --version | head -1)"
template_version="$(echo "$godot_version" | sed -E 's/^([0-9.]+)\.([a-z]+[0-9]*)\..*/\1.\2/')"
templates="$templates_root/$template_version"

game_version="$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)"
game_name="$(sed -n 's/^config\/name="\(.*\)"/\1/p' project.godot)"
echo "== $game_name $game_version, $mode build with Godot $godot_version"

# --- Import ---------------------------------------------------------------------
mkdir -p build
touch build/.gdignore
started=$(date +%s)
echo "== Importing the project"
"$GODOT" --headless --path . --import > build/import.log 2>&1 || true
if grep -qE "SCRIPT ERROR|Parse Error" build/import.log; then
	grep -E "SCRIPT ERROR|Parse Error" -A1 build/import.log | head -20
	echo "Import failed (build/import.log)"
	exit 1
fi

GDEXT="bin/voxel_native.gdextension"
GDEXT_BACKUP="build/voxel_native.gdextension.orig"
if [ -f "$GDEXT_BACKUP" ]; then mv "$GDEXT_BACKUP" "$GDEXT"; fi # left by an interrupted run
trap '[ -f "$GDEXT_BACKUP" ] && mv "$GDEXT_BACKUP" "$GDEXT"' EXIT

make_zip() { # folder (inside its parent) -> zip, keeping symlinks and exec bits
	local parent dir name zip
	parent="$(dirname "$1")"; name="$(basename "$1")"; zip="$2"
	rm -f "$zip"
	if [ "$host" = "Darwin" ]; then
		ditto -c -k --sequesterRsrc --keepParent "$1" "$zip"
	elif command -v zip > /dev/null; then
		(cd "$parent" && zip -qry "$zip" "$name")
	else
		(cd "$parent" && python3 -m zipfile -c "$zip" "$name")
	fi
}

# --- Export -----------------------------------------------------------------------
built=()
skipped=()
failed=()
suffix="$([ "$mode" = "debug" ] && echo " debug" || echo "")"
for platform in "${platforms[@]}"; do
	preset="$(preset_of "$platform")"
	template="$(template_of "$platform")"
	if [ ! -f "$templates/$template" ]; then
		echo "== $platform: skipped, no export template $templates/$template"
		skipped+=("$platform (no export templates $template_version)")
		continue
	fi
	out_dir="$ROOT/build/$platform"
	stage="$out_dir/$game_name"
	log="build/export-$platform.log"
	rm -rf "$stage"
	mkdir -p "$stage"
	lib="$(native_of "$platform")"
	if [ -f "$lib" ]; then
		lib_note="native library included"
	else
		# Godot fails an export whose GDExtension library is missing: this
		# export runs without it (the GDScript fallback), the line comes back after.
		lib_note="NO native library: $lib is missing, the game uses the slower GDScript fallback"
		cp "$GDEXT" "$GDEXT_BACKUP"
		grep -v "^$(gdext_key_of "$platform") = " "$GDEXT_BACKUP" > "$GDEXT"
	fi
	echo "== $platform: exporting \"$preset\" ($lib_note)"

	ok=true
	if [ "$platform" = "macos" ]; then
		# Exported as a zip (works on every host), unpacked into the folder.
		app_zip="$out_dir/export.zip"
		rm -f "$app_zip"
		"$GODOT" --headless --path . --export-$mode "$preset" "$app_zip" > "$log" 2>&1 || true
		if [ -f "$app_zip" ]; then
			if [ "$host" = "Darwin" ]; then ditto -x -k "$app_zip" "$stage"; else unzip -q "$app_zip" -d "$stage"; fi
			rm -f "$app_zip"
		fi
		[ -d "$stage/$game_name.app" ] || ok=false
	else
		case "$platform" in
			windows) binary="$game_name.exe" ;;
			linux) binary="$game_name.x86_64" ;;
			linux-arm64) binary="$game_name.arm64" ;;
		esac
		"$GODOT" --headless --path . --export-$mode "$preset" "$stage/$binary" > "$log" 2>&1 || true
		[ -f "$stage/$binary" ] || ok=false
	fi
	if [ -f "$GDEXT_BACKUP" ]; then
		mv "$GDEXT_BACKUP" "$GDEXT"
	fi
	grep -q "Project export for preset .* failed" "$log" && ok=false
	if ! $ok; then
		grep -iE "error" "$log" | head -10
		echo "== $platform: export failed ($log)"
		failed+=("$platform")
		continue
	fi

	# The dedicated server's files next to the game (Godot exports only into
	# the .pck/.app, so they are copied here).
	cp CHANGELOG.md SERVER.md "$stage/"
	missing_server=""
	for f in $(server_files_of "$platform"); do
		if [ -f "tools/server/$f" ]; then
			cp "tools/server/$f" "$stage/"
			case "$f" in *.sh|*.command) chmod +x "$stage/$f" ;; esac
		else
			missing_server="$missing_server $f"
		fi
	done
	[ -n "$missing_server" ] && echo "   (not in tools/server/ yet, not bundled:$missing_server)"

	if [ "$platform" = "macos" ] && [ "$host" = "Darwin" ]; then
		if codesign --verify --deep "$stage/$game_name.app" 2>/dev/null; then
			echo "   signature: ok (ad-hoc)"
		else
			echo "   signature: not valid (codesign --verify failed)"
		fi
	fi
	find "$stage" -name .DS_Store -delete
	result="$stage"
	if $zip_it; then
		result="$out_dir/$game_name $game_version-$platform$suffix.zip"
		make_zip "$stage" "$result"
	fi
	echo "   -> $result ($(du -sh "$result" | cut -f1))"
	built+=("$platform")
done

echo "== Done in $(( $(date +%s) - started )) s"
[ ${#built[@]} -gt 0 ] && echo "   built:   ${built[*]}"
for s in "${skipped[@]}"; do echo "   skipped: $s"; done
if [ ${#skipped[@]} -gt 0 ]; then
	echo "   Install the templates once: Godot editor > Editor > Manage Export Templates"
	echo "   > Download and Install (they go to $templates_root/)."
fi
[ ${#failed[@]} -gt 0 ] && echo "   FAILED:  ${failed[*]} (build/export-<platform>.log)"
if $open_after; then
	if [ "$host" = "Darwin" ]; then open build; else xdg-open build > /dev/null 2>&1 || true; fi
fi
if [ ${#failed[@]} -gt 0 ] || { $explicit && [ ${#skipped[@]} -gt 0 ]; }; then
	exit 1
fi
exit 0
