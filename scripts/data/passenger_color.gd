class_name PassengerColor
extends RefCounted
## Single central definition of the passenger/bus color palette, and the
## only place a JSON color string is converted to a typed Value. Unknown
## color strings are never silently coerced to a default -- from_string()
## returns INVALID, which every model's is_valid() must check for.

enum Value { RED, BLUE, YELLOW, GREEN, PURPLE }

const INVALID: int = -1

const NAME_TO_VALUE: Dictionary = {
	"red": Value.RED,
	"blue": Value.BLUE,
	"yellow": Value.YELLOW,
	"green": Value.GREEN,
	"purple": Value.PURPLE,
}


## Converts a lowercase-insensitive JSON color string to a typed Value.
## Returns INVALID for anything not in NAME_TO_VALUE -- callers must check
## is_valid() on the result rather than assume it succeeded.
static func from_string(value: String) -> int:
	return NAME_TO_VALUE.get(value.to_lower(), INVALID)


static func is_valid(value: int) -> bool:
	return NAME_TO_VALUE.values().has(value)


## Inverse of from_string(); returns "" for an invalid Value.
static func to_string_key(value: int) -> String:
	for key: String in NAME_TO_VALUE:
		if NAME_TO_VALUE[key] == value:
			return key
	return ""


## The single place a Value becomes an actual displayed Color. Shared by
## every view (Passenger, Bus, ...) so they never drift into slightly
## different reds/blues/etc. Returns a neutral gray for INVALID.
static func to_rgb(value: int) -> Color:
	match value:
		Value.RED:
			return Color(0.86, 0.20, 0.20)
		Value.BLUE:
			return Color(0.20, 0.45, 0.86)
		Value.YELLOW:
			return Color(0.93, 0.78, 0.20)
		Value.GREEN:
			return Color(0.25, 0.75, 0.35)
		Value.PURPLE:
			return Color(0.60, 0.30, 0.80)
		_:
			return Color(0.5, 0.5, 0.5)
