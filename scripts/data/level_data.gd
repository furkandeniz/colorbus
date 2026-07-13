class_name LevelData
extends RefCounted
## Pure data: a level definition (as authored in data/levels/*.json). No
## visual/Node reference of any kind.
##
## from_dict()/to_dict() only do structural conversion -- they never reject
## a malformed dict, just produce a LevelData that is_valid() will catch.
## The full business-rule validation (positive id, capacity balance per
## color, unknown colors, etc.) is LevelValidator's job, run on the raw
## JSON *before* a LevelData is ever built from it (see LevelLoader).

var id: int = 0
var name_key: String = ""
var waiting_slot_count: int = 0
var buses: Array[BusData] = []
var passenger_queues: Array[PassengerQueueData] = []
var move_limit: int = 0
var tutorial: bool = false
var difficulty: int = 0


## A level is only valid with a positive id, at least one waiting slot,
## and at least one valid bus -- an "empty"/malformed level isn't
## playable. This is a basic structural check, not the full business-rule
## validation LevelValidator performs on the raw JSON.
func is_valid() -> bool:
	if id <= 0:
		return false
	if waiting_slot_count <= 0:
		return false
	if buses.is_empty():
		return false
	for bus: BusData in buses:
		if bus == null or not bus.is_valid():
			return false
	for queue: PassengerQueueData in passenger_queues:
		if queue == null or not queue.is_valid():
			return false
	return true


## Builds a LevelData from a JSON-decoded Dictionary. Never trusts the
## shape: missing/malformed fields produce an incomplete LevelData that
## is_valid() will reject, rather than a crash or a silently-guessed value.
static func from_dict(data: Dictionary) -> LevelData:
	var level: LevelData = LevelData.new()

	level.id = int(data.get("id", 0))
	level.name_key = str(data.get("name_key", ""))
	level.waiting_slot_count = int(data.get("waiting_slot_count", 0))
	level.move_limit = int(data.get("move_limit", 0))
	level.tutorial = bool(data.get("tutorial", false))
	level.difficulty = int(data.get("difficulty", 0))

	if typeof(data.get("buses")) == TYPE_ARRAY:
		for item: Variant in data["buses"]:
			if typeof(item) == TYPE_DICTIONARY:
				level.buses.append(BusData.from_dict(item))

	if typeof(data.get("passenger_queues")) == TYPE_ARRAY:
		for item: Variant in data["passenger_queues"]:
			if typeof(item) == TYPE_ARRAY:
				level.passenger_queues.append(PassengerQueueData.from_array(item))

	return level


func to_dict() -> Dictionary:
	var buses_array: Array = []
	for bus: BusData in buses:
		buses_array.append(bus.to_dict())

	var queues_array: Array = []
	for queue: PassengerQueueData in passenger_queues:
		queues_array.append(queue.to_array())

	return {
		"id": id,
		"name_key": name_key,
		"waiting_slot_count": waiting_slot_count,
		"buses": buses_array,
		"passenger_queues": queues_array,
		"move_limit": move_limit,
		"tutorial": tutorial,
		"difficulty": difficulty,
	}
