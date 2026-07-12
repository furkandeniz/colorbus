extends SceneTree
## Headless checks for the Bus scene: wrong color rejected, correct color
## accepted, capacity never exceeded, and completion once full (with
## bus_completed firing exactly once, not once per extra attempt).
##
## Usage: godot --headless --path . --script res://tests/verify_bus.gd

var _all_ok: bool = true
var _bus_scene: PackedScene


func _initialize() -> void:
	_bus_scene = load("res://scenes/entities/bus.tscn")

	await _test_wrong_color_rejected()
	await _test_correct_color_accepted()
	await _test_capacity_not_exceeded()
	await _test_completes_when_full()
	await _test_inactive_bus_rejects()
	await _test_completed_bus_rejects_further_boarding()

	print("[BusTest] RESULT: %s" % ("PASS" if _all_ok else "FAIL"))
	quit(0 if _all_ok else 1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_all_ok = false
	print("[BusTest] %s -> %s" % [label, "OK" if condition else "FAIL"])


func _make_bus_ready(color: int, capacity: int, active: bool = true) -> Bus:
	var bus: Bus = _bus_scene.instantiate()
	root.add_child(bus)
	await process_frame
	bus.configure(color, capacity)
	bus.set_active(active)
	return bus


func _test_wrong_color_rejected() -> void:
	var bus: Bus = await _make_bus_ready(PassengerColor.Value.RED, 3)

	var accepted: bool = bus.board_passenger(PassengerColor.Value.BLUE)
	_check(not accepted, "board_passenger() with the wrong color is rejected")
	_check(bus.current_passengers == 0, "wrong-color attempt does not change current_passengers")
	_check(not bus.can_accept(PassengerColor.Value.BLUE), "can_accept() is false for a mismatched color")

	bus.queue_free()


func _test_correct_color_accepted() -> void:
	var bus: Bus = await _make_bus_ready(PassengerColor.Value.BLUE, 3)

	var received: Array = []
	bus.passenger_boarded.connect(func(b: Bus) -> void: received.append(b))

	_check(bus.can_accept(PassengerColor.Value.BLUE), "can_accept() is true for a matching color")
	var accepted: bool = bus.board_passenger(PassengerColor.Value.BLUE)
	_check(accepted, "board_passenger() with the correct color is accepted")
	_check(bus.current_passengers == 1, "current_passengers increments on a correct-color boarding")
	_check(received.size() == 1 and received[0] == bus, "passenger_boarded fires with this bus")

	bus.queue_free()


func _test_capacity_not_exceeded() -> void:
	var bus: Bus = await _make_bus_ready(PassengerColor.Value.GREEN, 2)

	_check(bus.board_passenger(PassengerColor.Value.GREEN), "1st passenger boards (capacity 2)")
	_check(bus.board_passenger(PassengerColor.Value.GREEN), "2nd passenger boards (capacity 2)")
	_check(bus.current_passengers == 2, "current_passengers reaches capacity")

	var overflow_accepted: bool = bus.board_passenger(PassengerColor.Value.GREEN)
	_check(not overflow_accepted, "boarding beyond capacity is rejected")
	_check(bus.current_passengers == 2, "current_passengers never exceeds capacity")

	bus.queue_free()


func _test_completes_when_full() -> void:
	var bus: Bus = await _make_bus_ready(PassengerColor.Value.YELLOW, 2)

	var completed_received: Array = []
	bus.bus_completed.connect(func(b: Bus) -> void: completed_received.append(b))

	_check(not bus.is_completed, "bus is not completed before it's full")
	bus.board_passenger(PassengerColor.Value.YELLOW)
	_check(not bus.is_completed, "bus is not completed with room left")
	bus.board_passenger(PassengerColor.Value.YELLOW)

	_check(bus.is_completed, "bus is completed once it reaches capacity")
	_check(completed_received.size() == 1 and completed_received[0] == bus, "bus_completed fires exactly once, with this bus")

	bus.queue_free()


func _test_inactive_bus_rejects() -> void:
	var bus: Bus = await _make_bus_ready(PassengerColor.Value.PURPLE, 3, false)

	_check(not bus.can_accept(PassengerColor.Value.PURPLE), "an inactive bus does not accept, even a matching color")
	_check(not bus.board_passenger(PassengerColor.Value.PURPLE), "board_passenger() on an inactive bus is rejected")
	_check(bus.current_passengers == 0, "inactive bus is untouched by a boarding attempt")

	bus.queue_free()


func _test_completed_bus_rejects_further_boarding() -> void:
	var bus: Bus = await _make_bus_ready(PassengerColor.Value.RED, 1)

	bus.board_passenger(PassengerColor.Value.RED)
	_check(bus.is_completed, "bus completed after its single seat is filled")

	var completed_received: Array = []
	bus.bus_completed.connect(func(b: Bus) -> void: completed_received.append(b))
	var accepted_after_completion: bool = bus.board_passenger(PassengerColor.Value.RED)

	_check(not accepted_after_completion, "a completed bus rejects further boarding")
	_check(bus.current_passengers == 1, "current_passengers does not change after completion")
	_check(completed_received.is_empty(), "bus_completed does not fire again for an already-completed bus")

	bus.queue_free()
