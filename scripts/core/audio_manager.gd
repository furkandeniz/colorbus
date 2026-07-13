extends Node
## Autoload singleton. Foundation for audio playback. No sound assets exist
## yet (assets/audio/ is empty) so play_sfx()/play_music() are safe no-ops
## until streams are registered -- this is the plumbing, not the content.
## Also honors SaveManager.sound_enabled/music_enabled -- both default true,
## so this is invisible until a settings toggle actually flips one off.

var _sfx_player: AudioStreamPlayer
var _music_player: AudioStreamPlayer
var _sfx_streams: Dictionary = {}
var _music_streams: Dictionary = {}


func _ready() -> void:
	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.bus = "Master"
	add_child(_sfx_player)

	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Master"
	add_child(_music_player)

	_apply_master_volume()
	SettingsManager.settings_changed.connect(_apply_master_volume)


## Registers a sound under `key` so play_sfx(key) can find it later. Call
## this once real audio assets exist; until then nothing is registered and
## play_sfx() silently no-ops.
func register_sfx(key: String, stream: AudioStream) -> void:
	_sfx_streams[key] = stream


func register_music(key: String, stream: AudioStream) -> void:
	_music_streams[key] = stream


func play_sfx(key: String) -> void:
	if not SaveManager.is_sound_enabled():
		return
	var stream: AudioStream = _sfx_streams.get(key)
	if stream == null:
		return
	_sfx_player.stream = stream
	_sfx_player.volume_db = linear_to_db(max(SettingsManager.sfx_volume, 0.0001))
	_sfx_player.play()


func play_music(key: String) -> void:
	if not SaveManager.is_music_enabled():
		return
	var stream: AudioStream = _music_streams.get(key)
	if stream == null:
		return
	_music_player.stream = stream
	_music_player.volume_db = linear_to_db(max(SettingsManager.music_volume, 0.0001))
	_music_player.play()


func stop_music() -> void:
	_music_player.stop()


func _apply_master_volume() -> void:
	var bus_index: int = AudioServer.get_bus_index("Master")
	if bus_index == -1:
		return
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(max(SettingsManager.master_volume, 0.0001)))
