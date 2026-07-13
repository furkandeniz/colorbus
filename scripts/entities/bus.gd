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
	pivot_offset = size / 2.0
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
	var was_active: bool = is_active
	is_active = p_active
	_update_visual()
	if p_active and not was_active:
		_play_entrance_animation()


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
		_play_completion_celebration()
		return true

	_update_visual()
	return true


## A new bus becoming active gets a brief scale bounce -- purely cosmetic,
## self-contained (Bus reacts to its own state change; nothing external
## needs to await this). Uses scale, never position -- BusQueue is a
## Container (HBoxContainer) that would silently override a position tween
## every frame.
func _play_entrance_animation() -> void:
	scale = Vector2(0.8, 0.8)
	var duration: float = AnimationConfig.duration(AnimationConfig.BUS_ENTRANCE)
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector2.ONE, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## A short "pop" celebration once the bus fills up, then a fade+shrink
## exit -- purely visual. The bus itself is never removed from BusQueue's
## _buses array or the scene tree (completed buses stay in place, per
## docs/ARCHITECTURE.md) -- this only ever touches scale/modulate/
## custom_minimum_size, so BusQueue's layout naturally reclaims the space
## once shrunk to zero, without any node ever being freed or the "don't
## remove completed buses" rule changing at all.
func _play_completion_celebration() -> void:
	var celebration_duration: float = AnimationConfig.duration(AnimationConfig.BUS_CELEBRATION)
	var exit_duration: float = AnimationConfig.duration(AnimationConfig.BUS_EXIT)

	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.15, 1.15), celebration_duration * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE, celebration_duration * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, exit_duration)
	tween.tween_property(self, "scale", Vector2.ZERO, exit_duration)
	tween.tween_property(self, "custom_minimum_size", Vector2.ZERO, exit_duration)


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
