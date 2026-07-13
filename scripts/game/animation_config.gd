class_name AnimationConfig
extends RefCounted
## Single central place for every gameplay animation's duration. Change
## timings here, not scattered across GameAnimator/Passenger/Bus/etc.
## Every duration is a *base* value in seconds -- always read it through
## duration() rather than the raw constant, so SettingsManager.reduce_motion
## is respected everywhere without every call site having to remember to
## check it itself.
##
## duration() deliberately never writes the bare identifier
## `SettingsManager` anywhere in this file's source (see _reduce_motion()
## below): Godot's `--script` runner eagerly parses/validates every
## class_name script's body to build its global class table *before*
## Autoload singletons are registered, and merely naming an Autoload
## identifier anywhere in a class_name script's source -- static or
## instance method, doesn't matter -- permanently corrupts that class's
## compiled form for the rest of the process (every later call fails with
## "Nonexistent function" or worse). Looking the singleton up by NodePath
## *string* instead sidesteps it entirely, since string literals aren't
## resolved as identifiers at that early pass.

const PASSENGER_TO_BUS: float = 0.35
const PASSENGER_TO_WAITING_SLOT: float = 0.3
const WAITING_TO_BUS: float = 0.3
const WAITING_COMPACTION: float = 0.2
const BUS_CELEBRATION: float = 0.2
const BUS_EXIT: float = 0.35
const BUS_ENTRANCE: float = 0.25
const REJECTED_FEEDBACK: float = 0.32
const POPUP_ENTRANCE: float = 0.3

## How much reduce_motion scales every duration down by. Not zero --
## the animation still needs to actually finish and fire `finished` so
## nothing waiting on it hangs; it's just fast enough to read as "instant".
const REDUCE_MOTION_SCALE: float = 0.15

## Any single call site's safety-net ceiling (see GameAnimator's timeout
## helper) needs a stable upper bound; expose the largest base duration in
## use so that stays in sync automatically as durations above change.
const MAX_BASE_DURATION: float = 0.35


## The actual duration to hand a Tween for `base_duration`, honoring
## SettingsManager.reduce_motion.
static func duration(base_duration: float) -> float:
	if _reduce_motion():
		return base_duration * REDUCE_MOTION_SCALE
	return base_duration


## Looks up SettingsManager.reduce_motion via NodePath string rather than
## the bare `SettingsManager` identifier -- see the class doc comment
## above for why. Defaults to false (full motion) if the main loop or the
## singleton isn't available for any reason, e.g. a script tool context
## with no SceneTree at all.
static func _reduce_motion() -> bool:
	var loop: SceneTree = Engine.get_main_loop() as SceneTree
	if loop == null:
		return false
	var settings: Node = loop.root.get_node_or_null("/root/SettingsManager")
	if settings == null:
		return false
	return bool(settings.get("reduce_motion"))
