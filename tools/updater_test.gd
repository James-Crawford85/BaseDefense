extends SceneTree
## Headless updater verification. Run:
##   godot --headless --path . --script res://tools/updater_test.gd
## Writes results to res://tools/updater_test.txt and quits.

const HEADERS: PackedStringArray = [
	"User-Agent: BaseDefense-Updater",
	"Accept: application/vnd.github+json",
]
const API := "https://api.github.com/repos/James-Crawford85/BaseDefense/releases/latest"

var _log: Array = []

func _initialize() -> void:
	var U = load("res://scripts/updater.gd")
	# 1. semver comparison
	var ok := true
	ok = ok and U.is_newer("v0.2.0", "v0.1.0")
	ok = ok and U.is_newer("0.1.1", "0.1.0")
	ok = ok and U.is_newer("1.0.0", "0.9.9")
	ok = ok and U.is_newer("0.2.0", "0.1.9")
	ok = ok and not U.is_newer("0.1.0", "0.1.0")
	ok = ok and not U.is_newer("0.1.0", "0.2.0")
	ok = ok and not U.is_newer("v0.1.0-beta", "0.1.0")
	_log.append("VERSION_COMPARE: %s" % ("OK" if ok else "FAIL"))

	# Let the SceneTree finish standing up its root before we add nodes / network.
	await process_frame
	await process_frame

	# 2. live GitHub API check (spoof current = 0.0.9 so v0.1.0 counts as newer)
	var http := HTTPRequest.new()
	root.add_child(http)
	http.request_completed.connect(_on_api)
	var err := http.request(API, HEADERS)
	if err != OK:
		_finish("API_REQUEST_ERR: %d" % err)

func _on_api(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_finish("API_HTTP_FAIL: result=%d code=%d" % [result, code])
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY:
		_finish("API_PARSE_FAIL")
		return
	var tag := str(data.get("tag_name", ""))
	var U = load("res://scripts/updater.gd")
	var detects: bool = U.is_newer(tag, "0.0.9")
	var zip_url := ""
	for asset in data.get("assets", []):
		if str(asset.get("name", "")).to_lower().ends_with(".zip"):
			zip_url = str(asset.get("browser_download_url", ""))
			break
	_log.append("API_LATEST_TAG: %s" % tag)
	_log.append("DETECTS_NEWER_THAN_0.0.9: %s" % detects)
	_log.append("ZIP_ASSET_FOUND: %s" % (zip_url != ""))
	if zip_url == "":
		_finish("no zip asset")
		return
	# 3. download the real asset and extract it
	var dl := HTTPRequest.new()
	dl.download_file = "user://ut_update.zip"
	root.add_child(dl)
	dl.request_completed.connect(_on_dl)
	if dl.request(zip_url, HEADERS) != OK:
		_finish("DL_REQUEST_ERR")

func _on_dl(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		_finish("DL_HTTP_FAIL: result=%d code=%d" % [result, code])
		return
	var reader := ZIPReader.new()
	if reader.open("user://ut_update.zip") != OK:
		_finish("ZIP_OPEN_FAIL")
		return
	var files := reader.get_files()
	var has_exe := false
	var has_appid := false
	for f in files:
		if f.ends_with("BaseDefense.exe"):
			has_exe = true
		if f.ends_with("steam_appid.txt"):
			has_appid = true
	reader.close()
	_log.append("ZIP_FILE_COUNT: %d" % files.size())
	_log.append("ZIP_HAS_EXE: %s" % has_exe)
	_log.append("ZIP_HAS_APPID: %s" % has_appid)
	_finish("DONE")

func _finish(status: String) -> void:
	_log.append("STATUS: %s" % status)
	var f := FileAccess.open("res://tools/updater_test.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	quit()
