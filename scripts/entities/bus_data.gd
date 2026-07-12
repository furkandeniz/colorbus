class_name BusData
extends RefCounted
## Pure data: a single bus. No visual/Node reference of any kind.

var color: int = PassengerColor.INVALID
var capacity: int = 0


func _init(p_color: int = PassengerColor.INVALID, p_capacity: int = 0) -> void:
	color = p_color
	capacity = p_capacity


func is_valid() -> bool:
	return PassengerColor.is_valid(color) and capacity > 0


## Builds a BusData from a JSON-decoded Dictionary. A missing/unrecognized
## color or a non-positive capacity produces an invalid BusData rather than
## a silently-defaulted one -- callers must check is_valid().
static func from_dict(data: Dictionary) -> BusData:
	var color_value: int = PassengerColor.INVALID
	if typeof(data.get("color")) == TYPE_STRING:
		color_value = PassengerColor.from_string(data["color"])
	var capacity_value: int = int(data.get("capacity", 0))
	return BusData.new(color_value, capacity_value)


func to_dict() -> Dictionary:
	return {"color": PassengerColor.to_string_key(color), "capacity": capacity}
