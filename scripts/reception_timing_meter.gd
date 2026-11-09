extends Control

const Timing = preload("res://scripts/animation_ball_preview.gd")
const GREEN := Color("65ff94")
const AMBER := Color("ffb968")
const INK := Color("111c29")
var fill := 0.0
var holding := false
var shown_this_serve := false
var result_time := 0.0
var grade := Timing.Grade.WAITING
var flash := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	offset_left = -154
	offset_right = 154
	offset_top = -102
	offset_bottom = -20
	hide()

func reset_serve() -> void:
	grade = Timing.Grade.WAITING
	shown_this_serve = false
	result_time = 0.0
	flash = 0.0
	hide()

func update_timing(active: bool, progress: float, space_held: bool, result: int, delta: float) -> void:
	if not active:
		hide()
		return
	holding = space_held
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
		visible = result_time > 0.0 and (shown_this_serve or grade == Timing.Grade.PERFECT)
	flash = maxf(0.0,flash-delta*2.5)
	if visible: queue_redraw()

func _draw() -> void:
	var track := Rect2(19,49,size.x-38,16)
	var zone_start := 0.84
	var style := StyleBoxFlat.new()
	style.bg_color = INK
	style.set_corner_radius_all(12)
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
	var heading := "BALL INCOMING"
	if holding: heading = "HOLDING SPACE"
	elif progress >= 1.0-Timing.GREEN_END/Timing.APPROACH_WINDOW: heading = "HOLD SPACE"
	match grade:
		Timing.Grade.PERFECT: heading = "PERFECT PASS"
		Timing.Grade.EARLY: heading = "TOO EARLY"
		Timing.Grade.LATE: heading = "TOO LATE"
		Timing.Grade.MISS: heading = "OUT OF REACH"
	if grade in [Timing.Grade.EARLY,Timing.Grade.LATE,Timing.Grade.MISS]: accent = AMBER
	var font := ThemeDB.fallback_font
	var font_size := 26 if grade == Timing.Grade.PERFECT else 19
	draw_string(font,Vector2(0,34),heading,HORIZONTAL_ALIGNMENT_CENTER,int(size.x),font_size,accent)
