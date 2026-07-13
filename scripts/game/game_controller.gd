class_name GameController
extends RefCounted
## The play-session state machine. Never Autoload -- lives only as long as
## a GameScreen instance holds a reference to it, so every level start is
## a genuinely fresh object. GameScreen builds the (empty) BusQueue/
## WaitingArea/PassengerQueue view nodes and hands them here; this class
## never instantiates a scene itself, only calls the public methods those
## already-built nodes expose. GameRules carries the stateless decision
## logic (legal-move / auto-board / win checks) so this class stays
## focused on sequencing state transitions and wiring signals.
##
## Waiting-area passengers are intentionally never connected to any game
## action here -- per the rules, only a queue's front passenger is ever
## player-selectable; passengers already in the waiting area only move
## again via the automatic FIFO boarding in _run_auto_board_cascade().
##
## Every passenger's actual on-screen move (queue -> bus, queue -> waiting
## slot, waiting slot -> bus) is a real, awaited flight through
## `_animator` (a GameAnimator) -- state transitions and board_passenger()/
## add_passenger() calls only ever happen *after* the flight that visually
## represents them has finished, never before, so the rendered board and
## the underlying game state can never disagree mid-animation.

enum State { LOADING, PLAYING, MOVING_PASSENGER, WON, LOST, PAUSED }

signal state_changed(state: State)

var state: State = State.LOADING
var level: LevelData = null
var moves_made: int = 0

var _bus_queue: BusQueue = null
var _waiting_area: WaitingArea = null
var _passenger_queues: Array[PassengerQueue] = []
var _animator: GameAnimator = null
var _state_before_pause: State = State.PLAYING


## p_passenger_queues must already be built with exactly
## p_level.passenger_queues.size() empty PassengerQueue instances --
## GameScreen's job, not this class's.
func _init(
	p_level: LevelData,
	p_bus_queue: BusQueue,
	p_waiting_area: WaitingArea,
	p_passenger_queues: Array[PassengerQueue],
	p_animator: GameAnimator
) -> void:
	level = p_level
	_bus_queue = p_bus_queue
	_waiting_area = p_waiting_area
	_passenger_queues = p_passenger_queues
	_animator = p_animator

	for queue: PassengerQueue in _passenger_queues:
		queue.passenger_selected.connect(_on_queue_passenger_selected.bind(queue))


## Configures every view node from `level` and starts play. Safe to call
## again (restart()) -- each view node's own configure() clears its
## previous contents first.
##
## The waiting area and passenger queues are put into their real starting
## shape *before* the bus queue is configured, so the auto-board cascade
## run explicitly below always sees the level's actual starting contents.
func start() -> void:
	_set_state(State.LOADING)
	moves_made = 0

	_waiting_area.configure(level.waiting_slot_count)

	for i: int in _passenger_queues.size():
		var colors: Array[int] = []
		if i < level.passenger_queues.size():
			for passenger: PassengerData in level.passenger_queues[i].passengers:
				colors.append(passenger.color)
		_passenger_queues[i].configure(colors)

	_bus_queue.configure(level.buses)

	if state != State.WON and state != State.LOST:
		_set_state(State.PLAYING)

	await _run_auto_board_cascade()
	_check_game_over()


func restart() -> void:
	if state == State.LOADING:
		return
	start()


func pause() -> void:
	if state != State.PLAYING:
		return
	_state_before_pause = state
	_set_state(State.PAUSED)


func resume() -> void:
	if state != State.PAUSED:
		return
	_set_state(_state_before_pause)


## The one entry point for a player action: a queue's front passenger was
## tapped. Ignored outright unless currently PLAYING (blocks both
## mid-animation re-selection and any double-processing of the same
## passenger -- reinforced by PassengerQueue's own lock and Passenger's
## own selectable flag).
func _on_queue_passenger_selected(passenger: Passenger, queue: PassengerQueue) -> void:
	if state != State.PLAYING:
		return

	var color: int = passenger.color
	var active_bus: Bus = _bus_queue.active_bus()
	var goes_to_bus: bool = active_bus != null and active_bus.can_accept(color)

	if not goes_to_bus and _waiting_area.is_full():
		# This specific move is rejected -- but that alone doesn't mean the
		# level is lost. Only a full sweep confirming no move is possible
		# anywhere decides that (see _check_game_over()).
		_check_game_over()
		return

	_set_state(State.MOVING_PASSENGER)

	# take_front() locks the queue and detaches the node without freeing it,
	# so it can be flown to its destination; the same passenger can't be
	# re-selected (queue stays locked) until finish_external_removal() below.
	var taken: Passenger = queue.take_front()
	if taken == null:
		if state != State.WON and state != State.LOST:
			_set_state(State.PLAYING)
		return

	if goes_to_bus:
		await _animator.fly_passenger_to(taken, active_bus, AnimationConfig.PASSENGER_TO_BUS)
		if is_instance_valid(taken):
			taken.queue_free()
		queue.finish_external_removal(color)

		# board_passenger() can complete the bus synchronously, advancing
		# BusQueue's active bus -- state may already be WON by the time
		# control comes back here, so it must never be stomped back to
		# PLAYING unconditionally below.
		active_bus.board_passenger(color)
		_play_sfx("passenger_board_bus")
	else:
		var slot_index: int = _waiting_area.add_passenger(color)
		# add_passenger() already instantly created the real destination
		# Passenger -- hide it until the flying duplicate arrives, so there's
		# never a visible double.
		var real_passenger: Passenger = _waiting_area.get_slot_passenger(slot_index)
		if real_passenger != null:
			real_passenger.modulate.a = 0.0

		var slot_control: Control = _waiting_area.get_slot_control(slot_index)
		await _animator.fly_passenger_to(taken, slot_control, AnimationConfig.PASSENGER_TO_WAITING_SLOT)
		if is_instance_valid(taken):
			taken.queue_free()
		queue.finish_external_removal(color)
		if is_instance_valid(real_passenger):
			real_passenger.modulate.a = 1.0
		_play_sfx("passenger_to_waiting")

	moves_made += 1

	await _run_auto_board_cascade()

	if state != State.WON and state != State.LOST:
		_set_state(State.PLAYING)
	_check_game_over()


## Explicit, awaited replacement for the old signal-driven auto-board
## (BusQueue.active_bus_changed used to trigger this synchronously): boards
## every waiting passenger matching the active bus's color, in FIFO order,
## flying each one there and awaiting its arrival before boarding the next
## -- so the animation can never race ahead of (or behind) the actual game
## state change. Runs after every player move and once after start()'s
## initial setup, covering exactly the trigger points active_bus_changed
## used to.
func _run_auto_board_cascade() -> void:
	var active_bus: Bus = _bus_queue.active_bus()
	while active_bus != null:
		var index: int = _waiting_area.find_first_slot_of_color(active_bus.color)
		if index == -1:
			break

		var taken: Passenger = _waiting_area.take_passenger_at(index)
		if taken == null:
			break
		var color: int = taken.color

		await _animator.fly_passenger_to(taken, active_bus, AnimationConfig.WAITING_TO_BUS)
		if is_instance_valid(taken):
			taken.queue_free()

		active_bus.board_passenger(color)
		_play_sfx("passenger_board_bus")

		active_bus = _bus_queue.active_bus()


## Fire-and-forget SFX trigger, silently no-op'ing (see AudioManager) until
## real audio assets exist. Reaches the AudioManager Autoload via NodePath
## string rather than the bare `AudioManager` identifier -- see
## AnimationConfig's class doc comment for why: naming an Autoload
## identifier anywhere in a class_name script's source corrupts that
## class's compile under Godot's `--script` runner.
func _play_sfx(key: String) -> void:
	var tree: SceneTree = _bus_queue.get_tree() if is_instance_valid(_bus_queue) else null
	if tree == null:
		return
	var audio: Node = tree.root.get_node_or_null("/root/AudioManager")
	if audio == null:
		return
	audio.call("play_sfx", key)


func _check_game_over() -> void:
	if state == State.WON or state == State.LOST:
		return
	if GameRules.is_level_won(_bus_queue):
		_set_state(State.WON)
		return
	if not GameRules.has_any_legal_move(_passenger_queues, _bus_queue.active_bus(), _waiting_area):
		_set_state(State.LOST)


func _set_state(new_state: State) -> void:
	state = new_state
	state_changed.emit(state)
	_debug_log("state -> %s" % State.keys()[state])


func _debug_log(message: String) -> void:
	if OS.is_debug_build():
		print("[GameController] %s" % message)
