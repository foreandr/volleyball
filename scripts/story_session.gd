extends Node
const Profile = preload("res://scripts/player_profile.gd")
var save_directory := "user://stories"
var creating_story := false
var draft: Dictionary = {}
var active: Dictionary = {}
var edit_entry: Dictionary = {}
var animation_draft: Dictionary = {}
var animation_return: Dictionary = {}

func begin_new() -> void:
	creating_story = true
	draft = Profile.DEFAULTS.duplicate(true)
	get_tree().change_scene_to_file("res://scenes/create.tscn")

func cancel_creation() -> void:
	creating_story = false
	draft.clear()

func save_new(profile: Dictionary) -> Error:
	var values := Profile.clean(profile)
	if values.name.is_empty(): return ERR_INVALID_DATA
	var directory_error := DirAccess.make_dir_recursive_absolute(save_directory)
	if directory_error != OK: return directory_error
	var id := Crypto.new().generate_random_bytes(12).hex_encode()
	var record := {"version":1,"id":id,"profile":values,"stage":"animations","selected_animations":[]}
	var path := save_directory.path_join(id+".json")
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(record,"\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK: return error
	active = record
	cancel_creation()
	remember(id)
	return OK

func read_record(id: String) -> Dictionary:
	if not id.is_valid_hex_number(false) or id.length() != 24: return {}
	var path := save_directory.path_join(id+".json")
	if not FileAccess.file_exists(path): return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or data.get("version",0) != 1: return {}
	if data.get("id","") != id or not data.get("profile") is Dictionary: return {}
	data.profile = Profile.clean(data.profile)
	return data

func saved_stories() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var directory := DirAccess.open(save_directory)
	if directory == null: return result
	for file in directory.get_files():
		if not file.ends_with(".json"): continue
		var record := read_record(file.get_basename())
		if not record.is_empty(): result.append(record)
	result.sort_custom(func(a,b): return str(a.profile.name).naturalnocasecmp_to(str(b.profile.name)) < 0)
	return result

func remember(id: String) -> void:
	var config := ConfigFile.new()
	config.set_value("story","last_save",id)
	config.save(save_directory.path_join("index.cfg"))

func last_id() -> String:
	var config := ConfigFile.new()
	if config.load(save_directory.path_join("index.cfg")) != OK: return ""
	var id := str(config.get_value("story","last_save",""))
	return id if not read_record(id).is_empty() else ""

func load_story(id: String) -> bool:
	var record := read_record(id)
	if record.is_empty(): return false
	active = record
	cancel_creation()
	remember(id)
	get_tree().change_scene_to_file("res://scenes/story_animations.tscn")
	return true

var edit_animation: Animation
var pass_output_angle := -1.0

var pass_distance := 6.0
var pass_start := Vector2.ZERO

var incoming_speed := 14.0
var incoming_angle := 40.0
var feed_spot := Vector2(0,12.5)

var incoming_spin := "No spin"
var spin_rate := 3.0
var float_strength := 0.6
