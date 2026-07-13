extends SceneTree
## One-off (but reproducible) generator for a temporary placeholder app
## icon: a dark square background (matching project.godot's boot splash
## color) with the 5 passenger colors as a row of dots, so Android/iOS
## exports have *something* real to package instead of failing outright
## on a missing required icon file. Not final app art -- replace
## assets/icons/app_icon_1024.png with real artwork before any real
## release, the same way the temporary bundle/package ids need replacing.
##
## Usage: godot --headless --path . --script res://tools/generate_placeholder_icon.gd

const SIZE: int = 1024
const OUTPUT_PATH: String = "res://assets/icons/app_icon_1024.png"


func _initialize() -> void:
	var image: Image = Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.09, 0.09, 0.11, 1.0))

	var colors: Array[Color] = [
		PassengerColor.to_rgb(PassengerColor.Value.RED),
		PassengerColor.to_rgb(PassengerColor.Value.BLUE),
		PassengerColor.to_rgb(PassengerColor.Value.YELLOW),
		PassengerColor.to_rgb(PassengerColor.Value.GREEN),
		PassengerColor.to_rgb(PassengerColor.Value.PURPLE),
	]

	var dot_radius: float = SIZE * 0.11
	var spacing: float = SIZE * 0.19
	var start_x: float = SIZE / 2.0 - spacing * 2.0
	var center_y: float = SIZE / 2.0

	for i: int in colors.size():
		_draw_filled_circle(image, Vector2(start_x + spacing * i, center_y), dot_radius, colors[i])

	var err: Error = image.save_png(OUTPUT_PATH)
	print("[GeneratePlaceholderIcon] save_png(%s) -> %s" % [OUTPUT_PATH, "OK" if err == OK else "FAIL (%d)" % err])
	quit(0 if err == OK else 1)


func _draw_filled_circle(image: Image, center: Vector2, radius: float, color: Color) -> void:
	var min_x: int = max(0, int(center.x - radius))
	var max_x: int = min(image.get_width() - 1, int(center.x + radius))
	var min_y: int = max(0, int(center.y - radius))
	var max_y: int = min(image.get_height() - 1, int(center.y + radius))

	for y: int in range(min_y, max_y + 1):
		for x: int in range(min_x, max_x + 1):
			if Vector2(x, y).distance_to(center) <= radius:
				image.set_pixel(x, y, color)
