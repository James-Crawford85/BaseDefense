extends Node
## Autoload "Updater": checks GitHub Releases for a newer build and, on request,
## downloads + applies it so players never have to re-download by hand.
##
## Flow: check_for_updates() hits the public GitHub API (no auth needed for a
## public repo), compares the latest release tag to this build's baked-in
## version (application/config/version), and emits `update_available` if we're
## behind. download_and_apply() fetches the release zip, extracts it beside the
## exe, then launches a tiny helper .bat that waits for the game to close,
## swaps the files, and relaunches — the standard Windows self-update dance,
## since a running exe can't overwrite itself.

signal update_available(version: String, notes: String)
signal up_to_date
signal check_failed(message: String)
signal download_progress(fraction: float)
signal update_failed(message: String)

const REPO := "James-Crawford85/BaseDefense"
const API_LATEST := "https://api.github.com/repos/%s/releases/latest" % REPO
const HEADERS: PackedStringArray = [
	"User-Agent: BaseDefense-Updater",
	"Accept: application/vnd.github+json",
]

var current_version: String = ""
var latest_version: String = ""
var latest_notes: String = ""
var download_url: String = ""
var download_size: int = 0
var available: bool = false

var _api: HTTPRequest
var _dl: HTTPRequest
var _downloading: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	current_version = str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	_api = HTTPRequest.new()
	_api.timeout = 10.0
	add_child(_api)
	_api.request_completed.connect(_on_api_completed)
	_dl = HTTPRequest.new()
	add_child(_dl)
	_dl.request_completed.connect(_on_download_completed)

func check_for_updates() -> void:
	# Editor runs have no exe to replace; still allow the check for testing.
	var err := _api.request(API_LATEST, HEADERS, HTTPClient.METHOD_GET)
	if err != OK:
		check_failed.emit("Could not reach the update server.")

func _on_api_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		check_failed.emit("Update check failed (HTTP %d)." % code)
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY or not data.has("tag_name"):
		check_failed.emit("Unexpected response from the update server.")
		return
	latest_version = str(data.tag_name)
	latest_notes = str(data.get("body", ""))
	download_url = ""
	download_size = 0
	for asset in data.get("assets", []):
		var aname := str(asset.get("name", ""))
		if aname.to_lower().ends_with(".zip"):
			download_url = str(asset.get("browser_download_url", ""))
			download_size = int(asset.get("size", 0))
			break
	if is_newer(latest_version, current_version):
		available = true
		update_available.emit(_clean(latest_version), latest_notes)
	else:
		available = false
		up_to_date.emit()

## True if version string `a` is strictly newer than `b` (semver-ish; a leading
## "v" and any non-numeric tail like "-beta" are ignored per component).
static func is_newer(a: String, b: String) -> bool:
	var pa := _parse(a)
	var pb := _parse(b)
	for i in range(maxi(pa.size(), pb.size())):
		var na: int = pa[i] if i < pa.size() else 0
		var nb: int = pb[i] if i < pb.size() else 0
		if na != nb:
			return na > nb
	return false

static func _parse(v: String) -> Array:
	var out: Array = []
	for part in _clean(v).split("."):
		var digits := ""
		for c in part:
			if c >= "0" and c <= "9":
				digits += c
			else:
				break
		out.append(int(digits) if digits != "" else 0)
	return out

static func _clean(v: String) -> String:
	var s := v.strip_edges()
	if s.begins_with("v") or s.begins_with("V"):
		s = s.substr(1)
	return s

# --- Download + apply ---

func download_and_apply() -> void:
	if not available or download_url == "":
		update_failed.emit("No update available to download.")
		return
	if OS.has_feature("editor"):
		update_failed.emit("Self-update is disabled in the editor (export a build to test it).")
		return
	if _downloading:
		return
	_downloading = true
	_dl.download_file = "user://update.zip"
	var err := _dl.request(download_url, HEADERS, HTTPClient.METHOD_GET)
	if err != OK:
		_downloading = false
		update_failed.emit("Could not start the download.")

func _process(_delta: float) -> void:
	if _downloading:
		var total := _dl.get_body_size()
		if total <= 0:
			total = download_size
		if total > 0:
			download_progress.emit(clampf(float(_dl.get_downloaded_bytes()) / float(total), 0.0, 1.0))

func _on_download_completed(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if not _downloading:
		return
	_downloading = false
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		update_failed.emit("Download failed (HTTP %d)." % code)
		return
	download_progress.emit(1.0)
	_apply("user://update.zip")

## Extracts the downloaded zip next to the exe and hands off to a helper batch
## that performs the swap once this process has exited. Returns via signal on
## failure; on success the game quits (the batch relaunches it).
func _apply(zip_path: String) -> void:
	var install_dir := OS.get_executable_path().get_base_dir()
	var exe_name := OS.get_executable_path().get_file()
	var staging := install_dir.path_join(".update")

	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		update_failed.emit("Downloaded update was unreadable.")
		return
	# Clear any stale staging from a previous attempt.
	_rm_rf(staging)
	for entry in reader.get_files():
		if entry.ends_with("/"):
			continue
		var out_path := staging.path_join(entry)
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f == null:
			update_failed.emit("Couldn't write update files (is the folder writable?).")
			reader.close()
			return
		f.store_buffer(reader.read_file(entry))
		f.close()
	reader.close()

	# The zip contains a top-level BaseDefense/ folder; copy its contents up.
	var src := staging.path_join("BaseDefense")
	if not DirAccess.dir_exists_absolute(src):
		src = staging  # fall back to flat layout
	if not _write_apply_script(install_dir, src, exe_name):
		update_failed.emit("Couldn't write the update helper.")
		return
	var bat := install_dir.path_join("apply_update.bat")
	OS.create_process("cmd.exe", ["/c", ProjectSettings.globalize_path(bat)])
	get_tree().quit()

func _write_apply_script(install_dir: String, src_dir: String, exe_name: String) -> bool:
	var install := ProjectSettings.globalize_path(install_dir).replace("/", "\\")
	var src := ProjectSettings.globalize_path(src_dir).replace("/", "\\")
	var lines := [
		"@echo off",
		"REM Steel Tide self-updater - waits for the game to close, swaps files, relaunches.",
		"timeout /t 2 /nobreak >nul",
		"robocopy \"%s\" \"%s\" /E /IS /IT /NFL /NDL /NJH /NJS /NC /NS >nul" % [src, install],
		"rmdir /s /q \"%s\\.update\"" % install,
		"start \"\" \"%s\\%s\"" % [install, exe_name],
		# Robust self-delete: (goto) with no label makes cmd release the batch
		# file handle, then del removes it. %~f0 needs a single %.
		"(goto) 2>nul & del \"%~f0\"",
	]
	var bat := install_dir.path_join("apply_update.bat")
	var f := FileAccess.open(bat, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string("\r\n".join(lines) + "\r\n")
	f.close()
	return true

func _rm_rf(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full := path.path_join(name)
		if d.current_is_dir():
			_rm_rf(full)
		else:
			DirAccess.remove_absolute(full)
		name = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(path)
