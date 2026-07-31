extends MainLoop
## One-shot dev tool: dumps the installed GodotSteam API surface (methods,
## signals, relevant project settings) to steam_probe.txt so netcode can be
## written against the exact installed version. Run:
##   godot --headless --path . --script res://tools/steam_probe.gd

func _initialize() -> void:
	var lines: Array = []
	lines.append("Steam class exists: %s" % ClassDB.class_exists("Steam"))
	lines.append("SteamMultiplayerPeer exists: %s" % ClassDB.class_exists("SteamMultiplayerPeer"))
	lines.append("Engine singleton Steam: %s" % Engine.has_singleton("Steam"))

	var interesting := ["steamInit", "steamInitEx", "run_callbacks", "isSteamRunning",
		"createLobby", "joinLobby", "leaveLobby", "setLobbyData", "getLobbyData",
		"requestLobbyList", "addRequestLobbyListStringFilter", "addRequestLobbyListDistanceFilter",
		"getLobbyOwner", "getNumLobbyMembers", "getLobbyMemberByIndex", "getLobbyMemberLimit",
		"getPersonaName", "getSteamID", "initRelayNetworkAccess", "getFriendPersonaName",
		"setLobbyJoinable", "getAppID", "loggedOn"]
	for cls in ["Steam", "SteamMultiplayerPeer"]:
		if not ClassDB.class_exists(cls):
			continue
		lines.append("\n=== %s methods ===" % cls)
		for m in ClassDB.class_get_method_list(cls, true):
			var name: String = m.name
			if cls == "SteamMultiplayerPeer" or name in interesting:
				var args: Array = []
				for a in m.args:
					args.append("%s:%s" % [a.name, type_string(a.type)])
				lines.append("%s(%s)" % [name, ", ".join(args)])
		lines.append("\n=== %s signals ===" % cls)
		for s in ClassDB.class_get_signal_list(cls, true):
			var name: String = s.name
			if cls == "SteamMultiplayerPeer" or ("lobby" in name or "network" in name):
				var args: Array = []
				for a in s.args:
					args.append(String(a.name))
				lines.append("%s(%s)" % [name, ", ".join(args)])

	lines.append("\n=== project settings (steam/*) ===")
	for setting in ["steam/initialization/app_id", "steam/initialization/initialize_on_startup",
			"steam/initialization/embed_callbacks"]:
		lines.append("%s -> has=%s val=%s" % [setting, ProjectSettings.has_setting(setting),
			str(ProjectSettings.get_setting(setting, "<none>"))])

	var f := FileAccess.open("res://tools/steam_probe.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()

func _process(_delta: float) -> bool:
	return true  # quit immediately
