extends SceneTree
## Headless responsive-layout check for scenes/app/main.tscn.
##
## The headless DisplayServer on this engine build ignores --resolution /
## --window-size (the real window always reports a fixed 1920x1920), so
## resolutions are instead tested with a SubViewport, whose size can be set
## directly regardless of the real window. main.tscn is instanced fresh
## inside a SubViewport of each target size, which drives the exact same
## anchor/Container layout code a real device of that size would run.
##
## Usage: godot --headless --path . --script res://tests/verify_responsive_layout.gd

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(360, 640),
	Vector2i(375, 812),
	Vector2i(390, 844),
	Vector2i(412, 915),
	Vector2i(430, 932),
]

var _main_scene: PackedScene


func _initialize() -> void:
	_main_scene = load("res://scenes/app/main.tscn")
	var all_passed: bool = true
	for target_size: Vector2i in RESOLUTIONS:
		var passed: bool = await _check_resolution(target_size)
		all_passed = all_passed and passed

	print("[ResponsiveTest] RESULT: %s" % ("PASS" if all_passed else "FAIL"))
	quit(0 if all_passed else 1)


func _check_resolution(target_size: Vector2i) -> bool:
	var sub_viewport: SubViewport = SubViewport.new()
	sub_viewport.size = target_size
	root.add_child(sub_viewport)

	var instance: Control = _main_scene.instantiate()
	sub_viewport.add_child(instance)

	await process_frame
	await process_frame
	await process_frame

	var header: Control = instance.get_node("%Header")
	var content: Control = instance.get_node("%ContentArea")
	var footer: Control = instance.get_node("%Footer")

	var viewport_size: Vector2 = Vector2(target_size)
	var header_rect: Rect2 = header.get_global_rect()
	var content_rect: Rect2 = content.get_global_rect()
	var footer_rect: Rect2 = footer.get_global_rect()

	var ok: bool = true
	ok = ok and is_equal_approx(header_rect.position.y, 0.0)
	ok = ok and is_equal_approx(header_rect.position.y + header_rect.size.y, content_rect.position.y)
	ok = ok and is_equal_approx(content_rect.position.y + content_rect.size.y, footer_rect.position.y)
	ok = ok and is_equal_approx(footer_rect.position.y + footer_rect.size.y, viewport_size.y)
	ok = ok and is_equal_approx(header_rect.size.x, viewport_size.x)
	ok = ok and is_equal_approx(content_rect.size.x, viewport_size.x)
	ok = ok and is_equal_approx(footer_rect.size.x, viewport_size.x)
	ok = ok and header_rect.size.y >= 0.0 and content_rect.size.y >= 0.0 and footer_rect.size.y >= 0.0

	print("[ResponsiveTest] %dx%d -> header=%s content=%s footer=%s ok=%s" % [
		target_size.x, target_size.y, header_rect, content_rect, footer_rect, ok
	])

	sub_viewport.queue_free()
	await process_frame

	return ok
