class_name CheckScripts
extends RefCounted
## Parser check: every .gd file under res://scripts, res://tools and
## res://tests must compile. Runs inside the actual project (Autoloads
## registered), unlike `godot --check-only -s`, which reports false
## "Identifier not found" errors for scripts that reference an Autoload.


static func run() -> bool:
	var roots: Array[String] = ["res://scripts", "res://tools", "res://tests"]
	var files: Array[String] = []
	for root_path: String in roots:
		ValidationFsUtils.collect_files_with_extension(root_path, ".gd", files)
	files.sort()

	var all_ok: bool = true
	for path: String in files:
		var script: GDScript = load(path) as GDScript
		var ok: bool = script != null
		if not ok:
			all_ok = false
		print("[CheckScripts] %s -> %s" % [path, "OK" if ok else "PARSE ERROR"])

	print("[CheckScripts] %d script(s) checked, result=%s" % [files.size(), "PASS" if all_ok else "FAIL"])
	return all_ok
