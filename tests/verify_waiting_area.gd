extends SceneTree
## Headless checks for WaitingArea/WaitingSlot: adding to the first empty
## slot, rejecting additions once full, finding a passenger by color,
## left-compaction after a removal, a dynamic slot count (including one
## derived from a LevelData, per the requirement that slot count can come
## from there), and the full/empty signals.
##
## Usage: godot --headless --path . --script res://tests/verify_waiting_area.gd

var _all_ok: bool = true
var _area_scene: PackedScene


func _initialize() -> void:
	_area_scene = load("res://scenes/game/waiting_area.tscn")

	await _test_default_slot_count()
	await _test_add_to_first_empty_slot()
	await _test_add_to_full_area_rejected()
	await _test_find_by_color()
	await _test_compaction_after_removal()
	await _test_dynamic_slot_count()
	await _test_full_and_emptied_signals()
	await _test_added_removed_signals()

	print("[WaitingAreaTest] RESULT: %s" % ("PASS" if _all_ok else "FAIL"))
	quit(0 if _all_ok else 1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_all_ok = false
	print("[WaitingAreaTest] %s -> %s" % [label, "OK" if condition else "FAIL"])


func _make_area_ready() -> WaitingArea:
	var area: WaitingArea = _area_scene.instantiate()
	root.add_child(area)
	await process_frame
	return area


func _test_default_slot_count() -> void:
	var area: WaitingArea = await _make_area_ready()
	_check(area.slot_count() == 3, "default slot count is 3")
	_check(area.is_empty(), "a freshly configured area is empty")
	_check(not area.is_full(), "a freshly configured area is not full")
	area.queue_free()


func _test_add_to_first_empty_slot() -> void:
	var area: WaitingArea = await _make_area_ready()

	var index_1: int = area.add_passenger(PassengerColor.Value.RED)
	_check(index_1 == 0, "first passenger lands in slot 0")
	_check(area.get_slot_color(0) == PassengerColor.Value.RED, "slot 0 shows the color that was added")

	var index_2: int = area.add_passenger(PassengerColor.Value.BLUE)
	_check(index_2 == 1, "second passenger lands in the next empty slot (1)")
	_check(area.get_slot_color(1) == PassengerColor.Value.BLUE, "slot 1 shows the second color")
	_check(area.get_slot_color(0) == PassengerColor.Value.RED, "slot 0 is undisturbed by the second addition")

	area.queue_free()


func _test_add_to_full_area_rejected() -> void:
	var area: WaitingArea = await _make_area_ready()

	area.add_passenger(PassengerColor.Value.RED)
	area.add_passenger(PassengerColor.Value.BLUE)
	area.add_passenger(PassengerColor.Value.YELLOW)
	_check(area.is_full(), "area reports full once all 3 default slots are occupied")

	var rejected_index: int = area.add_passenger(PassengerColor.Value.GREEN)
	_check(rejected_index == -1, "add_passenger() on a full area returns -1")
	_check(area.get_slot_color(0) == PassengerColor.Value.RED, "slot 0 is unchanged after a rejected addition")
	_check(area.get_slot_color(1) == PassengerColor.Value.BLUE, "slot 1 is unchanged after a rejected addition")
	_check(area.get_slot_color(2) == PassengerColor.Value.YELLOW, "slot 2 is unchanged after a rejected addition")

	area.queue_free()


func _test_find_by_color() -> void:
	var area: WaitingArea = await _make_area_ready()

	area.add_passenger(PassengerColor.Value.RED)
	area.add_passenger(PassengerColor.Value.BLUE)
	area.add_passenger(PassengerColor.Value.YELLOW)

	_check(area.find_first_slot_of_color(PassengerColor.Value.BLUE) == 1, "finds BLUE in slot 1")
	_check(area.find_first_slot_of_color(PassengerColor.Value.RED) == 0, "finds RED in slot 0")
	_check(area.find_first_slot_of_color(PassengerColor.Value.PURPLE) == -1, "a color that isn't waiting returns -1")

	area.queue_free()


func _test_compaction_after_removal() -> void:
	var area: WaitingArea = await _make_area_ready()

	area.add_passenger(PassengerColor.Value.RED)
	area.add_passenger(PassengerColor.Value.BLUE)
	area.add_passenger(PassengerColor.Value.YELLOW)

	var removed_color: int = area.remove_passenger_at(0)
	_check(removed_color == PassengerColor.Value.RED, "remove_passenger_at(0) returns the color that was there")

	_check(area.get_slot_color(0) == PassengerColor.Value.BLUE, "slot 0 now holds what was in slot 1 (compacted left)")
	_check(area.get_slot_color(1) == PassengerColor.Value.YELLOW, "slot 1 now holds what was in slot 2")
	_check(area.get_slot_color(2) == PassengerColor.INVALID, "slot 2 is empty -- no gap was left behind")
	_check(not area.is_full(), "area is no longer full after a removal")

	# Removing from the middle should compact the same way.
	var area2: WaitingArea = await _make_area_ready()
	area2.add_passenger(PassengerColor.Value.RED)
	area2.add_passenger(PassengerColor.Value.BLUE)
	area2.add_passenger(PassengerColor.Value.YELLOW)
	area2.remove_passenger_at(1)
	_check(area2.get_slot_color(0) == PassengerColor.Value.RED, "removing the middle slot leaves slot 0 untouched")
	_check(area2.get_slot_color(1) == PassengerColor.Value.YELLOW, "removing the middle slot pulls the last one left")
	_check(area2.get_slot_color(2) == PassengerColor.INVALID, "trailing slot is empty after middle removal")

	area.queue_free()
	area2.queue_free()


func _test_dynamic_slot_count() -> void:
	var area: WaitingArea = await _make_area_ready()

	area.configure(5)
	_check(area.slot_count() == 5, "configure(5) resizes the area to 5 slots")
	for i: int in 5:
		_check(area.add_passenger(PassengerColor.Value.RED) == i, "slot %d fills in order up to 5" % i)
	_check(area.is_full(), "a 5-slot area is full only once all 5 are occupied")

	area.configure(1)
	_check(area.slot_count() == 1, "reconfigure(1) shrinks the area and clears previous contents")
	_check(area.is_empty(), "reconfiguring clears any previously waiting passengers")

	# The requirement is specifically that slot count can come from
	# LevelData -- prove that path end to end, not just a bare int.
	var level: LevelData = LevelData.from_dict({
		"id": 999,
		"waiting_slot_count": 4,
		"buses": [{"color": "red", "capacity": 1}],
	})
	area.configure(level.waiting_slot_count)
	_check(area.slot_count() == level.waiting_slot_count, "slot count can be driven from LevelData.waiting_slot_count")
	_check(area.slot_count() == 4, "the LevelData in this test specifies 4 slots")

	area.queue_free()


func _test_full_and_emptied_signals() -> void:
	var area: WaitingArea = await _make_area_ready()

	var full_flag: Array = [false]
	var emptied_flag: Array = [false]
	area.waiting_area_full.connect(func() -> void: full_flag[0] = true)
	area.waiting_area_emptied.connect(func() -> void: emptied_flag[0] = true)

	area.add_passenger(PassengerColor.Value.RED)
	_check(not full_flag[0], "waiting_area_full has not fired with slots still open")
	area.add_passenger(PassengerColor.Value.BLUE)
	_check(not full_flag[0], "waiting_area_full still hasn't fired with one slot left")
	area.add_passenger(PassengerColor.Value.YELLOW)
	_check(full_flag[0], "waiting_area_full fires the moment the last slot fills")

	area.remove_passenger_at(0)
	_check(not emptied_flag[0], "waiting_area_emptied has not fired with passengers still waiting")
	area.remove_passenger_at(0)
	_check(not emptied_flag[0], "waiting_area_emptied still hasn't fired with one passenger left")
	area.remove_passenger_at(0)
	_check(emptied_flag[0], "waiting_area_emptied fires once the last passenger is removed")

	area.queue_free()


func _test_added_removed_signals() -> void:
	var area: WaitingArea = await _make_area_ready()

	var added: Array = []
	var removed: Array = []
	area.passenger_added.connect(func(color: int, index: int) -> void: added.append([color, index]))
	area.passenger_removed.connect(func(color: int, index: int) -> void: removed.append([color, index]))

	area.add_passenger(PassengerColor.Value.GREEN)
	_check(added.size() == 1 and added[0] == [PassengerColor.Value.GREEN, 0], "passenger_added fires with (color, slot_index)")

	area.remove_first_of_color(PassengerColor.Value.GREEN)
	_check(removed.size() == 1 and removed[0] == [PassengerColor.Value.GREEN, 0], "passenger_removed fires with (color, slot_index)")

	area.queue_free()
