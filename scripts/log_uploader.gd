class_name LogUploader
extends Node
## Отправка журналов игры (user://logs/*.txt) в ветку `logs` репозитория на GitHub (Contents API).
## Запускается из Blackbox через несколько секунд после старта, работает асинхронно и ничего не блокирует.
## Токен — в res://log_token.cfg (создаёт сборка, в git его нет). Нет токена, сети или ошибка — файлы остаются
## и уходят при следующем запуске. Отправленный файл переименовывается в *.sent (хранится не больше KEEP_SENT).

const DIR := "user://journals"
const TOKEN_CFG := "res://log_token.cfg"
const DEF_REPO := "Ne-collab228/GranitOps"
const DEF_BRANCH := "logs"
const MAX_FILES := 10
const MAX_BYTES := 1000000
const KEEP_SENT := 30
const KEEP_UNSENT := 40

var current_name := ""
var device := "pc"
var status := ""
var _token := ""
var _repo := DEF_REPO
var _branch := DEF_BRANCH
var _api := "https://api.github.com"  # в cfg можно переопределить (api=...) — для проверки на макете
var _http: HTTPRequest


func setup(cur_name: String, dev: String) -> void:
	current_name = cur_name
	device = dev


## Токен и настройки из cfg; false — отправка невозможна.
func _load_cfg() -> bool:
	var cf := ConfigFile.new()
	if cf.load(TOKEN_CFG) != OK:
		return false
	_token = str(cf.get_value("log", "token", "")).strip_edges()
	_repo = str(cf.get_value("log", "repo", DEF_REPO))
	_branch = str(cf.get_value("log", "branch", DEF_BRANCH))
	_api = str(cf.get_value("log", "api", _api))
	return _token != ""


## Неотправленные журналы, кроме текущего (старые первыми).
func pending() -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(DIR):
		if f.ends_with(".txt") and f != current_name:
			out.append(f)
	out.sort()
	return out


func run() -> void:
	_prune()
	if not bool(Settings.data.get("send_logs", true)) or not _load_cfg():
		return
	var files := pending()
	if files.is_empty():
		return
	_http = HTTPRequest.new()
	_http.timeout = 20.0
	add_child(_http)
	_env_proxy()
	var ok: bool = await _ensure_branch()
	if not ok:
		Blackbox.event("журналы: " + status)
		return
	var n := 0
	for f in files:
		if n >= MAX_FILES:
			break
		var sent: bool = await _send_file(f)
		if not sent:
			Blackbox.event("журналы: " + status)
			break
		n += 1
		await get_tree().create_timer(1.0).timeout  # пауза между файлами, чтобы не было рывков
	if n > 0:
		Blackbox.event("журналы отправлены: %d" % n)
	_prune()


## Для проверки на ПК за прокси: стандартные переменные https_proxy и SSL_CERT_FILE (на телефоне их нет).
func _env_proxy() -> void:
	if _api.begins_with("http://"):
		return
	var px := OS.get_environment("https_proxy")
	if px == "":
		px = OS.get_environment("HTTPS_PROXY")
	if px != "":
		var hp := px.get_slice("://", 1) if px.contains("://") else px
		if not hp.contains("@") and hp.contains(":"):
			_http.set_https_proxy(hp.get_slice(":", 0), int(hp.get_slice(":", 1).trim_suffix("/")))
	var ca := OS.get_environment("SSL_CERT_FILE")
	if ca != "" and FileAccess.file_exists(ca):
		var cert := X509Certificate.new()
		if cert.load(ca) == OK:
			_http.set_tls_options(TLSOptions.client(cert))


func _headers() -> PackedStringArray:
	return PackedStringArray(["Authorization: Bearer " + _token, "Accept: application/vnd.github+json",
		"User-Agent: GranitOps", "Content-Type: application/json", "X-GitHub-Api-Version: 2022-11-28"])


## Возвращает [код HTTP, разобранный JSON]; код 0 — нет сети/таймаут.
func _req(method: int, path: String, body: Variant = null) -> Array:
	var data := "" if body == null else JSON.stringify(body)
	var err := _http.request(_api + path, _headers(), method, data)
	if err != OK:
		status = "ошибка запроса %d" % err
		return [0, null]
	var res: Array = await _http.request_completed
	if int(res[0]) != HTTPRequest.RESULT_SUCCESS:
		status = "сеть: ошибка %d" % int(res[0])
		return [0, null]
	var parsed: Variant = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	return [int(res[1]), parsed]


## Ветка logs есть; иначе создаём от основной ветки репозитория.
func _ensure_branch() -> bool:
	var r: Array = await _req(HTTPClient.METHOD_GET, "/repos/%s/git/ref/heads/%s" % [_repo, _branch])
	if int(r[0]) == 200:
		return true
	if int(r[0]) != 404:
		if int(r[0]) != 0:  # при коде 0 статус уже записан в _req («сеть: ошибка»)
			status = "ветка: код %d" % int(r[0])
		return false
	var base := "main"
	var ri: Array = await _req(HTTPClient.METHOD_GET, "/repos/%s" % _repo)
	if int(ri[0]) == 200 and ri[1] is Dictionary:
		base = str((ri[1] as Dictionary).get("default_branch", "main"))
	var rb: Array = await _req(HTTPClient.METHOD_GET, "/repos/%s/git/ref/heads/%s" % [_repo, base])
	if int(rb[0]) != 200 or not (rb[1] is Dictionary):
		if int(rb[0]) != 0:
			status = "основная ветка: код %d" % int(rb[0])
		return false
	var sha := str(((rb[1] as Dictionary).get("object", {}) as Dictionary).get("sha", ""))
	var rc: Array = await _req(HTTPClient.METHOD_POST, "/repos/%s/git/refs" % _repo, {"ref": "refs/heads/" + _branch, "sha": sha})
	if int(rc[0]) == 201 or int(rc[0]) == 422:  # 422 — уже создана параллельно
		return true
	if int(rc[0]) != 0:
		status = "создание ветки: код %d" % int(rc[0])
	return false


func _send_file(fname: String) -> bool:
	var path := DIR.path_join(fname)
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		var fa := FileAccess.open(path, FileAccess.READ)
		if fa != null and fa.get_length() == 0:
			fa.close()
			DirAccess.remove_absolute(path)  # действительно пустой файл
		return true  # не удалось прочитать — пропускаем, файл остаётся
	if bytes.size() > MAX_BYTES:
		bytes = "[... начало журнала обрезано ...]\n".to_utf8_buffer() + bytes.slice(bytes.size() - MAX_BYTES)
	var remote := "logs/%s/%s" % [device, fname]
	var body := {"message": "журнал %s %s" % [device, fname.get_basename()],
		"content": Marshalls.raw_to_base64(bytes), "branch": _branch}
	var r: Array = await _req(HTTPClient.METHOD_PUT, "/repos/%s/contents/%s" % [_repo, remote], body)
	var code := int(r[0])
	# 201 — создан; 422 «sha wasn't supplied» — такой файл уже лежит в ветке (прошлая отправка прервалась)
	var msg := ""
	if r[1] is Dictionary:
		msg = str((r[1] as Dictionary).get("message", "")).to_lower()
	var exists := code == 422 and (msg.contains("sha") or msg.contains("already exists"))
	if code == 201 or code == 200 or exists:
		DirAccess.rename_absolute(path, path.get_basename() + ".sent")
		return true
	if code != 0:
		status = "отправка: код %d %s" % [code, msg.left(80)]
	return false


## Лишнее удаляем: отправленные сверх KEEP_SENT и совсем старые неотправленные сверх KEEP_UNSENT.
func _prune() -> void:
	var sent := PackedStringArray()
	var unsent := PackedStringArray()
	for f in DirAccess.get_files_at(DIR):
		if f.ends_with(".sent"):
			sent.append(f)
		elif f.ends_with(".txt") and f != current_name:
			unsent.append(f)
	sent.sort()
	unsent.sort()
	while sent.size() > KEEP_SENT:
		DirAccess.remove_absolute(DIR.path_join(sent[0]))
		sent.remove_at(0)
	while unsent.size() > KEEP_UNSENT:
		DirAccess.remove_absolute(DIR.path_join(unsent[0]))
		unsent.remove_at(0)
