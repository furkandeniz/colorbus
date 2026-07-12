class_name CheckMainSceneBoot
extends RefCounted
## Boots the project's configured main scene inside a SubViewport and
## confirms it loads and stays alive for a few frames. A SubViewport is
## used instead of resizing the real window because the headless
## DisplayServer on this engine build ignores --resolution/--window-size
## (see docs/RESPONSIVE_TEST_PLAN.md).


static func run() -> bool:
	var main_scene_path: String = str(ProjectSettings.get_setting("application/run/main_scene", ""))
	if main_scene_path.is_empty():
		print("[CheckMainSceneBoot] FAIL: application/run/main_scene is not set")
		return false

	var packed: PackedScene = load(main_scene_path) as PackedScene
	if packed == null:
		print("[CheckMainSceneBoot] FAIL: could not load %s" % main_scene_path)
		return false

	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var viewport_width: int = int(ProjectSettings.get_setting("display/window/size/viewport_width", 1080))
	var viewport_height: int = int(ProjectSettings.get_setting("display/window/size/viewport_height", 1920))

	var sub_viewport: SubViewport = SubViewport.new()
	sub_viewport.size = Vector2i(viewport_width, viewport_height)
	tree.root.add_child(sub_viewport)

	var instance: Node = packed.instantiate()
	sub_viewport.add_child(instance)

	await tree.process_frame
	await tree.process_frame
	await tree.process_frame

	var ok: bool = is_instance_valid(instance) and instance.is_inside_tree()

	sub_viewport.queue_free()
	await tree.process_frame

	print("[CheckMainSceneBoot] %s -> %s" % [main_scene_path, "PASS" if ok else "FAIL"])
	return ok
