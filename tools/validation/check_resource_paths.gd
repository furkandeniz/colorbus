class_name CheckResourcePaths
extends RefCounted
## Scans every .tscn/.tres/.gd file for res:// references (ext_resource
## paths, preload()/load() calls) and confirms each one actually resolves,
## catching broken links left behind by renamed/moved/deleted files.

const SCAN_EXTENSIONS: Array[String] = [".tscn", ".tres", ".gd"]
const PATH_PATTERN: String = "res://[A-Za-z0-9_./\\-]+"


static func run() -> bool:
	var files: Array[String] = []
	ValidationFsUtils.collect_files_with_extensions("res://", SCAN_EXTENSIONS, files)
	files.sort()

	var regex: RegEx = RegEx.new()
	regex.compile(PATH_PATTERN)

	var all_ok: bool = true
	var checked_count: int = 0
	var seen: Dictionary = {}

	for file_path: String in files:
		if file_path.begins_with("res://.godot/"):
			continue
		var text: String = _read_stripped(file_path)
		for match_result: RegExMatch in regex.search_all(text):
			var resource_path: String = match_result.get_string()
			checked_count += 1
			var key: String = "%s|%s" % [file_path, resource_path]
			if seen.has(key):
				continue
			seen[key] = true

			if not _reference_exists(resource_path):
				all_ok = false
				print("[CheckResourcePaths] BROKEN: %s references missing %s" % [file_path, resource_path])

	print("[CheckResourcePaths] %d reference(s) checked across %d file(s), result=%s" % [
		checked_count, files.size(), "PASS" if all_ok else "FAIL"
	])
	return all_ok


## A res:// reference is valid if it resolves to either a loadable resource
## file or an existing directory (some code/tooling references res://
## directories directly, e.g. for scanning).
static func _reference_exists(resource_path: String) -> bool:
	return ResourceLoader.exists(resource_path) or DirAccess.dir_exists_absolute(resource_path)


## Reads a file as text, stripping full-line GDScript comments so that
## example paths mentioned in doc comments don't produce false positives.
static func _read_stripped(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var lines: PackedStringArray = []
	while not file.eof_reached():
		var line: String = file.get_line()
		if not line.strip_edges().begins_with("#"):
			lines.append(line)
	file.close()
	return "\n".join(lines)
