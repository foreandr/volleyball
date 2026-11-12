extends RefCounted

const DIRECTORY := "user://iteration_lab"
const PATH := DIRECTORY+"/cpu-policy.json"
const SCHEMA := 1
var table := {}
var matches := 0
var shot_history: Array = []
var training := false
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
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	return data if data is Dictionary else {}

func choose(side: int, context: String, options: Array[int], fallback: int) -> int:
	if decisions[side].has(context): return int(decisions[side][context])
	var selected := fallback
	var samples: Dictionary = table.get(context,{})
	var best := 0.0
	for option in options:
		var result: Array = samples.get(str(option),[0,0])
		var count := float(result[0])
		if count < 12: continue
		var value := (float(result[1])+6.0)/(count+12.0)-0.50
		if option == fallback: value += 0.035
		if value > best:
			best = value
			selected = option
	if training and randf() < 0.18:
		selected = options[randi_range(0,options.size()-1)]
	decisions[side][context] = selected
	return selected

func used(side: int, context: String) -> void:
	if training and decisions[side].has(context): applied[side][context] = decisions[side][context]

func begin_point() -> void:
	for side in decisions.size():
		decisions[side].clear()
		applied[side].clear()

func finish_point(winner: int) -> void:
	if not training: return
	for side in applied.size():
		for context in applied[side]:
			var options: Dictionary = table.get_or_add(context,{})
			var key := str(applied[side][context])
			var result: Array = options.get_or_add(key,[0.0,0.0])
			if float(result[0]) >= 600.0:
				result[0] = float(result[0])*0.97
				result[1] = float(result[1])*0.97
			result[0] += 1.0
			if side == winner: result[1] += 1.0

func save_match(reads: Array) -> Error:
	matches += 1
	shot_history.clear()
	for side in reads:
		var observations := {}
		for zone in side:
			var read: Vector2 = side[zone]
			observations[str(zone)] = [read.x,read.y]
		shot_history.append(observations)
	return write_json(PATH,{"schema":SCHEMA,"matches":matches,"tactics":table,"shot_history":shot_history})

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
