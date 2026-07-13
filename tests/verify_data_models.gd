extends SceneTree
## Headless unit tests for the typed data models in scripts/data,
## scripts/entities and scripts/game (PassengerColor, PassengerData,
## BusData, PassengerQueueData, LevelData, GameState, GameStateSnapshot).
## Pure data -- no scene tree/app boot needed, but this still extends
## SceneTree since that's the simplest way to get a headless process with
## a clean exit code.
##
## Usage: godot --headless --path . --script res://tests/verify_data_models.gd

var _all_ok: bool = true


func _initialize() -> void:
	_test_passenger_color()
	_test_passenger_data()
	_test_bus_data()
	_test_passenger_queue_data()
	_test_level_data()
	_test_game_state()
	_test_game_state_snapshot()

	print("[DataModelTest] RESULT: %s" % ("PASS" if _all_ok else "FAIL"))
	quit(0 if _all_ok else 1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_all_ok = false
	print("[DataModelTest] %s -> %s" % [label, "OK" if condition else "FAIL"])


func _test_passenger_color() -> void:
	_check(PassengerColor.from_string("red") == PassengerColor.Value.RED, "PassengerColor red")
	_check(PassengerColor.from_string("BLUE") == PassengerColor.Value.BLUE, "PassengerColor case-insensitive")
	_check(PassengerColor.from_string("yellow") == PassengerColor.Value.YELLOW, "PassengerColor yellow")
	_check(PassengerColor.from_string("green") == PassengerColor.Value.GREEN, "PassengerColor green")
	_check(PassengerColor.from_string("purple") == PassengerColor.Value.PURPLE, "PassengerColor purple")
	_check(PassengerColor.from_string("magenta") == PassengerColor.INVALID, "PassengerColor unknown color -> INVALID, not silently accepted")
	_check(not PassengerColor.is_valid(PassengerColor.INVALID), "PassengerColor.is_valid(INVALID) is false")
	_check(PassengerColor.is_valid(PassengerColor.Value.RED), "PassengerColor.is_valid(RED) is true")
	_check(PassengerColor.to_string_key(PassengerColor.Value.GREEN) == "green", "PassengerColor round-trip")


func _test_passenger_data() -> void:
	var valid_passenger: PassengerData = PassengerData.from_dict({"color": "red"})
	_check(valid_passenger.is_valid(), "PassengerData valid color")

	var invalid_passenger: PassengerData = PassengerData.from_dict({"color": "not_a_color"})
	_check(not invalid_passenger.is_valid(), "PassengerData unknown color is invalid")

	var missing_passenger: PassengerData = PassengerData.from_dict({})
	_check(not missing_passenger.is_valid(), "PassengerData missing color is invalid")

	_check(valid_passenger.to_dict() == {"color": "red"}, "PassengerData round-trip to_dict")


func _test_bus_data() -> void:
	var valid_bus: BusData = BusData.from_dict({"color": "blue", "capacity": 3})
	_check(valid_bus.is_valid(), "BusData valid")

	var zero_capacity_bus: BusData = BusData.from_dict({"color": "blue", "capacity": 0})
	_check(not zero_capacity_bus.is_valid(), "BusData zero capacity is invalid")

	var bad_color_bus: BusData = BusData.from_dict({"color": "not_a_color", "capacity": 3})
	_check(not bad_color_bus.is_valid(), "BusData unknown color is invalid")

	_check(valid_bus.to_dict() == {"color": "blue", "capacity": 3}, "BusData round-trip to_dict")


func _test_passenger_queue_data() -> void:
	var empty_queue: PassengerQueueData = PassengerQueueData.new()
	_check(empty_queue.is_valid(), "empty PassengerQueueData is valid")
	_check(empty_queue.is_empty(), "empty PassengerQueueData is_empty")
	_check(empty_queue.front() == null, "empty PassengerQueueData front() is null")

	var source_array: Array = [{"color": "red"}, {"color": "blue"}]
	var queue: PassengerQueueData = PassengerQueueData.from_array(source_array)
	_check(queue.is_valid(), "PassengerQueueData from valid array is valid")
	_check(queue.front().color == PassengerColor.Value.RED, "PassengerQueueData front() is first passenger")
	_check(queue.to_array() == source_array, "PassengerQueueData round-trip to_array")

	var popped: PassengerData = queue.pop_front()
	_check(popped.color == PassengerColor.Value.RED, "PassengerQueueData pop_front returns front")
	_check(queue.front().color == PassengerColor.Value.BLUE, "PassengerQueueData pop_front advances")

	var bad_queue: PassengerQueueData = PassengerQueueData.from_array([{"color": "not_a_color"}])
	_check(not bad_queue.is_valid(), "PassengerQueueData with invalid passenger is invalid")


## A fully-shaped, balanced level dict (red: capacity 2 / 2 passengers,
## blue: capacity 3 / 3 passengers) -- the data-model layer doesn't itself
## check balance (that's LevelValidator's job, covered in
## tests/verify_level_loading.gd), but there's no reason to hand these
## tests an unrealistic sample.
func _make_sample_level_dict() -> Dictionary:
	return {
		"id": 42,
		"name_key": "level.test.name",
		"waiting_slot_count": 3,
		"buses": [
			{"color": "red", "capacity": 2},
			{"color": "blue", "capacity": 3},
		],
		"passenger_queues": [
			[{"color": "red"}, {"color": "blue"}],
			[{"color": "blue"}, {"color": "blue"}, {"color": "red"}],
		],
		"move_limit": 20,
		"tutorial": false,
		"difficulty": 2,
	}


func _test_level_data() -> void:
	var level: LevelData = LevelData.from_dict(_make_sample_level_dict())
	_check(level.is_valid(), "LevelData valid sample")
	_check(level.id == 42, "LevelData id")
	_check(level.name_key == "level.test.name", "LevelData name_key")
	_check(level.waiting_slot_count == 3, "LevelData waiting_slot_count")
	_check(level.buses.size() == 2, "LevelData buses size")
	_check(level.passenger_queues.size() == 2, "LevelData passenger_queues size")
	_check(level.move_limit == 20, "LevelData move_limit")
	_check(not level.tutorial, "LevelData tutorial")
	_check(level.difficulty == 2, "LevelData difficulty")

	var empty_level: LevelData = LevelData.from_dict({})
	_check(not empty_level.is_valid(), "LevelData empty dict is invalid")

	var no_buses_level: LevelData = LevelData.from_dict({"id": 1, "waiting_slot_count": 3})
	_check(not no_buses_level.is_valid(), "LevelData with no buses is invalid")


func _test_game_state() -> void:
	var level: LevelData = LevelData.from_dict(_make_sample_level_dict())
	var state: GameState = GameState.from_level(level)

	_check(state.is_valid(), "GameState from valid level is valid")
	_check(state.level_id == 42, "GameState.level_id matches LevelData.id")
	_check(state.waiting_slot_count == 3, "GameState.waiting_slot_count matches LevelData")
	_check(state.passenger_queues.size() == 2, "GameState.passenger_queues carried over from LevelData")
	_check(state.current_bus != null and state.current_bus.color == PassengerColor.Value.RED, "GameState current_bus is first bus")
	_check(state.bus_queue.size() == 1, "GameState bus_queue popped first bus")
	_check(state.moves_made == 0, "GameState starts with zero moves")
	_check(state.move_limit == 20, "GameState.move_limit matches LevelData")


func _test_game_state_snapshot() -> void:
	var level: LevelData = LevelData.from_dict(_make_sample_level_dict())
	var state: GameState = GameState.from_level(level)
	state.moves_made = 4

	var snapshot: GameStateSnapshot = state.to_snapshot()
	_check(snapshot.is_valid(), "GameStateSnapshot is valid")
	_check(_is_pure_data(snapshot.data), "GameStateSnapshot.data contains only pure data, no model/Node objects")

	var restored: GameState = snapshot.restore_game_state()
	_check(restored.level_id == state.level_id, "GameStateSnapshot restores level_id")
	_check(restored.waiting_slot_count == state.waiting_slot_count, "GameStateSnapshot restores waiting_slot_count")
	_check(restored.passenger_queues.size() == state.passenger_queues.size(), "GameStateSnapshot restores passenger_queues")
	_check(restored.moves_made == 4, "GameStateSnapshot restores moves_made")
	_check(restored.current_bus.color == state.current_bus.color, "GameStateSnapshot restores current_bus")
	_check(restored.is_valid(), "restored GameState is valid")

	var json_text: String = snapshot.to_json_string()
	var round_tripped: GameStateSnapshot = GameStateSnapshot.from_json_string(json_text)
	_check(round_tripped != null and round_tripped.is_valid(), "GameStateSnapshot JSON round-trip parses")
	_check(round_tripped.data.get("moves_made") == 4, "GameStateSnapshot JSON round-trip preserves data")


## Recursively confirms a value is JSON-safe pure data: no Object
## (RefCounted model, Node, etc.) anywhere in the structure.
func _is_pure_data(value: Variant) -> bool:
	match typeof(value):
		TYPE_DICTIONARY:
			for key: Variant in value:
				if not _is_pure_data(key) or not _is_pure_data(value[key]):
					return false
			return true
		TYPE_ARRAY:
			for item: Variant in value:
				if not _is_pure_data(item):
					return false
			return true
		TYPE_OBJECT:
			return false
		_:
			return true
