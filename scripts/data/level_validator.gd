class_name LevelValidator
extends RefCounted
## Validates a level's raw JSON Dictionary against every level-system rule
## (see docs/ARCHITECTURE.md), producing a LevelValidationResult with
## descriptive, file+field-path-prefixed errors. Runs on the raw JSON --
## LevelData.from_dict() is only ever called after this passes, so a
## broken level never gets converted, let alone handed to a game scene.

const REQUIRED_FIELDS: Array[String] = [
	"id", "name_key", "waiting_slot_count", "buses", "passenger_queues",
	"move_limit", "tutorial", "difficulty",
]


static func validate(data: Dictionary, source_label: String) -> LevelValidationResult:
	var result: LevelValidationResult = LevelValidationResult.new(source_label)

	for field: String in REQUIRED_FIELDS:
		if not data.has(field):
			result.add_error(field, "missing required field")

	if not result.is_valid():
		return result

	_validate_id(data, result)
	_validate_waiting_slot_count(data, result)
	_validate_name_key(data, result)
	_validate_move_limit(data, result)
	_validate_tutorial(data, result)
	_validate_difficulty(data, result)

	var bus_totals: Dictionary = _validate_buses(data, result)
	var passenger_totals: Dictionary = _validate_passenger_queues(data, result)

	if result.is_valid():
		_validate_balance(bus_totals, passenger_totals, result)

	return result


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _validate_id(data: Dictionary, result: LevelValidationResult) -> void:
	if not _is_number(data["id"]):
		result.add_error("id", "must be a number")
	elif int(data["id"]) <= 0:
		result.add_error("id", "must be positive, got %s" % str(data["id"]))


static func _validate_waiting_slot_count(data: Dictionary, result: LevelValidationResult) -> void:
	if not _is_number(data["waiting_slot_count"]):
		result.add_error("waiting_slot_count", "must be a number")
	elif int(data["waiting_slot_count"]) <= 0:
		result.add_error("waiting_slot_count", "must be greater than zero, got %s" % str(data["waiting_slot_count"]))


static func _validate_name_key(data: Dictionary, result: LevelValidationResult) -> void:
	if typeof(data["name_key"]) != TYPE_STRING or str(data["name_key"]).is_empty():
		result.add_error("name_key", "must be a non-empty string")


static func _validate_move_limit(data: Dictionary, result: LevelValidationResult) -> void:
	if not _is_number(data["move_limit"]):
		result.add_error("move_limit", "must be a number")
	elif int(data["move_limit"]) < 0:
		result.add_error("move_limit", "must not be negative, got %s" % str(data["move_limit"]))


static func _validate_tutorial(data: Dictionary, result: LevelValidationResult) -> void:
	if typeof(data["tutorial"]) != TYPE_BOOL:
		result.add_error("tutorial", "must be a boolean")


static func _validate_difficulty(data: Dictionary, result: LevelValidationResult) -> void:
	if not _is_number(data["difficulty"]):
		result.add_error("difficulty", "must be a number")


## Validates data["buses"]; returns {"total": int, "by_color": Dictionary}
## (color Value -> summed capacity), counting only entries whose color and
## capacity were themselves valid -- used by _validate_balance() after.
static func _validate_buses(data: Dictionary, result: LevelValidationResult) -> Dictionary:
	var totals: Dictionary = {"total": 0, "by_color": {}}

	if typeof(data["buses"]) != TYPE_ARRAY:
		result.add_error("buses", "must be an array")
		return totals

	var buses: Array = data["buses"]
	if buses.is_empty():
		result.add_error("buses", "must contain at least one bus")

	for i: int in buses.size():
		var path: String = "buses[%d]" % i
		var item: Variant = buses[i]
		if typeof(item) != TYPE_DICTIONARY:
			result.add_error(path, "must be an object")
			continue

		var color: int = _validate_color_field(item, "%s.color" % path, result)
		var capacity: Variant = item.get("capacity")
		var capacity_ok: bool = true
		if not _is_number(capacity):
			result.add_error("%s.capacity" % path, "must be a number")
			capacity_ok = false
		elif int(capacity) <= 0:
			result.add_error("%s.capacity" % path, "must be positive, got %s" % str(capacity))
			capacity_ok = false

		if PassengerColor.is_valid(color) and capacity_ok:
			totals["total"] += int(capacity)
			totals["by_color"][color] = totals["by_color"].get(color, 0) + int(capacity)

	return totals


## Validates data["passenger_queues"]; same {"total", "by_color"} shape as
## _validate_buses(), counting only passengers with a valid color.
static func _validate_passenger_queues(data: Dictionary, result: LevelValidationResult) -> Dictionary:
	var totals: Dictionary = {"total": 0, "by_color": {}}

	if typeof(data["passenger_queues"]) != TYPE_ARRAY:
		result.add_error("passenger_queues", "must be an array")
		return totals

	var queues: Array = data["passenger_queues"]
	for qi: int in queues.size():
		var queue_path: String = "passenger_queues[%d]" % qi
		var queue_item: Variant = queues[qi]
		if typeof(queue_item) != TYPE_ARRAY:
			result.add_error(queue_path, "must be an array")
			continue

		var passengers: Array = queue_item
		for pi: int in passengers.size():
			var path: String = "%s[%d]" % [queue_path, pi]
			var passenger_item: Variant = passengers[pi]
			if typeof(passenger_item) != TYPE_DICTIONARY:
				result.add_error(path, "must be an object")
				continue

			var color: int = _validate_color_field(passenger_item, "%s.color" % path, result)
			if PassengerColor.is_valid(color):
				totals["total"] += 1
				totals["by_color"][color] = totals["by_color"].get(color, 0) + 1

	return totals


## Validates a "color" string field on an object at field_path, returning
## the parsed PassengerColor.Value (or INVALID if it was missing/unknown --
## already recorded as an error on result in that case).
static func _validate_color_field(item: Dictionary, field_path: String, result: LevelValidationResult) -> int:
	var raw_color: Variant = item.get("color")
	if typeof(raw_color) != TYPE_STRING:
		result.add_error(field_path, "must be a string")
		return PassengerColor.INVALID

	var color: int = PassengerColor.from_string(raw_color)
	if not PassengerColor.is_valid(color):
		result.add_error(field_path, "unknown color '%s'" % raw_color)
	return color


## The two balance rules: total passenger count must equal total bus
## capacity, and each color's passenger count must equal that color's
## total bus capacity (checked over the union of colors appearing on
## either side, so a color with passengers but no matching bus -- or vice
## versa -- is still caught).
static func _validate_balance(bus_totals: Dictionary, passenger_totals: Dictionary, result: LevelValidationResult) -> void:
	var bus_total: int = bus_totals["total"]
	var passenger_total: int = passenger_totals["total"]
	if bus_total != passenger_total:
		result.add_error(
			"passenger_queues/buses",
			"total passenger count (%d) does not match total bus capacity (%d)" % [passenger_total, bus_total]
		)

	var bus_by_color: Dictionary = bus_totals["by_color"]
	var passenger_by_color: Dictionary = passenger_totals["by_color"]
	var all_colors: Dictionary = {}
	for color: int in bus_by_color:
		all_colors[color] = true
	for color: int in passenger_by_color:
		all_colors[color] = true

	for color: int in all_colors:
		var bus_amount: int = bus_by_color.get(color, 0)
		var passenger_amount: int = passenger_by_color.get(color, 0)
		if bus_amount != passenger_amount:
			var color_name: String = PassengerColor.to_string_key(color)
			result.add_error(
				"passenger_queues/buses",
				"%s passenger count (%d) does not match %s bus capacity (%d)" % [color_name, passenger_amount, color_name, bus_amount]
			)
