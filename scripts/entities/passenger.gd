class_name Passenger
extends Control
## Reusable passenger token. No external visual assets -- appearance is a
## single rounded Panel colored from PassengerColor, and input is captured
## by an invisible child Button (so a single tap/click can't double-fire,
## exactly like every other UI button in this project: see
## input_devices/pointing/emulate_* in project.godot). Data (configure/
## set_selectable/set_disabled/set_moving) and visual updates
## (_update_visual) are kept in separate methods.

signal passenger_selected(passenger: Passenger)

const CORNER_RADIUS: int = 200

var color: int = PassengerColor.INVALID
var selectable: bool = true
var is_moving: bool = false

var _disabled_override: bool = false

@onready var _visual: Panel = %Visual
@onready var _input_button: Button = %InputButton


func _ready() -> void:
	_input_button.pressed.connect(_on_pressed)
	_update_visual()


## The one entry point for setting this passenger's color from outside.
## Only touches data; _update_visual() does the actual redraw.
func configure(p_color: int) -> void:
	color = p_color
	_update_visual()


func set_selectable(p_selectable: bool) -> void:
	selectable = p_selectable
	_update_visual()


func set_disabled(p_disabled: bool) -> void:
	_disabled_override = p_disabled
	_update_visual()


func set_moving(p_moving: bool) -> void:
	is_moving = p_moving
	_update_visual()


## Whether a tap/click should currently do anything: selectable, not
## disabled, not mid-move, and configured with a recognized color.
func can_be_selected() -> bool:
	return selectable and not _disabled_override and not is_moving and PassengerColor.is_valid(color)


func _on_pressed() -> void:
	if can_be_selected():
		passenger_selected.emit(self)


## Foundation for board-position movement: tweens this passenger's
## position to target_position over duration seconds, blocking selection
## for as long as it's moving. Nothing calls this yet -- no real gameplay
## target exists (added when the waiting-area/bus scenes land).
func move_to(target_position: Vector2, duration: float = 0.3) -> void:
	set_moving(true)
	var tween: Tween = create_tween()
	tween.tween_property(self, "position", target_position, duration)
	tween.finished.connect(_on_move_finished)


func _on_move_finished() -> void:
	set_moving(false)


## The only place appearance is computed/applied. A passenger that can't
## currently be selected (for any of the reasons in can_be_selected())
## always renders muted, regardless of which flag caused it.
##
## configure()/set_selectable()/etc. can legitimately be called right after
## instantiate() + add_child(), before _ready() has run (@onready vars not
## resolved yet) -- in that case just skip the redraw; _ready() calls
## _update_visual() itself once the node is actually ready, and by then it
## will pick up whatever state was set in the meantime.
func _update_visual() -> void:
	if not is_node_ready():
		return

	var active: bool = can_be_selected()
	var base_color: Color = PassengerColor.to_rgb(color)
	var display_color: Color = base_color if active else base_color.lerp(Color(0.55, 0.55, 0.55), 0.7)

	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = display_color
	style.set_corner_radius_all(CORNER_RADIUS)
	_visual.add_theme_stylebox_override("panel", style)

	_input_button.disabled = not active
