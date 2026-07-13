class_name PassengerQueue
extends VBoxContainer
## Vertical queue of Passenger tokens. Only the front (topmost) passenger is
## selectable; removing it promotes the next one automatically. `_passengers`
## is the single source of truth for both data order and visual order --
## Passenger nodes are the queue's children in the exact same order as this
## array, so the two can never drift apart (there's no separate index to
## keep in sync).

signal passenger_selected(passenger: Passenger)
signal passenger_removed(color: int)
signal queue_emptied

const PassengerScene: PackedScene = preload("res://scenes/entities/passenger.tscn")
const REMOVE_DURATION: float = 0.2

var _passengers: Array[Passenger] = []
var _is_locked: bool = false
var _removed_passengers: Dictionary = {}


## Rebuilds the queue from a list of PassengerColor.Value colors (front is
## colors[0]). Clears any existing passengers first, so this is safe to
## call more than once on the same queue.
func configure(colors: Array[int]) -> void:
	_clear()
	for color: int in colors:
		var passenger: Passenger = PassengerScene.instantiate()
		add_child(passenger)
		passenger.configure(color)
		passenger.passenger_selected.connect(_on_passenger_selected)
		_passengers.append(passenger)
	_refresh_selectable()


func is_empty() -> bool:
	return _passengers.is_empty()


func passenger_count() -> int:
	return _passengers.size()


func front() -> Passenger:
	return _passengers[0] if not _passengers.is_empty() else null


func is_locked() -> bool:
	return _is_locked


func _on_passenger_selected(passenger: Passenger) -> void:
	passenger_selected.emit(passenger)


## Removes the front passenger (e.g. once it's boarded a bus), locking the
## whole queue for the duration of the fade-out so nothing else can be
## selected mid-animation, then promoting the new front and emitting
## queue_emptied if that was the last passenger. A no-op if the queue is
## already locked, empty, or (defensively) if this exact passenger has
## already been removed -- never removes the same passenger twice.
func remove_front() -> void:
	if _is_locked:
		return
	var passenger: Passenger = front()
	if passenger == null or _removed_passengers.has(passenger):
		return

	_removed_passengers[passenger] = true
	_is_locked = true
	_refresh_selectable()

	var tween: Tween = create_tween()
	tween.tween_property(passenger, "modulate:a", 0.0, REMOVE_DURATION)
	tween.finished.connect(_on_remove_finished.bind(passenger))


func _on_remove_finished(passenger: Passenger) -> void:
	var color: int = passenger.color

	_passengers.erase(passenger)
	remove_child(passenger)
	passenger.queue_free()

	_is_locked = false
	_refresh_selectable()

	passenger_removed.emit(color)

	if _passengers.is_empty():
		queue_emptied.emit()


func _clear() -> void:
	for passenger: Passenger in _passengers:
		if passenger.passenger_selected.is_connected(_on_passenger_selected):
			passenger.passenger_selected.disconnect(_on_passenger_selected)
		remove_child(passenger)
		passenger.queue_free()
	_passengers.clear()
	_removed_passengers.clear()
	_is_locked = false


## The only place selectable state is assigned: locked -> nobody selectable,
## unlocked -> only index 0 (the front) is.
func _refresh_selectable() -> void:
	for i: int in _passengers.size():
		_passengers[i].set_selectable(not _is_locked and i == 0)
