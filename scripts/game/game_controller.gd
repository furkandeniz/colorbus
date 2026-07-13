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
## again via the automatic FIFO boarding in _on_active_bus_changed().

enum State { LOADING, PLAYING, MOVING_PASSENGER, WON, LOST, PAUSED }

signal state_changed(state: State)

var state: State = State.LOADING
var level: LevelData = null
var moves_made: int = 0

var _bus_queue: BusQueue = null
var _waiting_area: WaitingArea = null
var _passenger_queues: Array[PassengerQueue] = []
var _state_before_pause: State = State.PLAYING


## p_passenger_queues must already be built with exactly
## p_level.passenger_queues.size() empty PassengerQueue instances --
## GameScreen's job, not this class's.
func _init(
	p_level: LevelData,
	p_bus_queue: BusQueue,
	p_waiting_area: WaitingArea,
	p_passenger_queues: Array[PassengerQueue]
) -> void:
	level = p_level
	_bus_queue = p_bus_queue
	_waiting_area = p_waiting_area
	_passenger_queues = p_passenger_queues

	_bus_queue.active_bus_changed.connect(_on_active_bus_changed)
	for queue: PassengerQueue in _passenger_queues:
		queue.passenger_selected.connect(_on_queue_passenger_selected.bind(queue))


## Configures every view node from `level` and starts play. Safe to call
## again (restart()) -- each view node's own configure() clears its
## previous contents first.
##
## Order matters here: BusQueue.configure() synchronously emits
## active_bus_changed (our own _on_active_bus_changed handler is already
## connected in _init()), which runs a full auto-board + _check_game_over()
## pass immediately -- so the waiting area and passenger queues must
## already be in their real starting shape *before* the bus queue is
## configured, or that first check would wrongly see empty queues and
## call it a deadlock.
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

	# The configure() call above may have already synchronously reached
	# WON/LOST via the cascade described above -- never stomp that back to
	# PLAYING.
	if state != State.WON and state != State.LOST:
		_set_state(State.PLAYING)

	var active_bus: Bus = _bus_queue.active_bus()
	if active_bus != null:
		GameRules.auto_board_from_waiting_area(active_bus, _waiting_area)
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
	queue.remove_front()
	await queue.passenger_removed

	if goes_to_bus:
		# board_passenger() can complete the bus synchronously, which can
		# cascade through BusQueue's active_bus_changed -> this class's own
		# _on_active_bus_changed -> auto-boarding -> _check_game_over(),
		# all before this line returns -- state may already be WON by the
		# time control comes back here, so it must never be stomped back
		# to PLAYING unconditionally below.
		active_bus.board_passenger(color)
	else:
		_waiting_area.add_passenger(color)

	moves_made += 1
	if state != State.WON and state != State.LOST:
		_set_state(State.PLAYING)
	_check_game_over()


func _on_active_bus_changed(bus: Bus) -> void:
	GameRules.auto_board_from_waiting_area(bus, _waiting_area)
	_check_game_over()


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
