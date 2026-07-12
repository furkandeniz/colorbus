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


func _on_play_pressed() -> void:
	# Placeholder routing: with no gameplay yet, Play goes to LevelSelect
	# the same as Levels. Will change to "resume/next level" once gameplay
	# and save progress exist.
	AppRouter.push_screen(AppRouter.Screen.LEVEL_SELECT)


func _on_levels_pressed() -> void:
	AppRouter.push_screen(AppRouter.Screen.LEVEL_SELECT)


func _on_settings_pressed() -> void:
	AppRouter.push_screen(AppRouter.Screen.SETTINGS)
