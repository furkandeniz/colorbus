extends SceneTree
## Headless checks for the PassengerQueue scene: configuring from a color
## list, that only the front passenger is ever selectable, that removing
## the front advances the queue, that the last removal emits
## queue_emptied, and that a queue can't be double-removed or selected
## mid-animation.
##
## Real click/tap simulation isn't possible headlessly (see
## docs/ARCHITECTURE.md) -- "pressing" a passenger is simulated by calling
## its private _on_pressed() directly, same as tests/verify_passenger.gd.
##
## Usage: godot --headless --path . --script res://tests/verify_passenger_queue.gd

var _all_ok: bool = true
var _queue_scene: PackedScene


func _initialize() -> void:
	_queue_scene = load("res://scenes/game/passenger_queue.tscn")

	await _test_configure_and_order()
	await _test_only_front_selectable()
	await _test_remove_front_advances_queue()
	await _test_last_removal_emits_queue_emptied()
	await _test_cannot_remove_twice()
	await _test_locked_during_animation()

	print("[PassengerQueueTest] RESULT: %s" % ("PASS" if _all_ok else "FAIL"))
	quit(0 if _all_ok else 1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_all_ok = false
	print("[PassengerQueueTest] %s -> %s" % [label, "OK" if condition else "FAIL"])


func _make_queue_ready() -> PassengerQueue:
	var queue: PassengerQueue = _queue_scene.instantiate()
	root.add_child(queue)
	await process_frame
	return queue


func _test_configure_and_order() -> void:
	var queue: PassengerQueue = await _make_queue_ready()
	var colors: Array[int] = [
		PassengerColor.Value.RED,
		PassengerColor.Value.BLUE,
		PassengerColor.Value.YELLOW,
	]
	queue.configure(colors)
	await process_frame

	_check(queue.passenger_count() == 3, "configure() creates one Passenger per color")
	_check(not queue.is_empty(), "configured queue is not empty")
	_check(queue.front().color == PassengerColor.Value.RED, "front() is the first color")

	# Data order (queue._passengers) and visual order (child index) must
	# match exactly, color by color.
	var order_matches: bool = true
	for i: int in colors.size():
		if queue.get_child(i) != queue._passengers[i]:
			order_matches = false
		if queue._passengers[i].color != colors[i]:
			order_matches = false
	_check(order_matches, "data order and visual (child) order match")

	queue.queue_free()


func _test_only_front_selectable() -> void:
	var queue: PassengerQueue = await _make_queue_ready()
	queue.configure([PassengerColor.Value.RED, PassengerColor.Value.BLUE, PassengerColor.Value.GREEN])
	await process_frame

	_check(queue.front().can_be_selected(), "front passenger is selectable")
	_check(not queue._passengers[1].can_be_selected(), "second passenger is not selectable")
	_check(not queue._passengers[2].can_be_selected(), "third passenger is not selectable")

	queue.queue_free()


func _test_remove_front_advances_queue() -> void:
	var queue: PassengerQueue = await _make_queue_ready()
	queue.configure([PassengerColor.Value.RED, PassengerColor.Value.BLUE, PassengerColor.Value.GREEN])
	await process_frame

	var old_front: Passenger = queue.front()
	var received: Array = []
	queue.passenger_selected.connect(func(p: Passenger) -> void: received.append(p))
	old_front._on_pressed()
	_check(received.size() == 1 and received[0] == old_front, "PassengerQueue forwards passenger_selected from the front")

	queue.remove_front()
	await create_timer(0.4).timeout

	_check(queue.passenger_count() == 2, "removing the front leaves the rest")
	_check(queue.front().color == PassengerColor.Value.BLUE, "next passenger becomes front")
	_check(queue.front().can_be_selected(), "new front becomes selectable automatically")
	_check(not queue.is_locked(), "queue unlocks once the removal animation finishes")

	queue.queue_free()


func _test_last_removal_emits_queue_emptied() -> void:
	var queue: PassengerQueue = await _make_queue_ready()
	queue.configure([PassengerColor.Value.PURPLE])
	await process_frame

	# A plain `var emptied: bool` reassigned inside the lambda below would
	# only mutate the lambda's own captured copy (GDScript closures capture
	# locals by value), never visible to this outer scope -- wrap it in an
	# Array (a reference type) so `emptied[0] = true` actually mutates the
	# same object both sides see, same idiom as `received.append(p)` above.
	var emptied: Array = [false]
	queue.queue_emptied.connect(func() -> void: emptied[0] = true)

	queue.remove_front()
	await create_timer(0.4).timeout

	_check(emptied[0], "removing the last passenger emits queue_emptied")
	_check(queue.is_empty(), "queue reports empty after the last removal")
	_check(queue.front() == null, "front() is null on an empty queue")

	queue.queue_free()


func _test_cannot_remove_twice() -> void:
	var queue: PassengerQueue = await _make_queue_ready()
	queue.configure([PassengerColor.Value.RED, PassengerColor.Value.BLUE])
	await process_frame

	var front_passenger: Passenger = queue.front()
	queue.remove_front()
	# Locked mid-animation: a second call must be ignored, not start a
	# second removal of the same (or any) passenger.
	queue.remove_front()
	await create_timer(0.4).timeout

	_check(queue.passenger_count() == 1, "only one passenger was removed despite two remove_front() calls")
	_check(queue.front().color == PassengerColor.Value.BLUE, "the surviving passenger is the second one, not re-removed")
	_check(not is_instance_valid(front_passenger) or front_passenger.get_parent() == null, "the removed passenger is actually gone")

	queue.queue_free()


func _test_locked_during_animation() -> void:
	var queue: PassengerQueue = await _make_queue_ready()
	queue.configure([PassengerColor.Value.RED, PassengerColor.Value.BLUE])
	await process_frame

	queue.remove_front()
	_check(queue.is_locked(), "queue is locked immediately after remove_front()")
	_check(not queue._passengers[0].can_be_selected(), "even the animating-out front is not selectable while locked")
	_check(not queue._passengers[1].can_be_selected(), "second passenger is not selectable while locked either")

	await create_timer(0.4).timeout
	_check(not queue.is_locked(), "queue unlocks after the animation finishes")

	queue.queue_free()
