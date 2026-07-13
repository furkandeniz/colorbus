extends Node
## Autoload singleton. Foundation for user-facing app settings (audio
## volumes, language). Persists independently from SaveManager -- settings
## are app-level preferences, not game progress.

const SETTINGS_PATH: String = "user://settings.json"

signal settings_changed

var master_volume: float = 1.0
var music_volume: float = 1.0
var sfx_volume: float = 1.0
var language: String = "en"
## Accessibility hook: when true, AnimationConfig.duration() scales every
## gameplay animation duration down toward near-instant. No settings-panel
## toggle exists yet (settings_panel.tscn is still a placeholder) -- this
## is the persisted, functional half of "prepared for a reduce-motion
## setting", ready for a UI control to flip later.
var reduce_motion: bool = false


func _ready() -> void:
	load_settings()


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	settings_changed.emit()


func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	settings_changed.emit()


func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	settings_changed.emit()


func set_language(locale: String) -> void:
	language = locale
	settings_changed.emit()


func set_reduce_motion(value: bool) -> void:
	reduce_motion = value
	settings_changed.emit()


func save_settings() -> bool:
	var payload: Dictionary = {
		"master_volume": master_volume,
		"music_volume": music_volume,
		"sfx_volume": sfx_volume,
		"language": language,
		"reduce_motion": reduce_motion,
	}
	var file: FileAccess = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("SettingsManager: could not open %s for writing (error %d)" % [SETTINGS_PATH, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(payload))
	file.close()
	return true


## Loads user://settings.json if present and valid. Falls back to defaults
## on a missing or corrupt file rather than failing -- a bad settings file
## must never block the app from starting.
func load_settings() -> bool:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return false

	var file: FileAccess = FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return false

	var text: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		push_warning("SettingsManager: %s is corrupt (%s), using defaults" % [SETTINGS_PATH, json.get_error_message()])
		return false

	var parsed: Variant = json.get_data()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SettingsManager: %s did not contain a JSON object, using defaults" % SETTINGS_PATH)
		return false

	master_volume = clampf(float(parsed.get("master_volume", master_volume)), 0.0, 1.0)
	music_volume = clampf(float(parsed.get("music_volume", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(parsed.get("sfx_volume", sfx_volume)), 0.0, 1.0)
	language = str(parsed.get("language", language))
	reduce_motion = bool(parsed.get("reduce_motion", reduce_motion))
	settings_changed.emit()
	return true
