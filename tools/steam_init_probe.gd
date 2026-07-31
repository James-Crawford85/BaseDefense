extends MainLoop
## Dev probe: actually attempts Steam init with app 480 and reports the result
## dict + working directory, so we can see WHY init fails. Run:
##   godot --headless --path . --script res://tools/steam_init_probe.gd

func _initialize() -> void:
	var lines: Array = []
	lines.append("cwd: %s" % OS.get_environment("PWD"))
	lines.append("exec dir: %s" % OS.get_executable_path().get_base_dir())
	lines.append("res:// appid exists: %s" % FileAccess.file_exists("res://steam_appid.txt"))
	lines.append("Steam.isSteamRunning: %s" % Steam.isSteamRunning())
	var res: Dictionary = Steam.steamInitEx(480, false)
	lines.append("steamInitEx(480) -> %s" % str(res))
	if int(res.get("status", 1)) == 0:
		lines.append("persona: %s" % Steam.getPersonaName())
		lines.append("steamID: %s" % Steam.getSteamID())
	var f := FileAccess.open("res://tools/steam_init_probe.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()

func _process(_delta: float) -> bool:
	return true
