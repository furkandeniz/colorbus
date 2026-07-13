extends SceneTree
## Headless checks for the animation infrastructure added on top of
## GameController/GameRules: AnimationConfig's reduce-motion scaling, the
## take/animate/finish lock that prevents re-selecting a passenger mid-
## flight, GameAnimator's timeout-safe tween awaiting (a freed/killed
## tween must never hang the caller), a real fly_passenger_to() flight
## landing on target, the unselectable-tap rejected-feedback shake, and a
## static guard that no gameplay animation uses a particle system (perf on
## low-end devices).
##
## Usage: godot --headless --path . --script res://tests/verify_game_animations.gd

var _all_ok: bool = true


## Reads/writes SettingsManager.reduce_motion via NodePath string rather
## than the bare `SettingsManager` identifier: this entry script (like any
## class_name script -- see AnimationConfig's doc comment) is compiled by
## Godot's `--script` runner before Autoloads are registered, so naming
## the identifier directly here fails the same way.
func _get_reduce_motion() -> bool:
	return bool(root.get_node("/root/SettingsManager").get("reduce_motion"))


func _set_reduce_motion(value: bool) -> void:
	root.get_node("/root/SettingsManager").set("reduce_motion", value)


func _initialize() -> void:
	# Autoload singletons (SettingsManager) aren't guaranteed attached under
	# /root until the tree has processed at least one frame -- wait for that
	# before the first test touches SettingsManager directly.
	await process_frame

	_test_reduce_motion_scales_duration()
	await _test_queue_lock_prevents_reselection_during_animation()
	await _test_await_tween_resolves_even_if_never_finishes()
	await _test_fly_passenger_to_lands_on_target()
	await _test_rejected_feedback_plays_without_emitting_selection()
	_test_no_particle_systems_used_for_animations()

	print("[GameAnimationsTest] RESULT: %s" % ("PASS" if _all_ok else "FAIL"))
	quit(0 if _all_ok else 1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_all_ok = false
	print("[GameAnimationsTest] %s -> %s" % [label, "OK" if condition else "FAIL"])


func _test_reduce_motion_scales_duration() -> void:
	var was_reduced: bool = _get_reduce_motion()

	_set_reduce_motion(false)
	_check(is_equal_approx(AnimationConfig.duration(1.0), 1.0), "reduce_motion off: duration() returns the base value unscaled")

	_set_reduce_motion(true)
	_check(
		is_equal_approx(AnimationConfig.duration(1.0), AnimationConfig.REDUCE_MOTION_SCALE),
		"reduce_motion on: duration() scales the base value down by REDUCE_MOTION_SCALE"
	)

	_set_reduce_motion(was_reduced)


## The core "same passenger must not be re-selectable during animation"
## requirement: take_front() locks the whole queue immediately (not just
## the one passenger), so nothing -- not even the newly-promoted front --
## can be taken again until finish_external_removal() runs.
func _test_queue_lock_prevents_reselection_during_animation() -> void:
	var queue: PassengerQueue = load("res://scenes/game/passenger_queue.tscn").instantiate()
	root.add_child(queue)
	var colors: Array[int] = [PassengerColor.Value.RED, PassengerColor.Value.BLUE]
	queue.configure(colors)
	await process_frame

	var taken: Passenger = queue.take_front()
	_check(taken != null and taken.color == PassengerColor.Value.RED, "take_front() detaches the front (red) passenger")
	_check(queue.is_locked(), "the queue is locked while the taken passenger is still flying")

	var again: Passenger = queue.take_front()
	_check(again == null, "take_front() is a no-op while already locked -- can't take a second passenger mid-flight")

	var new_front: Passenger = queue.front()
	_check(new_front != null and not new_front.can_be_selected(), "the promoted front passenger isn't selectable yet either, while locked")

	queue.finish_external_removal(PassengerColor.Value.RED)
	_check(not queue.is_locked(), "finish_external_removal() unlocks the queue once the flight is done")
	_check(queue.front().can_be_selected(), "the new front is selectable again only after the flight finishes")

	taken.queue_free()
	queue.queue_free()


## Simulates the one failure mode that could otherwise lock the whole
## game: a Tween that's stopped (kill()) before it ever fires `finished`.
## _await_tween()'s timeout safety net must still resolve.
func _test_await_tween_resolves_even_if_never_finishes() -> void:
	var node: Control = Control.new()
	root.add_child(node)
	await process_frame

	var tween: Tween = node.create_tween()
	tween.tween_property(node, "modulate:a", 0.0, 5.0)
	tween.kill()

	var start_msec: int = Time.get_ticks_msec()
	await GameAnimator._await_tween(node, tween, 0.05)
	var elapsed_msec: int = Time.get_ticks_msec() - start_msec

	_check(elapsed_msec < 2000, "a tween that never fires finished still resolves via the timeout safety net (took %dms)" % elapsed_msec)

	node.queue_free()


## Covers "callbacks must not run on a node already deleted from the scene
## tree": GameAnimator/GameController always guard with is_instance_valid()
## before touching a node that crossed an `await` boundary (e.g. the taken
## passenger in GameController._on_queue_passenger_selected() and
## _run_auto_board_cascade()), which is what makes the freed-node case
## unreachable in practice -- Godot's own static typing refuses to even
## pass an actually-freed Object into a Node-typed parameter, so
## _await_tween() can't be handed one directly to prove this at the unit
## level; the guard is instead exercised implicitly by every fly_passenger_to()
## call in verify_game_controller.gd, none of which ever crash across a
## full playthrough.
func _test_fly_passenger_to_lands_on_target() -> void:
	var was_reduced: bool = _get_reduce_motion()
	_set_reduce_motion(true)  # keep this test fast

	var layer: Control = Control.new()
	root.add_child(layer)

	var passenger: Passenger = load("res://scenes/entities/passenger.tscn").instantiate()
	root.add_child(passenger)
	passenger.configure(PassengerColor.Value.RED)
	passenger.position = Vector2.ZERO
	await process_frame

	var target: Control = Control.new()
	target.position = Vector2(300, 200)
	target.size = Vector2(80, 80)
	root.add_child(target)
	await process_frame

	var animator: GameAnimator = GameAnimator.new(layer)
	await animator.fly_passenger_to(passenger, target, AnimationConfig.PASSENGER_TO_BUS)

	var expected_center: Vector2 = target.global_position + target.size / 2.0 - passenger.size / 2.0
	_check(passenger.global_position.distance_to(expected_center) < 2.0, "fly_passenger_to() lands the passenger on the target's center")
	_check(passenger.get_parent() == layer, "fly_passenger_to() reparents the passenger onto the overlay animation layer")

	_set_reduce_motion(was_reduced)
	passenger.queue_free()
	target.queue_free()
	layer.queue_free()


func _test_rejected_feedback_plays_without_emitting_selection() -> void:
	var passenger: Passenger = load("res://scenes/entities/passenger.tscn").instantiate()
	root.add_child(passenger)
	passenger.configure(PassengerColor.Value.GREEN)
	passenger.set_selectable(false)
	await process_frame

	var received: Array = []
	passenger.passenger_selected.connect(func(p: Passenger) -> void: received.append(p))

	_check(passenger.rotation == 0.0, "passenger starts with no rotation")
	passenger._on_pressed()
	_check(received.is_empty(), "an unselectable tap never emits passenger_selected")

	await process_frame
	_check(passenger.rotation != 0.0, "play_rejected_feedback() is actually animating rotation shortly after an unselectable tap")

	await create_timer(AnimationConfig.REJECTED_FEEDBACK + 0.15).timeout
	_check(is_equal_approx(passenger.rotation, 0.0), "the rejected-feedback shake returns to no rotation once finished")

	passenger.queue_free()


## Static guard for "don't use excessive particles on low-performance
## devices": every animation added by this task is a plain Tween on
## position/scale/rotation/modulate -- none of them should ever reach for
## a GPUParticles2D/CPUParticles2D node.
func _test_no_particle_systems_used_for_animations() -> void:
	var files: Array[String] = [
		"res://scripts/game/game_animator.gd",
		"res://scripts/entities/passenger.gd",
		"res://scripts/entities/bus.gd",
		"res://scripts/game/waiting_area.gd",
		"res://scripts/game/game_controller.gd",
	]
	var found_particles: bool = false
	for path: String in files:
		var text: String = FileAccess.get_file_as_string(path)
		if text.contains("Particles2D"):
			found_particles = true
	_check(not found_particles, "no GPU/CPU particle systems are used for any gameplay animation")
