class_name GameState
extends RefCounted
## Pure data: the mutable, in-progress state of a play session, derived
## from a LevelData. No visual/Node reference of any kind -- this is not a
## GameController, just the data a (future) GameController would drive.

var level_id: int = 0
var waiting_slot_count: int = 0
var passenger_queues: Array[PassengerQueueData] = []
var bus_queue: Array[BusData] = []
var current_bus: BusData = null
var moves_made: int = 0
var move_limit: int = 0
var is_complete: bool = false
var is_failed: bool = false


## Builds a fresh GameState from a LevelData: the waiting slot count and
## passenger queues start as authored, and the first bus in the queue
## becomes current_bus.
static func from_level(level: LevelData) -> GameState:
	var state: GameState = GameState.new()
	state.level_id = level.id
	state.waiting_slot_count = level.waiting_slot_count
	state.passenger_queues = level.passenger_queues.duplicate()
	state.move_limit = level.move_limit
	state.bus_queue = level.buses.duplicate()
	if not state.bus_queue.is_empty():
		state.current_bus = state.bus_queue.pop_front()
	return state


func is_valid() -> bool:
	if level_id <= 0:
		return false
	if waiting_slot_count <= 0:
		return false
	for queue: PassengerQueueData in passenger_queues:
		if queue == null or not queue.is_valid():
			return false
	for bus: BusData in bus_queue:
		if bus == null or not bus.is_valid():
			return false
	if current_bus != null and not current_bus.is_valid():
		return false
	return true


func to_snapshot() -> GameStateSnapshot:
	return GameStateSnapshot.from_game_state(self)
