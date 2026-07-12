class_name LevelData
extends RefCounted
## Pure data: a level definition (as authored in data/levels/*.json). No
## visual/Node reference of any kind.

var level_id: String = ""
var waiting_area: WaitingAreaData = null
var bus_queue: Array[BusData] = []


func _init(p_level_id: String = "", p_waiting_area: WaitingAreaData = null, p_bus_queue: Array[BusData] = []) -> void:
	level_id = p_level_id
	waiting_area = p_waiting_area
	bus_queue = p_bus_queue


## A level is only valid with a non-empty id, a valid waiting area, and at
## least one valid bus in the queue -- an "empty" level isn't playable.
func is_valid() -> bool:
	if level_id.is_empty():
		return false
	if waiting_area == null or not waiting_area.is_valid():
		return false
	if bus_queue.is_empty():
		return false
	for bus: BusData in bus_queue:
		if bus == null or not bus.is_valid():
			return false
	return true


## Builds a LevelData from a JSON-decoded Dictionary. Never trusts the
## shape: missing/malformed fields produce an incomplete LevelData that
## is_valid() will reject, rather than a crash or a silently-guessed value.
static func from_dict(data: Dictionary) -> LevelData:
	var level: LevelData = LevelData.new()
	level.level_id = str(data.get("id", ""))

	if typeof(data.get("waiting_area")) == TYPE_ARRAY:
		level.waiting_area = WaitingAreaData.from_array(data["waiting_area"])
	else:
		level.waiting_area = WaitingAreaData.new()

	if typeof(data.get("buses")) == TYPE_ARRAY:
		for item: Variant in data["buses"]:
			if typeof(item) == TYPE_DICTIONARY:
				level.bus_queue.append(BusData.from_dict(item))

	return level


func to_dict() -> Dictionary:
	var buses_array: Array = []
	for bus: BusData in bus_queue:
		buses_array.append(bus.to_dict())
	return {
		"id": level_id,
		"waiting_area": waiting_area.to_array() if waiting_area != null else [],
		"buses": buses_array,
	}
