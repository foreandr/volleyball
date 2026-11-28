extends Node

signal changed
signal import_finished(message: String)

const TITLES := {"spike":"Spike", "block":"Stuff block", "serve":"Jump spin serve", "dig":"Forearm dig","career_stuff":"Career - left-hand stuff","career_touch":"Career - right-hand touch"}
const DIRECTORY := "user://menu_highlights"
var entries := {}
var rotation: Array = []
var player: VideoStreamPlayer
var running := false
var current := ""
var import_job := -1
var result := {}

func configure(screen: VideoStreamPlayer) -> void:
	player = screen
	for id in TITLES:
		entries[id] = {"title":TITLES[id], "file":"res://assets/menu/highlights/%s.ogv" % id}
	var custom = StorySession.game_options.get_value("highlights","library",{})
	if custom is Dictionary:
		for id in custom:
			if custom[id] is Dictionary and FileAccess.file_exists(custom[id].get("file","")):
				entries[id] = custom[id]
	for id in StorySession.game_options.get_value("highlights","rotation",TITLES.keys()):
		if entries.has(id) and not rotation.has(id): rotation.append(id)
	player.finished.connect(next_clip)
	set_process(false)

func save() -> void:
	var custom := {}
	for id in entries:
		if not TITLES.has(id): custom[id] = entries[id]
	StorySession.game_options.set_value("highlights","library",custom)
	StorySession.game_options.set_value("highlights","rotation",rotation)
	StorySession.save_options()
	changed.emit()

func activate(enabled: bool) -> void:
	running = enabled
	if enabled: next_clip()
	else: stop()

func stop() -> void:
	player.stop()
	player.hide()
	current = ""

func next_clip() -> void:
	if not running or rotation.is_empty():
		stop()
		return
	play_clip(rotation[(rotation.find(current)+1) % rotation.size()])

func play_clip(id: String) -> void:
	if not running or not entries.has(id): return
	var stream := VideoStreamTheora.new()
	stream.file = entries[id].file
	player.stream = stream
	current = id
	player.show()
	player.play()

func include_clip(id: String, enabled: bool) -> void:
	if enabled and not rotation.has(id): rotation.append(id)
	elif not enabled: rotation.erase(id)
	if running and (current.is_empty() or (not enabled and current == id)): next_clip()
	save()

func remove_custom(id: String) -> void:
	if TITLES.has(id) or not entries.has(id): return
	var managed := DIRECTORY.path_join(id+".ogv")
	var path:String=entries[id].file
	entries.erase(id)
	include_clip(id,false)
	if path==managed and id.length()==64 and id.is_valid_hex_number(false):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(managed))
		var poster := managed.get_basename()+".jpg"
		if FileAccess.file_exists(poster): DirAccess.remove_absolute(ProjectSettings.globalize_path(poster))

func converter() -> String:
	var exe := "ffmpeg.exe" if OS.get_name()=="Windows" else "ffmpeg"
	var local := ProjectSettings.globalize_path("user://tools").path_join(exe)
	if FileAccess.file_exists(local): return local
	for directory in OS.get_environment("PATH").split(";" if OS.get_name()=="Windows" else ":",false):
		var path := directory.path_join(exe)
		if FileAccess.file_exists(path): return path
	return ""

func import_clip(path: String) -> void:
	if import_job >= 0: return
	var tool := converter()
	if path.get_extension().to_lower() != "ogv" and tool.is_empty():
		import_finished.emit("Choose an Ogg Theora (.ogv) clip, or install FFmpeg to import other videos.")
		return
	import_job = WorkerThreadPool.add_task(convert_clip.bind(path,tool))
	set_process(true)

func convert_clip(path: String, tool: String) -> void:
	result = {"error":"Could not read this video."}
	var hash_id := FileAccess.get_sha256(path)
	if hash_id.is_empty(): return
	if DirAccess.make_dir_recursive_absolute(DIRECTORY)!=OK: return
	var target := DIRECTORY.path_join(hash_id+".ogv")
	if not FileAccess.file_exists(target):
		var temp := ProjectSettings.globalize_path(DIRECTORY.path_join(hash_id+"-import.ogv"))
		var err: int
		if path.get_extension().to_lower()=="ogv":
			var source := FileAccess.open(path,FileAccess.READ)
			if not source or source.get_length()<64: return
			if source.get_buffer(4096).hex_encode().find("807468656f7261")<0: return
			source.close()
			err = DirAccess.copy_absolute(path,temp)
		else:
			err = OS.execute(tool,["-v","error","-y","-i",path,"-map","0:v:0","-an","-vf","scale=1280:720:force_original_aspect_ratio=decrease:force_divisible_by=2,fps=30","-pix_fmt","yuv420p","-c:v","libtheora","-q:v","7",temp])
		if err != 0 or DirAccess.rename_absolute(temp,ProjectSettings.globalize_path(target)) != OK:
			if FileAccess.file_exists(temp): DirAccess.remove_absolute(temp)
			return
	var poster := DIRECTORY.path_join(hash_id+".jpg")
	if not tool.is_empty() and not FileAccess.file_exists(poster):
		OS.execute(tool,["-v","error","-y","-i",ProjectSettings.globalize_path(target),"-frames:v","1","-vf","scale=320:180:force_original_aspect_ratio=decrease",ProjectSettings.globalize_path(poster)])
	result = {"id":hash_id,"title":path.get_file().get_basename(),"file":target,"poster":poster if FileAccess.file_exists(poster) else ""}

func _process(_delta: float) -> void:
	if not WorkerThreadPool.is_task_completed(import_job): return
	WorkerThreadPool.wait_for_task_completion(import_job)
	import_job = -1
	set_process(false)
	if result.has("error"):
		import_finished.emit(result.error)
		return
	entries[result.id] = {"title":result.title,"file":result.file,"poster":result.poster}
	include_clip(result.id,true)
	import_finished.emit("Added "+str(result.title))

func _exit_tree() -> void:
	if import_job >= 0: WorkerThreadPool.wait_for_task_completion(import_job)
