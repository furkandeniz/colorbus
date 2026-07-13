class_name WaitingArea
extends HBoxContainer
## Row of WaitingSlot positions (default 3, resizable via configure(),
## e.g. from LevelData.waiting_slot_count). Passengers go into the
## first empty slot and are kept in arrival order; a passenger can be
## found/removed by color from any position, and removing one always
## compacts the rest left with no gaps.
##
## `_occupancy: Array[int]` (one PassengerColor.Value, or
## PassengerColor.INVALID, per slot) is the single source of truth -- a
## safe plain-data array, not a set of Node references. Every mutation
## updates _occupancy first, then _render_slot()/_render_all_slots()
## recreate the Passenger nodes to match it; Passengers are never moved
## between slots directly.

signal passenger_added(color: int, slot_index: int)
signal passenger_removed(color: int, slot_index: int)
signal passenger_selected(passenger: Passenger, slot_index: int)
signal waiting_area_full
signal waiting_area_emptied

const DEFAULT_SLOT_COUNT: int = 3
const SlotScene: PackedScene = preload("res://scenes/entities/waiting_slot.tscn")
const PassengerScene: PackedScene = preload("res://scenes/entities/passenger.tscn")

var _slots: Array[WaitingSlot] = []
var _occupancy: Array[int] = []


func _ready() -> void:
	if _slots.is_empty():
		configure(DEFAULT_SLOT_COUNT)


## Sets the number of slots and clears any existing contents. Safe to call
## more than once (e.g. re-configuring for a new level).
func configure(slot_count: int = DEFAULT_SLOT_COUNT) -> void:
	_clear_slots()
	for i: int in slot_count:
		var slot: WaitingSlot = SlotScene.instantiate()
		add_child(slot)
		_slots.append(slot)
		_occupancy.append(PassengerColor.INVALID)


func slot_count() -> int:
	return _slots.size()


func is_full() -> bool:
	return not _occupancy.has(PassengerColor.INVALID)


func is_empty() -> bool:
	for color: int in _occupancy:
		if PassengerColor.is_valid(color):
			return false
	return true


## The color in a given slot, or PassengerColor.INVALID if empty/out of
## range -- the safe, data-only way to inspect contents.
func get_slot_color(index: int) -> int:
	if index < 0 or index >= _occupancy.size():
		return PassengerColor.INVALID
	return _occupancy[index]


## The slot index of the first (earliest-added) passenger of p_color, or
## -1 if none are waiting.
func find_first_slot_of_color(p_color: int) -> int:
	for i: int in _occupancy.size():
		if _occupancy[i] == p_color:
			return i
	return -1


## Adds a passenger of p_color to the first empty slot. Returns the slot
## index it landed in, or -1 if the area is already full (nothing changes
## in that case).
func add_passenger(p_color: int) -> int:
	var index: int = _occupancy.find(PassengerColor.INVALID)
	if index == -1:
		return -1

	_occupancy[index] = p_color
	_render_slot(index)
	passenger_added.emit(p_color, index)

	if is_full():
		waiting_area_full.emit()

	return index


## Removes the passenger at slot_index (if any) and compacts everything
## after it one slot to the left, so there's never a gap. Returns the
## removed color, or PassengerColor.INVALID if that slot was already
## empty or out of range.
func remove_passenger_at(slot_index: int) -> int:
	if slot_index < 0 or slot_index >= _occupancy.size():
		return PassengerColor.INVALID

	var removed_color: int = _occupancy[slot_index]
	if not PassengerColor.is_valid(removed_color):
		return PassengerColor.INVALID

	_occupancy.remove_at(slot_index)
	_occupancy.append(PassengerColor.INVALID)
	for i: int in range(slot_index, _occupancy.size()):
		_render_slot(i)

	passenger_removed.emit(removed_color, slot_index)
	if is_empty():
		waiting_area_emptied.emit()

	return removed_color


## Convenience: finds and removes the first passenger of p_color. Returns
## the slot index it was removed from, or -1 if none was waiting.
func remove_first_of_color(p_color: int) -> int:
	var index: int = find_first_slot_of_color(p_color)
	if index == -1:
		return -1
	remove_passenger_at(index)
	return index


func _on_passenger_selected(passenger: Passenger, slot_index: int) -> void:
	passenger_selected.emit(passenger, slot_index)


## Rebuilds this one slot's Passenger from _occupancy[index] -- always
## clears first, then creates a fresh Passenger if that slot isn't empty.
## Simple and correct rather than diffed/animated: nothing here requires
## preserving a specific Passenger instance across a re-render.
func _render_slot(index: int) -> void:
	var slot: WaitingSlot = _slots[index]
	slot.clear()

	var color: int = _occupancy[index]
	if not PassengerColor.is_valid(color):
		return

	var passenger: Passenger = PassengerScene.instantiate()
	slot.set_passenger(passenger)
	passenger.configure(color)
	passenger.passenger_selected.connect(_on_passenger_selected.bind(index))


func _clear_slots() -> void:
	for slot: WaitingSlot in _slots:
		remove_child(slot)
		slot.queue_free()
	_slots.clear()
	_occupancy.clear()
