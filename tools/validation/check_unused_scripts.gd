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

	var script_texts: Dictionary = {}
	for file_path: String in scan_files:
		var text: String = CheckResourcePaths._read_stripped(file_path)
		script_texts[file_path] = text
		for match_result: RegExMatch in regex.search_all(text):
			referenced[match_result.get_string()] = true

	_collect_class_name_references(script_texts, referenced)

	return referenced


## A script referenced only through its global `class_name` (no res://
## literal anywhere, e.g. `PassengerColor.from_string(...)`) would
## otherwise be flagged unused. For every .gd file that declares a
## class_name, check whether that identifier appears as a whole word in
## any *other* scanned file's text; if so, treat the declaring path as
## referenced.
static func _collect_class_name_references(script_texts: Dictionary, referenced: Dictionary) -> void:
	var class_name_regex: RegEx = RegEx.new()
	class_name_regex.compile("(?m)^class_name\\s+(\\w+)")

	var gd_paths: Array[String] = []
	for path: String in script_texts:
		if path.ends_with(".gd"):
			gd_paths.append(path)

	for path: String in gd_paths:
		var declaration: RegExMatch = class_name_regex.search(script_texts[path])
		if declaration == null:
			continue
		var class_id: String = declaration.get_string(1)
		var usage_regex: RegEx = RegEx.new()
		usage_regex.compile("\\b%s\\b" % class_id)

		for other_path: String in gd_paths:
			if other_path == path:
				continue
			if usage_regex.search(script_texts[other_path]) != null:
				referenced[path] = true
				break
