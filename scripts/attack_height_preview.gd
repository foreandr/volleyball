extends Control

var camera: Camera3D
var points := PackedVector3Array()
var notice := Label.new()
var fade: Tween

func _ready() -> void:
	mouse_filter=MOUSE_FILTER_IGNORE
	add_child(notice)
	notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	notice.position.y=86
	notice.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	notice.grow_horizontal=Control.GROW_DIRECTION_BOTH
	notice.add_theme_constant_override("outline_size",5)

func show_arc(view:Camera3D,start:Vector3,end:Vector3,seconds:float,index:int) -> void:
	camera=view
	points.clear()
	for i in 41:
		var t:=i/40.
		points.append(start.lerp(end,t)+Vector3.UP*4.905*seconds*seconds*t*(1.-t))
	notice.text="Set height %d   ·   %.2f s"%[index,seconds]
	if fade: fade.kill()
	modulate.a=1.
	show()
	fade=create_tween()
	fade.tween_interval(1.15)
	fade.tween_property(self,"modulate:a",0.,.55)
	fade.tween_callback(hide)

func _process(_delta:float) -> void:
	if visible: queue_redraw()

func _draw() -> void:
	if not camera: return
	for point in points:
		if camera.is_position_behind(point): continue
		var screen:=camera.unproject_position(point)
		draw_circle(screen,3.,Color("26251d"))
		draw_circle(screen,2.,Color("ffdf78"))
