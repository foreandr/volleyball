extends RefCounted

const Policy = preload("res://scripts/cpu_policy.gd")

var pid := -1
var run_path := ""

func status() -> Dictionary:
	var data := Policy.read_json(Policy.DIRECTORY+"/status.json")
	var worker := int(data.get("pid",0))
	if pid > 0 and OS.is_process_running(pid) and worker != pid:
		data = {"state":"starting","pid":pid,"run":run_path}
		worker = pid
	var state := str(data.get("state","ready"))
	var running := state in ["running","starting"] and worker > 0 and OS.is_process_running(worker)
	if running and FileAccess.file_exists(str(data.run)+"/stop"):
		state = "stopping"
	elif not running and state in ["running","starting"]:
		state = "stopped"
	data["state"] = state
	data["running"] = running
	return data

func start(minutes: int) -> bool:
	if status().running: return false
	var id := "%d-%d-%d" % [int(Time.get_unix_time_from_system()),OS.get_process_id(),Time.get_ticks_msec()]
	run_path = Policy.DIRECTORY+"/runs/"+id
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
