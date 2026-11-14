#!/usr/bin/env bash
# Starts the dedicated server of the game in this folder (Linux): no window,
# the world runs on its own. Settings: server.properties next to the game
# (made with explanations on the first start); see SERVER.md.
# Type server commands here (help, list, say, kick, ban, op, whitelist,
# save-all); "stop", Ctrl+C or closing the terminal saves and stops.
#   ./start-server.sh [--port N] [--world NAME]

cd "$(dirname "$0")" || exit 1
NAME="Voxel Engine Bedrock Edition"
case "$(uname -m)" in
	aarch64|arm64) GAME="./$NAME.arm64" ;;
	*) GAME="./$NAME.x86_64" ;;
esac
if [ ! -x "$GAME" ]; then
	GAME="$(ls ./*.x86_64 ./*.arm64 2>/dev/null | head -n 1)"
fi
if [ -z "$GAME" ] || [ ! -f "$GAME" ]; then
	echo "The game was not found next to this script ($NAME.x86_64 / .arm64)"
	exit 1
fi
[ -x "$GAME" ] || chmod +x "$GAME"

# Godot can't catch signals itself: its console is a pipe this script
# feeds, and Ctrl+C / SIGTERM / SIGHUP become "stop" there.
fifo="$(mktemp -u "${TMPDIR:-/tmp}/voxel-server.XXXXXX")"
mkfifo "$fifo"
"$GAME" --headless --server "$@" < "$fifo" &
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
