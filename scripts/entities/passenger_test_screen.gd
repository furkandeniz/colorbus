extends Control
## Manual/visual test harness for the Passenger scene: open
## scenes/entities/passenger_test.tscn directly in the Godot editor and run
## it to click through all 5 colors, toggle selectable/disabled, and try
## the move_to() Tween demo. Not part of the automated suite -- headless
## GUI clicks can't be simulated in this project's environment (see
## docs/ARCHITECTURE.md); tests/verify_passenger.gd covers the automated
## checks by calling the same code paths directly instead.

const PassengerScene: PackedScene = preload("res://scenes/entities/passenger.tscn")

const DEMO_COLORS: Array[int] = [
	PassengerColor.Value.RED,
	PassengerColor.Value.BLUE,
	PassengerColor.Value.YELLOW,
	PassengerColor.Value.GREEN,
	PassengerColor.Value.PURPLE,
]

@onready var _passenger_row: HBoxContainer = %PassengerRow
@onready var _status_label: Label = %StatusLabel
@onready var _toggle_selectable_button: Button = %ToggleSelectableButton
@onready var _toggle_disabled_button: Button = %ToggleDisabledButton
@onready var _move_demo_button: Button = %MoveDemoButton

var _passengers: Array[Control] = []
var _selectable_state: bool = true
var _disabled_state: bool = false


func _ready() -> void:
	for color: int in DEMO_COLORS:
		var passenger: Control = PassengerScene.instantiate()
		_passenger_row.add_child(passenger)
		passenger.configure(color)
		passenger.passenger_selected.connect(_on_passenger_selected)
		_passengers.append(passenger)

	_toggle_selectable_button.pressed.connect(_on_toggle_selectable_pressed)
	_toggle_disabled_button.pressed.connect(_on_toggle_disabled_pressed)
	_move_demo_button.pressed.connect(_on_move_demo_pressed)

	_status_label.text = "status.no_selection"


func _on_passenger_selected(passenger: Control) -> void:
	_status_label.text = "status.selected:%s" % PassengerColor.to_string_key(passenger.color)


func _on_toggle_selectable_pressed() -> void:
	_selectable_state = not _selectable_state
	for passenger: Control in _passengers:
		passenger.set_selectable(_selectable_state)


func _on_toggle_disabled_pressed() -> void:
	_disabled_state = not _disabled_state
	for passenger: Control in _passengers:
		passenger.set_disabled(_disabled_state)


func _on_move_demo_pressed() -> void:
	for i: int in _passengers.size():
		var passenger: Control = _passengers[i]
		var offset: Vector2 = Vector2(0, -40 if i % 2 == 0 else 40)
		passenger.move_to(passenger.position + offset, 0.4)
