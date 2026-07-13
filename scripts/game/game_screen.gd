extends Control
## The main gameplay screen. Loads AppRouter.pending_level_id via
## LevelRepository, builds the BusQueue/WaitingArea/PassengerQueue view
## nodes for it, and hands them to a fresh GameController (never Autoload
## -- owned solely by this scene instance, freed with it when AppRouter
## replaces the screen). This script only builds Nodes and reacts to
## GameController.state_changed for popups/buttons; GameController and
## GameRules own every actual gameplay decision.

const BusQueueScene: PackedScene = preload("res://scenes/game/bus_queue.tscn")
const WaitingAreaScene: PackedScene = preload("res://scenes/game/waiting_area.tscn")
const PassengerQueueScene: PackedScene = preload("res://scenes/game/passenger_queue.tscn")

@onready var _safe_area: MarginContainer = %SafeArea
@onready var _level_info_label: Label = %LevelInfoLabel
@onready var _bus_area: Control = %BusArea
@onready var _waiting_area_container: Control = %WaitingAreaContainer
@onready var _passenger_queues_container: HBoxContainer = %PassengerQueuesContainer
@onready var _restart_button: Button = %RestartButton
@onready var _pause_button: Button = %PauseButton
@onready var _win_popup: Control = %WinPopup
@onready var _lose_popup: Control = %LosePopup
@onready var _win_next_button: Button = %WinNextButton
@onready var _win_menu_button: Button = %WinMenuButton
@onready var _lose_retry_button: Button = %LoseRetryButton
@onready var _lose_menu_button: Button = %LoseMenuButton

var controller: GameController = null


func _ready() -> void:
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()

	_restart_button.pressed.connect(_on_restart_pressed)
	_pause_button.pressed.connect(_on_pause_pressed)
	_win_next_button.pressed.connect(_on_win_next_pressed)
	_win_menu_button.pressed.connect(_on_menu_pressed)
	_lose_retry_button.pressed.connect(_on_restart_pressed)
	_lose_menu_button.pressed.connect(_on_menu_pressed)

	_win_popup.visible = false
	_lose_popup.visible = false

	_load_and_start(AppRouter.pending_level_id)


func _apply_safe_area() -> void:
	var margins: Dictionary = PlatformService.get_safe_area_margins()
	_safe_area.add_theme_constant_override("margin_left", int(margins["left"]))
	_safe_area.add_theme_constant_override("margin_top", int(margins["top"]))
	_safe_area.add_theme_constant_override("margin_right", int(margins["right"]))
	_safe_area.add_theme_constant_override("margin_bottom", int(margins["bottom"]))


## A level failing to load here (missing file, failed validation) is a
## controlled, non-crashing dead end -- errors are logged (debug builds
## only) and the screen just stays empty rather than starting a broken
## game. Real callers only ever reach this with one of the 5 validated
## sample levels, so this path is defensive, not the common case.
func _load_and_start(level_id: int) -> void:
	var result: LevelLoadResult = LevelRepository.load_level_by_id(level_id)
	if not result.is_success():
		if OS.is_debug_build():
			for error: String in result.errors:
				print("[GameScreen] %s" % error)
		return

	var bus_queue: BusQueue = BusQueueScene.instantiate()
	_bus_area.add_child(bus_queue)

	var waiting_area: WaitingArea = WaitingAreaScene.instantiate()
	_waiting_area_container.add_child(waiting_area)

	var passenger_queues: Array[PassengerQueue] = []
	for i: int in result.level.passenger_queues.size():
		var queue: PassengerQueue = PassengerQueueScene.instantiate()
		_passenger_queues_container.add_child(queue)
		passenger_queues.append(queue)

	controller = GameController.new(result.level, bus_queue, waiting_area, passenger_queues)
	controller.state_changed.connect(_on_state_changed)
	_level_info_label.text = result.level.name_key
	controller.start()


func _on_state_changed(state: GameController.State) -> void:
	_win_popup.visible = state == GameController.State.WON
	_lose_popup.visible = state == GameController.State.LOST
	_pause_button.disabled = state == GameController.State.WON or state == GameController.State.LOST


func _on_restart_pressed() -> void:
	_win_popup.visible = false
	_lose_popup.visible = false
	if controller != null:
		controller.restart()


func _on_pause_pressed() -> void:
	if controller == null:
		return
	if controller.state == GameController.State.PAUSED:
		controller.resume()
	else:
		controller.pause()


func _on_win_next_pressed() -> void:
	if controller != null:
		AppRouter.start_level(controller.level.id + 1)


func _on_menu_pressed() -> void:
	AppRouter.push_screen(AppRouter.Screen.MAIN_MENU)
