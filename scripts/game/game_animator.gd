class_name GameAnimator
extends RefCounted
## Orchestrates every cross-location "flying" gameplay animation (passenger
## between queue / waiting slot / bus) plus popup entrances, so
## GameController can sequence real, awaitable animations without ever
## racing ahead of them. Owns no game state of its own -- only ever moves/
## reparents view nodes it's handed and awaits their completion.
##
## Cross-parent flights reparent onto a dedicated non-Container overlay
## Control (_layer, GameScreen's %AnimationLayer) because every parent a
## flying passenger might come from (PassengerQueue's VBoxContainer,
## WaitingSlot) or go to (BusQueue's HBoxContainer) is a Container that
## would silently reset a child's position every layout pass -- reparenting
## preserves global_position across the move so the flight starts exactly
## where the passenger visually was.

var _layer: Control = null


func _init(animation_layer: Control) -> void:
	_layer = animation_layer


## Flies passenger from wherever it currently is to target's center,
## reparenting it onto the overlay layer first. Caller must have already
## detached passenger from its original parent (e.g. via take_front()/
## take_passenger()/take_passenger_at()) -- this only ever adds it to
## _layer, never removes it from anywhere else. Always resolves within a
## bounded time even if the tween itself never fires `finished` (see
## _await_tween), so a stray flight can never lock the whole game.
func fly_passenger_to(passenger: Passenger, target: Control, base_duration: float) -> void:
	_reparent_to_layer(passenger)

	var duration: float = AnimationConfig.duration(base_duration)
	var target_center: Vector2 = target.global_position + target.size / 2.0 - passenger.size / 2.0

	var tween: Tween = passenger.create_tween()
	tween.tween_property(passenger, "global_position", target_center, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

	await _await_tween(passenger, tween, duration)


## Win/lose popup entrance: a brief scale+fade pop-in on `panel` (the Panel
## inside the popup's CenterContainer -- scale/modulate are always safe
## there regardless of the CenterContainer parent). Makes popup_root
## visible itself, so callers no longer need to flip .visible directly.
func animate_popup_entrance(popup_root: Control, panel: Control) -> void:
	popup_root.visible = true
	panel.pivot_offset = panel.size / 2.0
	panel.scale = Vector2(0.7, 0.7)
	panel.modulate.a = 0.0

	var duration: float = AnimationConfig.duration(AnimationConfig.POPUP_ENTRANCE)
	var tween: Tween = panel.create_tween()
	tween.set_parallel(true)
	tween.tween_property(panel, "scale", Vector2.ONE, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "modulate:a", 1.0, duration)


## Moves node onto the overlay layer, preserving its current on-screen
## position (global_position survives the reparent, but layout-driven
## local position wouldn't).
func _reparent_to_layer(node: Control) -> void:
	var previous_global_position: Vector2 = node.global_position
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	_layer.add_child(node)
	node.global_position = previous_global_position


## Races tween.finished against a hard timeout so a tween that never fires
## `finished` (freed target, engine hiccup, whatever) can never hang an
## awaiting caller forever -- the single mechanism behind "an animation
## failure must not lock the game". The timeout adds a safety margin over
## the nominal duration since `finished` normally fires right on time; the
## timeout only ever needs to catch the abnormal case.
static func _await_tween(node: Node, tween: Tween, duration: float) -> void:
	var done: Array[bool] = [false]
	tween.finished.connect(func() -> void: done[0] = true)

	if not is_instance_valid(node):
		return
	var tree: SceneTree = node.get_tree()
	if tree == null:
		return

	var timeout_timer: SceneTreeTimer = tree.create_timer(duration + 0.5)
	timeout_timer.timeout.connect(func() -> void: done[0] = true)

	while not done[0]:
		await tree.process_frame
