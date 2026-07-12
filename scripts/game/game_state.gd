class_name GameState
extends RefCounted
## Pure data: the mutable, in-progress state of a play session, derived
## from a LevelData. No visual/Node reference of any kind -- this is not a
## GameController, just the data a (future) GameController would drive.

var level_id: String = ""
var waiting_area: WaitingAreaData = null
var bus_queue: Array[BusData] = []
var current_bus: BusData = null
var moves_made: int = 0
var is_complete: bool = false
var is_failed: bool = false


func _init() -> void:
	waiting_area = WaitingAreaData.new()


## Builds a fresh GameState from a LevelData: the waiting area starts as
## authored, and the first bus in the queue becomes current_bus.
static func from_level(level: LevelData) -> GameState:
	var state: GameState = GameState.new()
	state.level_id = level.level_id
	state.waiting_area = level.waiting_area
	state.bus_queue = level.bus_queue.duplicate()
	if not state.bus_queue.is_empty():
		state.current_bus = state.bus_queue.pop_front()
	return state


func is_valid() -> bool:
	if level_id.is_empty():
		return false
	if waiting_area == null or not waiting_area.is_valid():
		return false
	for bus: BusData in bus_queue:
		if bus == null or not bus.is_valid():
			return false
	if current_bus != null and not current_bus.is_valid():
		return false
	return true


func to_snapshot() -> GameStateSnapshot:
	return GameStateSnapshot.from_game_state(self)
