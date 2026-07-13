extends SceneTree
## Headless checks for LevelSelect: every JSON level is listed, locked vs.
## unlocked levels render correctly (a disabled button for locked, an
## enabled one showing stars for unlocked), tapping an unlocked level opens
## GameScreen with the right level id, winning a level unlocks the next one
## and LevelSelect reflects that immediately, and progress survives a
## simulated app restart (SaveManager.load_data() re-reading save.json from
## disk, exactly like a cold launch would).
##
## Real click/tap simulation isn't possible headlessly (see CLAUDE.md) --
## "tapping" a level button calls its private _on_level_button_pressed
## via the button's own pressed signal (Button.emit_signal), and "tapping"
## a passenger calls Passenger._on_pressed() directly, same as every other
## test here.
##
## SaveManager's own real user://save.json is unavoidably touched by this
## test (LevelSelect reads live progress from it) -- this backs up
## whatever's on disk first and restores it afterward, same approach as
## verify_save_manager.gd.
##
## Usage: godot --headless --path . --script res://tests/verify_level_select.gd

const SAVE_PATH: String = "user://save.json"
const MAX_SETTLE_FRAMES: int = 600

var _all_ok: bool = true


func _initialize() -> void:
	var save: Node = root.get_node("SaveManager")

	var had_backup: bool = FileAccess.file_exists(SAVE_PATH)
	var backup_text: String = ""
	if had_backup:
		var backup_file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
		backup_text = backup_file.get_as_text()
		backup_file.close()

	_reset_save(save)

	var packed: PackedScene = load("res://scenes/app/main.tscn")
	var app: Control = packed.instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	await process_frame

	var app_router: Node = root.get_node("AppRouter")

	app_router.push_screen(app_router.Screen.LEVEL_SELECT)
	await process_frame

	var level_select: Control = _current_level_select(app)
	_check(level_select != null, "LevelSelect mounts into %ScreenRoot")
	if level_select == null:
		_finish(save, had_backup, backup_text)
		return

	var list: Control = level_select.get_node("%LevelListContainer")
	_check(list.get_child_count() == 5, "all 5 sample levels are listed")

	var button1: Button = _find_button(list, 1)
	var button2: Button = _find_button(list, 2)
	_check(button1 != null and not button1.disabled, "level 1 (unlocked by default) has an enabled button")
	_check(button2 != null and button2.disabled, "level 2 (locked by default) has a disabled button")

	var status2: Label = _find_status(list, 2)
	_check(status2 != null and status2.text == "level.locked", "level 2's row shows the locked marker, not a star count")

	# Tap level 1's button (the real Button.pressed signal, not a direct
	# method call) -- confirms the actual wiring, not just the handler.
	button1.pressed.emit()
	await process_frame
	await process_frame
	await process_frame

	var screen_root: Control = app.get_node("%ScreenRoot")
	var game_screen: Node = screen_root.get_child(screen_root.get_child_count() - 1) if screen_root.get_child_count() > 0 else null
	_check(game_screen != null, "tapping level 1's button opens GameScreen")
	if game_screen == null:
		_finish(save, had_backup, backup_text)
		return

	var controller: GameController = game_screen.controller
	_check(controller != null and controller.level.id == 1, "GameScreen opened with the correct level id (1)")

	# Play level 1 to a real WON state through the actual queues, the same
	# way verify_game_controller.gd's full-playthrough test does.
	var queue: PassengerQueue = controller._passenger_queues[0]
	_tap_front(queue)
	await _await_settle(controller)
	_tap_front(queue)
	await _await_settle(controller)
	_check(controller.state == GameController.State.WON, "level 1 was actually won through real gameplay")

	_check(save.is_level_unlocked(2), "winning level 1 unlocks level 2 immediately (no restart needed)")

	# Simulate a full app restart: SaveManager re-reads save.json from disk
	# exactly like a cold launch would, and a freshly-rebuilt LevelSelect
	# must still reflect the unlock and the star result.
	save.load_data()
	app_router.push_screen(app_router.Screen.MAIN_MENU)
	await process_frame
	app_router.push_screen(app_router.Screen.LEVEL_SELECT)
	await process_frame

	var level_select_after_restart: Control = _current_level_select(app)
	var list_after: Control = level_select_after_restart.get_node("%LevelListContainer")
	var button2_after: Button = _find_button(list_after, 2)
	var status1_after: Label = _find_status(list_after, 1)

	_check(button2_after != null and not button2_after.disabled, "after a simulated restart, level 2 is still unlocked")
	_check(status1_after != null and status1_after.text == "%d/3" % save.get_stars_for_level(1), "after a simulated restart, level 1 still shows its earned stars")
	_check(save.get_stars_for_level(1) >= 1, "level 1's won result earned at least 1 star")

	app.queue_free()

	_finish(save, had_backup, backup_text)


func _finish(save: Node, had_backup: bool, backup_text: String) -> void:
	if had_backup:
		var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		file.store_string(backup_text)
		file.close()
	else:
		var dir: DirAccess = DirAccess.open("user://")
		if dir != null and FileAccess.file_exists(SAVE_PATH):
			dir.remove(SAVE_PATH.get_file())
	save.load_data()

	print("[LevelSelectTest] RESULT: %s" % ("PASS" if _all_ok else "FAIL"))
	quit(0 if _all_ok else 1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_all_ok = false
	print("[LevelSelectTest] %s -> %s" % [label, "OK" if condition else "FAIL"])


## Resets SaveManager to fresh defaults (level 1 unlocked, nothing
## completed) so this test's assumptions about lock state hold regardless
## of whatever the real on-disk save currently contains.
func _reset_save(save: Node) -> void:
	var dir: DirAccess = DirAccess.open("user://")
	if dir != null and FileAccess.file_exists(SAVE_PATH):
		dir.remove(SAVE_PATH.get_file())
	save.load_data()


func _current_level_select(app: Control) -> Control:
	var screen_root: Control = app.get_node("%ScreenRoot")
	if screen_root.get_child_count() == 0:
		return null
	return screen_root.get_child(screen_root.get_child_count() - 1) as Control


func _find_button(list: Control, level_id: int) -> Button:
	return list.get_node_or_null("LevelRow%d/LevelButton%d" % [level_id, level_id])


func _find_status(list: Control, level_id: int) -> Label:
	return list.get_node_or_null("LevelRow%d/StatusLabel%d" % [level_id, level_id])


func _tap_front(queue: PassengerQueue) -> void:
	var front: Passenger = queue.front()
	if front != null:
		front._on_pressed()


func _await_settle(controller: GameController) -> void:
	for i: int in MAX_SETTLE_FRAMES:
		if controller.state != GameController.State.MOVING_PASSENGER:
			return
		await process_frame
