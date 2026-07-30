extends MainLoop
## One-shot asset tool: turns the raw Enemy_* vehicle art (magenta backing)
## into game-ready sprites — downscale, key out the magenta, crop to bounds.
## All outputs face UP; the Ogre source faces down so it gets rotated 180.
## Writes assets/enemy_<type>.png.
## Usage: godot --headless --script res://tools/process_enemies.gd

const TARGET := 512  # longest side before keying (keeps the pixel loop fast)

const SOURCES: Array = [
	{"src": "Enemy_Grunt.jpeg", "out": "grunt", "flip": false},
	{"src": "Enemy_Runner.jpeg", "out": "runner", "flip": false},
	{"src": "Enemy_Stinger.jpeg", "out": "stinger", "flip": false},
	{"src": "Enemy_Brute.jpeg", "out": "brute", "flip": false},
	{"src": "Enemy_Ogre.jpeg", "out": "ogre", "flip": true},
	{"src": "Enemy Spitter.png", "out": "spitter", "flip": false},
]

func _initialize() -> void:
	for entry in SOURCES:
		var img := Image.load_from_file(
			ProjectSettings.globalize_path("res://assets/" + entry.src))
		img.convert(Image.FORMAT_RGBA8)
		var s := float(TARGET) / maxi(img.get_width(), img.get_height())
		img.resize(int(round(img.get_width() * s)), int(round(img.get_height() * s)),
			Image.INTERPOLATE_LANCZOS)
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
		if entry.flip:
			img.rotate_180()
		img = img.get_region(img.get_used_rect())
		var dst := "res://assets/enemy_%s.png" % entry.out
		img.save_png(ProjectSettings.globalize_path(dst))
		print("enemy_%s: %dx%d" % [entry.out, img.get_width(), img.get_height()])

func _process(_delta: float) -> bool:
	return true  # exit immediately after _initialize
