extends SceneTree
## End-to-end MVP verification: scenarios not already covered by a more
## focused test file elsewhere (see docs/mvp-test-report.md for the full
## scenario-to-test mapping). Boots the real app shell through
## `main.tscn` -> `AppRouter` for every scenario here, same as
## `verify_game_controller.gd`'s "playable via MainMenu" tests, rather
## than exercising `GameController` in isolation.
##
## Real click/tap simulation isn't possible headlessly (see CLAUDE.md) --
## "tapping" a passenger/button calls its private `_on_pressed()` or emits
## its real `pressed` signal directly, same as every other test here.
##
## Usage: godot --headless --path . --script res://tests/verify_mvp_end_to_end.gd

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

	await _test_replay_resets_state()
	await _test_restart_mid_animation_does_not_error()
	await _test_screen_change_mid_animation_does_not_error()
	await _test_next_level_button_progresses()
	await _test_settings_panel_toggles_persist()
	await _test_safe_area_popups_are_inside_safe_area_container()
	await _test_rapid_multi_queue_taps_process_only_one()
	await _test_last_level_completion()

	_restore_backup(save, had_backup, backup_text)

	print("[MvpEndToEndTest] RESULT: %s" % ("PASS" if _all_ok else "FAIL"))
	quit(0 if _all_ok else 1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_all_ok = false
	print("[MvpEndToEndTest] %s -> %s" % [label, "OK" if condition else "FAIL"])


func _reset_save(save: Node) -> void:
	var dir: DirAccess = DirAccess.open("user://")
	if dir != null and FileAccess.file_exists(SAVE_PATH):
		dir.remove(SAVE_PATH.get_file())
	save.load_data()


func _restore_backup(save: Node, had_backup: bool, text: String) -> void:
	if had_backup:
		var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		file.store_string(text)
		file.close()
	else:
		var dir: DirAccess = DirAccess.open("user://")
		if dir != null and FileAccess.file_exists(SAVE_PATH):
			dir.remove(SAVE_PATH.get_file())
	save.load_data()


func _boot_app() -> Control:
	var packed: PackedScene = load("res://scenes/app/main.tscn")
	var app: Control = packed.instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	await process_frame
	return app


func _current_screen(app: Control) -> Node:
	var screen_root: Control = app.get_node("%ScreenRoot")
	if screen_root.get_child_count() == 0:
		return null
	return screen_root.get_child(screen_root.get_child_count() - 1)


func _tap_front(queue: PassengerQueue) -> void:
	var front: Passenger = queue.front()
	if front != null:
		front._on_pressed()


func _await_settle(controller: GameController) -> void:
	for i: int in MAX_SETTLE_FRAMES:
		if controller.state != GameController.State.MOVING_PASSENGER:
			return
		await process_frame


## "Tekrar oynama": after making a real move, pressing Restart puts the
## level back to its exact starting shape -- moves_made back to 0 and the
## first queue's front back to its original color.
func _test_replay_resets_state() -> void:
	var app: Control = await _boot_app()
	var app_router: Node = app.get_node("/root/AppRouter")
	app_router.start_level(1)
	await process_frame
	await process_frame
	await process_frame

	var game_screen: Node = _current_screen(app)
	var controller: GameController = game_screen.controller
	var queue: PassengerQueue = controller._passenger_queues[0]
	var original_front_color: int = queue.front().color

	_tap_front(queue)
	await _await_settle(controller)
	_check(controller.moves_made == 1, "replay: a real move was made before restarting")

	game_screen.get_node("%RestartButton").pressed.emit()
	await process_frame

	_check(controller.moves_made == 0, "replay: Restart resets moves_made to 0")
	_check(controller.state == GameController.State.PLAYING, "replay: Restart returns to PLAYING")
	_check(queue.front().color == original_front_color, "replay: Restart puts the first queue's front back to its original color")

	app.queue_free()


## Regression test for the animation-interrupted-by-restart bug found
## during the MVP audit: mashing Restart while a passenger is still
## flying must not touch the freed pre-restart queue/bus (previously:
## "Invalid call. Nonexistent function 'board_passenger' in base
## 'previously freed'").
func _test_restart_mid_animation_does_not_error() -> void:
	var app: Control = await _boot_app()
	var app_router: Node = app.get_node("/root/AppRouter")
	app_router.start_level(1)
	await process_frame
	await process_frame
	await process_frame

	var game_screen: Node = _current_screen(app)
	var controller: GameController = game_screen.controller
	var queue: PassengerQueue = controller._passenger_queues[0]

	_tap_front(queue)
	await process_frame
	_check(controller.state == GameController.State.MOVING_PASSENGER, "restart-mid-animation: a flight is genuinely in progress")

	game_screen.get_node("%RestartButton").pressed.emit()
	await process_frame
	_check(controller.state == GameController.State.PLAYING, "restart-mid-animation: Restart takes effect immediately")

	# Let the original (now-orphaned) flight's timeout safety net resolve.
	await create_timer(1.0).timeout
	_check(controller.moves_made == 0, "restart-mid-animation: the abandoned move was never counted against the fresh restart")

	app.queue_free()


## Regression test for the animation-interrupted-by-navigation bug found
## during the MVP audit: backing out to the menu while a passenger is
## still flying must not touch the freed GameScreen/queue/bus
## (previously: "Invalid call. Nonexistent function
## 'finish_external_removal' in base 'previously freed'").
func _test_screen_change_mid_animation_does_not_error() -> void:
	var app: Control = await _boot_app()
	var app_router: Node = app.get_node("/root/AppRouter")
	app_router.start_level(2)
	await process_frame
	await process_frame
	await process_frame

	var game_screen: Node = _current_screen(app)
	var controller: GameController = game_screen.controller
	var queue: PassengerQueue = controller._passenger_queues[0]

	_tap_front(queue)
	await process_frame
	_check(controller.state == GameController.State.MOVING_PASSENGER, "screen-change-mid-animation: a flight is genuinely in progress")

	app_router.push_screen(app_router.Screen.MAIN_MENU)
	await process_frame
	_check(_current_screen(app).name == "MainMenu", "screen-change-mid-animation: navigation away succeeds immediately")

	# Let the orphaned flight's timeout safety net resolve; this must not
	# print a script error (checked by tools/validate.sh's crash/error
	# detection over this test's own log, same as every other check).
	await create_timer(1.0).timeout
	_check(true, "screen-change-mid-animation: the orphaned flight settled without touching a freed node")

	app.queue_free()


## "Sonraki bölüm": winning level 1 and tapping the Win popup's "next
## level" button actually opens GameScreen for level 2, not just that
## SaveManager records the unlock (already covered by
## verify_level_select.gd).
func _test_next_level_button_progresses() -> void:
	var app: Control = await _boot_app()
	var app_router: Node = app.get_node("/root/AppRouter")
	app_router.start_level(1)
	await process_frame
	await process_frame
	await process_frame

	var game_screen: Node = _current_screen(app)
	var controller: GameController = game_screen.controller
	var queue: PassengerQueue = controller._passenger_queues[0]
	for i: int in 4:  # level 1 is [red,red,blue,blue] vs red(2)/blue(2) -- 4 taps to win
		_tap_front(queue)
		await _await_settle(controller)
	_check(controller.state == GameController.State.WON, "next-level: level 1 was actually won")

	game_screen.get_node("%WinNextButton").pressed.emit()
	await process_frame
	await process_frame
	await process_frame

	var next_screen: Node = _current_screen(app)
	_check(next_screen != null and next_screen.controller != null, "next-level: a new GameScreen mounted after tapping Win Next")
	if next_screen != null and next_screen.controller != null:
		_check(next_screen.controller.level.id == 2, "next-level: the new GameScreen is actually level 2")

	app.queue_free()


## "Ses ayarı" / "Titreşim ayarı": the Settings screen's toggles actually
## read and write SaveManager's real flags, through the real UI signal,
## not a direct method call.
func _test_settings_panel_toggles_persist() -> void:
	var app: Control = await _boot_app()
	var app_router: Node = app.get_node("/root/AppRouter")
	var save: Node = root.get_node("SaveManager")

	app_router.push_screen(app_router.Screen.SETTINGS)
	await process_frame

	var settings_screen: Node = _current_screen(app)
	var sound_toggle: CheckButton = settings_screen.get_node("%SoundToggle")
	var vibration_toggle: CheckButton = settings_screen.get_node("%VibrationToggle")

	_check(sound_toggle.button_pressed == save.is_sound_enabled(), "settings: sound toggle reflects the real saved state on open")
	_check(vibration_toggle.button_pressed == save.is_vibration_enabled(), "settings: vibration toggle reflects the real saved state on open")

	sound_toggle.toggled.emit(false)
	_check(not save.is_sound_enabled(), "settings: turning the sound toggle off updates SaveManager")
	vibration_toggle.toggled.emit(false)
	_check(not save.is_vibration_enabled(), "settings: turning the vibration toggle off updates SaveManager")

	save.load_data()
	_check(not save.is_sound_enabled(), "settings: sound=off survives a reload (real persistence, not just in-memory)")
	_check(not save.is_vibration_enabled(), "settings: vibration=off survives a reload")

	sound_toggle.toggled.emit(true)
	vibration_toggle.toggled.emit(true)

	app.queue_free()


## "iOS safe area": structural regression guard for the Milestone 15 bug
## (WinPopup/LosePopup rendering outside %SafeArea's margins) -- both
## popups must be actual descendants of %SafeArea, not siblings of it.
func _test_safe_area_popups_are_inside_safe_area_container() -> void:
	var app: Control = await _boot_app()
	var app_router: Node = app.get_node("/root/AppRouter")
	app_router.start_level(1)
	await process_frame
	await process_frame
	await process_frame

	var game_screen: Node = _current_screen(app)
	var safe_area: Control = game_screen.get_node("%SafeArea")
	var win_popup: Control = game_screen.get_node("%WinPopup")
	var lose_popup: Control = game_screen.get_node("%LosePopup")

	_check(safe_area.is_ancestor_of(win_popup), "safe-area: WinPopup is a descendant of %SafeArea, not a sibling")
	_check(safe_area.is_ancestor_of(lose_popup), "safe-area: LosePopup is a descendant of %SafeArea, not a sibling")

	app.queue_free()


## "Hızlı art arda dokunma": tapping two *different* queues' fronts back
## to back, in the same frame (no await between them), must only ever
## process one move -- the second tap has to see MOVING_PASSENGER (set
## synchronously by the first, before either await) and bail out, exactly
## like the same-passenger double-tap case verify_game_controller.gd
## already covers.
func _test_rapid_multi_queue_taps_process_only_one() -> void:
	var app: Control = await _boot_app()
	var app_router: Node = app.get_node("/root/AppRouter")
	app_router.start_level(2)  # 2 queues
	await process_frame
	await process_frame
	await process_frame

	var game_screen: Node = _current_screen(app)
	var controller: GameController = game_screen.controller
	var queue_a: PassengerQueue = controller._passenger_queues[0]
	var queue_b: PassengerQueue = controller._passenger_queues[1]
	var b_front_color_before: int = queue_b.front().color

	_tap_front(queue_a)
	_tap_front(queue_b)  # synchronous, same frame -- no await in between
	await _await_settle(controller)

	_check(controller.moves_made == 1, "rapid-multi-tap: only one of the two synchronous taps was processed")
	_check(queue_b.front() != null and queue_b.front().color == b_front_color_before, "rapid-multi-tap: the second queue's front passenger is untouched")

	app.queue_free()


## "Son bölüm tamamlama": a full, real playthrough of level 20 (the
## hardest/last shipped level) to an actual WON state, using
## LevelSolver.find_winning_moves() to derive the tap sequence rather
## than hand-deriving it -- this level has a tight waiting area (2 slots)
## where a wrong move order can genuinely deadlock the game.
func _test_last_level_completion() -> void:
	var result: LevelLoadResult = LevelRepository.load_level_by_id(20)
	if not result.is_success():
		_check(false, "last-level: level 20 loads")
		return

	var moves: Array[int] = LevelSolver.find_winning_moves(result.level)
	_check(not moves.is_empty(), "last-level: LevelSolver found a winning move sequence for level 20")
	if moves.is_empty():
		return

	var app: Control = await _boot_app()
	var app_router: Node = app.get_node("/root/AppRouter")
	app_router.start_level(20)
	await process_frame
	await process_frame
	await process_frame

	var game_screen: Node = _current_screen(app)
	var controller: GameController = game_screen.controller
	_check(controller.level.id == 20, "last-level: GameScreen opened level 20")

	for queue_index: int in moves:
		if controller.state == GameController.State.WON:
			break
		_tap_front(controller._passenger_queues[queue_index])
		await _await_settle(controller)

	_check(controller.state == GameController.State.WON, "last-level: level 20 was actually won end to end")

	app.queue_free()
