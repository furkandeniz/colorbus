class_name LevelLoader
extends RefCounted
## Loads and validates a single level JSON file. Never crashes the game on
## a broken level -- a missing file, invalid JSON, or a level that fails
## LevelValidator all produce a LevelLoadResult with a descriptive error
## instead of throwing/propagating an exception. A raw JSON Dictionary is
## never hand-waved into a LevelData (let alone a game scene) unless it
## passes LevelValidator first.


static func load_level(path: String) -> LevelLoadResult:
	var result: LevelLoadResult = LevelLoadResult.new()

	if not FileAccess.file_exists(path):
		result.errors.append("%s: file does not exist" % path)
		return result

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		result.errors.append("%s: could not open file (error %d)" % [path, FileAccess.get_open_error()])
		return result

	var text: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		result.errors.append("%s: invalid JSON (line %d: %s)" % [path, json.get_error_line(), json.get_error_message()])
		return result

	var parsed: Variant = json.get_data()
	if typeof(parsed) != TYPE_DICTIONARY:
		result.errors.append("%s: JSON root must be an object" % path)
		return result

	var validation: LevelValidationResult = LevelValidator.validate(parsed, path)
	if not validation.is_valid():
		result.errors.append_array(validation.errors)
		return result

	result.level = LevelData.from_dict(parsed)
	return result
