extends Control
## Root of the app shell: a safe-area aware Header / ContentArea / Footer
## stack. Header hosts the back button and current screen title; ContentArea
## hosts %ScreenRoot, where AppRouter mounts whichever screen (MainMenu /
## LevelSelect / Settings) is currently active. Contains no game logic.

const SCREEN_TITLES: Dictionary = {
	AppRouter.Screen.MAIN_MENU: "menu.title",
	AppRouter.Screen.LEVEL_SELECT: "screen.level_select.title",
	AppRouter.Screen.SETTINGS: "screen.settings.title",
	AppRouter.Screen.GAME: "screen.game.title",
}

@onready var _safe_area: MarginContainer = %SafeArea
@onready var _header: Control = %Header
@onready var _content_area: Control = %ContentArea
@onready var _footer: Control = %Footer
@onready var _screen_root: Control = %ScreenRoot
@onready var _back_button: Button = %BackButton
@onready var _screen_title_label: Label = %ScreenTitleLabel


func _ready() -> void:
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_apply_safe_area()

	_back_button.pressed.connect(_on_back_pressed)
	AppRouter.screen_changed.connect(_on_screen_changed)
	AppRouter.register_screen_root(_screen_root)
	AppRouter.push_screen(AppRouter.Screen.MAIN_MENU)

	await get_tree().process_frame
	_print_layout_debug()


func _on_viewport_size_changed() -> void:
	_apply_safe_area()


func _on_back_pressed() -> void:
	AppRouter.pop_screen()


func _on_screen_changed(screen: AppRouter.Screen) -> void:
	_screen_title_label.text = SCREEN_TITLES.get(screen, "")
	_back_button.visible = AppRouter.can_pop()


func _apply_safe_area() -> void:
	var margins: Dictionary = PlatformService.get_safe_area_margins()
	_safe_area.add_theme_constant_override("margin_left", int(margins["left"]))
	_safe_area.add_theme_constant_override("margin_top", int(margins["top"]))
	_safe_area.add_theme_constant_override("margin_right", int(margins["right"]))
	_safe_area.add_theme_constant_override("margin_bottom", int(margins["bottom"]))


func _print_layout_debug() -> void:
	var size: Vector2i = get_viewport().get_visible_rect().size
	print("[ColorBus] viewport=%d x %d" % [size.x, size.y])
	print("[ColorBus] header_rect=%s" % [_header.get_global_rect()])
	print("[ColorBus] content_rect=%s" % [_content_area.get_global_rect()])
	print("[ColorBus] footer_rect=%s" % [_footer.get_global_rect()])
