extends Control

const Timing = preload("res://scripts/animation_ball_preview.gd")
const GREEN := Color("65ff94")
const AMBER := Color("ffb968")
const INK := Color("111c29")
var held := 0.0
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

func update_timing(active: bool, seconds: float, result: int, delta: float) -> void:
	visible = active
	if not active: return
	if result != grade:
		held = seconds
		flash = 1.0 if result == Timing.Grade.PERFECT else 0.0
	grade = result
	if grade == Timing.Grade.WAITING: held = seconds
	flash = maxf(0.0,flash-delta*2.5)
	queue_redraw()

func _draw() -> void:
	var track := Rect2(19,49,size.x-38,16)
	var zone_start := Timing.GREEN_START/Timing.METER_DURATION
	var zone_end := Timing.GREEN_END/Timing.METER_DURATION
	var style := StyleBoxFlat.new()
	style.bg_color = INK
	style.set_corner_radius_all(12)
	style.set_border_width_all(2)
	style.border_color = GREEN if grade == Timing.Grade.PERFECT else Color("39556c")
	draw_style_box(style,Rect2(Vector2.ZERO,size))
	if flash > 0.0:
		draw_rect(Rect2(Vector2(5,5),size-Vector2(10,10)),Color(GREEN,flash*0.22))
	draw_rect(track,Color("35475b"))
	var green_zone := Rect2(track.position.x+track.size.x*zone_start,track.position.y,track.size.x*(zone_end-zone_start),track.size.y)
	draw_rect(green_zone,GREEN if grade == Timing.Grade.PERFECT else Color("3fc775"))
	var cursor_x := track.position.x+track.size.x*clampf(held/Timing.METER_DURATION,0.0,1.0)
	var accent := GREEN if grade == Timing.Grade.PERFECT else Color.WHITE
	draw_line(Vector2(cursor_x,track.position.y-4),Vector2(cursor_x,track.end.y+4),Color.WHITE,3,true)
	var heading := "HOLD SPACE" if held <= 0.0 else "RECEPTION TIMING"
	match grade:
		Timing.Grade.PERFECT: heading = "PERFECT PASS"
		Timing.Grade.EARLY: heading = "TOO EARLY"
		Timing.Grade.LATE: heading = "TOO LATE"
		Timing.Grade.MISS: heading = "OUT OF REACH"
	if grade in [Timing.Grade.EARLY,Timing.Grade.LATE,Timing.Grade.MISS]: accent = AMBER
	var font := ThemeDB.fallback_font
	var font_size := 26 if grade == Timing.Grade.PERFECT else 19
	draw_string(font,Vector2(0,34),heading,HORIZONTAL_ALIGNMENT_CENTER,int(size.x),font_size,accent)
