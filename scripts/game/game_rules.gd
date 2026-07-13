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


## Star rating for a completed level, from how many player moves it took
## relative to the level's authored move_limit (the minimum possible is
## always exactly one player move per passenger, regardless of whether it
## routes straight to a bus or via the waiting area -- auto-boarding from
## the waiting area doesn't count as a move). A win always earns at least
## 1 star, even over the limit -- move_limit isn't currently a loss
## condition (see docs/ARCHITECTURE.md), so finishing at all is never
## worth zero. A level authored with no move_limit (<= 0) can't be rated
## for efficiency at all, so it's always the full 3.
static func calculate_stars(moves_made: int, move_limit: int) -> int:
	if move_limit <= 0:
		return 3

	var ratio: float = float(moves_made) / float(move_limit)
	if ratio <= 0.5:
		return 3
	if ratio <= 0.75:
		return 2
	return 1
