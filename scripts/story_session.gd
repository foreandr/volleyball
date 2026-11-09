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
var pass_output_angle := 74.67337813955865

var pass_distance := 5.0
var pass_start := Vector2(0.05625502,-3.4254649)

var incoming_speed := 18.6
var incoming_angle := 22.49393445518888
var feed_spot := Vector2(1.5444031,14.2)

var incoming_spin := "No spin"
var spin_rate := 6.8
var float_strength := 0.6

var source_height := 3.3
var feed_fit := "angle"

var receive_direction := 0
var receive_distance_tier := 1
var dive_kick_ms := -70
var dive_lower_ms := 180
var ball_tab := 0
var pass_destination := Vector2(0.026413498,1.5744464)
var pass_apex := 4.9
var destination_fit := "height"

var reception_body := "Balanced"
var reception_hands := "From platform"
var preview_camera := {
	"distance": 15.011005634576883,
	"focus": Vector3(-4.4370165,1,1.1591442),
	"pitch": 0.4883845413923259,
	"yaw": 4.626478332834786,
}
var preview_hash := 0
var preview_path := "user://preview_setup.cfg"
const PREVIEW_FIELDS := ["pass_start","pass_distance","pass_output_angle","incoming_speed","incoming_angle","feed_spot","incoming_spin","spin_rate","float_strength","source_height","feed_fit","receive_direction","receive_distance_tier","dive_kick_ms","dive_lower_ms","ball_tab","pass_destination","pass_apex","destination_fit","preview_camera"]

func _ready() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"),true)
	var config := ConfigFile.new()
	if config.load(preview_path)==OK:
		for field in PREVIEW_FIELDS:
			if config.has_section_key("preview",field): set(field,config.get_value("preview",field))

func save_preview_setup() -> void:
	var values := {}
	for field in PREVIEW_FIELDS: values[field] = get(field)
	var signature := hash(values)
	if signature==preview_hash: return
	var config := ConfigFile.new()
	for field in values: config.set_value("preview",field,values[field])
	if config.save(preview_path)==OK: preview_hash = signature

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.physical_keycode != KEY_M or event.ctrl_pressed or event.alt_pressed or event.meta_pressed: return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return
	var master := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(master,not AudioServer.is_bus_mute(master))
	get_viewport().set_input_as_handled()
