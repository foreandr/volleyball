extends Node

var file: FileAccess
var axes := {}
var sequence := 0

func _ready() -> void:
	var dir := "user://interaction_logs"
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("session_%s_%d.jsonl" % [Time.get_datetime_string_from_system().replace(":","-"),OS.get_process_id()])
	file = FileAccess.open(path,FileAccess.WRITE)
	record("session",{"controllers":Input.get_connected_joypads(),"build":Engine.get_version_info().string})
	get_tree().root.window_input.connect(raw)
	get_tree().node_added.connect(watch)
	get_tree().scene_changed.connect(func(): record("scene",{}))
	Input.joy_connection_changed.connect(func(id,connected): record("controller",{"device":id,"connected":connected}))

func watch(node: Node) -> void:
	if node is Window: node.window_input.connect(raw)
	if node is BaseButton:
		var path := str(node.get_path())
		node.pressed.connect(func(): record("ui_press",{"control":path}))

func raw(e: InputEvent) -> void:
	if e is InputEventJoypadButton:
		record("button",{"device":e.device,"id":e.button_index,"control":e.as_text(),"down":e.pressed})
	elif e is InputEventJoypadMotion:
		var key := "%d/%d" % [e.device,e.axis]
		var level := roundi(e.axis_value*8)
		if axes.get(key,0)!=level:
			axes[key]=level
			record("axis",{"device":e.device,"id":e.axis,"value":e.axis_value})
	elif e is InputEventMouseButton:
		record("mouse",{"button":e.button_index,"down":e.pressed,"position":str(e.position)})
	elif e is InputEventKey and not e.echo:
		var focus := get_viewport().gui_get_focus_owner()
		if not (focus is LineEdit or focus is TextEdit or get_tree().paused):
			record("key",{"code":e.physical_keycode,"down":e.pressed})

func record(kind: String, fields: Dictionary) -> void:
	if not file: return
	sequence += 1
	var scene := get_tree().current_scene
	var row := {"seq":sequence,"ms":Time.get_ticks_msec(),"kind":kind,"scene":scene.scene_file_path if scene else ""}
	row.merge(fields)
	file.store_line(JSON.stringify(row))
	file.flush()
