extends MainLoop
## One-shot asset tool: turns the Military_upgrade_card_Level*.jpeg templates
## into UI-ready textures — downscale, key out the magenta backing, crop to
## the card's bounds. Writes assets/card_lv1..4.png.
## Usage: godot --headless --script res://tools/process_cards.gd

const TARGET_W := 448

func _initialize() -> void:
	for i in range(1, 5):
		var src := "res://assets/Military_upgrade_card_Level%d.jpeg" % i
		var dst := "res://assets/card_lv%d.png" % i
		var img := Image.load_from_file(ProjectSettings.globalize_path(src))
		img.convert(Image.FORMAT_RGBA8)
		# Downscale BEFORE the per-pixel key so the GDScript loop stays fast.
		var h := int(round(img.get_height() * float(TARGET_W) / img.get_width()))
		img.resize(TARGET_W, h, Image.INTERPOLATE_LANCZOS)
		for y in range(img.get_height()):
			for x in range(img.get_width()):
				var c := img.get_pixel(x, y)
				var pinkness := minf(c.r, c.b) - c.g
				if pinkness >= 0.4:
					img.set_pixel(x, y, Color(0, 0, 0, 0))
				elif pinkness > 0.1:
					var a := 1.0 - (pinkness - 0.1) / 0.3
					img.set_pixel(x, y, Color(
						minf(c.r, c.g * 1.5), c.g, minf(c.b, c.g * 1.5), c.a * a))
		img = img.get_region(img.get_used_rect())
		img.save_png(ProjectSettings.globalize_path(dst))
		print("card_lv%d: %dx%d" % [i, img.get_width(), img.get_height()])

func _process(_delta: float) -> bool:
	return true  # exit immediately after _initialize
