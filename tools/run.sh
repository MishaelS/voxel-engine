#!/bin/zsh
# Runs the game from the project's sources, without the Godot editor (a
# debug run: the full F3 screen, errors in this console).
#
#   tools/run.sh              the title screen
#   tools/run.sh --release    with the release build's short F3 screen
#   tools/run.sh -- <args>    anything after -- goes to Godot (e.g. --verbose)
#   tools/run.sh --server [--port N] [--world NAME] [--config FILE]
#                             a dedicated server (SERVER.md), headless; it uses
#                             server.properties in the current folder if there
#                             is one, else the game folder's. Type commands in
#                             this console; stop, Ctrl+C or SIGTERM save and stop
#
# Godot: $GODOT, else the editor in /Applications, else `godot` on the PATH.
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$(pwd)"
cd "$ROOT"

extra=()
release=false
server=false
server_args=()
while [ $# -gt 0 ]; do
	case "$1" in
		--release) release=true ;;
		--server) server=true; shift; server_args=("$@"); break ;;
		--) shift; extra=("$@"); break ;;
		-h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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
if $server; then
	# Godot can't catch signals itself: it reads its console from a pipe
	# this script feeds, and Ctrl+C / SIGTERM / SIGHUP become "stop" there,
	# which saves the world and the players. (Started from the folder this
	# script was run in: server.properties there is found.)
	fifo="$(mktemp -u "${TMPDIR:-/tmp}/voxel-server.XXXXXX")"
	mkfifo "$fifo"
	(cd "$HERE" && exec "$GODOT" --headless --path "$ROOT" -- --server "${server_args[@]}" < "$fifo") &
	pid=$!
	exec 3>"$fifo"
	rm -f "$fifo"
	stopping=false
	stop_server() {
		if ! $stopping; then
			stopping=true
			echo "stop" >&3
		fi
	}
	trap stop_server INT TERM HUP
	while kill -0 "$pid" 2>/dev/null; do
		if IFS= read -r -t 1 line; then
			echo "$line" >&3
		fi
	done
	exec 3>&-
	wait "$pid"
	exit $?
fi

user_args=()
$release && user_args=(++ --short-f3)
exec "$GODOT" --path . "${extra[@]}" "${user_args[@]}"
