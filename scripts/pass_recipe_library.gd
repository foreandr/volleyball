extends RefCounted
## Source recipes are the authoring format. Baked clips remain the save format.
const DIRECTORY := "res://assets/animation_recipes"
const PHASES := ["ready","prepare","approach","contact","follow","recover","end"]
static var records := {}
static var contents := {}
static var clips := {}
static var revision := 0

static func refresh() -> bool:
	var changed := false
	for file in DirAccess.get_files_at(DIRECTORY):
		if not file.ends_with(".json") or file=="reception_bodies.json": continue
		var path := DIRECTORY.path_join(file)
		var text := FileAccess.get_file_as_string(path)
		if contents.get(path,"")==text: continue
		var parser := JSON.new()
		if parser.parse(text)!=OK: continue # Keep the last working version during a save.
		var values: Array = parser.data if parser.data is Array else [parser.data]
		var valid := true
		for value in values:
			if not value is Dictionary or not value.has_all(["id","name"]) or not (value.has("phases") or value.has("extends")):
				valid = false
		if not valid: continue
		for id in records.keys():
			if records[id].file==path: records.erase(id)
		for value in values: records[value.id] = {"data":value,"file":path}
		contents[path] = text
		changed = true
	for path in contents.keys():
		if not FileAccess.file_exists(path):
			contents.erase(path)
			for id in records.keys():
				if records[id].file==path: records.erase(id)
			changed = true
	if changed:
		revision += 1
		clips.clear()
	return changed

static func resolve(id: String, parents: Array = []) -> Dictionary:
	if not records.has(id) or parents.has(id): return {}
	var data: Dictionary = records[id].data
	var result: Dictionary = {}
	if data.has("extends"):
		result = resolve(str(data.extends),parents+[id])
		if result.is_empty(): return {}
	result = result.duplicate(true)
	for key in data:
		if not key in ["extends","defaults","poses"]:
			result[key] = data[key].duplicate(true) if data[key] is Array or data[key] is Dictionary else data[key]
	if not result.has_all(["duration","contact_time","phases"]): return {}
	if not result.phases is Array or result.phases.size()<2: return {}
	for index in result.phases.size():
		var phase: Dictionary = result.phases[index]
		phase.merge(data.get("defaults",{}),true)
		var name_: String = PHASES[index] if index<PHASES.size() else str(index)
		phase.merge(data.get("poses",{}).get(name_,{}),true)
		if not phase.has_all(["time","hips","torso_lean","platform","grip","wrist_l","wrist_r","elbow_l","elbow_r","curl_l","curl_r","head_pitch","wrist_flex","palm_l","palm_r"]): return {}
		if index>0 and float(phase.time)<=float(result.phases[index-1].time): return {}
	return result

static func signature(id: String) -> int:
	return hash(resolve(id))

static func clip(actor: Node3D, id: String) -> Animation:
	var recipe := resolve(id)
	if recipe.is_empty(): return null
	var key := str(hash(recipe))
	if clips.has(key): return clips[key]
	var start := Time.get_ticks_usec()
	var author := preload("res://tools/animation_author.gd").new(actor.skeleton,load("res://assets/animations/goalkeeper_idle.tres"))
	var animation: Animation = author.bake(recipe)
	animation.set_meta("recipe_id",id)
	clips[key] = animation
	print("Recipe ",id," ready in ",(Time.get_ticks_usec()-start)/1000," ms")
	return animation
