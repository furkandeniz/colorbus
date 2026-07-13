extends Control
## Lists every level found under data/levels/ (via LevelRepository) as a
## row (Button + a stars Label); tapping an unlocked one starts it through
## AppRouter.start_level(). A level file that fails to load/validate is
## simply skipped -- LevelSelect never crashes over one broken level file,
## it just doesn't offer that one.
##
## Lock state and stars come entirely from SaveManager
## (is_level_unlocked()/get_stars_for_level()) -- this screen never decides
## progress itself, only reflects it. Locked levels still get a row (so the
## player can see how many levels exist and roughly how far they've come),
## just with a disabled button and no star label.

const LOCKED_MARK: String = "level.locked"

@onready var _level_list: VBoxContainer = %LevelListContainer


func _ready() -> void:
	for result: LevelLoadResult in LevelRepository.load_all_levels():
		if result.is_success():
			_add_level_row(result.level)


func _add_level_row(level: LevelData) -> void:
	var unlocked: bool = SaveManager.is_level_unlocked(level.id)
	var stars: int = SaveManager.get_stars_for_level(level.id)

	var row: HBoxContainer = HBoxContainer.new()
	row.name = "LevelRow%d" % level.id
	row.add_theme_constant_override("separation", 16)

	var button: Button = Button.new()
	button.name = "LevelButton%d" % level.id
	button.text = "level.button:%d" % level.id
	button.custom_minimum_size = Vector2(0, 120)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.disabled = not unlocked
	if unlocked:
		button.pressed.connect(_on_level_button_pressed.bind(level.id))
	row.add_child(button)

	var status_label: Label = Label.new()
	status_label.name = "StatusLabel%d" % level.id
	status_label.custom_minimum_size = Vector2(140, 0)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.text = ("%d/3" % stars) if unlocked else LOCKED_MARK
	row.add_child(status_label)

	_level_list.add_child(row)


func _on_level_button_pressed(level_id: int) -> void:
	AppRouter.start_level(level_id)
