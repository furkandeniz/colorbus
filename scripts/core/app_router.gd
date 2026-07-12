extends Node
## Autoload singleton. Single centralized place for app-level screen
## navigation (MainMenu / LevelSelect / Settings) and the Android hardware
## back button (NOTIFICATION_WM_GO_BACK_REQUEST). The app root scene
## registers the Control it wants screens mounted into via
## register_screen_root(); screens themselves know nothing about each
## other and never hold direct references to one another.

enum Screen { MAIN_MENU, LEVEL_SELECT, SETTINGS }

signal screen_changed(screen: Screen)

const SCREEN_SCENES: Dictionary = {
	Screen.MAIN_MENU: "res://scenes/menus/main_menu.tscn",
	Screen.LEVEL_SELECT: "res://scenes/menus/level_select.tscn",
	Screen.SETTINGS: "res://scenes/menus/settings_panel.tscn",
}

var _screen_root: Node = null
var _stack: Array[Screen] = []
var _current_instance: Node = null


func register_screen_root(container: Node) -> void:
	_screen_root = container
	if not _stack.is_empty():
		_show_current()


func push_screen(screen: Screen) -> void:
	if not _stack.is_empty() and _stack[-1] == screen:
		return
	_stack.append(screen)
	_show_current()


## Pops the current screen and returns to the previous one. Returns false
## if already at the root screen (nothing left to pop) -- the Android back
## handler below uses this to decide whether to fall through to
## PlatformService.quit_app() instead.
func pop_screen() -> bool:
	if _stack.size() <= 1:
		return false
	_stack.pop_back()
	_show_current()
	return true


func current_screen() -> Screen:
	if _stack.is_empty():
		return Screen.MAIN_MENU
	return _stack[-1]


func can_pop() -> bool:
	return _stack.size() > 1


func _show_current() -> void:
	if _screen_root == null:
		push_warning("AppRouter: no screen root registered yet")
		return
	if _stack.is_empty():
		return

	if _current_instance != null:
		_current_instance.queue_free()
		_current_instance = null

	var screen: Screen = current_screen()
	var scene_path: String = SCREEN_SCENES[screen]
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		push_error("AppRouter: could not load screen scene %s" % scene_path)
		return

	_current_instance = packed.instantiate()
	_screen_root.add_child(_current_instance)
	screen_changed.emit(screen)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if not pop_screen():
			PlatformService.quit_app()
