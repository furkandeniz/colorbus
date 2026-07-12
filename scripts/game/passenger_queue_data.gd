class_name PassengerQueueData
extends RefCounted
## Pure data: a single-file line of waiting passengers. Only the front
## passenger can board a bus. No visual/Node reference of any kind.

var passengers: Array[PassengerData] = []


func _init(p_passengers: Array[PassengerData] = []) -> void:
	passengers = p_passengers


func is_empty() -> bool:
	return passengers.is_empty()


func front() -> PassengerData:
	return passengers[0] if not passengers.is_empty() else null


func pop_front() -> PassengerData:
	return passengers.pop_front() if not passengers.is_empty() else null


## An empty queue is valid (an empty waiting slot); a non-empty queue is
## only valid if every passenger in it is valid.
func is_valid() -> bool:
	for passenger: PassengerData in passengers:
		if passenger == null or not passenger.is_valid():
			return false
	return true


## Builds a PassengerQueueData from a JSON-decoded Array. Any element that
## isn't a Dictionary is skipped rather than crashing the parse; the
## resulting queue may then fail is_valid() if that leaves invalid data.
static func from_array(data: Array) -> PassengerQueueData:
	var queue: PassengerQueueData = PassengerQueueData.new()
	for item: Variant in data:
		if typeof(item) == TYPE_DICTIONARY:
			queue.passengers.append(PassengerData.from_dict(item))
	return queue


func to_array() -> Array:
	var result: Array = []
	for passenger: PassengerData in passengers:
		result.append(passenger.to_dict())
	return result
