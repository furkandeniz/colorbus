#!/usr/bin/env bash
# Color Bus: Validate Project
# Runs all automated quality checks: headless import, GDScript parse check,
# JSON syntax check, broken res:// reference check, unused-script report,
# a headless main-scene boot check, a responsive-layout check across 5
# phone resolutions, and an app-navigation check. Exits 0 only if every
# gating check passes.
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

run_step() {
    local label="$1"
    local script_path="$2"
    local log_file="$LOG_DIR/$(basename "$script_path").log"

    echo "-- $label --"
    "$GODOT_BIN" --headless --path . --script "$script_path" >"$log_file" 2>&1
    local status=$?
    cat "$log_file"
    echo

    if grep -qE "Segmentation fault|Fatal error:|Assertion failed" "$log_file"; then
        echo "FAIL: engine-level crash detected in $label"
        exit 1
    fi
    if [ $status -ne 0 ]; then
        echo "FAIL: $label failed (see output above)"
        exit 1
    fi
}

echo "== Color Bus: Validate Project =="
echo "Godot: $("$GODOT_BIN" --version)"
echo

echo "-- Step 1/4: headless import --"
IMPORT_LOG="$LOG_DIR/import.log"
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

echo "Step 2/4:"
run_step "script parse / JSON / resource-path / boot checks" "res://tools/validation/run_all.gd"

echo "Step 3/4:"
run_step "responsive layout check (5 phone resolutions)" "res://tests/verify_responsive_layout.gd"

echo "Step 4/4:"
run_step "app navigation check (MainMenu/LevelSelect/Settings/back)" "res://tests/verify_navigation.gd"

echo "PASS: all checks passed"
exit 0
