class_name GameStateSnapshot
extends RefCounted
## Pure data only: a GameState snapshot for save/undo/replay. `data` holds
## nothing but primitives, Arrays and Dictionaries (JSON-serializable) --
## never a PassengerData/BusData/PassengerQueueData instance, and never a
## Node. restore_game_state() is the only place this gets turned back into
## live model objects.

var data: Dictionary = {}


func _init(p_data: Dictionary = {}) -> void:
	data = p_data


static func from_game_state(state: GameState) -> GameStateSnapshot:
	var bus_queue_array: Array = []
	for bus: BusData in state.bus_queue:
		bus_queue_array.append(bus.to_dict())

	var queues_array: Array = []
	for queue: PassengerQueueData in state.passenger_queues:
		queues_array.append(queue.to_array())

	var payload: Dictionary = {
		"level_id": state.level_id,
		"waiting_slot_count": state.waiting_slot_count,
		"passenger_queues": queues_array,
		"bus_queue": bus_queue_array,
		"current_bus": state.current_bus.to_dict() if state.current_bus != null else null,
		"moves_made": state.moves_made,
		"move_limit": state.move_limit,
		"is_complete": state.is_complete,
		"is_failed": state.is_failed,
	}
	return GameStateSnapshot.new(payload)


func restore_game_state() -> GameState:
	var state: GameState = GameState.new()
	state.level_id = int(data.get("level_id", 0))
	state.waiting_slot_count = int(data.get("waiting_slot_count", 0))

	state.passenger_queues = []
	for item: Variant in data.get("passenger_queues", []):
		if typeof(item) == TYPE_ARRAY:
			state.passenger_queues.append(PassengerQueueData.from_array(item))

	state.bus_queue = []
	for item: Variant in data.get("bus_queue", []):
		if typeof(item) == TYPE_DICTIONARY:
			state.bus_queue.append(BusData.from_dict(item))

	var current_bus_data: Variant = data.get("current_bus")
	if typeof(current_bus_data) == TYPE_DICTIONARY:
		state.current_bus = BusData.from_dict(current_bus_data)

	state.moves_made = int(data.get("moves_made", 0))
	state.move_limit = int(data.get("move_limit", 0))
	state.is_complete = bool(data.get("is_complete", false))
	state.is_failed = bool(data.get("is_failed", false))
	return state


func is_valid() -> bool:
	return data.has("level_id") and data.has("waiting_slot_count") and data.has("bus_queue")


func to_json_string() -> String:
	return JSON.stringify(data)


static func from_json_string(text: String) -> GameStateSnapshot:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return null
	var parsed: Variant = json.get_data()
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	return GameStateSnapshot.new(parsed)
