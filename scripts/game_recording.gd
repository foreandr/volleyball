extends Node

# Self-contained Motion JPEG capture of the game viewport, including its HUD.
const FOLDER := "user://recordings"
const FPS := 20
const SIZE := Vector2i(960,540)
const SEGMENT := 30.0
const RETENTION := 1800
const NET_ALERT_FOLDER := "user://recordings/net-attack-alerts"
const NET_ALERT_FRAMES := FPS*10
var recent_frames: Array[PackedByteArray]=[]
var next_recent_frame := 0
var alert_jobs: Array[int]=[]
var clip: FileAccess
var index := PackedInt32Array()
var started := 0
var movi := 0
var frame_count_at := 0
var stream_length_at := 0
var next_frame := 0
var last_jpeg := PackedByteArray()
var cleanup_at := 0
var fps_label: Label
var net_alert_label: Label
var net_alert_fade: Tween
var clock_label: Label
var capture_available := true
var next_clock_update := 0

static func local_clock() -> String:
	var tenth:=int(Time.get_unix_time_from_system()*10.)%10
	return "%s.%d"%[Time.get_time_string_from_system(),tenth]

func _ready() -> void:
	if DisplayServer.get_name()=="headless":
		set_process(false)
		return
	process_mode=Node.PROCESS_MODE_ALWAYS
	var overlay := CanvasLayer.new()
	overlay.layer=100
	add_child(overlay)
	clock_label=Label.new()
	var plate_panel := PanelContainer.new()
	overlay.add_child(plate_panel)
	net_alert_label=Label.new()
	overlay.add_child(net_alert_label)
	net_alert_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	net_alert_label.offset_top=105.
	net_alert_label.grow_horizontal=Control.GROW_DIRECTION_BOTH
	net_alert_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	net_alert_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	net_alert_label.add_theme_font_size_override("font_size",24)
	net_alert_label.add_theme_constant_override("outline_size",5)
	net_alert_label.modulate=Color("ffd782")
	net_alert_label.hide()
	var row := HBoxContainer.new()
	plate_panel.add_child(row)
	row.mouse_filter=Control.MOUSE_FILTER_IGNORE
	row.add_child(clock_label)
	fps_label=Label.new()
	row.add_child(fps_label)
	fps_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	fps_label.add_theme_font_size_override("font_size",19)
	plate_panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	plate_panel.position=Vector2(12,10)
	clock_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	clock_label.add_theme_font_size_override("font_size",19)
	var plate := StyleBoxFlat.new()
	plate.bg_color=Color("10191fdb")
	plate.set_corner_radius_all(4)
	plate.content_margin_left=8
	plate.content_margin_right=8
	plate.content_margin_top=2
	plate.content_margin_bottom=2
	plate_panel.add_theme_stylebox_override("panel",plate)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
	prune()

func prune() -> void:
	var now := int(Time.get_unix_time_from_system())
	for filename in DirAccess.get_files_at(FOLDER):
		if filename.begins_with("tryout-capture-") and filename.ends_with(".avi") and FileAccess.get_modified_time(FOLDER+"/"+filename)<now-RETENTION:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(FOLDER+"/"+filename))

func tag(value: String) -> void:
	clip.store_buffer(value.to_ascii_buffer())

func words(values: Array) -> void:
	for value in values: clip.store_32(value)

func patch(offset: int,value: int) -> void:
	var end := clip.get_position()
	clip.seek(offset)
	clip.store_32(value)
	clip.seek(end)

func begin_clip(path := "") -> void:
	var stamp := Time.get_datetime_string_from_system().replace(":","-")
	if path.is_empty(): path=FOLDER+"/tryout-capture-%s-%d-%d.avi"%[stamp,OS.get_process_id(),Time.get_ticks_msec()]
	clip=FileAccess.open(path,FileAccess.WRITE)
	if not clip:
		push_error("Game recording folder is unwritable")
		capture_available=false
		return
	tag("RIFF")
	clip.store_32(0)
	tag("AVI ")
	tag("LIST")
	clip.store_32(192)
	tag("hdrl")
	tag("avih")
	words([56,1000000/FPS,0,0,16])
	frame_count_at=clip.get_position()
	words([0,0,1,0,SIZE.x,SIZE.y,0,0,0,0])
	tag("LIST")
	clip.store_32(116)
	tag("strl")
	tag("strh")
	clip.store_32(56)
	tag("vids")
	tag("MJPG")
	words([0,0,0,1,FPS,0])
	stream_length_at=clip.get_position()
	words([0,0,0xffffffff,0])
	for edge in [0,0,SIZE.x,SIZE.y]: clip.store_16(edge)
	tag("strf")
	words([40,40,SIZE.x,SIZE.y])
	clip.store_16(1)
	clip.store_16(24)
	tag("MJPG")
	words([SIZE.x*SIZE.y*3,0,0,0,0])
	tag("LIST")
	movi=clip.get_position()
	clip.store_32(0)
	tag("movi")
	started=Time.get_ticks_msec()
	next_frame=started

func append_frame(jpeg: PackedByteArray) -> void:
	index.append(clip.get_position()-movi-4)
	index.append(jpeg.size())
	tag("00dc")
	clip.store_32(jpeg.size())
	clip.store_buffer(jpeg)
	if jpeg.size()%2: clip.store_8(0)

func finish() -> void:
	if not clip: return
	patch(movi,clip.get_position()-movi-4)
	tag("idx1")
	clip.store_32(index.size()*8)
	for i in range(0,index.size(),2):
		tag("00dc")
		words([16,index[i],index[i+1]])
	patch(frame_count_at,index.size()/2)
	patch(stream_length_at,index.size()/2)
	patch(4,clip.get_position()-8)
	clip.close()
	clip=null
	index.clear()
	last_jpeg.clear()

# Keep readbacks and JPEG conversions ordered without blocking court simulation.
# Four slots cover the rendering device's buffered frames at the 20 Hz capture rate.
class Capture:
	var timestamp: int
	var worker := -1
	var jpeg := PackedByteArray()
	var unsupported := false

	func read_gpu(texture: RID) -> void:
		var rd := RenderingServer.get_rendering_device()
		var handle := RenderingServer.texture_get_rd_texture(texture)
		if not handle.is_valid():
			fallback.call_deferred()
			return
		var fmt := rd.texture_get_format(handle)
		if fmt.format not in [RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM,RenderingDevice.DATA_FORMAT_R8G8B8A8_SRGB]:
			fallback.call_deferred()
			return
		if rd.texture_get_data_async(handle,0,receive.bind(fmt.width,fmt.height))!=OK:
			fallback.call_deferred()

	func fallback() -> void:
		unsupported=true

	func receive(data:PackedByteArray,width:int,height:int) -> void:
		if data.size()!=width*height*4:
			fallback.call_deferred()
			return
		start.call_deferred(Image.create_from_data(width,height,false,Image.FORMAT_RGBA8,data))

	func start(image:Image) -> void:
		worker=WorkerThreadPool.add_task(encode.bind(image))

	func encode(image:Image) -> void:
		image.resize(SIZE.x,SIZE.y,Image.INTERPOLATE_BILINEAR)
		jpeg=image.save_jpg_to_buffer(.77)

var jobs:Array[Capture]=[]
var fallback_read := false
var next_request := 0

func _process(_dt: float) -> void:
	var now := Time.get_ticks_msec()
	if now>=next_clock_update:
		next_clock_update=now+50
		clock_label.text=local_clock()
		var fps := InteractionTrace.display_fps
		fps_label.text="%d FPS"%fps
		fps_label.modulate=Color("72dc8b") if fps>55 else (Color("ffda61") if fps>=50 else Color("ff6565"))
	if not capture_available: return
	for i in range(alert_jobs.size()-1,-1,-1):
		if WorkerThreadPool.is_task_completed(alert_jobs[i]):
			WorkerThreadPool.wait_for_task_completion(alert_jobs[i])
			alert_jobs.remove_at(i)
	while not jobs.is_empty():
		var job := jobs[0]
		if job.unsupported:
			fallback_read=true
			jobs.pop_front()
			continue
		if job.worker<0 or not WorkerThreadPool.is_task_completed(job.worker): break
		WorkerThreadPool.wait_for_task_completion(job.worker)
		jobs.pop_front()
		if not job.jpeg.is_empty(): store_frame(job.jpeg,job.timestamp)
	if now>=cleanup_at:
		prune()
		cleanup_at=now+30000
	if now<next_request or jobs.size()>=4: return
	if not clip or now-started>=SEGMENT*1000:
		if not jobs.is_empty(): return
		finish()
		begin_clip()
		if not clip: return
	var frame:=Capture.new()
	frame.timestamp=now
	var texture:=get_viewport().get_texture()
	if fallback_read or not RenderingServer.get_rendering_device():
		var image:=texture.get_image()
		if not image or image.is_empty(): return
		frame.start(image)
	else:
		RenderingServer.call_on_render_thread(frame.read_gpu.bind(texture.get_rid()))
	jobs.append(frame)
	next_request=now+1000/FPS

func store_frame(jpeg: PackedByteArray,now:int) -> void:
	while next_frame+1000/FPS<=now and not last_jpeg.is_empty():
		append_live_frame(last_jpeg)
		next_frame+=1000/FPS
	append_live_frame(jpeg)
	last_jpeg=jpeg
	next_frame+=1000/FPS

func append_live_frame(jpeg:PackedByteArray) -> void:
	append_frame(jpeg)
	if recent_frames.size()<NET_ALERT_FRAMES: recent_frames.append(jpeg)
	else: recent_frames[next_recent_frame]=jpeg
	next_recent_frame=(next_recent_frame+1)%NET_ALERT_FRAMES

func show_net_attack_alert(jersey:Variant,reason:String) -> void:
	if not is_instance_valid(net_alert_label): return
	if net_alert_fade: net_alert_fade.kill()
	net_alert_label.text="Net attack alert · #%s · %s"%[jersey,reason]
	net_alert_label.modulate.a=0.
	net_alert_label.show()
	net_alert_fade=create_tween()
	net_alert_fade.tween_property(net_alert_label,"modulate:a",1.,.20)
	net_alert_fade.tween_interval(2.75)
	net_alert_fade.tween_property(net_alert_label,"modulate:a",0.,.65)
	net_alert_fade.tween_callback(net_alert_label.hide)

func save_net_attack_alert(details:Dictionary) -> String:
	if recent_frames.size()<2: return ""
	if DirAccess.make_dir_recursive_absolute(NET_ALERT_FOLDER)!=OK: return ""
	var id:="%d-%d"%[int(Time.get_unix_time_from_system()*1000000),OS.get_process_id()]
	var path:=NET_ALERT_FOLDER.path_join(id+".avi")
	var frames:Array[PackedByteArray]=[]
	for offset in recent_frames.size():
		var source:=(next_recent_frame+offset)%NET_ALERT_FRAMES if recent_frames.size()==NET_ALERT_FRAMES else offset
		frames.append(recent_frames[source])
	alert_jobs.append(WorkerThreadPool.add_task(write_attack_alert.bind(get_script(),path,frames,details.duplicate(true))))
	return path

static func write_attack_alert(writer_script:Script,path:String,frames:Array[PackedByteArray],details:Dictionary) -> void:
	var writer=writer_script.new()
	writer.begin_clip(path+".tmp")
	if writer.clip:
		for jpeg in frames: writer.append_frame(jpeg)
		writer.finish()
		if DirAccess.rename_absolute(path+".tmp",path)==OK:
			details["clip"]=ProjectSettings.globalize_path(path)
			var entry:=FileAccess.open(path.get_basename()+".json",FileAccess.WRITE)
			if entry: entry.store_string(JSON.stringify(details,"\t"))
	writer.free()

func _exit_tree() -> void:
	for alert in alert_jobs:
		WorkerThreadPool.wait_for_task_completion(alert)
	for job in jobs:
		if job.worker>=0:
			WorkerThreadPool.wait_for_task_completion(job.worker)
			if clip and not job.jpeg.is_empty(): store_frame(job.jpeg,job.timestamp)
	finish()
