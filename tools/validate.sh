#!/usr/bin/env bash
# Color Bus: Validate Project
# Runs all automated quality checks: headless import, GDScript parse check,
# JSON syntax check, broken res:// reference check, unused-script report,
# and a headless main-scene boot check. Exits 0 only if every gating check
# passes.
set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

GODOT_BIN="${GODOT_BIN:-godot}"
if ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
    if [ -x "/Applications/Godot.app/Contents/MacOS/Godot" ]; then
        GODOT_BIN="/Applications/Godot.app/Contents/MacOS/Godot"
    else
        echo "ERROR: 'godot' not found on PATH and no /Applications/Godot.app install found." >&2
        echo "Set GODOT_BIN to your Godot 4 executable and re-run." >&2
        exit 1
    fi
fi

LOG_DIR="$(mktemp -d)"
trap 'rm -rf "$LOG_DIR"' EXIT
IMPORT_LOG="$LOG_DIR/import.log"
CHECKS_LOG="$LOG_DIR/checks.log"

echo "== Color Bus: Validate Project =="
echo "Godot: $("$GODOT_BIN" --version)"
echo

echo "-- Step 1/2: headless import --"
"$GODOT_BIN" --headless --path . --import >"$IMPORT_LOG" 2>&1
import_status=$?
cat "$IMPORT_LOG"
if [ $import_status -ne 0 ]; then
    echo
    echo "FAIL: project import failed (exit $import_status)"
    exit 1
fi
echo "Import: OK"
echo

echo "-- Step 2/2: script parse / JSON / resource-path / boot checks --"
"$GODOT_BIN" --headless --path . --script res://tools/validation/run_all.gd >"$CHECKS_LOG" 2>&1
checks_status=$?
cat "$CHECKS_LOG"
echo

if grep -qE "Segmentation fault|Fatal error:|Assertion failed" "$CHECKS_LOG"; then
    echo "FAIL: engine-level crash detected in check output"
    exit 1
fi

if [ $checks_status -ne 0 ]; then
    echo "FAIL: one or more gating checks failed (see output above)"
    exit 1
fi

echo "PASS: all checks passed"
exit 0
