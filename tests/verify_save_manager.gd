extends SceneTree
## Headless checks for SaveManager: first-launch defaults, a save/reload
## round trip, a corrupt save file not crashing (and self-healing to fresh
## defaults), level unlocking, never downgrading a level's best star
## result on a worse replay, and settings (music/sound/vibration)
## persistence.
##
## This is the --script entry point, compiled before Autoloads exist as
## global identifiers (see CLAUDE.md) -- SaveManager is looked up via
## /root/SaveManager rather than the bare global name, same pattern
## verify_navigation.gd already uses for AppRouter.
##
## SaveManager's own real user://save.json is unavoidably what's under
## test here (there's no separate "test" path for the thing that owns
## SAVE_PATH) -- this backs up whatever's on disk before mutating it and
## restores it afterward, so running this test never permanently loses a
## developer's real local save.
##
## Usage: godot --headless --path . --script res://tests/verify_save_manager.gd

const SAVE_PATH: String = "user://save.json"

var _all_ok: bool = true


func _initialize() -> void:
	var save: Node = root.get_node("SaveManager")

	var had_backup: bool = FileAccess.file_exists(SAVE_PATH)
	var backup_text: String = ""
	if had_backup:
		var backup_file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
		backup_text = backup_file.get_as_text()
		backup_file.close()

	_test_first_launch_defaults(save)
	_test_save_and_reload(save)
	_test_corrupt_save_file(save)
	_test_level_unlocking(save)
	_test_never_downgrades_stars(save)
	_test_settings_persist(save)

	_restore_backup(had_backup, backup_text)
	save.load_data()

	print("[SaveManagerTest] RESULT: %s" % ("PASS" if _all_ok else "FAIL"))
	quit(0 if _all_ok else 1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_all_ok = false
	print("[SaveManagerTest] %s -> %s" % [label, "OK" if condition else "FAIL"])


func _delete_save_file() -> void:
	var dir: DirAccess = DirAccess.open("user://")
	if dir == null:
		return
	if FileAccess.file_exists(SAVE_PATH):
		dir.remove(SAVE_PATH.get_file())
	var tmp_path: String = SAVE_PATH + ".tmp"
	if FileAccess.file_exists(tmp_path):
		dir.remove(tmp_path.get_file())


func _restore_backup(had_backup: bool, text: String) -> void:
	if had_backup:
		var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		file.store_string(text)
		file.close()
	else:
		_delete_save_file()


func _test_first_launch_defaults(save: Node) -> void:
	_delete_save_file()
	save.load_data()

	_check(save.is_first_launch(), "no save file: is_first_launch() is true")
	_check(save.get_highest_unlocked_level() == 1, "no save file: level 1 is unlocked by default")
	_check(save.get_stars_for_level(1) == 0, "no save file: level 1 has no stars yet")
	_check(not save.is_level_completed(1), "no save file: level 1 isn't completed yet")
	_check(save.is_music_enabled(), "no save file: music defaults on")
	_check(save.is_sound_enabled(), "no save file: sound defaults on")
	_check(save.is_vibration_enabled(), "no save file: vibration defaults on")
	_check(save.get_last_played_level() == 0, "no save file: no last-played level yet")
	_check(FileAccess.file_exists(SAVE_PATH), "a default save file is written to disk on first launch")


func _test_save_and_reload(save: Node) -> void:
	_delete_save_file()
	save.load_data()

	save.record_level_result(1, 3)
	save.set_last_played_level(2)
	save.mark_first_launch_complete()

	# Simulate the app closing and reopening: reload from disk into the
	# same running singleton and confirm every field actually round-tripped
	# through save.json, not just held in memory.
	save.load_data()

	_check(save.get_stars_for_level(1) == 3, "reload: level 1's stars survive a save/reload cycle")
	_check(save.get_highest_unlocked_level() == 2, "reload: unlocking level 2 survives a save/reload cycle")
	_check(save.is_level_completed(1), "reload: level 1's completed flag survives a save/reload cycle")
	_check(save.get_last_played_level() == 2, "reload: last-played level survives a save/reload cycle")
	_check(not save.is_first_launch(), "reload: first-launch-completed survives a save/reload cycle")


func _test_corrupt_save_file(save: Node) -> void:
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string("{ this is not valid JSON at all !!")
	file.close()

	var loaded: bool = save.load_data()

	_check(not loaded, "load_data() reports failure for a corrupt save file")
	_check(save.get_highest_unlocked_level() == 1, "a corrupt save file falls back to fresh defaults, not a crash")
	_check(save.is_first_launch(), "a corrupt save file's fallback defaults count as first-launch again")

	# It must also have self-healed the file on disk, not left the garbage
	# there to break the next launch too.
	var reread: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	var text: String = reread.get_as_text() if reread != null else ""
	if reread != null:
		reread.close()
	var json: JSON = JSON.new()
	_check(json.parse(text) == OK, "the corrupt file is overwritten with valid JSON defaults, not left broken")


func _test_level_unlocking(save: Node) -> void:
	_delete_save_file()
	save.load_data()

	_check(save.is_level_unlocked(1), "level 1 is unlocked from a fresh save")
	_check(not save.is_level_unlocked(2), "level 2 is not yet unlocked from a fresh save")

	save.record_level_result(1, 2)

	_check(save.is_level_unlocked(2), "winning level 1 unlocks level 2")
	_check(not save.is_level_unlocked(3), "winning level 1 does not unlock level 3")
	_check(save.get_stars_for_level(1) == 2, "winning level 1 records its star count")


func _test_never_downgrades_stars(save: Node) -> void:
	_delete_save_file()
	save.load_data()

	save.record_level_result(1, 3)
	save.record_level_result(1, 1)

	_check(save.get_stars_for_level(1) == 3, "a worse replay (1 star) never downgrades an earlier 3-star result")

	save.record_level_result(1, 2)
	_check(save.get_stars_for_level(1) == 3, "a middling replay (2 stars) still never downgrades an earlier 3-star result")


func _test_settings_persist(save: Node) -> void:
	_delete_save_file()
	save.load_data()

	save.set_music_enabled(false)
	save.set_sound_enabled(false)
	save.set_vibration_enabled(false)
	save.load_data()

	_check(not save.is_music_enabled(), "music_enabled=false survives a reload")
	_check(not save.is_sound_enabled(), "sound_enabled=false survives a reload")
	_check(not save.is_vibration_enabled(), "vibration_enabled=false survives a reload")

	save.set_music_enabled(true)
	save.set_sound_enabled(true)
	save.set_vibration_enabled(true)
	save.load_data()

	_check(save.is_music_enabled(), "music_enabled=true survives a reload")
	_check(save.is_sound_enabled(), "sound_enabled=true survives a reload")
	_check(save.is_vibration_enabled(), "vibration_enabled=true survives a reload")
