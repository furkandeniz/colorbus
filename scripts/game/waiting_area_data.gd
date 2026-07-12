class_name WaitingAreaData
extends RefCounted
## Pure data: the waiting platform, made of parallel passenger queues
## ("slots"). No visual/Node reference of any kind.

var queues: Array[PassengerQueueData] = []


func _init(p_queues: Array[PassengerQueueData] = []) -> void:
	queues = p_queues


func slot_count() -> int:
	return queues.size()


func is_valid() -> bool:
	for queue: PassengerQueueData in queues:
		if queue == null or not queue.is_valid():
			return false
	return true


## Builds a WaitingAreaData from a JSON-decoded Array of arrays (one array
## per queue/slot). Any element that isn't an Array is skipped rather than
## crashing the parse.
static func from_array(data: Array) -> WaitingAreaData:
	var area: WaitingAreaData = WaitingAreaData.new()
	for item: Variant in data:
		if typeof(item) == TYPE_ARRAY:
			area.queues.append(PassengerQueueData.from_array(item))
	return area


func to_array() -> Array:
	var result: Array = []
	for queue: PassengerQueueData in queues:
		result.append(queue.to_array())
	return result
