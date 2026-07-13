extends SceneTree
## Headless checks for the JSON-based level system: LevelLoader,
## LevelValidator, and LevelRepository. Writes temporary broken level files
## under user:// (never touches the real data/levels/ files) to exercise
## each rejection path, then cleans them up.
##
## Usage: godot --headless --path . --script res://tests/verify_level_loading.gd

const TEMP_DIR: String = "user://test_levels"

var _all_ok: bool = true


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(TEMP_DIR)

	_test_valid_level_loads()
	_test_missing_field_rejected()
	_test_invalid_color_rejected()
	_test_capacity_mismatch_rejected()
	_test_nonexistent_file_controlled_error()
	_test_first_five_levels_are_valid()

	_cleanup_temp_dir()

	print("[LevelLoadingTest] RESULT: %s" % ("PASS" if _all_ok else "FAIL"))
	quit(0 if _all_ok else 1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_all_ok = false
	print("[LevelLoadingTest] %s -> %s" % [label, "OK" if condition else "FAIL"])


func _valid_level_dict() -> Dictionary:
	return {
		"id": 1001,
		"name_key": "level.test.name",
		"waiting_slot_count": 3,
		"tutorial": false,
		"difficulty": 1,
		"move_limit": 10,
		"buses": [
			{"color": "red", "capacity": 2},
		],
		"passenger_queues": [
			[{"color": "red"}, {"color": "red"}],
		],
	}


func _write_temp_level(filename: String, data: Dictionary) -> String:
	var path: String = TEMP_DIR.path_join(filename)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	return path


func _test_valid_level_loads() -> void:
	var path: String = _write_temp_level("valid.json", _valid_level_dict())
	var result: LevelLoadResult = LevelLoader.load_level(path)

	_check(result.is_success(), "a valid level loads successfully")
	_check(result.level != null and result.level.id == 1001, "the loaded LevelData has the right id")
	_check(result.errors.is_empty(), "a valid level produces no errors")


func _test_missing_field_rejected() -> void:
	var data: Dictionary = _valid_level_dict()
	data.erase("move_limit")
	var path: String = _write_temp_level("missing_field.json", data)
	var result: LevelLoadResult = LevelLoader.load_level(path)

	_check(not result.is_success(), "a level missing a required field is rejected")
	_check(result.level == null, "no LevelData is produced for a rejected level")

	var mentions_field: bool = false
	var mentions_file: bool = false
	for error: String in result.errors:
		if error.contains("move_limit"):
			mentions_field = true
		if error.contains(path):
			mentions_file = true
	_check(mentions_field, "the error mentions the missing field path (move_limit)")
	_check(mentions_file, "the error mentions the source file")


func _test_invalid_color_rejected() -> void:
	var data: Dictionary = _valid_level_dict()
	data["buses"] = [{"color": "not_a_real_color", "capacity": 2}]
	var path: String = _write_temp_level("invalid_color.json", data)
	var result: LevelLoadResult = LevelLoader.load_level(path)

	_check(not result.is_success(), "an unknown color is rejected")

	var mentions_color: bool = false
	for error: String in result.errors:
		if error.contains("unknown color"):
			mentions_color = true
	_check(mentions_color, "the error explains the color is unknown")


func _test_capacity_mismatch_rejected() -> void:
	var data: Dictionary = _valid_level_dict()
	data["buses"] = [{"color": "red", "capacity": 5}]  # passengers still total 2
	var path: String = _write_temp_level("capacity_mismatch.json", data)
	var result: LevelLoadResult = LevelLoader.load_level(path)

	_check(not result.is_success(), "a total-passenger/total-capacity mismatch is rejected")

	var mentions_mismatch: bool = false
	for error: String in result.errors:
		if error.contains("does not match"):
			mentions_mismatch = true
	_check(mentions_mismatch, "the error explains the capacity mismatch")


func _test_nonexistent_file_controlled_error() -> void:
	var result: LevelLoadResult = LevelLoader.load_level(TEMP_DIR.path_join("does_not_exist.json"))

	_check(not result.is_success(), "loading a nonexistent file fails gracefully")
	_check(result.level == null, "no LevelData for a missing file")
	_check(not result.errors.is_empty(), "a missing file produces a descriptive error, not a crash")


func _test_first_five_levels_are_valid() -> void:
	var results: Array[LevelLoadResult] = LevelRepository.load_all_levels()
	_check(results.size() == 5, "exactly 5 sample levels are found under data/levels/")

	var seen_ids: Array[int] = []
	var seen_difficulties: Array[int] = []
	for result: LevelLoadResult in results:
		if not result.is_success():
			for error: String in result.errors:
				print("[LevelLoadingTest]   sample level error: %s" % error)
		_check(result.is_success(), "sample level loads and validates")
		if result.level != null:
			seen_ids.append(result.level.id)
			seen_difficulties.append(result.level.difficulty)

	_check(seen_ids == [1, 2, 3, 4, 5], "sample level ids are 1 through 5 in order")
	_check(seen_difficulties == [1, 2, 3, 4, 5], "sample levels increase in difficulty from easy to hard")
	if not results.is_empty() and results[0].level != null:
		_check(results[0].level.tutorial, "level 1 is the tutorial level")


func _cleanup_temp_dir() -> void:
	var dir: DirAccess = DirAccess.open(TEMP_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not dir.current_is_dir():
			dir.remove(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(TEMP_DIR)
