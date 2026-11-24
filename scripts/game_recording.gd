extends Node

# Self-contained Motion JPEG capture of the game viewport, including its HUD.
const FOLDER := "user://recordings"
const FPS := 20
const SIZE := Vector2i(960,540)
const SEGMENT := 30.0
const RETENTION := 1800
var clip: FileAccess
var index := PackedInt32Array()
var started := 0
var movi := 0
var frame_count_at := 0
var stream_length_at := 0
var next_frame := 0
var last_jpeg := PackedByteArray()
var cleanup_at := 0

func _ready() -> void:
	if DisplayServer.get_name()=="headless" or OS.get_cmdline_args().has("-s") or OS.get_cmdline_args().has("--script"):
		set_process(false)
		return
	process_mode=Node.PROCESS_MODE_ALWAYS
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

func begin_clip() -> void:
	var stamp := Time.get_datetime_string_from_system().replace(":","-")
	clip=FileAccess.open(FOLDER+"/tryout-capture-%s-%d-%d.avi"%[stamp,OS.get_process_id(),Time.get_ticks_msec()],FileAccess.WRITE)
	if not clip:
		push_error("Game recording folder is unwritable")
		set_process(false)
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

func _process(_dt: float) -> void:
	var now := Time.get_ticks_msec()
	if now<next_frame: return
	if now>=cleanup_at:
		prune()
		cleanup_at=now+30000
	if clip and now-started>=SEGMENT*1000: finish()
	if not clip:
		begin_clip()
		if not clip: return
	var frame := get_viewport().get_texture().get_image()
	if not frame or frame.is_empty(): return
	frame.resize(SIZE.x,SIZE.y,Image.INTERPOLATE_BILINEAR)
	var jpeg := frame.save_jpg_to_buffer(.77)
	while next_frame+1000/FPS<=now and not last_jpeg.is_empty():
		append_frame(last_jpeg)
		next_frame+=1000/FPS
	append_frame(jpeg)
	last_jpeg=jpeg
	next_frame+=1000/FPS

func _exit_tree() -> void:
	finish()
