extends Node
const Profile = preload("res://scripts/player_profile.gd")
var save_directory := "user://stories"
var creating_story := false
var draft: Dictionary = {}
var active: Dictionary = {}
var edit_entry: Dictionary = {}
var animation_draft: Dictionary = {}
var animation_return: Dictionary = {}
var attack_swing_tuning: Dictionary = {}
var match_preferences := ConfigFile.new()
const MATCH_SETTINGS_PATH := "user://match_settings.cfg"
var attack_ball_audio_muted := false
var forearm_reception_skill := 100.0
var hand_reception_skill := 100.0
var setting_skill := 100.0

func begin_new() -> void:
	creating_story = true
	draft = Profile.DEFAULTS.duplicate(true)
	MenuPresentation.load_scene("res://scenes/create.tscn")

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
	MenuPresentation.load_scene("res://scenes/story_animations.tscn")
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
var lab_replay_path := ""
var open_home_simulation := false
var offline_size := 2
var offline_away_size := 2
var offline_controller := 0 # -1 watches, 0 controls home, 1 controls away.
var offline_roster: Array[Dictionary] = []
var kit_colors := [Color("287fda"),Color("d9874e")]
var pad_bindings := [JOY_BUTTON_A,JOY_BUTTON_X,JOY_BUTTON_Y,JOY_BUTTON_B]
var game_options := ConfigFile.new()
const OPTIONS := "user://game_options.cfg"

var master_volume := 20.
var master_gain := AudioEffectAmplify.new()

func set_master_volume(value: float) -> void:
	master_volume=clampf(value,0.,100.)
	# Below 20 attenuate after limiting, preserving the old low-volume response.
	AudioServer.set_bus_volume_db(0,linear_to_db(minf(master_volume/20.,1.)))
	master_gain.volume_db=6.+linear_to_db(maxf(1.,master_volume/20.))

func save_options() -> void:
	game_options.set_value("match","buttons",pad_bindings)
	game_options.set_value("audio","master_percent",master_volume)
	game_options.save(OPTIONS)

var open_home_play := false
var play_launch_consumed := false
var open_passing_drill := false
var frame_editor_origin := ""
var return_to_drill := ""
var drill_menu_category := ""
var demo_launch_consumed := false
var iteration_run := preload("res://scripts/iteration_run.gd").new()
const PREVIEW_FIELDS := ["pass_start","pass_distance","pass_output_angle","incoming_speed","incoming_angle","feed_spot","incoming_spin","spin_rate","float_strength","source_height","feed_fit","receive_direction","receive_distance_tier","ball_tab","pass_destination","pass_apex","destination_fit","preview_camera"]

const IMPACT_BUS := "Ball impacts"

func _ready() -> void:
	master_gain.volume_db=6.
	AudioServer.add_bus_effect(0,master_gain)
	AudioServer.add_bus_effect(0,AudioEffectHardLimiter.new())
	AudioServer.add_bus()
	var impact_bus := AudioServer.bus_count-1
	AudioServer.set_bus_name(impact_bus,IMPACT_BUS)
	var boost := AudioEffectAmplify.new()
	boost.volume_db=20.
	AudioServer.add_bus_effect(impact_bus,boost)
	AudioServer.add_bus_effect(impact_bus,AudioEffectHardLimiter.new())
	if game_options.load(OPTIONS) == OK:
		pad_bindings = game_options.get_value("match","buttons",pad_bindings)
		var previous := db_to_linear(float(game_options.get_value("audio","volume_db",0.0)))*20.
		set_master_volume(game_options.get_value("audio","master_percent",previous))
	if DisplayServer.get_name() != "headless":
		Engine.max_fps = 60
		apply_video_options()
	match_preferences.load(MATCH_SETTINGS_PATH)
	var device: String=game_options.get_value("audio","device","Default")
	if device in AudioServer.get_output_device_list(): AudioServer.output_device=device
	AudioServer.set_bus_mute(0,game_options.get_value("audio","muted",false))
	var config := ConfigFile.new()
	if config.load(preview_path)==OK:
		for field in PREVIEW_FIELDS:
			if config.has_section_key("preview",field): set(field,config.get_value("preview",field))

func apply_video_options() -> void:
	if game_options.has_section_key("video","fullscreen"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if game_options.get_value("video","fullscreen") else DisplayServer.WINDOW_MODE_MAXIMIZED)
	if game_options.has_section_key("video","vsync"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if game_options.get_value("video","vsync") else DisplayServer.VSYNC_DISABLED)

func ensure_background_training() -> void:
	if DisplayServer.get_name() != "headless" and not iteration_run.status().running:
		iteration_run.start(0)

func match_preference(key: String, fallback: Variant) -> Variant:
	return match_preferences.get_value("match",key,fallback)

func save_match_preference(key: String, value: Variant) -> void:
	if match_preferences.has_section_key("match",key) and match_preferences.get_value("match",key) == value: return
	match_preferences.set_value("match",key,value)
	match_preferences.save(MATCH_SETTINGS_PATH)

func load_drill_setup(drill: String) -> Dictionary:
	var setup: Variant = match_preference(drill+"_setup",{})
	return setup.duplicate(true) if setup is Dictionary else {}

func save_drill_setup(drill: String, setup: Dictionary) -> void:
	save_match_preference(drill+"_setup",setup.duplicate(true))

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
	if event.physical_keycode != KEY_M or not event.ctrl_pressed or event.shift_pressed or event.alt_pressed or event.meta_pressed: return
	var page := get_tree().current_scene
	if page and page.has_method("toggle_match_replay") and is_instance_valid(page.get("demo_match")): return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return
	set_game_muted(not AudioServer.is_bus_mute(0))
	get_viewport().set_input_as_handled()

func set_game_muted(muted: bool) -> void:
	AudioServer.set_bus_mute(0,muted)
	game_options.set_value("audio","muted",muted)
	save_options()

func prepare_ready_frame_editor() -> void:
	edit_entry={"id":"shared_ready","name":"Ready stance","category":"Setting","type":"Overhead"}
	edit_animation=preload("res://assets/animations/goalkeeper_idle.tres")
	animation_draft.clear()

func add_saved_frame_picker(parent: Container, before_open: Callable) -> void:
	var library := preload("res://scripts/volleyball_animations.gd")
	var choices := library.custom_entries()
	if choices.is_empty(): return
	var picker := OptionButton.new()
	picker.add_item("Open saved animation...")
	for saved in choices: picker.add_item(saved.name)
	parent.add_child(picker)
	picker.item_selected.connect(func(index: int):
		if index<1: return
		var saved := choices[index-1]
		var clip := load(saved.path) as Animation
		if not clip: return
		edit_entry=saved
		edit_animation=clip
		animation_draft.clear()
		before_open.call()
		MenuPresentation.load_scene("res://scenes/animation_editor.tscn"))
