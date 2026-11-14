#!/usr/bin/env bash
# Runs a dedicated server (SERVER.md): no window, no sound, the world and
# the players only. Lines typed here are server commands (help, list, say,
# kick, ban, op, whitelist, save-all, stop...). Ctrl+C, or SIGTERM (systemd,
# docker stop, kill), saves the world and stops the server cleanly.
#
#   tools/run_server.sh                         server.properties in this folder
#   tools/run_server.sh --port 25570 --world survival2
#   tools/run_server.sh --config /srv/voxel/server.properties
#
# The settings file is made with the defaults on the first start (in the
# current folder unless --config says where); logs go to logs/ next to it.
# Godot: $GODOT, else `godot` on the PATH, else the editor in /Applications.
# An exported game: GODOT=/path/to/the/game tools/run_server.sh (it runs
# the game's own files then, not this project's).


ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$(pwd)"

if [ -z "${GODOT}" ]; then
	for candidate in "$(command -v godot 2>/dev/null)" "$(command -v godot4 2>/dev/null)" \
			"/Applications/Разработка/Godot.app/Contents/MacOS/Godot" "/Applications/Godot.app/Contents/MacOS/Godot"; do
		if [ -n "$candidate" ] && [ -x "$candidate" ]; then
			GODOT="$candidate"
			break
		fi
	done
fi
if [ -z "${GODOT}" ] || [ ! -x "$GODOT" ]; then
	echo "Godot not found: set GODOT=/path/to/godot (Godot 4.5, or the exported game)"
	exit 1
fi

args=("$@")
has_config=false
for arg in "$@"; do
	[ "$arg" = "--config" ] && has_config=true
done
$has_config || args+=(--config "$HERE/server.properties")

project=()
if [ -f "$ROOT/project.godot" ] && [ -z "${EXPORTED}" ]; then
	project=(--path "$ROOT")
	if [ ! -d "$ROOT/.godot" ]; then
		echo "== First run: importing the project"
		"$GODOT" --headless --path "$ROOT" --import > /dev/null 2>&1 || true
	fi
fi

# Godot can't catch signals itself: it reads its console from a pipe that
# this script feeds; Ctrl+C / SIGTERM become "stop" there. (In a script,
# a background job ignores Ctrl+C, so only this script gets it.)
fifo="$(mktemp -u "${TMPDIR:-/tmp}/voxel-server.XXXXXX")"
mkfifo "$fifo"
"$GODOT" --headless "${project[@]}" -- --server "${args[@]}" < "$fifo" &
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
	elif [ $? -le 128 ]; then
		sleep 1 # (no console: under systemd, or the input closed)
	fi
done
exec 3>&-
wait "$pid"
