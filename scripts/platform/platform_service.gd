extends Node
## Autoload singleton. Single point of contact for anything platform-specific
## (Android, iOS, desktop). Game and UI code must never branch on OS name
## directly -- they call into this service instead.

enum PlatformKind { ANDROID, IOS, DESKTOP, WEB, UNKNOWN }

var current_platform: PlatformKind = PlatformKind.UNKNOWN
var has_touch_screen: bool = false


func _ready() -> void:
	current_platform = _detect_platform()
	has_touch_screen = DisplayServer.is_touchscreen_available()


func _detect_platform() -> PlatformKind:
	var os_name: String = OS.get_name()
	match os_name:
		"Android":
			return PlatformKind.ANDROID
		"iOS":
			return PlatformKind.IOS
		"Web":
			return PlatformKind.WEB
		"macOS", "Windows", "Linux", "LinuxBSD":
			return PlatformKind.DESKTOP
		_:
			return PlatformKind.UNKNOWN


func is_mobile() -> bool:
	return current_platform == PlatformKind.ANDROID or current_platform == PlatformKind.IOS


## Returns the safe area insets (in pixels, current screen space) as
## left/top/right/bottom margins that UI must not place content under
## (notches, rounded corners, home indicators, status bars).
func get_safe_area_margins() -> Dictionary:
	var screen_index: int = DisplayServer.window_get_current_screen()
	var screen_rect: Rect2i = DisplayServer.screen_get_usable_rect(screen_index)
	var safe_rect: Rect2i = DisplayServer.get_display_safe_area()

	if safe_rect.size.x <= 0 or safe_rect.size.y <= 0:
		return {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}

	var left: float = float(safe_rect.position.x - screen_rect.position.x)
	var top: float = float(safe_rect.position.y - screen_rect.position.y)
	var right: float = float((screen_rect.position.x + screen_rect.size.x) - (safe_rect.position.x + safe_rect.size.x))
	var bottom: float = float((screen_rect.position.y + screen_rect.size.y) - (safe_rect.position.y + safe_rect.size.y))

	return {
		"left": max(left, 0.0),
		"top": max(top, 0.0),
		"right": max(right, 0.0),
		"bottom": max(bottom, 0.0),
	}
