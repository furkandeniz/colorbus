extends SceneTree
## Standalone entry point for CheckLevelSolvability, wired into
## tools/validate.sh as its own step -- level design is a substantial,
## separate concern from run_all.gd's structural checks (parse/JSON/
## resource-path/boot), and each level's diagnostic output is worth its
## own clearly-labeled step in the validate.sh log.
##
## Usage: godot --headless --path . --script res://tools/validation/run_level_solvability.gd


func _initialize() -> void:
	var ok: bool = CheckLevelSolvability.run()
	print("[LevelSolvabilityCheck] RESULT: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
