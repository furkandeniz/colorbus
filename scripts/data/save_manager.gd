extends Node
## Autoload singleton. Foundation for local persistence under user://.
## Holds plain data only (Dictionary of primitives/arrays/dictionaries) --
## never a Node or Object reference, per project rules. No game-progress
## fields exist yet; this is the loading/saving mechanism other systems
## will build on.

const SAVE_PATH: String = "user://save.json"

var _data: Dictionary = {}


func _ready() -> void:
	load_data()


func get_value(key: String, default_value: Variant = null) -> Variant:
	return _data.get(key, default_value)


func set_value(key: String, value: Variant) -> void:
	_data[key] = value


func save_data() -> bool:
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("SaveManager: could not open %s for writing (error %d)" % [SAVE_PATH, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(_data))
	file.close()
	return true


## Loads user://save.json if present and valid. A missing or corrupt file
## is treated as "no save yet" (empty data) rather than an error -- this
## must never crash the app on first launch or after a bad write.
func load_data() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		_data = {}
		return false

	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		_data = {}
		return false

	var text: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		push_warning("SaveManager: %s is corrupt (%s), starting with empty save" % [SAVE_PATH, json.get_error_message()])
		_data = {}
		return false

	var parsed: Variant = json.get_data()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SaveManager: %s did not contain a JSON object, starting with empty save" % SAVE_PATH)
		_data = {}
		return false

	_data = parsed
	return true
