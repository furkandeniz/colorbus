extends SceneTree
## Headless checks for the BusQueue scene: only the first bus is active,
## filling the active bus advances to the next one (active_bus_changed),
## and completing the last bus completes the whole queue
## (bus_queue_completed).
##
## Usage: godot --headless --path . --script res://tests/verify_bus_queue.gd

var _all_ok: bool = true
var _queue_scene: PackedScene


func _initialize() -> void:
	_queue_scene = load("res://scenes/game/bus_queue.tscn")

	await _test_configure_and_first_active()
	await _test_advances_to_next_bus()
	await _test_last_bus_completes_queue()
	await _test_stale_completion_from_inactive_bus_ignored()

	print("[BusQueueTest] RESULT: %s" % ("PASS" if _all_ok else "FAIL"))
	quit(0 if _all_ok else 1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_all_ok = false
	print("[BusQueueTest] %s -> %s" % [label, "OK" if condition else "FAIL"])


func _make_queue_ready() -> BusQueue:
	var queue: BusQueue = _queue_scene.instantiate()
	root.add_child(queue)
	await process_frame
	return queue


func _make_bus_data_list() -> Array[BusData]:
	var list: Array[BusData] = [
		BusData.new(PassengerColor.Value.RED, 1),
		BusData.new(PassengerColor.Value.BLUE, 1),
		BusData.new(PassengerColor.Value.GREEN, 1),
	]
	return list


func _test_configure_and_first_active() -> void:
	var queue: BusQueue = await _make_queue_ready()

	var changed_received: Array = []
	queue.active_bus_changed.connect(func(b: Bus) -> void: changed_received.append(b))

	queue.configure(_make_bus_data_list())
	await process_frame

	_check(queue.bus_count() == 3, "configure() creates one Bus per BusData")
	_check(not queue.is_empty(), "configured queue is not empty")
	_check(queue.active_bus() != null, "the first bus is active after configure()")
	_check(queue.active_bus().color == PassengerColor.Value.RED, "the active bus is the first one in the list")
	_check(queue.active_bus().is_active, "active_bus() itself reports is_active true")

	for i: int in range(1, queue.bus_count()):
		_check(not queue.get_child(i).is_active, "bus #%d is not active" % i)

	_check(changed_received.size() == 1 and changed_received[0] == queue.active_bus(), "active_bus_changed fires once on initial configure()")

	queue.queue_free()


func _test_advances_to_next_bus() -> void:
	var queue: BusQueue = await _make_queue_ready()
	queue.configure(_make_bus_data_list())
	await process_frame

	var first_bus: Bus = queue.active_bus()
	var changed_received: Array = []
	queue.active_bus_changed.connect(func(b: Bus) -> void: changed_received.append(b))

	first_bus.board_passenger(PassengerColor.Value.RED)
	await process_frame

	_check(first_bus.is_completed, "the first bus is completed once full")
	_check(queue.active_bus() != first_bus, "BusQueue's active bus is no longer the completed one")
	_check(queue.active_bus().color == PassengerColor.Value.BLUE, "the second bus becomes active")
	_check(queue.active_bus().is_active, "the newly active bus reports is_active true")
	_check(changed_received.size() == 1 and changed_received[0] == queue.active_bus(), "active_bus_changed fires with the new active bus")
	_check(queue.bus_count() == 3, "completed buses are not removed from the queue")

	queue.queue_free()


func _test_last_bus_completes_queue() -> void:
	var queue: BusQueue = await _make_queue_ready()
	queue.configure(_make_bus_data_list())
	await process_frame

	var completed_flag: Array = [false]
	queue.bus_queue_completed.connect(func() -> void: completed_flag[0] = true)

	# Fill red, then blue, then green -- three buses, one seat each.
	queue.active_bus().board_passenger(PassengerColor.Value.RED)
	await process_frame
	_check(not completed_flag[0], "bus_queue_completed has not fired after only 2 of 3 buses are done")

	queue.active_bus().board_passenger(PassengerColor.Value.BLUE)
	await process_frame
	_check(not completed_flag[0], "bus_queue_completed still not fired with the last bus still active")

	queue.active_bus().board_passenger(PassengerColor.Value.GREEN)
	await process_frame

	_check(completed_flag[0], "bus_queue_completed fires once the last bus completes")
	_check(queue.active_bus() == null, "active_bus() is null once the whole queue is completed")

	for i: int in queue.bus_count():
		_check(queue.get_child(i).is_completed, "bus #%d is marked completed" % i)

	queue.queue_free()


func _test_stale_completion_from_inactive_bus_ignored() -> void:
	var queue: BusQueue = await _make_queue_ready()
	queue.configure(_make_bus_data_list())
	await process_frame

	var active_before: Bus = queue.active_bus()
	var second_bus: Bus = queue.get_child(1)

	# Simulate a stray bus_completed from a bus that isn't the active one --
	# BusQueue must not advance because of it.
	second_bus.bus_completed.emit(second_bus)
	await process_frame

	_check(queue.active_bus() == active_before, "a stale bus_completed from a non-active bus does not advance the queue")

	queue.queue_free()
