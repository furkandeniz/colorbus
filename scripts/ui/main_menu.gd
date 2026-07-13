extends Control
## Main menu screen: Play / Levels / Settings. Pushed onto AppRouter as the
## root screen. No visual assets -- plain Godot Controls only.

@onready var _play_button: Button = %PlayButton
@onready var _levels_button: Button = %LevelsButton
@onready var _settings_button: Button = %SettingsButton


func _ready() -> void:
	_play_button.pressed.connect(_on_play_pressed)
	_levels_button.pressed.connect(_on_levels_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)

	# Reaching the main menu at all is "the app has launched" -- marks
	# first-launch complete exactly once (a no-op on every later launch).
	SaveManager.mark_first_launch_complete()


## Resumes the last-played level if there is one, otherwise starts the
## furthest level the player has unlocked (level 1 on a fresh save).
func _on_play_pressed() -> void:
	var level_id: int = SaveManager.get_last_played_level()
	if level_id <= 0:
		level_id = SaveManager.get_highest_unlocked_level()
	AppRouter.start_level(level_id)


func _on_levels_pressed() -> void:
	AppRouter.push_screen(AppRouter.Screen.LEVEL_SELECT)


func _on_settings_pressed() -> void:
	AppRouter.push_screen(AppRouter.Screen.SETTINGS)
