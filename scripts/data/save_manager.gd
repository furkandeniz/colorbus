extends Node
## Autoload singleton. Local persistence under user://save.json: level
## progress (unlock state, star ratings, completion), a few user-facing
## toggles, first-launch status, and the last-played level. Holds plain
## data only (Dictionary/Array of primitives) -- never a Node or Object
## reference, per project rules.
##
## save_version + _migrate() exist so a future schema change has somewhere
## to hook in: bump CURRENT_SAVE_VERSION, add a match arm to _migrate_step()
## that transforms the *previous* version's shape into the next, and
## load_data() runs every step in sequence until the data is current.
## Only the v0 (no version field at all -- a pre-this-milestone or missing
## save) -> v1 step exists today, which just stamps the version; a real
## future migration would look the same shape, just with actual field
## renames/moves inside that match arm.

signal progress_changed

const SAVE_PATH: String = "user://save.json"
const CURRENT_SAVE_VERSION: int = 1

var save_version: int = CURRENT_SAVE_VERSION
var highest_unlocked_level: int = 1
var completed_levels: Array[int] = []
var level_stars: Dictionary = {}
var music_enabled: bool = true
var sound_enabled: bool = true
var vibration_enabled: bool = true
var first_launch_completed: bool = false
var last_played_level: int = 0


func _ready() -> void:
	load_data()


func is_first_launch() -> bool:
	return not first_launch_completed


func mark_first_launch_complete() -> void:
	if first_launch_completed:
		return
	first_launch_completed = true
	save_data()


func get_highest_unlocked_level() -> int:
	return highest_unlocked_level


func is_level_unlocked(level_id: int) -> bool:
	return level_id <= highest_unlocked_level


func is_level_completed(level_id: int) -> bool:
	return completed_levels.has(level_id)


## Stars are stored keyed by String(level_id) rather than the int itself --
## a Dictionary round-tripped through JSON.stringify()/parse() always comes
## back with String keys, so reading by int key would silently miss every
## entry loaded from disk. str(level_id) is used on both the read and
## write side so an in-memory-only value and a freshly-loaded one behave
## identically.
func get_stars_for_level(level_id: int) -> int:
	return int(level_stars.get(str(level_id), 0))


## Records the outcome of winning level_id with `stars` (0-3): marks it
## completed, unlocks level_id + 1, and keeps the *best* star result ever
## earned -- a later, worse replay never downgrades a prior good result.
## Safe to call more than once for the same level (replays).
func record_level_result(level_id: int, stars: int) -> void:
	if level_id <= 0:
		return

	if not completed_levels.has(level_id):
		completed_levels.append(level_id)

	var key: String = str(level_id)
	var previous_stars: int = int(level_stars.get(key, 0))
	level_stars[key] = max(previous_stars, clampi(stars, 0, 3))

	highest_unlocked_level = max(highest_unlocked_level, level_id + 1)

	save_data()
	progress_changed.emit()


func get_last_played_level() -> int:
	return last_played_level


func set_last_played_level(level_id: int) -> void:
	last_played_level = level_id
	save_data()


func is_music_enabled() -> bool:
	return music_enabled


func set_music_enabled(value: bool) -> void:
	music_enabled = value
	save_data()


func is_sound_enabled() -> bool:
	return sound_enabled


func set_sound_enabled(value: bool) -> void:
	sound_enabled = value
	save_data()


func is_vibration_enabled() -> bool:
	return vibration_enabled


func set_vibration_enabled(value: bool) -> void:
	vibration_enabled = value
	save_data()


## Serializes current state to a Dictionary (JSON-safe: only primitives/
## arrays/dictionaries) -- the one place the on-disk shape is defined.
func _to_dict() -> Dictionary:
	return {
		"save_version": CURRENT_SAVE_VERSION,
		"highest_unlocked_level": highest_unlocked_level,
		"completed_levels": completed_levels.duplicate(),
		"level_stars": level_stars.duplicate(),
		"music_enabled": music_enabled,
		"sound_enabled": sound_enabled,
		"vibration_enabled": vibration_enabled,
		"first_launch_completed": first_launch_completed,
		"last_played_level": last_played_level,
	}


## Resets every field to a fresh default save -- used on first launch and
## whenever the on-disk file is missing or corrupt beyond recovery.
func _reset_to_defaults() -> void:
	save_version = CURRENT_SAVE_VERSION
	highest_unlocked_level = 1
	completed_levels = []
	level_stars = {}
	music_enabled = true
	sound_enabled = true
	vibration_enabled = true
	first_launch_completed = false
	last_played_level = 0


## Writes the current state to SAVE_PATH via write-to-temp-then-rename:
## the payload is fully written to a sibling .tmp file first, then that
## file atomically replaces SAVE_PATH via DirAccess.rename() (an OS-level
## rename on every platform this project targets). A crash or power loss
## mid-write can therefore never leave a half-written, corrupt save.json in
## place -- readers only ever see either the fully-old or fully-new file.
func save_data() -> bool:
	var payload: Dictionary = _to_dict()
	var tmp_path: String = SAVE_PATH + ".tmp"

	var file: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_warning("SaveManager: could not open %s for writing (error %d)" % [tmp_path, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(payload))
	file.close()

	var dir: DirAccess = DirAccess.open("user://")
	if dir == null:
		push_warning("SaveManager: could not open user:// to finalize the save")
		return false

	var err: Error = dir.rename(tmp_path.get_file(), SAVE_PATH.get_file())
	if err != OK:
		push_warning("SaveManager: could not finalize %s (error %d)" % [SAVE_PATH, err])
		return false
	return true


## Loads user://save.json if present and valid, migrating it to
## CURRENT_SAVE_VERSION if older. A missing file means "first launch" --
## resets to (and persists) fresh defaults. A present-but-corrupt file (bad
## JSON, or valid JSON that isn't an object) must never crash the app: it's
## treated the same as "no save yet", falling back to fresh defaults, and
## the corrupt file is immediately overwritten with those defaults so the
## next launch doesn't hit the same corruption again.
func load_data() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		_reset_to_defaults()
		save_data()
		return false

	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		_reset_to_defaults()
		save_data()
		return false

	var text: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		push_warning("SaveManager: %s is corrupt (%s), resetting to defaults" % [SAVE_PATH, json.get_error_message()])
		_reset_to_defaults()
		save_data()
		return false

	var parsed: Variant = json.get_data()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SaveManager: %s did not contain a JSON object, resetting to defaults" % SAVE_PATH)
		_reset_to_defaults()
		save_data()
		return false

	_apply_dict(_migrate(parsed))
	return true


## Upgrades an on-disk Dictionary of any older save_version to
## CURRENT_SAVE_VERSION, one step at a time. Only a version-stamping no-op
## step exists today (there is no version before this milestone's schema);
## a real future migration adds another match arm here that transforms the
## dict's shape, without load_data()/save_data() needing to change at all.
func _migrate(data: Dictionary) -> Dictionary:
	var version: int = int(data.get("save_version", 0))
	while version < CURRENT_SAVE_VERSION:
		version = _migrate_step(data, version)
	return data


func _migrate_step(data: Dictionary, from_version: int) -> int:
	match from_version:
		0:
			data["save_version"] = 1
			return 1
		_:
			data["save_version"] = CURRENT_SAVE_VERSION
			return CURRENT_SAVE_VERSION


## Applies a validated, migrated Dictionary to live fields -- never trusts
## individual field types/shapes either (a hand-edited or partially-corrupt
## file can still parse as valid JSON with the wrong shape inside).
func _apply_dict(data: Dictionary) -> void:
	save_version = int(data.get("save_version", CURRENT_SAVE_VERSION))
	highest_unlocked_level = max(1, int(data.get("highest_unlocked_level", 1)))

	completed_levels = []
	var raw_completed: Variant = data.get("completed_levels", [])
	if typeof(raw_completed) == TYPE_ARRAY:
		for item: Variant in raw_completed:
			if (typeof(item) == TYPE_INT or typeof(item) == TYPE_FLOAT) and not completed_levels.has(int(item)):
				completed_levels.append(int(item))

	level_stars = {}
	var raw_stars: Variant = data.get("level_stars", {})
	if typeof(raw_stars) == TYPE_DICTIONARY:
		for key: Variant in raw_stars.keys():
			var value: Variant = raw_stars[key]
			if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
				level_stars[str(key)] = clampi(int(value), 0, 3)

	music_enabled = bool(data.get("music_enabled", true))
	sound_enabled = bool(data.get("sound_enabled", true))
	vibration_enabled = bool(data.get("vibration_enabled", true))
	first_launch_completed = bool(data.get("first_launch_completed", false))
	last_played_level = int(data.get("last_played_level", 0))
