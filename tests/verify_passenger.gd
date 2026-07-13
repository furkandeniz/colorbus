extends SceneTree
## Headless checks for the reusable Passenger scene: all 5 colors configure
## correctly, and the selectable/disabled/moving states gate selection and
## change the rendered style. Also smoke-tests the move_to() Tween
## foundation (not wired to any real gameplay target yet).
##
## Real click/tap simulation isn't possible headlessly (the headless
## DisplayServer here doesn't run GUI pointer picking -- see
## docs/ARCHITECTURE.md), so "pressing" the passenger is simulated by
## calling the private _on_pressed() directly, same as
## tests/verify_navigation.gd does for AppRouter's back-button handler.
##
## Usage: godot --headless --path . --script res://tests/verify_passenger.gd

const COLORS: Array[int] = [
	PassengerColor.Value.RED,
	PassengerColor.Value.BLUE,
	PassengerColor.Value.YELLOW,
	PassengerColor.Value.GREEN,
	PassengerColor.Value.PURPLE,
]

var _all_ok: bool = true
var _passenger_scene: PackedScene


func _initialize() -> void:
	_passenger_scene = load("res://scenes/entities/passenger.tscn")

	await _test_default_state()
	for color: int in COLORS:
		await _test_color(color)
	await _test_selectable_gate()
	await _test_disabled_gate()
	await _test_moving_gate()
	await _test_move_to()

	print("[PassengerTest] RESULT: %s" % ("PASS" if _all_ok else "FAIL"))
	quit(0 if _all_ok else 1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_all_ok = false
	print("[PassengerTest] %s -> %s" % [label, "OK" if condition else "FAIL"])


## Instances Passenger, adds it to the tree, and waits a frame so _ready()
## (and its initial _update_visual()) has actually run before the caller
## inspects rendered/derived state.
func _make_passenger_ready() -> Control:
	var passenger: Control = _passenger_scene.instantiate()
	root.add_child(passenger)
	await process_frame
	return passenger


func _test_default_state() -> void:
	var passenger: Control = await _make_passenger_ready()
	_check(passenger.color == PassengerColor.INVALID, "unconfigured passenger has INVALID color")
	_check(not passenger.can_be_selected(), "unconfigured passenger cannot be selected")
	passenger.queue_free()


func _test_color(color: int) -> void:
	var passenger: Control = await _make_passenger_ready()
	passenger.configure(color)

	var label: String = PassengerColor.to_string_key(color)
	_check(passenger.color == color, "configure(%s) stores color" % label)
	_check(passenger.can_be_selected(), "configure(%s) is selectable by default" % label)

	var received: Array = []
	passenger.passenger_selected.connect(func(p: Control) -> void: received.append(p))
	passenger._on_pressed()
	_check(received.size() == 1 and received[0] == passenger, "configure(%s) emits passenger_selected on press" % label)

	passenger.queue_free()


func _test_selectable_gate() -> void:
	var passenger: Control = await _make_passenger_ready()
	passenger.configure(PassengerColor.Value.RED)

	passenger.set_selectable(false)
	_check(not passenger.can_be_selected(), "set_selectable(false) blocks selection")

	var received: Array = []
	passenger.passenger_selected.connect(func(p: Control) -> void: received.append(p))
	passenger._on_pressed()
	_check(received.is_empty(), "not selectable: press does not emit passenger_selected")

	passenger.set_selectable(true)
	_check(passenger.can_be_selected(), "set_selectable(true) restores selection")

	passenger.queue_free()


func _test_disabled_gate() -> void:
	var passenger: Control = await _make_passenger_ready()
	passenger.configure(PassengerColor.Value.BLUE)

	# _input_button is deliberately always enabled (see passenger.gd) so
	# _on_pressed() -- not Button.disabled -- is the single gate; that's
	# what makes play_rejected_feedback() reachable for an unselectable tap.
	var input_button: Button = passenger.get_node("%InputButton")
	_check(not input_button.disabled, "the input button stays enabled regardless of selectability")

	passenger.set_disabled(true)
	_check(not passenger.can_be_selected(), "set_disabled(true) blocks selection")

	var received: Array = []
	passenger.passenger_selected.connect(func(p: Control) -> void: received.append(p))
	passenger._on_pressed()
	_check(received.is_empty(), "disabled: press does not emit passenger_selected")
	_check(not input_button.disabled, "the input button is still enabled after set_disabled(true) (rejected feedback still needs to run)")

	passenger.set_disabled(false)
	_check(passenger.can_be_selected(), "set_disabled(false) restores selection")

	passenger.queue_free()


func _test_moving_gate() -> void:
	var passenger: Control = await _make_passenger_ready()
	passenger.configure(PassengerColor.Value.GREEN)

	passenger.set_moving(true)
	_check(not passenger.can_be_selected(), "set_moving(true) blocks selection")

	passenger.set_moving(false)
	_check(passenger.can_be_selected(), "set_moving(false) restores selection")

	passenger.queue_free()


func _test_move_to() -> void:
	var passenger: Control = await _make_passenger_ready()
	passenger.configure(PassengerColor.Value.PURPLE)
	passenger.position = Vector2.ZERO

	var target: Vector2 = Vector2(200, 0)
	passenger.move_to(target, 0.05)
	_check(passenger.is_moving, "move_to() sets is_moving immediately")
	_check(not passenger.can_be_selected(), "moving passenger cannot be selected")

	await create_timer(0.3).timeout

	_check(not passenger.is_moving, "move_to() clears is_moving once the tween finishes")
	_check(passenger.position.distance_to(target) < 1.0, "move_to() reaches the target position")
	_check(passenger.can_be_selected(), "passenger selectable again after the move finishes")

	passenger.queue_free()
