extends RefCounted

const DIRECTORY := "user://iteration_lab"
const PATH := DIRECTORY+"/cpu-policy.json"
const DEMO_DIRECTORY := DIRECTORY+"/demo-matches"
const SCHEMA := 1
var table := {}
var matches := 0
var shot_history: Array = []
var training := false
var demo_recording := false
var demo_exploring := false
var demo_table := {}
var demo_pending := {}
var demo_matches := 0
var demo_shot_history: Array = []
var decisions: Array[Dictionary] = [{},{}]
var applied: Array[Dictionary] = [{},{}]

func load_profile() -> void:
	var data := read_json(PATH)
	if data.is_empty(): data = read_json(PATH+".bak")
	if int(data.get("schema",0)) != SCHEMA: return
	var saved: Variant = data.get("tactics",{})
	if saved is Dictionary: table = saved
	matches = maxi(0,int(data.get("matches",0)))
	var history: Variant = data.get("shot_history",[])
	if history is Array: shot_history = history

static func read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null: return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary: return {}
	return json.data

func load_demo(team_size: int, spectator: bool) -> void:
	demo_table.clear()
	demo_pending.clear()
	demo_matches = 0
	demo_shot_history.clear()
	var directory := DEMO_DIRECTORY.path_join(str(team_size))
	if not DirAccess.dir_exists_absolute(directory): return
	var files := DirAccess.get_files_at(directory)
	files.sort()
	for file in files:
		if not file.ends_with(".json"): continue
		var data := read_json(directory.path_join(file))
		if int(data.get("schema",0)) != SCHEMA or not data.get("tactics") is Dictionary: continue
		for context in data.tactics:
			var options: Dictionary = demo_table.get_or_add(context,{})
			for option in data.tactics[context]:
				var sample: Array = data.tactics[context][option]
				var total: Array = options.get_or_add(option,[0.0,0.0])
				total[0] += float(sample[0])
				total[1] += float(sample[1])
		if bool(data.get("spectator",false)) == spectator and data.get("shot_history") is Array:
			demo_matches += 1
			demo_shot_history = data.shot_history

func save_demo(team_size: int, spectator: bool, reads: Array) -> Error:
	var file := "%d-%d-%d.json" % [int(Time.get_unix_time_from_system()*1000000),OS.get_process_id(),Time.get_ticks_usec()]
	var path := DEMO_DIRECTORY.path_join(str(team_size)).path_join(file)
	return write_json(path,{"schema":SCHEMA,"spectator":spectator,"tactics":demo_pending,"shot_history":encode_reads(reads)})

func choose(side: int, context: String, options: Array[int], fallback: int) -> int:
	if decisions[side].has(context): return int(decisions[side][context])
	var selected := fallback
	var samples: Dictionary = table.get(context,{})
	var demo_samples: Dictionary = demo_table.get(context,{})
	var best := 0.0
	for option in options:
		var result: Array = samples.get(str(option),[0,0])
		var demo_result: Array = demo_samples.get(str(option),[0,0])
		var count := float(result[0])+float(demo_result[0])
		if count < 12: continue
		var value := (float(result[1])+float(demo_result[1])+6.0)/(count+12.0)-0.50
		if option == fallback: value += 0.035
		if value > best:
			best = value
			selected = option
	var exploration := 0.18 if training else (0.08 if demo_exploring else 0.0)
	if exploration > 0.0 and randf() < exploration:
		selected = options[randi_range(0,options.size()-1)]
	decisions[side][context] = selected
	return selected

func used(side: int, context: String) -> void:
	if (training or demo_recording) and decisions[side].has(context): applied[side][context] = decisions[side][context]

func begin_point() -> void:
	for side in decisions.size():
		decisions[side].clear()
		applied[side].clear()

func finish_point(winner: int) -> void:
	if not training and not demo_recording: return
	var outcomes := table if training else demo_pending
	for side in applied.size():
		for context in applied[side]:
			var options: Dictionary = outcomes.get_or_add(context,{})
			var key := str(applied[side][context])
			var result: Array = options.get_or_add(key,[0.0,0.0])
			if float(result[0]) >= 600.0:
				result[0] = float(result[0])*0.97
				result[1] = float(result[1])*0.97
			result[0] += 1.0
			if side == winner: result[1] += 1.0

func save_match(reads: Array) -> Error:
	matches += 1
	shot_history = encode_reads(reads)
	return write_json(PATH,{"schema":SCHEMA,"matches":matches,"tactics":table,"shot_history":shot_history})

static func encode_reads(reads: Array) -> Array:
	var history := []
	for side in reads:
		var observations := {}
		for zone in side:
			var read: Vector2 = side[zone]
			observations[str(zone)] = [read.x,read.y]
		history.append(observations)
	return history

static func write_json(path: String, data: Dictionary) -> Error:
	var absolute := ProjectSettings.globalize_path(path)
	var directory := absolute.get_base_dir()
	var result := DirAccess.make_dir_recursive_absolute(directory)
	if result != OK: return result
	var temporary := absolute+".tmp"
	var backup := absolute+".bak"
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data,"  "))
	file.flush()
	file.close()
	if FileAccess.file_exists(absolute):
		if FileAccess.file_exists(backup): DirAccess.remove_absolute(backup)
		result = DirAccess.rename_absolute(absolute,backup)
		if result != OK: return result
	result = DirAccess.rename_absolute(temporary,absolute)
	if result != OK and FileAccess.file_exists(backup): DirAccess.rename_absolute(backup,absolute)
	return result
