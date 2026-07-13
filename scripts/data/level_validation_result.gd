class_name LevelValidationResult
extends RefCounted
## Pure data: the outcome of validating one level's raw JSON. `errors` is
## a flat list of human-readable strings, each already prefixed with the
## source file and the exact field path that failed -- e.g.
## "res://data/levels/level_03.json: buses[1].capacity - must be positive
## (got 0)". Collects every applicable error in one pass rather than
## stopping at the first, so a level author sees everything wrong at once.

var source_label: String = ""
var errors: Array[String] = []


func _init(p_source_label: String = "") -> void:
	source_label = p_source_label


func is_valid() -> bool:
	return errors.is_empty()


func add_error(field_path: String, message: String) -> void:
	errors.append("%s: %s - %s" % [source_label, field_path, message])
