extends Control
## Manual/visual test harness for PassengerQueue: open
## scenes/game/passenger_queue_test.tscn directly in the Godot editor to
## click through multiple queues -- select the front passenger, remove it
## with the button below each queue, and watch the queue advance and (once
## empty) disappear. Not part of the automated suite -- see
## tests/verify_passenger_queue.gd for that.

const QueueScene: PackedScene = preload("res://scenes/game/passenger_queue.tscn")

const DEMO_QUEUES: Array[Array] = [
	[PassengerColor.Value.RED, PassengerColor.Value.BLUE, PassengerColor.Value.YELLOW],
	[PassengerColor.Value.GREEN, PassengerColor.Value.PURPLE],
	[PassengerColor.Value.BLUE, PassengerColor.Value.RED, PassengerColor.Value.GREEN, PassengerColor.Value.PURPLE],
]

@onready var _queue_row: HBoxContainer = %QueueRow
@onready var _status_label: Label = %StatusLabel

var _queues: Array[PassengerQueue] = []


func _ready() -> void:
	for colors: Array in DEMO_QUEUES:
		var typed_colors: Array[int] = []
		for color: Variant in colors:
			typed_colors.append(color)
		_add_queue_column(typed_colors)

	_status_label.text = "status.no_selection"


func _add_queue_column(colors: Array[int]) -> void:
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)

	var queue: PassengerQueue = QueueScene.instantiate()
	column.add_child(queue)
	queue.configure(colors)
	queue.passenger_selected.connect(_on_passenger_selected.bind(queue))
	queue.queue_emptied.connect(_on_queue_emptied.bind(queue))
	_queues.append(queue)

	var remove_button: Button = Button.new()
	remove_button.text = "controls.remove_front"
	remove_button.pressed.connect(_on_remove_pressed.bind(queue))
	column.add_child(remove_button)

	_queue_row.add_child(column)


func _on_passenger_selected(passenger: Passenger, queue: PassengerQueue) -> void:
	_status_label.text = "status.selected:%s" % PassengerColor.to_string_key(passenger.color)


func _on_remove_pressed(queue: PassengerQueue) -> void:
	queue.remove_front()


func _on_queue_emptied(queue: PassengerQueue) -> void:
	_status_label.text = "status.queue_emptied"
