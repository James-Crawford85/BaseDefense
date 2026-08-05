extends Node
## Autoload "Fonts": the game's house typefaces, loaded once at boot.
##
## Direction (see docs/ui-fonts.md): Rajdhani + Oxanium are the two house fonts,
## used across ALL UI for a unified look. Rajdhani is the everyday face (labels,
## numbers, values); Oxanium is the heavier accent face (titles, alerts, headers).
## Orbitron is a sparing "something a bit different but still fitting" flourish.
##
## Rajdhani is also wired in as the project's default font (project.godot,
## gui/theme/custom_font), so every control renders it without any per-label code.
## This autoload is for the exceptions: picking a specific Rajdhani weight, or
## switching a label to the Oxanium accent / Orbitron flourish faces.

const _RAJDHANI := {
	"light": "res://assets/fonts/Rajdhani/Rajdhani-Light.ttf",
	"regular": "res://assets/fonts/Rajdhani/Rajdhani-Regular.ttf",
	"medium": "res://assets/fonts/Rajdhani/Rajdhani-Medium.ttf",
	"semibold": "res://assets/fonts/Rajdhani/Rajdhani-SemiBold.ttf",
	"bold": "res://assets/fonts/Rajdhani/Rajdhani-Bold.ttf",
}
const _OXANIUM := {
	"regular": "res://assets/fonts/Oxanium/static/Oxanium-Regular.ttf",
	"medium": "res://assets/fonts/Oxanium/static/Oxanium-Medium.ttf",
	"semibold": "res://assets/fonts/Oxanium/static/Oxanium-SemiBold.ttf",
	"bold": "res://assets/fonts/Oxanium/static/Oxanium-Bold.ttf",
	"extrabold": "res://assets/fonts/Oxanium/static/Oxanium-ExtraBold.ttf",
}
const _ORBITRON := {
	"regular": "res://assets/fonts/Orbitron/static/Orbitron-Regular.ttf",
	"medium": "res://assets/fonts/Orbitron/static/Orbitron-Medium.ttf",
	"semibold": "res://assets/fonts/Orbitron/static/Orbitron-SemiBold.ttf",
	"bold": "res://assets/fonts/Orbitron/static/Orbitron-Bold.ttf",
	"black": "res://assets/fonts/Orbitron/static/Orbitron-Black.ttf",
}

# Everyday HUD/body faces (Rajdhani).
var body: FontFile          # regular — default weight for most text
var body_medium: FontFile
var body_semibold: FontFile
var body_bold: FontFile
# Accent / title face (Oxanium).
var title: FontFile         # semibold — headers, section titles
var title_bold: FontFile    # bold — big titles
var alert: FontFile         # extrabold — major alerts ("WAVE INCOMING")
# Sparing flourish face (Orbitron).
var flourish: FontFile

func _ready() -> void:
	body = _load(_RAJDHANI, "regular")
	body_medium = _load(_RAJDHANI, "medium")
	body_semibold = _load(_RAJDHANI, "semibold")
	body_bold = _load(_RAJDHANI, "bold")
	title = _load(_OXANIUM, "semibold")
	title_bold = _load(_OXANIUM, "bold")
	alert = _load(_OXANIUM, "extrabold")
	flourish = _load(_ORBITRON, "bold")

func _load(family: Dictionary, weight: String) -> FontFile:
	var path: String = family[weight]
	if ResourceLoader.exists(path):
		return load(path)
	return null

# --- Helpers: set a control's font (and optionally size) in one call. ---

## Apply a font override to a Control (Label, Button, etc.). `font` is one of the
## exposed faces (e.g. Fonts.title). Pass size <= 0 to leave the size untouched.
func apply(ctrl: Control, font: FontFile, size: int = 0) -> void:
	if font != null:
		ctrl.add_theme_font_override("font", font)
	if size > 0:
		ctrl.add_theme_font_size_override("font_size", size)
