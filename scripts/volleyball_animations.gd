extends RefCounted
const Recipes = preload("res://scripts/pass_recipe_library.gd")
static var ENTRIES: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/animations/catalog.json"))

static var custom_directory := "user://animations/custom"
static var custom_cache: Array[Dictionary] = []
static var cache_ready := false

static func custom_entries() -> Array[Dictionary]:
	if cache_ready: return custom_cache
	custom_cache.clear()
	var path := custom_directory.path_join("catalog.json")
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Array:
			for entry in parsed:
				if entry is Dictionary and entry.has_all(["id","name","category","type","path"]) and FileAccess.file_exists(entry.path): custom_cache.append(entry)
	cache_ready = true
	return custom_cache

static func save_copy(clip: Animation, original: Dictionary, title: String) -> Dictionary:
	if title.strip_edges().is_empty(): return {}
	if DirAccess.make_dir_recursive_absolute(custom_directory) != OK: return {}
	var existing := custom_entries().duplicate(true)
	var id := "custom_"+Crypto.new().generate_random_bytes(12).hex_encode()
	var path := custom_directory.path_join(id+".tres")
	var copy := clip.duplicate(true) as Animation
	copy.resource_name = title.strip_edges()
	if ResourceSaver.save(copy,path) != OK: return {}
	var entry := {"id":id,"name":copy.resource_name,"category":original.category,"type":original.type,"path":path,"source":original.id}
	existing.append(entry)
	var temporary := custom_directory.path_join("catalog.tmp")
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if file == null: return {}
	file.store_string(JSON.stringify(existing,"\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK: return {}
	if DirAccess.rename_absolute(temporary,custom_directory.path_join("catalog.json")) != OK: return {}
	custom_cache = existing
	cache_ready = true
	return entry

static func category_name(value: String) -> String:
	if value == "Spiking": return "Attacking"
	return "Forearm reception" if value in ["Passing","Digging","Reception","Forearm reception"] else value

static func type_name(category: String, value: String) -> String:
	return "Forearm" if category_name(category)=="Forearm reception" else value

static func entries(category: String, move_type: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	Recipes.refresh()
	var available: Array = ENTRIES.duplicate(true)
	for id in Recipes.records:
		var recipe := Recipes.resolve(id)
		if recipe.is_empty(): continue
		var found := false
		for entry in available:
			if entry.id==id:
				entry.recipe = id
				entry.name = recipe.name
				found = true
		if not found: available.append({"id":id,"name":recipe.name,"category":"Forearm reception","type":"Forearm","recipe":id,"path":Recipes.records[id].file})
	for entry in available+custom_entries():
		if category_name(entry.category)==category_name(category) and type_name(entry.category,entry.type)==type_name(category,move_type):
			var copy: Dictionary = entry.duplicate(true)
			copy.category = category_name(entry.category)
			copy.type = type_name(entry.category,entry.type)
			if str(copy.id).begins_with("straight_pass_"): copy.name = str(copy.name).replace("Straight Pass","Platform")
			result.append(copy)
	return result

static func load_clip(entry: Dictionary, actor: Node3D) -> Animation:
	if entry.has("recipe"):
		var animation := Recipes.clip(actor,str(entry.recipe))
		if animation!=null: return animation
	return load(entry.path) if not str(entry.path).ends_with(".json") else null
