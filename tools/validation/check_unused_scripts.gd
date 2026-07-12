class_name CheckUnusedScripts
extends RefCounted
## Informational-only report of .gd files under res://scripts that don't
## appear to be referenced by any scene, Autoload, or other script. Does
## NOT gate the validation result -- a script can be legitimately unused
## mid-development. Read the report and decide.


static func run() -> void:
	var all_scripts: Array[String] = []
	ValidationFsUtils.collect_files_with_extension("res://scripts", ".gd", all_scripts)
	all_scripts.sort()

	var referenced: Dictionary = _collect_referenced_paths()

	var unused: Array[String] = []
	for path: String in all_scripts:
		if not referenced.has(path):
			unused.append(path)

	if unused.is_empty():
		print("[CheckUnusedScripts] all %d script(s) under res://scripts are referenced" % all_scripts.size())
	else:
		for path: String in unused:
			print("[CheckUnusedScripts] possibly unused: %s" % path)
		print("[CheckUnusedScripts] %d of %d script(s) look unused (informational only)" % [
			unused.size(), all_scripts.size()
		])


static func _collect_referenced_paths() -> Dictionary:
	var referenced: Dictionary = {}

	for prop: Dictionary in ProjectSettings.get_property_list():
		var prop_name: String = prop["name"]
		if prop_name.begins_with("autoload/"):
			var value: String = str(ProjectSettings.get_setting(prop_name))
			referenced[value.trim_prefix("*")] = true

	var regex: RegEx = RegEx.new()
	regex.compile(CheckResourcePaths.PATH_PATTERN)

	var scan_files: Array[String] = []
	ValidationFsUtils.collect_files_with_extensions("res://", [".tscn", ".tres", ".gd"], scan_files)
	for file_path: String in scan_files:
		var text: String = CheckResourcePaths._read_stripped(file_path)
		for match_result: RegExMatch in regex.search_all(text):
			referenced[match_result.get_string()] = true

	return referenced
