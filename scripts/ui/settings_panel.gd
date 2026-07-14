extends Control
## Settings screen: music/sound/vibration toggles, backed directly by
## SaveManager (the same flags AudioManager.play_sfx()/play_music() and a
## future haptic call already gate on -- this screen doesn't own any state
## of its own, only reflects and edits SaveManager's). Loaded as part of
## AppRouter mounting the scene, not a class_name script, so referencing
## SaveManager by its bare Autoload name here is safe (see CLAUDE.md).

@onready var _music_toggle: CheckButton = %MusicToggle
@onready var _sound_toggle: CheckButton = %SoundToggle
@onready var _vibration_toggle: CheckButton = %VibrationToggle


func _ready() -> void:
	_music_toggle.button_pressed = SaveManager.is_music_enabled()
	_sound_toggle.button_pressed = SaveManager.is_sound_enabled()
	_vibration_toggle.button_pressed = SaveManager.is_vibration_enabled()

	_music_toggle.toggled.connect(_on_music_toggled)
	_sound_toggle.toggled.connect(_on_sound_toggled)
	_vibration_toggle.toggled.connect(_on_vibration_toggled)


func _on_music_toggled(enabled: bool) -> void:
	SaveManager.set_music_enabled(enabled)


func _on_sound_toggled(enabled: bool) -> void:
	SaveManager.set_sound_enabled(enabled)


func _on_vibration_toggled(enabled: bool) -> void:
	SaveManager.set_vibration_enabled(enabled)
