extends MainLoop
## One-shot asset tool: keys magenta backgrounds out of raw character art.
## Usage (writes assets/soldier.png from assets/Character_Soldier.png by default):
##   godot --headless --script res://tools/chroma_key.gd
##   godot --headless --script res://tools/chroma_key.gd -- <src.png> <dst.png>

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var src := "res://assets/Character_Soldier.png"
	var dst := "res://assets/soldier.png"
	if args.size() >= 2:
		src = args[0]
		dst = args[1]
	var img := Image.load_from_file(ProjectSettings.globalize_path(src))
	img.convert(Image.FORMAT_RGBA8)
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c := img.get_pixel(x, y)
			# Magenta reads as high red+blue, low green.
			var pinkness := minf(c.r, c.b) - c.g
			if pinkness >= 0.4:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
			elif pinkness > 0.1:
				# Soft edge: fade alpha and clamp the magenta spill toward green.
				var a := 1.0 - (pinkness - 0.1) / 0.3
				img.set_pixel(x, y, Color(
					minf(c.r, c.g * 1.5), c.g, minf(c.b, c.g * 1.5), c.a * a))
	img.save_png(ProjectSettings.globalize_path(dst))
	print("chroma_key: %s -> %s (%dx%d)" % [src, dst, img.get_width(), img.get_height()])

func _process(_delta: float) -> bool:
	return true  # exit immediately after _initialize
