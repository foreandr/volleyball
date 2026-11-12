extends RefCounted

const Policy = preload("res://scripts/cpu_policy.gd")
const SPEED_PATH := Policy.DIRECTORY+"/speed.json"

var pid := -1
var run_path := ""
var started_at := -1
var lab_auto_started := false

static func faster_training() -> bool:
	return bool(Policy.read_json(SPEED_PATH).get("faster",false))

static func training_rest(batch_ms: int, faster: bool) -> float:
	if faster: return clampf(float(batch_ms)*0.00020,0.004,0.06)
	return clampf(float(batch_ms)*0.00055,0.008,0.10)

func speed_picker() -> OptionButton:
	var picker := OptionButton.new()
	picker.name = "TrainingSpeed"
	picker.add_item("Balanced")
	picker.add_item("Faster")
	picker.select(1 if faster_training() else 0)
	picker.item_selected.connect(func(index: int):
		if Policy.write_json(SPEED_PATH,{"faster":index == 1}) != OK:
			picker.select(1 if faster_training() else 0))
	return picker

static func worker_port() -> int:
	var profile := ProjectSettings.globalize_path(Policy.DIRECTORY).replace("\\","/").to_lower()
	return 36000+posmod(profile.hash(),10000)

func status() -> Dictionary:
	var data := Policy.read_json(Policy.DIRECTORY+"/status.json")
	if data.is_empty(): data = Policy.read_json(Policy.DIRECTORY+"/status.json.bak")
	var worker := int(data.get("pid",0))
	var state := str(data.get("state","ready"))
	var heartbeat := float(data.get("heartbeat",0.0))
	var recent := heartbeat > 0.0 and absf(Time.get_unix_time_from_system()-heartbeat) < 15.0
	var running := state == "running" and worker > 0 and (recent or OS.is_process_running(worker))
	if not running and pid > 0 and worker != pid and Time.get_ticks_msec()-started_at < 15000 and OS.is_process_running(pid):
		data = {"state":"starting","pid":pid,"run":run_path}
		worker = pid
		state = "starting"
		running = true
	if running and FileAccess.file_exists(str(data.run)+"/stop"):
		state = "stopping"
	elif not running and state in ["running","starting"]:
		state = "stopped"
	data["state"] = state
	data["running"] = running
	if not data.has("saved_matches"):
		data["saved_matches"] = int(Policy.read_json(Policy.PATH).get("matches",0))
	return data

func start(minutes: int) -> bool:
	if status().running: return false
	var id := "%d-%d-%d" % [int(Time.get_unix_time_from_system()),OS.get_process_id(),Time.get_ticks_msec()]
	run_path = Policy.DIRECTORY+"/runs/"+id
	started_at = Time.get_ticks_msec()
	pid = OS.create_process(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),
		"--script","res://tools/iteration_worker.gd","--",id,str(minutes)])
	return pid > 0

func stop() -> bool:
	var data := status()
	if not data.running: return false
	var directory := str(data.get("run",""))
	if directory.is_empty(): return false
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) != OK: return false
	var file := FileAccess.open(directory+"/stop",FileAccess.WRITE)
	if file == null: return false
	file.close()
	return true
