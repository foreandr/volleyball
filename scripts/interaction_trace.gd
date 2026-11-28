extends Node

var file: FileAccess
var axes := {}
var sequence := 0

const FPS_WINDOW_US := 250000
var display_fps := 60
var previous_frame_us := 0
var window_us := 0
var frames := 0
var worst_us := 0
var last_band := 0
var last_report_us := 0

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var elapsed := now-previous_frame_us
	previous_frame_us=now
	if elapsed<=0: return
	frames+=1
	window_us+=elapsed
	worst_us=maxi(worst_us,elapsed)
	if window_us<FPS_WINDOW_US: return
	display_fps=roundi(1000000.*frames/window_us)
	var band := 2 if display_fps<50 else (1 if display_fps<=55 else 0)
	if (band!=last_band or (band>0 and now-last_report_us>=1000000)):
		var scene := get_tree().current_scene
		var fields := {"fps":display_fps,"worst_frame_ms":worst_us/1000.,
			"time":Time.get_time_string_from_system(),"focused":get_window().has_focus(),
			"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}
		var viewport := get_viewport().get_viewport_rid()
		fields["render_gpu_ms"]=RenderingServer.viewport_get_measured_render_time_gpu(viewport)
		fields["render_cpu_ms"]=RenderingServer.viewport_get_measured_render_time_cpu(viewport)
		fields["physics_ms"]=Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.
		if scene and "phase" in scene: fields["phase"]=scene.get("phase")
		record(["fps_recovered","fps_warning","fps_critical"][band],fields)
		last_report_us=now
	last_band=band
	frames=0
	window_us=0
	worst_us=0

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	set_process(DisplayServer.get_name()!="headless")
	if is_processing(): RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
	previous_frame_us=Time.get_ticks_usec()
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
