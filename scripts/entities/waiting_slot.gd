class_name WaitingSlot
extends Control
## A single waiting-area position holding at most one Passenger. No
## external visual assets -- an always-visible faint bordered Panel gives
## the slot a boundary so empty slots are still visible; a Passenger (when
## present) renders on top of it. WaitingSlot makes no add/remove/boarding
## decisions of its own -- it's a dumb container; WaitingArea owns all of
## that logic and decides what goes in each slot.

const CORNER_RADIUS: int = 16

@onready var _outline: Panel = %SlotOutline

var _passenger: Passenger = null


func _ready() -> void:
	_update_outline()


func is_empty() -> bool:
	return _passenger == null


## The color currently shown here, or PassengerColor.INVALID if empty --
## the safe, data-only way to query slot contents without touching a Node.
func get_color() -> int:
	return _passenger.color if _passenger != null else PassengerColor.INVALID


func get_passenger() -> Passenger:
	return _passenger


## Parents p_passenger into this slot. Callers must clear() first if the
## slot is already occupied -- a slot only ever holds one passenger.
func set_passenger(p_passenger: Passenger) -> void:
	_passenger = p_passenger
	add_child(p_passenger)
	_update_outline()


func clear() -> void:
	if _passenger != null:
		_passenger.queue_free()
		_passenger = null
	_update_outline()


## Like clear(), but hands back the live Passenger instead of freeing it --
## used when the caller wants to animate it (flying to a bus, say) before
## it's actually disposed of.
func take_passenger() -> Passenger:
	if _passenger == null:
		return null
	var passenger: Passenger = _passenger
	remove_child(passenger)
	_passenger = null
	_update_outline()
	return passenger


func _update_outline() -> void:
	if not is_node_ready():
		return

	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.05)
	style.set_border_width_all(2)
	style.border_color = Color(1, 1, 1, 0.2)
	style.set_corner_radius_all(CORNER_RADIUS)
	_outline.add_theme_stylebox_override("panel", style)
