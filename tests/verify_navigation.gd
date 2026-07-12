extends SceneTree
## Headless navigation check: boots the app shell and drives AppRouter
## through MainMenu -> LevelSelect -> back -> Settings -> Android back
## button -> back-at-root, verifying %ScreenRoot's active screen, the
## Header title, and the back button's visibility at each step.
##
## Simulated taps call AppRouter directly (push_screen/pop_screen) rather
## than synthesizing InputEvents -- the headless DisplayServer on this
## engine build doesn't run GUI pointer picking at all (confirmed while
## building this check), so real click/tap simulation isn't possible here.
## This still exercises the exact code path the Play/Levels/Settings/Back
## buttons call.
##
## Note: this script is the --script *entry point*, which GDScript compiles
## before the project's Autoloads are registered as global identifiers (the
## same reason `--check-only -s` can't see them -- see CLAUDE.md). So
## AppRouter is looked up at runtime via /root/AppRouter instead of the bare
## global name. Its Screen enum is read off that same live instance
## (app_router.Screen.X) rather than via a preload of app_router.gd, since
## preloading would force a fresh compile of that script in this entry
## script's context and hit the exact same unresolved-Autoload problem for
## the PlatformService reference inside it. Scripts *loaded from inside*
## _initialize() (like main_screen.gd) don't have any of this restriction
## and use the bare `AppRouter` name normally.
##
## Usage: godot --headless --path . --script res://tests/verify_navigation.gd


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/app/main.tscn")
	var app: Control = packed.instantiate()
	root.add_child(app)

	var app_router: Node = root.get_node("AppRouter")

	await process_frame
	await process_frame
	await process_frame

	var all_ok: bool = true

	all_ok = _expect(app, app_router, app_router.Screen.MAIN_MENU, "MainMenu", false, "initial screen is MainMenu") and all_ok

	app_router.push_screen(app_router.Screen.LEVEL_SELECT)
	await process_frame
	all_ok = _expect(app, app_router, app_router.Screen.LEVEL_SELECT, "LevelSelect", true, "push LEVEL_SELECT") and all_ok

	app_router.pop_screen()
	await process_frame
	all_ok = _expect(app, app_router, app_router.Screen.MAIN_MENU, "MainMenu", false, "pop back to MainMenu") and all_ok

	app_router.push_screen(app_router.Screen.SETTINGS)
	await process_frame
	all_ok = _expect(app, app_router, app_router.Screen.SETTINGS, "SettingsPanel", true, "push SETTINGS") and all_ok

	# Simulate the Android hardware back button (centralized in AppRouter).
	app_router._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await process_frame
	all_ok = _expect(app, app_router, app_router.Screen.MAIN_MENU, "MainMenu", false, "Android back from SETTINGS returns to MainMenu") and all_ok

	# Back again at the root screen must not crash and must not change screen
	# (falls through to PlatformService.quit_app(), a no-op off-Android).
	app_router._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await process_frame
	all_ok = _expect(app, app_router, app_router.Screen.MAIN_MENU, "MainMenu", false, "Android back at root stays on MainMenu") and all_ok

	print("[NavigationTest] RESULT: %s" % ("PASS" if all_ok else "FAIL"))
	quit(0 if all_ok else 1)


## expected_screen is intentionally untyped: its static type is the nested
## enum on AppRouter's script, which GDScript can't spell as a type
## annotation when accessed through a preloaded GDScript const (only through
## a class_name or the live Autoload identifier, neither available to this
## entry script -- see the note above).
func _expect(app: Control, app_router: Node, expected_screen, expected_root_name: String, expect_back_visible: bool, label: String) -> bool:
	var screen_root: Control = app.get_node("%ScreenRoot")
	var back_button: Button = app.get_node("%BackButton")
	var title_label: Label = app.get_node("%ScreenTitleLabel")

	var ok: bool = true
	ok = ok and app_router.current_screen() == expected_screen
	ok = ok and screen_root.get_child_count() == 1
	if screen_root.get_child_count() == 1:
		ok = ok and screen_root.get_child(0).name == expected_root_name
	ok = ok and back_button.visible == expect_back_visible
	ok = ok and not title_label.text.is_empty()

	print("[NavigationTest] %s -> %s" % [label, "OK" if ok else "FAIL"])
	return ok
