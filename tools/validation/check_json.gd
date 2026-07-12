class_name CheckJson
extends RefCounted
## Syntax check for every .json file under res://data. A project with zero
## JSON files (no levels authored yet) passes trivially.


static func run() -> bool:
	var files: Array[String] = []
	ValidationFsUtils.collect_files_with_extension("res://data", ".json", files)
	files.sort()

	var all_ok: bool = true
	for path: String in files:
		if not _check_file(path):
			all_ok = false

	print("[CheckJson] %d file(s) checked, result=%s" % [files.size(), "PASS" if all_ok else "FAIL"])
	return all_ok


static func _check_file(path: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		print("[CheckJson] %s -> FAIL (cannot open, error %d)" % [path, FileAccess.get_open_error()])
		return false

	var text: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	var error: Error = json.parse(text)
	if error != OK:
		print("[CheckJson] %s -> FAIL (line %d: %s)" % [path, json.get_error_line(), json.get_error_message()])
		return false

	print("[CheckJson] %s -> OK" % path)
	return true
