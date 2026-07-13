#!/usr/bin/env bash
# Color Bus: Validate Project
# Runs all automated quality checks: headless import, GDScript parse check,
# JSON syntax check, broken res:// reference check, unused-script report,
# a headless main-scene boot check, a responsive-layout check across 5
# phone resolutions, an app-navigation check, a typed-data-model check, a
# Passenger scene check, a PassengerQueue scene check, a Bus scene check, a
# BusQueue scene check, a WaitingArea scene check, a level
# loading/validation check, a GameController integration check, and a
# gameplay-animation infrastructure check. Exits 0 only if every gating
# check passes.
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
    if grep -qE "Failed to load script|Compilation failed" "$log_file"; then
        echo "FAIL: $label failed to compile -- its checks never ran (see output above)"
        exit 1
    fi
    if ! grep -qE "RESULT: PASS|Overall: *PASS" "$log_file"; then
        echo "FAIL: $label produced no passing result marker -- its checks may not have run at all (see output above)"
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

echo "-- Step 1/13: headless import --"
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

echo "Step 2/13:"
run_step "script parse / JSON / resource-path / boot checks" "res://tools/validation/run_all.gd"

echo "Step 3/13:"
run_step "responsive layout check (5 phone resolutions)" "res://tests/verify_responsive_layout.gd"

echo "Step 4/13:"
run_step "app navigation check (MainMenu/LevelSelect/Settings/back)" "res://tests/verify_navigation.gd"

echo "Step 5/13:"
run_step "typed data model checks" "res://tests/verify_data_models.gd"

echo "Step 6/13:"
run_step "Passenger scene checks (5 colors, selectable/disabled/moving)" "res://tests/verify_passenger.gd"

echo "Step 7/13:"
run_step "PassengerQueue checks (front-only selection, advance, queue_emptied)" "res://tests/verify_passenger_queue.gd"

echo "Step 8/13:"
run_step "Bus checks (color match, capacity, completion)" "res://tests/verify_bus.gd"

echo "Step 9/13:"
run_step "BusQueue checks (active bus advance, bus_queue_completed)" "res://tests/verify_bus_queue.gd"

echo "Step 10/13:"
run_step "WaitingArea checks (first-empty-slot, full/empty, compaction, dynamic size)" "res://tests/verify_waiting_area.gd"

echo "Step 11/13:"
run_step "Level loading/validation checks (LevelLoader/LevelValidator/LevelRepository, 5 sample levels)" "res://tests/verify_level_loading.gd"

echo "Step 12/13:"
run_step "GameController integration checks (full playthrough, auto-board, deadlock, all 5 levels playable via MainMenu)" "res://tests/verify_game_controller.gd"

echo "Step 13/13:"
run_step "Gameplay animation checks (reduce-motion scaling, animation lock, timeout safety, flight landing, rejected feedback)" "res://tests/verify_game_animations.gd"

echo "PASS: all checks passed"
exit 0
