#!/bin/zsh
# Builds the game from the console, without opening the Godot editor:
# (optionally the native library,) the project's import, then the export of
# the "macOS" preset (export_presets.cfg) to build/macos/.
#
#   tools/build.sh                  release build: build/macos/Voxel Engine Bedrock Edition <version>.zip
#   tools/build.sh --debug          debug build (with the console wrapper and the full F3 screen)
#   tools/build.sh --app            a .app next to the zip instead of the zip
#   tools/build.sh --native         rebuild native/ (C++) first
#   tools/build.sh -o path.zip      another output (.zip, .app or .dmg)
#   tools/build.sh --open           show the result in Finder when done
#
# Godot: $GODOT, else the editor in /Applications, else `godot` on the PATH.
# It needs the export templates of the same version (Editor > Manage Export
# Templates once, or unpacked into ~/Library/Application Support/Godot/export_templates).
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

mode="release"
native=false
open_after=false
as_app=false
output=""
while [ $# -gt 0 ]; do
	case "$1" in
		--debug) mode="debug" ;;
		--release) mode="release" ;;
		--native) native=true ;;
		--app) as_app=true ;;
		--open) open_after=true ;;
		-o|--output) shift; output="$1" ;;
		-h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) echo "Unknown option: $1 (see --help)"; exit 1 ;;
	esac
	shift
done

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
	echo "Godot not found: set GODOT=/path/to/Godot.app/Contents/MacOS/Godot"
	exit 1
fi
godot_version="$("$GODOT" --version | head -1)"
template_version="$(echo "$godot_version" | sed -E 's/^([0-9.]+)\.([a-z]+[0-9]*)\..*/\1.\2/')"
templates="$HOME/Library/Application Support/Godot/export_templates/$template_version"
if [ ! -d "$templates" ]; then
	echo "No export templates for Godot $template_version in $templates"
	echo "Install them once: Godot editor > Editor > Manage Export Templates."
	exit 1
fi

game_version="$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)"
game_name="$(sed -n 's/^config\/name="\(.*\)"/\1/p' project.godot)"
if [ -z "$output" ]; then
	suffix="$([ "$mode" = "debug" ] && echo " debug" || echo "")"
	extension="$($as_app && echo app || echo zip)"
	output="build/macos/$game_name $game_version$suffix.$extension"
fi
mkdir -p "$(dirname "$output")"

echo "== $game_name $game_version, $mode build with Godot $godot_version"

# --- Native library -----------------------------------------------------------
if $native || [ ! -f bin/libvoxel_native.framework/libvoxel_native ]; then
	echo "== Native library (native/build.sh)"
	native/build.sh
fi

# --- Import and export ----------------------------------------------------------
started=$(date +%s)
echo "== Importing the project"
"$GODOT" --headless --path . --import > build/import.log 2>&1 || true
if grep -qE "SCRIPT ERROR|Parse Error" build/import.log; then
	grep -E "SCRIPT ERROR|Parse Error" -A1 build/import.log | head -20
	echo "Import failed (build/import.log)"
	exit 1
fi

echo "== Exporting to $output"
rm -rf "$output"
"$GODOT" --headless --path . --export-$mode "macOS" "$output" > build/export.log 2>&1 || true
if [ ! -e "$output" ]; then
	grep -iE "error" build/export.log | head -20
	echo "Export failed (build/export.log)"
	exit 1
fi

# --- Check -------------------------------------------------------------------------
app="$output"
check_dir=""
if [[ "$output" == *.zip ]]; then
	check_dir="$(mktemp -d)"
	ditto -x -k "$output" "$check_dir"
	app="$(ls -d "$check_dir"/*.app | head -1)"
fi
if [[ "$app" == *.app ]]; then
	if codesign --verify --deep "$app" 2>/dev/null; then
		echo "== Signature: ok (ad-hoc)"
	else
		echo "== Signature: not valid (codesign --verify failed)"
	fi
	if [ -f "$app/Contents/Frameworks/libvoxel_native.framework/libvoxel_native" ]; then
		echo "== Native library: included"
	else
		echo "== Native library: missing (the game falls back to GDScript)"
	fi
fi
[ -n "$check_dir" ] && rm -rf "$check_dir"

size="$(du -sh "$output" | cut -f1)"
echo "== Done in $(( $(date +%s) - started )) s: $output ($size)"
$open_after && open -R "$output"
exit 0
