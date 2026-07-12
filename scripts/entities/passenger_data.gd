class_name PassengerData
extends RefCounted
## Pure data: a single passenger. No visual/Node reference of any kind.

var color: int = PassengerColor.INVALID


func _init(p_color: int = PassengerColor.INVALID) -> void:
	color = p_color


func is_valid() -> bool:
	return PassengerColor.is_valid(color)


## Builds a PassengerData from a JSON-decoded Dictionary. Never trusts the
## shape: a missing/non-string "color" or an unrecognized color name simply
## produces an invalid PassengerData (color = PassengerColor.INVALID) --
## callers must check is_valid(), nothing is silently defaulted.
static func from_dict(data: Dictionary) -> PassengerData:
	var color_value: int = PassengerColor.INVALID
	if typeof(data.get("color")) == TYPE_STRING:
		color_value = PassengerColor.from_string(data["color"])
	return PassengerData.new(color_value)


func to_dict() -> Dictionary:
	return {"color": PassengerColor.to_string_key(color)}
