#!/usr/bin/env bash
# Starts the dedicated server of the game in this folder (macOS): double-
# click this file. No game window: the world runs on its own in this
# Terminal window. Settings: server.properties next to the game (made with
# explanations on the first start); see SERVER.md.
# Type server commands here (help, list, say, kick, ban, op, whitelist,
# save-all); "stop", Ctrl+C or closing the window saves and stops.
# (macOS may ask the first time: right-click > Open, or System Settings >
# Privacy & Security > Open Anyway.)

cd "$(dirname "$0")" || exit 1
APP="./Voxel Engine Godot Edition.app"
if [ ! -d "$APP" ]; then
	APP="$(ls -d ./*.app 2>/dev/null | head -n 1)"
fi
if [ -z "$APP" ] || [ ! -d "$APP/Contents/MacOS" ]; then
	echo "The game (Voxel Engine Godot Edition.app) was not found next to this file"
	read -r -p "Press Return to close" _
	exit 1
fi
EXE="$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$APP/Contents/Info.plist" 2>/dev/null)"
GAME="$APP/Contents/MacOS/$EXE"
if [ -z "$EXE" ] || [ ! -x "$GAME" ]; then
	GAME="$(ls "$APP"/Contents/MacOS/* 2>/dev/null | head -n 1)"
fi

# Godot can't catch signals itself: its console is a pipe this script
# feeds, and Ctrl+C / closing the window become "stop" there.
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
		sleep 1
	fi
done
exec 3>&-
wait "$pid"
echo "The server stopped. You can close this window."
