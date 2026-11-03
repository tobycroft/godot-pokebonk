#!/usr/bin/env bash
# One-command verification for the pokebonk-web -> Godot port.
#
#   ./scripts/verify.sh              # import + headless suite + boot every scene
#   GODOT_BIN=/path/to/Godot ./scripts/verify.sh
#
# Layers:
#   1. resource import (also compiles every GDScript)
#   2. res://test/SmokeTest.tscn -- 390+ assertions: data integrity, formula
#      parity against data/pb/golden_values.json, run simulation, save round-trip
#   3. each screen launched for 90 frames with a real renderer, to catch runtime
#      errors the headless path cannot see (materials, meshes, UI construction)
#
# Exits non-zero if any layer reports a script error or a failed assertion.

set -u
GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
cd "$(dirname "$0")/.."

if [ ! -x "$GODOT_BIN" ]; then
	echo "Godot binary not found at: $GODOT_BIN (set GODOT_BIN)" >&2
	exit 2
fi

fail=0

echo "### 1/3 import + compile"
import_log="$(mktemp)"
"$GODOT_BIN" --headless --path . --import >"$import_log" 2>&1
errors=$(grep -c -E "SCRIPT ERROR|Parse Error|Compile Error|Error importing" "$import_log")
echo "    compile/import errors: $errors"
[ "$errors" -eq 0 ] || { grep -E "SCRIPT ERROR|Parse Error|Compile Error|Error importing" "$import_log" | head -10; fail=1; }

echo "### 2/3 headless suite"
"$GODOT_BIN" --headless --path . res://test/SmokeTest.tscn
suite_rc=$?
echo "    smoke exit code: $suite_rc"
[ "$suite_rc" -eq 0 ] || fail=1

echo "### 3/3 scene boots (windowed renderer, 90 frames each)"
for scene in MainMenu Pokedex Lab FusionMachine SaveManager Run; do
	out="$(mktemp)"
	"$GODOT_BIN" --path . --quit-after 90 "res://scenes/$scene.tscn" >"$out" 2>&1
	bad=$(grep -c -E "SCRIPT ERROR|ERROR:" "$out")
	printf "    %-14s errors=%s\n" "$scene" "$bad"
	if [ "$bad" -ne 0 ]; then
		grep -E "SCRIPT ERROR|ERROR:" "$out" | head -5
		fail=1
	fi
	rm -f "$out"
done

rm -f "$import_log"
if [ "$fail" -eq 0 ]; then
	echo "### verification passed"
else
	echo "### verification FAILED" >&2
fi
exit $fail
