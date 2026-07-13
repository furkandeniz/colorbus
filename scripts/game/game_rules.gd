class_name GameRules
extends RefCounted
## Stateless gameplay rules, factored out of GameController so its state
## machine stays focused on *sequencing* rather than *deciding*. Every
## function here just inspects the view nodes it's given (BusQueue/
## WaitingArea/PassengerQueue) and returns an answer or performs one
## already-defined mutation -- no state of its own, nothing to keep in
## sync.


## Whether the player can currently make progress at all: at least one
## queue's front passenger either matches the active bus's color, or the
## waiting area still has room to hold it temporarily. If the bus queue
## itself is already finished, that's the win path, not a deadlock, so
## it counts as "a legal move" here (callers check win separately first).
static func has_any_legal_move(
	queues: Array[PassengerQueue], active_bus: Bus, waiting_area: WaitingArea
) -> bool:
	if active_bus == null:
		return true

	var waiting_area_has_room: bool = not waiting_area.is_full()

	for queue: PassengerQueue in queues:
		if queue.is_empty():
			continue
		var front: Passenger = queue.front()
		if front == null:
			continue
		if active_bus.can_accept(front.color) or waiting_area_has_room:
			return true

	return false


## The level is won once the bus queue itself is done -- every bus
## completed in sequence. Given LevelValidator guarantees total passenger
## count equals total bus capacity, this is also sufficient on its own
## (every passenger must already be boarded by then), but callers may
## still want to confirm queues/waiting area are empty for their own
## peace of mind.
static func is_level_won(bus_queue: BusQueue) -> bool:
	return bus_queue.active_bus() == null
