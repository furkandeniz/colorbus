class_name LevelSolver
extends RefCounted
## Comprehensive solvability checker for LevelData: models the exact
## GameController/GameRules gameplay mechanics as pure data (no Node/
## Control ever touched -- see docs/ARCHITECTURE.md) and searches for a
## winning sequence of player moves via breadth-first search over
## abstract game states, so the reported min_moves (when solvable) is a
## true shortest solution, not just "a" solution.
##
## Only the front of each passenger queue is ever selectable, and which
## branch a move takes (board the active bus directly vs. sit in the
## waiting area) is *forced* by whether the active bus currently accepts
## that color -- never a player choice. So the only real decision at each
## step is *which queue's front to process next*, giving a small
## branching factor (at most the number of non-empty queues) regardless
## of how many total passengers a level has.
##
## States are deduplicated via a canonical string key (_state_key()) so
## the search explores a DAG rather than an exponential tree of move
## orderings, and is additionally bounded by MAX_EXPLORED_STATES so a
## pathological level can never hang the checker in a runaway search --
## exhausting the bound without finding a win is reported distinctly
## ("inconclusive"), never silently treated as solvable OR unsolvable.

const MAX_EXPLORED_STATES: int = 200000


## Runs the search on `level` and returns a Dictionary:
## {"solvable": bool, "min_moves": int (-1 if none found),
##  "states_explored": int, "reason": String (only non-empty when
##  unsolvable or inconclusive)}.
static func solve(level: LevelData) -> Dictionary:
	var start_state: Dictionary = _initial_state(level)

	if _is_won(start_state):
		return {"solvable": true, "min_moves": 0, "states_explored": 1, "reason": ""}

	var visited: Dictionary = {_state_key(start_state): true}
	var frontier: Array = [start_state]
	var depth: int = 0
	var explored: int = 1

	while not frontier.is_empty():
		depth += 1
		var next_frontier: Array = []

		for state: Dictionary in frontier:
			var queues: Array = state["queues"]
			for queue_index: int in queues.size():
				var next_state: Variant = _apply_move(state, queue_index, level.waiting_slot_count)
				if next_state == null:
					continue

				explored += 1
				if explored > MAX_EXPLORED_STATES:
					return {
						"solvable": false,
						"min_moves": -1,
						"states_explored": explored,
						"reason": "search bound (%d states) exhausted before finding a win or proving a deadlock -- inconclusive, treat as a design smell (likely too many queues/colors for a clean state space)" % MAX_EXPLORED_STATES,
					}

				if _is_won(next_state):
					return {"solvable": true, "min_moves": depth, "states_explored": explored, "reason": ""}

				var key: String = _state_key(next_state)
				if visited.has(key):
					continue
				visited[key] = true
				next_frontier.append(next_state)

		frontier = next_frontier

	return {
		"solvable": false,
		"min_moves": -1,
		"states_explored": explored,
		"reason": _diagnose_deadlock(level),
	}


static func _initial_state(level: LevelData) -> Dictionary:
	var queues: Array = []
	for queue_data: PassengerQueueData in level.passenger_queues:
		var colors: Array = []
		for passenger: PassengerData in queue_data.passengers:
			colors.append(passenger.color)
		queues.append(colors)

	var buses: Array = []
	for bus_data: BusData in level.buses:
		buses.append({"color": bus_data.color, "remaining": bus_data.capacity})

	return {"queues": queues, "waiting": {}, "waiting_total": 0, "buses": buses}


static func _is_won(state: Dictionary) -> bool:
	return (state["buses"] as Array).is_empty()


## Applies "process this queue's front" to state, running the deterministic
## auto-board cascade afterward. Returns null if that specific move is
## illegal right now (queue empty, or the color doesn't match the active
## bus and the waiting area is already full) -- an illegal move is never a
## real transition, exactly like GameController rejecting it outright.
static func _apply_move(state: Dictionary, queue_index: int, waiting_capacity: int) -> Variant:
	var queues: Array = state["queues"]
	var queue: Array = queues[queue_index]
	if queue.is_empty():
		return null

	var color: int = queue[0]
	var buses: Array = state["buses"]
	var has_active_bus: bool = not buses.is_empty()
	var active_color: int = buses[0]["color"] if has_active_bus else -1
	var active_remaining: int = buses[0]["remaining"] if has_active_bus else 0
	var goes_to_bus: bool = has_active_bus and active_color == color and active_remaining > 0

	if not goes_to_bus and int(state["waiting_total"]) >= waiting_capacity:
		return null

	var new_queues: Array = queues.duplicate()
	var new_queue: Array = queue.duplicate()
	new_queue.pop_front()
	new_queues[queue_index] = new_queue

	var new_waiting: Dictionary = (state["waiting"] as Dictionary).duplicate()
	var new_waiting_total: int = int(state["waiting_total"])
	var new_buses: Array = _duplicate_buses(buses)

	if goes_to_bus:
		new_buses[0]["remaining"] -= 1
		if int(new_buses[0]["remaining"]) <= 0:
			new_buses.pop_front()
	else:
		new_waiting[color] = int(new_waiting.get(color, 0)) + 1
		new_waiting_total += 1

	var new_state: Dictionary = {
		"queues": new_queues,
		"waiting": new_waiting,
		"waiting_total": new_waiting_total,
		"buses": new_buses,
	}
	_run_auto_board_cascade(new_state)
	return new_state


## Boards every waiting passenger matching the (possibly just-changed)
## active bus's color, in FIFO order, until it's full or no more match --
## then repeats for whatever bus becomes active next, exactly mirroring
## GameController._run_auto_board_cascade(). Mutates new_state in place
## (it's always a freshly-duplicated state, never shared).
static func _run_auto_board_cascade(state: Dictionary) -> void:
	var buses: Array = state["buses"]
	var waiting: Dictionary = state["waiting"]

	while not buses.is_empty():
		var active: Dictionary = buses[0]
		var available: int = int(waiting.get(active["color"], 0))
		if available <= 0:
			break

		waiting[active["color"]] = available - 1
		state["waiting_total"] = int(state["waiting_total"]) - 1
		active["remaining"] = int(active["remaining"]) - 1
		if int(active["remaining"]) <= 0:
			buses.pop_front()


static func _duplicate_buses(buses: Array) -> Array:
	var copy: Array = []
	for bus: Dictionary in buses:
		copy.append({"color": bus["color"], "remaining": bus["remaining"]})
	return copy


## Canonical string key for state deduplication -- two states with the
## same remaining queue contents, waiting composition, and bus progress
## are interchangeable for every purpose the search cares about, however
## different the move order that produced them.
static func _state_key(state: Dictionary) -> String:
	var key: String = ""

	for queue: Array in state["queues"] as Array:
		for color: int in queue:
			key += str(color)
			key += ","
		key += "|"

	var waiting: Dictionary = state["waiting"]
	var waiting_colors: Array = waiting.keys()
	waiting_colors.sort()
	for color: int in waiting_colors:
		key += "w%d:%d," % [color, int(waiting[color])]
	key += "|"

	for bus: Dictionary in state["buses"] as Array:
		key += "b%d:%d," % [int(bus["color"]), int(bus["remaining"])]

	return key


## Best-effort explanation of why the *initial* state's reachable space
## never wins -- re-simulates the state reached by always preferring a
## direct board over waiting (a reasonable "greedy" playthrough) until
## stuck, then describes exactly what's blocking it. This is a diagnostic
## for a human fixing the level, not a proof (the actual BFS above is the
## proof) -- good enough to point at the right queue/color/capacity to
## adjust rather than re-deriving it by hand.
static func _diagnose_deadlock(level: LevelData) -> String:
	var state: Dictionary = _initial_state(level)

	while true:
		var moved: bool = false
		var queues: Array = state["queues"]

		# Prefer any queue whose front matches the active bus.
		for queue_index: int in queues.size():
			var queue: Array = queues[queue_index]
			if queue.is_empty():
				continue
			var buses: Array = state["buses"]
			if not buses.is_empty() and buses[0]["color"] == queue[0] and int(buses[0]["remaining"]) > 0:
				state = _apply_move(state, queue_index, level.waiting_slot_count)
				moved = true
				break
		if moved:
			continue

		# Otherwise take the first queue that still has room to wait.
		for queue_index: int in queues.size():
			var queue: Array = queues[queue_index]
			if queue.is_empty():
				continue
			var candidate: Variant = _apply_move(state, queue_index, level.waiting_slot_count)
			if candidate != null:
				state = candidate
				moved = true
				break

		if not moved:
			break

	if _is_won(state):
		return "greedy playthrough won -- the BFS-proven deadlock happens only along other move orders; inspect states_explored and try a less-tight waiting_slot_count or a less-adversarial queue order"

	var buses: Array = state["buses"]
	var color_name: String = PassengerColor.to_string_key(buses[0]["color"]) if not buses.is_empty() else "?"
	var fronts: Array = []
	for queue: Array in state["queues"] as Array:
		if not queue.is_empty():
			fronts.append(PassengerColor.to_string_key(queue[0]))

	return "deadlocked: active bus needs '%s', no queue front matches it (remaining fronts: %s) and the waiting area is full (%d/%d)" % [
		color_name, str(fronts), int(state["waiting_total"]), level.waiting_slot_count
	]
