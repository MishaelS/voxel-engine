#!/bin/zsh
# Runs the game from the project's sources, without the Godot editor (a
# debug run: the full F3 screen, errors in this console).
#
#   tools/run.sh              the title screen
#   tools/run.sh --release    with the release build's short F3 screen
#   tools/run.sh -- <args>    anything after -- goes to Godot (e.g. --verbose)
#
# Godot: $GODOT, else the editor in /Applications, else `godot` on the PATH.
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

extra=()
release=false
while [ $# -gt 0 ]; do
	case "$1" in
		--release) release=true ;;
		--) shift; extra=("$@"); break ;;
		-h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) echo "Unknown option: $1 (see --help)"; exit 1 ;;
	esac
	shift
done

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

if [ ! -d .godot ]; then
	echo "== First run: importing the project"
	"$GODOT" --headless --path . --import > /dev/null 2>&1 || true
fi
user_args=()
$release && user_args=(++ --short-f3)
exec "$GODOT" --path . "${extra[@]}" "${user_args[@]}"
