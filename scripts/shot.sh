#!/usr/bin/env bash
# Render one screen to a PNG so the UI can be reviewed without a human clicking.
#
#   ./scripts/shot.sh                 # every scene into /tmp/pb-<scene>.png
#   ./scripts/shot.sh MainMenu         # just one
#
# Uses the App autoload's --pb-shot hook (captures frame 30, then quits).
set -u
GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
cd "$(dirname "$0")/.."

scenes=("$@")
if [ "${#scenes[@]}" -eq 0 ]; then
	scenes=(MainMenu Pokedex Lab FusionMachine SaveManager Run)
fi

for scene in "${scenes[@]}"; do
	out="/tmp/pb-${scene}.png"
	rm -f "$out"
	# --quit-after is a safety net in case the capture hook never fires.
	"$GODOT_BIN" --path . "res://scenes/$scene.tscn" --quit-after 240 \
		-- --pb-shot "$out" >"/tmp/pb-${scene}.log" 2>&1
	if [ -f "$out" ]; then
		echo "shot $scene -> $out ($(stat -f%z "$out") bytes)"
	else
		echo "shot $scene FAILED; log tail:"
		tail -6 "/tmp/pb-${scene}.log" | sed 's/^/    /'
	fi
done
