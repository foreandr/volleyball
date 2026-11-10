extends Control

const Timing = preload("res://scripts/animation_ball_preview.gd")
const GREEN := Color("65ff94")
const AMBER := Color("ffb968")
const INK := Color("111c29")
var actor: Node3D
var camera: Camera3D
var stage: Control
var action_name := "PASS"
var cpu := false
var fill := 0.0
var receiving := false
var shown_this_serve := false
var result_time := 0.0
var grade := Timing.Grade.WAITING
var flash := 0.0
var green_zone_start := 0.78
var cue_start := 1.0-Timing.GREEN_END/Timing.APPROACH_WINDOW

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(156,42)
	hide()

func follow_player(player: Node3D, view: Camera3D, viewport_panel: Control) -> void:
	actor = player
	camera = view
	stage = viewport_panel
	update_position()

func _process(_delta: float) -> void:
	if visible: update_position()

func update_position() -> void:
	if not is_instance_valid(actor) or not is_instance_valid(camera): return
	var rig: Skeleton3D = actor.skeleton
	var head := rig.find_bone("Head")
	var point := actor.global_position+Vector3.UP*1.85
	if head >= 0:
		point = rig.to_global(rig.get_bone_global_pose(head).origin)+Vector3.UP*0.26
		point.y = maxf(point.y,actor.global_position.y+1.25)
	var projected := camera.unproject_position(point)*stage.size/Vector2(camera.get_viewport().size)
	modulate.a = 0.0 if camera.is_position_behind(point) or not Rect2(Vector2.ZERO,stage.size).has_point(projected) else 1.0
	position = projected-Vector2(size.x*0.5,size.y+5.0)

func reset_serve() -> void:
	grade = Timing.Grade.WAITING
	shown_this_serve = false
	result_time = 0.0
	flash = 0.0
	hide()

func update_timing(active: bool, progress: float, receiving_now: bool, result: int, delta: float, green_start := -1.0) -> void:
	if not active:
		hide()
		return
	receiving = receiving_now
	green_zone_start = green_start if green_start >= 0.0 else 0.78
	cue_start = green_start if green_start >= 0.0 else 1.0-Timing.GREEN_END/Timing.APPROACH_WINDOW
	if result != grade:
		flash = 1.0 if result == Timing.Grade.PERFECT else 0.0
		result_time = 0.85
	grade = result
	if grade == Timing.Grade.WAITING:
		visible = progress >= 0.0
		if visible:
			fill = progress
			shown_this_serve = true
	else:
		fill = 1.0
		result_time = maxf(0.0,result_time-delta)
		visible = result_time > 0.0 and (shown_this_serve or grade in [Timing.Grade.PERFECT,Timing.Grade.BODY_DIG])
	flash = maxf(0.0,flash-delta*2.5)
	if visible:
		update_position()
		queue_redraw()

func _draw() -> void:
	var track := Rect2(9,25,size.x-18,9)
	var zone_start := green_zone_start
	var style := StyleBoxFlat.new()
	style.bg_color = INK
	style.set_corner_radius_all(7)
	style.set_border_width_all(2)
	style.border_color = GREEN if grade == Timing.Grade.PERFECT else Color("39556c")
	draw_style_box(style,Rect2(Vector2.ZERO,size))
	if flash > 0.0:
		draw_rect(Rect2(Vector2(5,5),size-Vector2(10,10)),Color(GREEN,flash*0.22))
	draw_rect(track,Color("35475b"))
	var green_zone := Rect2(track.position.x+track.size.x*zone_start,track.position.y,track.size.x*(1.0-zone_start),track.size.y)
	draw_rect(green_zone,Color("227749"))
	var progress := clampf(fill,0.0,1.0)
	var filled := Rect2(track.position,Vector2(track.size.x*progress,track.size.y))
	var bar_color := Color("83cfff")
	if grade == Timing.Grade.PERFECT: bar_color = GREEN
	elif grade != Timing.Grade.WAITING: bar_color = AMBER
	draw_rect(filled,bar_color)
	if grade == Timing.Grade.WAITING and progress > zone_start:
		draw_rect(Rect2(green_zone.position,Vector2(track.size.x*(progress-zone_start),track.size.y)),GREEN)
	var accent := GREEN if grade == Timing.Grade.PERFECT else Color.WHITE
	var heading := "CPU PASS" if cpu else "BALL INCOMING"
	if receiving and not cpu: heading = "SETTING" if action_name == "SET" else "RECEIVING"
	elif not cpu and progress >= cue_start: heading = "TAP Q"
	match grade:
		Timing.Grade.PERFECT: heading = "PERFECT "+action_name
		Timing.Grade.EARLY: heading = "TOO EARLY"
		Timing.Grade.LATE: heading = "TOO LATE"
		Timing.Grade.MISS: heading = "OUT OF REACH"
		Timing.Grade.BODY_DIG: heading = "BODY DIG"
	if grade in [Timing.Grade.EARLY,Timing.Grade.LATE,Timing.Grade.MISS]: accent = AMBER
	var font := ThemeDB.fallback_font
	var font_size := 16 if grade == Timing.Grade.PERFECT else 13
	draw_string(font,Vector2(0,19),heading,HORIZONTAL_ALIGNMENT_CENTER,int(size.x),font_size,accent)
