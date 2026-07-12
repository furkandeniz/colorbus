extends SceneTree
## Runs every automated check in tools/validation/ and exits 0 only if all
## gating checks pass (unused-script report is informational and does not
## gate the result).
##
## Usage: godot --headless --path . --script res://tools/validation/run_all.gd


func _initialize() -> void:
	print("=== Color Bus project validation ===\n")

	var scripts_ok: bool = CheckScripts.run()
	print("")
	var json_ok: bool = CheckJson.run()
	print("")
	var resource_paths_ok: bool = CheckResourcePaths.run()
	print("")
	CheckUnusedScripts.run()
	print("")
	var boot_ok: bool = await CheckMainSceneBoot.run()
	print("")

	var all_passed: bool = scripts_ok and json_ok and resource_paths_ok and boot_ok

	print("=== Summary ===")
	print("Scripts parse:   %s" % ("PASS" if scripts_ok else "FAIL"))
	print("JSON syntax:     %s" % ("PASS" if json_ok else "FAIL"))
	print("Resource paths:  %s" % ("PASS" if resource_paths_ok else "FAIL"))
	print("Main scene boot: %s" % ("PASS" if boot_ok else "FAIL"))
	print("Unused scripts:  informational only, see report above")
	print("Overall:         %s" % ("PASS" if all_passed else "FAIL"))

	quit(0 if all_passed else 1)
