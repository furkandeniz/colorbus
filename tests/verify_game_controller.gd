extends SceneTree
## Integration tests for GameController + GameRules, wired to real Bus/
## BusQueue/WaitingArea/PassengerQueue scenes (never mocks), plus an
## end-to-end check that all 20 MVP levels are actually reachable and
## playable through the real app navigation stack (main.tscn -> MainMenu
## -> AppRouter.start_level() -> GameScreen), proving "playable via
## MainMenu" rather than just asserting GameController in isolation.
##
## Real click/tap simulation isn't possible headlessly (see
## docs/ARCHITECTURE.md) -- "tapping" a passenger calls its private
## _on_pressed() directly, same pattern as every other test here.
##
## Every move now runs a real, awaited GameAnimator flight rather than an
## instant fade, so tests wait for GameController.state to actually leave
## MOVING_PASSENGER (_await_settle()) instead of a guessed fixed delay --
## robust regardless of how long any single animation actually takes.
##
## Usage: godot --headless --path . --script res://tests/verify_game_controller.gd

## Safety ceiling for _await_settle() below -- real gameplay animations
## never take this long; it only exists so a genuine bug (state stuck in
## MOVING_PASSENGER) fails the test instead of hanging the runner forever.
const MAX_SETTLE_FRAMES: int = 600

var _all_ok: bool = true


func _initialize() -> void:
	await _test_level_one_full_playthrough_wins()
	await _test_mismatched_color_routes_to_waiting_area()
	await _test_auto_board_on_active_bus_change_can_win()
	await _test_rejected_move_does_not_end_game_if_move_exists_elsewhere()
	await _test_successful_move_can_trigger_deadlock_loss()
	await _test_cannot_process_same_passenger_twice()
	await _test_all_five_levels_playable_via_app()

	print("[GameControllerTest] RESULT: %s" % ("PASS" if _all_ok else "FAIL"))
	quit(0 if _all_ok else 1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_all_ok = false
	print("[GameControllerTest] %s -> %s" % [label, "OK" if condition else "FAIL"])


## Builds fresh, empty BusQueue/WaitingArea/PassengerQueue/AnimationLayer
## view nodes (one queue per level.passenger_queues entry) and a
## GameController wired to them, mirroring exactly what GameScreen does --
## without going through the screen/AppRouter navigation stack, so
## scenarios can be constructed directly.
func _make_game(level: LevelData) -> Dictionary:
	var bus_queue: BusQueue = load("res://scenes/game/bus_queue.tscn").instantiate()
	root.add_child(bus_queue)

	var waiting_area: WaitingArea = load("res://scenes/game/waiting_area.tscn").instantiate()
	root.add_child(waiting_area)

	var passenger_queues: Array[PassengerQueue] = []
	for i: int in level.passenger_queues.size():
		var queue: PassengerQueue = load("res://scenes/game/passenger_queue.tscn").instantiate()
		root.add_child(queue)
		passenger_queues.append(queue)

	var animation_layer: Control = Control.new()
	root.add_child(animation_layer)

	await process_frame

	var animator: GameAnimator = GameAnimator.new(animation_layer)
	var controller: GameController = GameController.new(level, bus_queue, waiting_area, passenger_queues, animator)
	controller.start()
	await process_frame

	return {
		"controller": controller,
		"bus_queue": bus_queue,
		"waiting_area": waiting_area,
		"passenger_queues": passenger_queues,
		"animation_layer": animation_layer,
	}


func _free_game(game: Dictionary) -> void:
	game["bus_queue"].queue_free()
	game["waiting_area"].queue_free()
	for queue: PassengerQueue in game["passenger_queues"]:
		queue.queue_free()
	game["animation_layer"].queue_free()


func _tap_front(queue: PassengerQueue) -> void:
	var front: Passenger = queue.front()
	if front != null:
		front._on_pressed()


## Waits until controller has left MOVING_PASSENGER (a move plus any
## auto-board cascade it triggers has fully resolved), rather than a
## guessed fixed delay -- exactly the invariant this task requires: no
## assertion about post-move state runs before the animation actually
## finishes. Bounded by MAX_SETTLE_FRAMES so a genuine stuck-state bug
## fails the test instead of hanging the runner.
func _await_settle(controller: GameController) -> void:
	for i: int in MAX_SETTLE_FRAMES:
		if controller.state != GameController.State.MOVING_PASSENGER:
			return
		await process_frame


## Level 1 is [red, red, blue, blue] in a single queue against buses
## red(2) then blue(2) -- a perfectly linear tutorial with zero waiting-area
## use required: tap 4 times, red completes and blue becomes active exactly
## when the queue's colors switch, then blue completes on the 4th tap.
func _test_level_one_full_playthrough_wins() -> void:
	var result: LevelLoadResult = LevelRepository.load_level_by_id(1)
	_check(result.is_success(), "level 1 loads for the full-playthrough test")
	if not result.is_success():
		return

	var game: Dictionary = await _make_game(result.level)
	var controller: GameController = game["controller"]
	var bus_queue: BusQueue = game["bus_queue"]
	var queue: PassengerQueue = game["passenger_queues"][0]

	_check(controller.state == GameController.State.PLAYING, "level 1: GameController reaches PLAYING after start()")
	_check(bus_queue.active_bus().color == PassengerColor.Value.RED, "level 1: the active bus is red")

	_tap_front(queue)
	await _await_settle(controller)
	_check(bus_queue.active_bus().color == PassengerColor.Value.RED, "level 1: still on the red bus after the 1st move")
	_check(bus_queue.active_bus().current_passengers == 1, "level 1: 1st matching passenger boards the active bus")
	_check(controller.state == GameController.State.PLAYING, "level 1: back to PLAYING after the 1st move")

	_tap_front(queue)
	await _await_settle(controller)
	_check(bus_queue.active_bus().color == PassengerColor.Value.BLUE, "level 1: the red bus filling up advances to the blue bus")
	_check(controller.state == GameController.State.PLAYING, "level 1: still playing once the queue moves on to blue")

	_tap_front(queue)
	await _await_settle(controller)
	_check(bus_queue.active_bus().current_passengers == 1, "level 1: 3rd move boards the first blue passenger")

	_tap_front(queue)
	await _await_settle(controller)
	_check(controller.state == GameController.State.WON, "level 1: the level is won once the blue bus fills up too")
	_check(controller.moves_made == 4, "level 1: exactly 4 moves were counted")

	_free_game(game)


func _test_mismatched_color_routes_to_waiting_area() -> void:
	var data: Dictionary = {
		"id": 5001, "name_key": "x", "waiting_slot_count": 3,
		"tutorial": false, "difficulty": 1, "move_limit": 10,
		"buses": [{"color": "blue", "capacity": 1}],
		# A second (blue) queue keeps a legal move available after routing
		# the first (red) passenger to the waiting area -- otherwise the
		# blue bus could never be satisfied at all and this would be a
		# genuine (and correctly detected) deadlock, not what this test
		# means to check.
		"passenger_queues": [[{"color": "red"}], [{"color": "blue"}]],
	}
	var level: LevelData = LevelData.from_dict(data)
	var game: Dictionary = await _make_game(level)
	var controller: GameController = game["controller"]
	var bus_queue: BusQueue = game["bus_queue"]
	var waiting_area: WaitingArea = game["waiting_area"]
	var queue: PassengerQueue = game["passenger_queues"][0]

	_tap_front(queue)
	await _await_settle(controller)

	_check(bus_queue.active_bus().current_passengers == 0, "mismatched color never boards the active bus")
	_check(waiting_area.get_slot_color(0) == PassengerColor.Value.RED, "mismatched passenger is routed to the waiting area instead")
	_check(controller.state == GameController.State.PLAYING, "still playing after routing to the waiting area")

	_free_game(game)


func _test_auto_board_on_active_bus_change_can_win() -> void:
	var data: Dictionary = {
		"id": 5002, "name_key": "x", "waiting_slot_count": 3,
		"tutorial": false, "difficulty": 1, "move_limit": 10,
		"buses": [{"color": "red", "capacity": 1}, {"color": "blue", "capacity": 1}],
		"passenger_queues": [[{"color": "blue"}, {"color": "red"}]],
	}
	var level: LevelData = LevelData.from_dict(data)
	var game: Dictionary = await _make_game(level)
	var controller: GameController = game["controller"]
	var bus_queue: BusQueue = game["bus_queue"]
	var waiting_area: WaitingArea = game["waiting_area"]
	var queue: PassengerQueue = game["passenger_queues"][0]

	# Blue doesn't match the active red bus -- goes to the waiting area.
	_tap_front(queue)
	await _await_settle(controller)
	_check(waiting_area.get_slot_color(0) == PassengerColor.Value.BLUE, "blue passenger waits for its bus")

	# Red matches and completes the red bus, advancing to the blue bus --
	# the awaited auto-board cascade should then fly the waiting blue
	# passenger onto it, complete it too, and win the level, all before
	# _await_settle() returns.
	_tap_front(queue)
	await _await_settle(controller)

	_check(waiting_area.is_empty(), "the waiting blue passenger was auto-boarded once the blue bus became active")
	_check(controller.state == GameController.State.WON, "auto-boarding the last passenger wins the level")

	_free_game(game)


func _test_rejected_move_does_not_end_game_if_move_exists_elsewhere() -> void:
	var data: Dictionary = {
		"id": 5003, "name_key": "x", "waiting_slot_count": 1,
		"tutorial": false, "difficulty": 1, "move_limit": 10,
		"buses": [{"color": "red", "capacity": 1}],
		"passenger_queues": [[{"color": "blue"}], [{"color": "red"}]],
	}
	var level: LevelData = LevelData.from_dict(data)
	var game: Dictionary = await _make_game(level)
	var controller: GameController = game["controller"]
	var bus_queue: BusQueue = game["bus_queue"]
	var waiting_area: WaitingArea = game["waiting_area"]
	var queues: Array[PassengerQueue] = game["passenger_queues"]

	# Fill the single waiting slot directly (test setup, not a player
	# move) so the next mismatched tap has nowhere to go.
	waiting_area.add_passenger(PassengerColor.Value.GREEN)
	_check(waiting_area.is_full(), "waiting area is full (test setup)")

	_tap_front(queues[0])  # blue: mismatched, and the waiting area is full
	await _await_settle(controller)

	_check(controller.state == GameController.State.PLAYING, "a rejected move doesn't end the game while queue 2's red still matches")
	_check(queues[0].passenger_count() == 1, "the rejected passenger is still in its queue")
	_check(controller.moves_made == 0, "a rejected move doesn't count as a move")

	_tap_front(queues[1])  # red: matches, completes the only bus -> win
	await _await_settle(controller)
	_check(controller.state == GameController.State.WON, "the level can still be won after an earlier rejected move")

	_free_game(game)


func _test_successful_move_can_trigger_deadlock_loss() -> void:
	var data: Dictionary = {
		"id": 5004, "name_key": "x", "waiting_slot_count": 1,
		"tutorial": false, "difficulty": 1, "move_limit": 10,
		"buses": [{"color": "red", "capacity": 1}],
		"passenger_queues": [[{"color": "blue"}], [{"color": "blue"}]],
	}
	var level: LevelData = LevelData.from_dict(data)
	var game: Dictionary = await _make_game(level)
	var controller: GameController = game["controller"]
	var queues: Array[PassengerQueue] = game["passenger_queues"]

	# Blue doesn't match red, but the (single-slot) waiting area still has
	# room -- this move is accepted... and immediately traps queue 2's
	# blue front with nowhere left to go and no bus it can ever match.
	_tap_front(queues[0])
	await _await_settle(controller)

	_check(controller.state == GameController.State.LOST, "a successful move that fills the last waiting slot can itself cause a deadlock loss")

	_free_game(game)


func _test_cannot_process_same_passenger_twice() -> void:
	var result: LevelLoadResult = LevelRepository.load_level_by_id(1)
	if not result.is_success():
		_check(false, "level 1 loads for the double-tap test")
		return

	var game: Dictionary = await _make_game(result.level)
	var controller: GameController = game["controller"]
	var bus_queue: BusQueue = game["bus_queue"]
	var queue: PassengerQueue = game["passenger_queues"][0]

	var front: Passenger = queue.front()
	front._on_pressed()
	front._on_pressed()  # synchronous second tap on the same passenger
	await _await_settle(controller)

	_check(bus_queue.active_bus().current_passengers == 1, "only one passenger boarded despite two synchronous taps on it")
	_check(controller.moves_made == 1, "moves_made was only incremented once")

	_free_game(game)


## The end-to-end proof that the first five levels are playable via
## MainMenu: boots the real app shell, then drives AppRouter.start_level()
## (what LevelSelect's buttons call) for each of levels 1-20 and confirms a
## real GameScreen mounts with a GameController that actually reaches
## PLAYING for the right level.
func _test_all_five_levels_playable_via_app() -> void:
	var packed: PackedScene = load("res://scenes/app/main.tscn")
	var app: Control = packed.instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	await process_frame

	var app_router: Node = root.get_node("AppRouter")

	for level_id: int in range(1, 21):
		app_router.start_level(level_id)
		await process_frame
		await process_frame
		await process_frame

		var screen_root: Control = app.get_node("%ScreenRoot")
		var game_screen: Node = null
		if screen_root.get_child_count() > 0:
			game_screen = screen_root.get_child(screen_root.get_child_count() - 1)

		_check(game_screen != null, "level %d: GameScreen mounts into %%ScreenRoot" % level_id)
		if game_screen == null:
			continue

		var controller: GameController = game_screen.controller
		_check(controller != null, "level %d: a GameController was constructed" % level_id)
		if controller == null:
			continue

		_check(controller.level.id == level_id, "level %d: the correct level was loaded" % level_id)
		_check(controller.state == GameController.State.PLAYING, "level %d: reaches PLAYING through the real app/MainMenu stack" % level_id)

	app.queue_free()
