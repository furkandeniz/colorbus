class_name BusQueue
extends HBoxContainer
## Horizontal queue of Bus tokens, arriving in sequence -- only the first
## (index 0 among the not-yet-completed buses) is ever active. Buses are
## never removed once completed: they stay visible, marked completed, and
## _active_index simply advances to the next one. Business logic lives
## entirely here and in Bus; this class does no rendering of its own
## beyond arranging Bus children (an HBoxContainer).

signal active_bus_changed(bus: Bus)
signal bus_queue_completed

const BusScene: PackedScene = preload("res://scenes/entities/bus.tscn")

var _buses: Array[Bus] = []
var _active_index: int = -1


## Rebuilds the queue from a list of BusData (bus_data_list[0] arrives
## first). Clears any existing buses first, so this is safe to call more
## than once on the same queue.
func configure(bus_data_list: Array[BusData]) -> void:
	_clear()
	for bus_data: BusData in bus_data_list:
		var bus: Bus = BusScene.instantiate()
		add_child(bus)
		bus.configure(bus_data.color, bus_data.capacity)
		bus.bus_completed.connect(_on_bus_completed)
		_buses.append(bus)

	_active_index = 0 if not _buses.is_empty() else -1
	_refresh_active()
	if active_bus() != null:
		active_bus_changed.emit(active_bus())


func is_empty() -> bool:
	return _buses.is_empty()


func bus_count() -> int:
	return _buses.size()


func active_bus() -> Bus:
	if _active_index < 0 or _active_index >= _buses.size():
		return null
	return _buses[_active_index]


func _on_bus_completed(bus: Bus) -> void:
	# Guard against a stale signal from a bus that isn't the active one
	# mattering here -- only the active bus completing should ever advance
	# the queue.
	if bus != active_bus():
		return

	_active_index += 1
	_refresh_active()

	if active_bus() != null:
		active_bus_changed.emit(active_bus())
	else:
		bus_queue_completed.emit()


func _refresh_active() -> void:
	for i: int in _buses.size():
		_buses[i].set_active(i == _active_index)


func _clear() -> void:
	for bus: Bus in _buses:
		if bus.bus_completed.is_connected(_on_bus_completed):
			bus.bus_completed.disconnect(_on_bus_completed)
		remove_child(bus)
		bus.queue_free()
	_buses.clear()
	_active_index = -1
