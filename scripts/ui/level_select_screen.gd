extends Control
## Lists every level found under data/levels/ (via LevelRepository) as a
## button; tapping one starts it through AppRouter.start_level(). A level
## file that fails to load/validate is simply skipped -- LevelSelect never
## crashes over one broken level file, it just doesn't offer that one.

@onready var _level_list: VBoxContainer = %LevelListContainer


func _ready() -> void:
	for result: LevelLoadResult in LevelRepository.load_all_levels():
		if result.is_success():
			_add_level_button(result.level)


func _add_level_button(level: LevelData) -> void:
	var button: Button = Button.new()
	button.text = "level.button:%d" % level.id
	button.custom_minimum_size = Vector2(0, 120)
	button.pressed.connect(_on_level_button_pressed.bind(level.id))
	_level_list.add_child(button)


func _on_level_button_pressed(level_id: int) -> void:
	AppRouter.start_level(level_id)
