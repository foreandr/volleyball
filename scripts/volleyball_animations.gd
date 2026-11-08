extends RefCounted
const ENTRIES := [{"id":"straight_pass_01","name":"Straight Pass 1","category":"Passing","type":"Straight","path":"res://assets/animations/straight_pass_01.tres"}]

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

static func entries(category: String, move_type: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in ENTRIES+custom_entries():
		if entry.category == category and entry.type == move_type: result.append(entry)
	return result
