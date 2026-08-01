extends Node
## Autoload "Net": multiplayer session + lobby management.
##
## Two transports behind one interface:
##  - Steam (GodotSteam GDExtension + SteamMultiplayerPeer): public lobbies with
##    matchmaking — host creates a lobby, friends see it in the browser and join.
##    Uses Valve's dev app id 480 until the game has its own Steamworks app.
##  - ENet (LAN / direct IP): always available, no Steam needed. Also what the
##    headless multiplayer smoke test uses.
##
## The host is always peer 1 and simulates the whole game; see main.gd for the
## snapshot/event replication. This node only handles session + lobby roster.

signal lobby_updated                     # roster / ready / class changed
signal lobby_list_ready(lobbies: Array)  # [{id, name, players, cap}]
signal session_error(message: String)
signal game_starting                     # fired on every peer when host starts

const APP_ID := 480          # SpaceWar dev app id; replace with a real one later
const LOBBY_KEY := "basedefense_v1"  # lobby browser filter so we only see our lobbies
const ENET_PORT := 24565
const MAX_PLAYERS := 4

enum Mode { OFFLINE, HOST, CLIENT }

var mode: int = Mode.OFFLINE
var transport := ""          # "steam" | "enet" | ""
var steam_ok := false
var steam_name := ""
var lobby_id: int = 0
var roster: Dictionary = {}  # peer_id -> {"name": String, "tank": String, "ready": bool}
var started := false         # a run is in progress
var return_to_lobby := false # after a restart, menu should land on the lobby screen

var game: Node = null        # main.gd registers itself here each scene load

var _host_pending := false   # waiting for Steam lobby_created

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_init_steam()

func _process(_delta: float) -> void:
	if steam_ok:
		Steam.run_callbacks()

func _init_steam() -> void:
	if not ClassDB.class_exists("Steam"):
		return
	if not Steam.isSteamRunning():
		return
	var res: Dictionary = Steam.steamInitEx(APP_ID, false)
	steam_ok = int(res.get("status", 1)) == 0
	if not steam_ok:
		push_warning("Steam init failed: %s" % str(res))
		return
	steam_name = Steam.getPersonaName()
	Steam.initRelayNetworkAccess()  # warm up P2P relay routing early
	Steam.lobby_created.connect(_on_steam_lobby_created)
	Steam.lobby_joined.connect(_on_steam_lobby_joined)
	Steam.lobby_match_list.connect(_on_steam_lobby_list)

# --- Session facts ---

func active() -> bool:
	return mode != Mode.OFFLINE

## True when this instance runs the simulation (solo or the MP host).
func is_authority() -> bool:
	return mode != Mode.CLIENT

func hosting() -> bool:
	return mode == Mode.HOST

func my_id() -> int:
	return multiplayer.get_unique_id() if active() else 1

func player_name() -> String:
	if steam_ok:
		return steam_name
	return "Commander %d" % (my_id() % 1000)

## Build version both peers must share to play together (from project settings).
## Used by the join handshake and advertised in Steam lobby data.
func game_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))

# --- Hosting / joining ---

func host_game(force_lan := false) -> void:
	if steam_ok and not force_lan:
		_host_steam()
	else:
		_host_enet()

func _host_steam() -> void:
	mode = Mode.HOST
	transport = "steam"
	_host_pending = true
	Steam.createLobby(2, MAX_PLAYERS)  # 2 = public lobby

func _on_steam_lobby_created(connect_result: int, this_lobby_id: int) -> void:
	if not _host_pending:
		return
	_host_pending = false
	if connect_result != 1:
		_fail("Steam couldn't create the lobby (code %d)." % connect_result)
		return
	lobby_id = this_lobby_id
	Steam.setLobbyData(lobby_id, "game", LOBBY_KEY)
	Steam.setLobbyData(lobby_id, "name", "%s's squad" % player_name())
	Steam.setLobbyData(lobby_id, "version", game_version())  # shown in the browser
	var peer := SteamMultiplayerPeer.new()
	var err: int = peer.host_with_lobby(lobby_id)
	if err != OK:
		_fail("Steam host failed (error %d)." % err)
		return
	multiplayer.multiplayer_peer = peer
	_reset_roster_as_host()

func _host_enet() -> void:
	mode = Mode.HOST
	transport = "enet"
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(ENET_PORT, MAX_PLAYERS - 1)
	if err != OK:
		_fail("Couldn't open LAN server on port %d (error %d)." % [ENET_PORT, err])
		return
	multiplayer.multiplayer_peer = peer
	_reset_roster_as_host()

func _reset_roster_as_host() -> void:
	roster = {1: {"name": player_name(), "tank": "assault", "ready": false}}
	started = false
	lobby_updated.emit()

## Two steps: first actually join the Steam lobby, THEN (in the lobby_joined
## callback) open the peer connection to the host. connect_to_lobby needs us to
## already be a lobby member so it can read the owner's SteamID — calling it
## before joining fails with ERR_CANT_CREATE (error 20).
func join_steam_lobby(id: int) -> void:
	mode = Mode.CLIENT
	transport = "steam"
	lobby_id = id
	Steam.joinLobby(id)

func _on_steam_lobby_joined(joined_lobby: int, _perms: int, _locked: bool, response: int) -> void:
	if mode != Mode.CLIENT:
		return
	if response != 1:  # 1 = k_EChatRoomEnterResponseSuccess
		_fail("Lobby join refused (code %d)." % response)
		return
	lobby_id = joined_lobby
	var peer := SteamMultiplayerPeer.new()
	var err: int = peer.connect_to_lobby(joined_lobby)
	if err != OK:
		_fail("Couldn't connect to the host (error %d)." % err)
		return
	multiplayer.multiplayer_peer = peer

func join_enet(ip: String) -> void:
	mode = Mode.CLIENT
	transport = "enet"
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, ENET_PORT)
	if err != OK:
		_fail("Couldn't connect to %s (error %d)." % [ip, err])
		return
	multiplayer.multiplayer_peer = peer

func refresh_lobby_list() -> void:
	if not steam_ok:
		lobby_list_ready.emit([])
		return
	Steam.addRequestLobbyListStringFilter("game", LOBBY_KEY, 0)  # 0 = equal
	Steam.addRequestLobbyListDistanceFilter(3)  # 3 = worldwide
	Steam.requestLobbyList()

func _on_steam_lobby_list(lobbies: Array) -> void:
	var out: Array = []
	for id in lobbies:
		out.append({
			"id": int(id),
			"name": Steam.getLobbyData(id, "name"),
			"players": Steam.getNumLobbyMembers(id),
			"cap": Steam.getLobbyMemberLimit(id),
			"version": Steam.getLobbyData(id, "version"),
		})
	lobby_list_ready.emit(out)

func leave() -> void:
	if steam_ok and lobby_id != 0:
		Steam.leaveLobby(lobby_id)
	lobby_id = 0
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = Mode.OFFLINE
	transport = ""
	roster = {}
	started = false
	return_to_lobby = false
	lobby_updated.emit()

func _fail(message: String) -> void:
	leave()
	session_error.emit(message)

## Best-effort LAN address to show the host so friends can direct-connect.
func local_ip() -> String:
	for addr in IP.get_local_addresses():
		var s := String(addr)
		if s.begins_with("192.168.") or s.begins_with("10.") or s.begins_with("172."):
			return s
	return "127.0.0.1"

# --- Connection callbacks ---

func _on_peer_connected(_peer_id: int) -> void:
	# Roster entry appears when the client introduces itself (srv_hello).
	pass

func _on_peer_disconnected(peer_id: int) -> void:
	if hosting():
		roster.erase(peer_id)
		rpc(&"cl_roster", roster)
		lobby_updated.emit()
		if started and game != null and is_instance_valid(game) and game.has_method("host_peer_left"):
			game.host_peer_left(peer_id)

func _on_connected_to_server() -> void:
	rpc_id(1, &"srv_hello", player_name(), game_version())

func _on_connection_failed() -> void:
	_fail("Connection failed — host not reachable.")

func _on_server_disconnected() -> void:
	if mode == Mode.OFFLINE:
		return  # already torn down (e.g. after a version-mismatch kick)
	var was_started := started
	_fail("Lost connection to the host.")
	if was_started:
		get_tree().paused = false
		get_tree().reload_current_scene()

# --- Lobby roster RPCs (host relays authoritative state) ---

@rpc("any_peer", "reliable")
func srv_hello(display_name: String, version: String = "") -> void:
	if not hosting():
		return
	var sender := multiplayer.get_remote_sender_id()
	# Reject mismatched builds before they can desync the sim. Clients too old to
	# send a version (or to understand cl_kick) just never get added, and the
	# backstop timer below drops them.
	if version != game_version():
		var shown := version if version != "" else "an older build"
		rpc_id(sender, &"cl_kick", "Version mismatch: host is v%s, you have v%s. Update to join." % [game_version(), shown])
		var peer := multiplayer.multiplayer_peer
		get_tree().create_timer(1.0).timeout.connect(func():
			if peer != null and multiplayer.multiplayer_peer == peer and peer.has_method("disconnect_peer"):
				peer.disconnect_peer(sender))
		return
	roster[sender] = {"name": display_name, "tank": "assault", "ready": false}
	rpc(&"cl_roster", roster)
	lobby_updated.emit()

## Host rejected us (e.g. version mismatch) — surface why and drop to the menu.
@rpc("authority", "reliable")
func cl_kick(reason: String) -> void:
	_fail(reason)

@rpc("any_peer", "reliable")
func srv_set_tank(tank: String) -> void:
	if not hosting():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1
	if roster.has(sender) and TankData.CLASSES.has(tank):
		roster[sender].tank = tank
		rpc(&"cl_roster", roster)
		lobby_updated.emit()

@rpc("any_peer", "reliable")
func srv_set_ready(ready: bool) -> void:
	if not hosting():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1
	if roster.has(sender):
		roster[sender].ready = ready
		rpc(&"cl_roster", roster)
		lobby_updated.emit()

@rpc("authority", "reliable")
func cl_roster(new_roster: Dictionary) -> void:
	roster = new_roster
	lobby_updated.emit()

## Local helpers so callers don't care whether they're host or client.
func set_my_tank(tank: String) -> void:
	if hosting():
		if roster.has(1) and TankData.CLASSES.has(tank):
			roster[1].tank = tank
			rpc(&"cl_roster", roster)
			lobby_updated.emit()
	elif active():
		rpc_id(1, &"srv_set_tank", tank)

func set_my_ready(ready: bool) -> void:
	if hosting():
		if roster.has(1):
			roster[1].ready = ready
			rpc(&"cl_roster", roster)
			lobby_updated.emit()
	elif active():
		rpc_id(1, &"srv_set_ready", ready)

func all_ready() -> bool:
	if roster.is_empty():
		return false
	for id in roster:
		if not roster[id].ready:
			return false
	return true

## Host-only: launch the run for everyone.
func request_start() -> void:
	if not hosting() or not all_ready():
		return
	if steam_ok and lobby_id != 0:
		Steam.setLobbyJoinable(lobby_id, false)  # no joins mid-run
	rpc(&"cl_start", roster)
	cl_start(roster)

@rpc("authority", "reliable")
func cl_start(final_roster: Dictionary) -> void:
	roster = final_roster
	started = true
	game_starting.emit()

## Any peer returning to the lobby after a run (scene reload path).
func back_to_lobby() -> void:
	started = false
	return_to_lobby = true
	if hosting():
		if steam_ok and lobby_id != 0:
			Steam.setLobbyJoinable(lobby_id, true)
		for id in roster:
			roster[id].ready = false
		rpc(&"cl_roster", roster)
	lobby_updated.emit()
