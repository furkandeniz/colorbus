class_name Bus
extends Control
## Reusable bus token: color, capacity, current passenger count, active/
## completed state, and a fill indicator. No external visual assets --
## appearance is a rounded Panel plus a ProgressBar, both colored at
## runtime from PassengerColor. Business logic (configure/board_passenger/
## set_active) and visual updates (_update_visual) are kept in separate
## methods. Unlike Passenger, a Bus has no click/tap surface of its own --
## boarding is driven programmatically (by whatever decides a selected
## passenger matches the active bus), not by tapping the bus.

signal passenger_boarded(bus: Bus)
signal bus_completed(bus: Bus)

const CORNER_RADIUS: int = 24

var color: int = PassengerColor.INVALID
var capacity: int = 0
var current_passengers: int = 0
var is_active: bool = false
var is_completed: bool = false

@onready var _visual: Panel = %Visual
@onready var _fill_bar: ProgressBar = %FillBar
@onready var _count_label: Label = %CountLabel


func _ready() -> void:
	_update_visual()


## The one entry point for setting this bus's color/capacity from outside.
## Always starts a fresh bus: 0 passengers, not completed. Only touches
## data; _update_visual() does the actual redraw.
func configure(p_color: int, p_capacity: int) -> void:
	color = p_color
	capacity = p_capacity
	current_passengers = 0
	is_completed = false
	_update_visual()


func set_active(p_active: bool) -> void:
	is_active = p_active
	_update_visual()


## Whether this bus would currently accept a passenger of p_color: active,
## not already completed, has room left, and configured with a color that
## actually matches.
func can_accept(p_color: int) -> bool:
	return (
		is_active
		and not is_completed
		and PassengerColor.is_valid(color)
		and current_passengers < capacity
		and p_color == color
	)


## Boards one passenger of p_color if can_accept(p_color) is true. Returns
## whether it actually boarded -- never exceeds capacity, never boards a
## mismatched color, never boards onto an inactive/completed bus. Marks
## the bus completed (and emits bus_completed) the moment it reaches
## capacity.
func board_passenger(p_color: int) -> bool:
	if not can_accept(p_color):
		return false

	current_passengers += 1
	passenger_boarded.emit(self)

	if current_passengers >= capacity:
		is_completed = true
		bus_completed.emit(self)

	_update_visual()
	return true


## The only place appearance is computed/applied. configure()/set_active()
## can legitimately be called right after instantiate() + add_child(),
## before _ready() has run (@onready vars not resolved yet) -- in that
## case just skip the redraw; _ready() calls _update_visual() itself once
## the node is actually ready.
func _update_visual() -> void:
	if not is_node_ready():
		return

	var base_color: Color = PassengerColor.to_rgb(color)
	var showing_active: bool = is_active and not is_completed
	var display_color: Color = base_color if showing_active else base_color.lerp(Color(0.55, 0.55, 0.55), 0.6)

	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = display_color
	panel_style.set_corner_radius_all(CORNER_RADIUS)
	_visual.add_theme_stylebox_override("panel", panel_style)

	var fill_style: StyleBoxFlat = StyleBoxFlat.new()
	fill_style.bg_color = base_color
	fill_style.set_corner_radius_all(CORNER_RADIUS)
	_fill_bar.add_theme_stylebox_override("fill", fill_style)

	_fill_bar.max_value = max(capacity, 1)
	_fill_bar.value = current_passengers

	_count_label.text = "%d/%d" % [current_passengers, capacity]
