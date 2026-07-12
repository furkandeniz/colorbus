extends Control
## Root of the responsive app shell: a safe-area aware Header / ContentArea /
## Footer stack plus a temporary debug label showing the live viewport size.
## Contains no game logic -- this is the mobile layout scaffold only.

@onready var _safe_area: MarginContainer = %SafeArea
@onready var _debug_label: Label = %DebugLabel
@onready var _header: Control = %Header
@onready var _content_area: Control = %ContentArea
@onready var _footer: Control = %Footer


func _ready() -> void:
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_apply_safe_area()
	await get_tree().process_frame
	_update_debug_label()
	_print_layout_debug()


func _on_viewport_size_changed() -> void:
	_apply_safe_area()
	_update_debug_label()


func _apply_safe_area() -> void:
	var margins: Dictionary = PlatformService.get_safe_area_margins()
	_safe_area.add_theme_constant_override("margin_left", int(margins["left"]))
	_safe_area.add_theme_constant_override("margin_top", int(margins["top"]))
	_safe_area.add_theme_constant_override("margin_right", int(margins["right"]))
	_safe_area.add_theme_constant_override("margin_bottom", int(margins["bottom"]))


func _update_debug_label() -> void:
	var size: Vector2i = get_viewport().get_visible_rect().size
	_debug_label.text = "%d x %d" % [size.x, size.y]
	print("[ColorBus] viewport=%d x %d" % [size.x, size.y])


func _print_layout_debug() -> void:
	print("[ColorBus] header_rect=%s" % [_header.get_global_rect()])
	print("[ColorBus] content_rect=%s" % [_content_area.get_global_rect()])
	print("[ColorBus] footer_rect=%s" % [_footer.get_global_rect()])
