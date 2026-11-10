extends Control

const START_COLOR := Color("62d9f0")
const BALL_COLOR := Color("ffd477")
const COURT_COLOR := Color("8caebc")

var drill: Node3D

func _ready() -> void:
	custom_minimum_size.y = 310
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(drill): return
	var scale_: float = minf((size.x-24.0)/11.0,12.0)
	var center := Vector2(size.x*0.5,126.0)
	var bounds := Rect2(center-Vector2(4.5,9.0)*scale_,Vector2(9.0,18.0)*scale_)
	draw_rect(bounds,Color("243b49"))
	draw_rect(bounds,COURT_COLOR,false,1.0)
	for z in [1.0,4.0,7.0]:
		var y: float = center.y-(z-4.0)*scale_
		draw_line(Vector2(bounds.position.x,y),Vector2(bounds.end.x,y),COURT_COLOR,2.0 if z == 4.0 else 1.0)
	var start: Vector3 = drill.jump.start if drill.swing_practice or drill.jump.active else drill.RECEIVE_START
	var ball: Vector3 = drill.ball.position
	var start_marker := center+Vector2(-start.x,4.0-start.z)*scale_
	var ball_marker := center+Vector2(-ball.x,4.0-ball.z)*scale_
	var map_bounds := bounds.grow(10.0)
	ball_marker = ball_marker.clamp(map_bounds.position,map_bounds.end)
	draw_circle(ball_marker,4.5,BALL_COLOR)
	draw_arc(start_marker,8.0,0.0,TAU,24,START_COLOR,2.0,true)
	var font := get_theme_default_font()
	draw_circle(Vector2(16,265),4.5,START_COLOR)
	draw_string(font,Vector2(29,270),"Attacker start",HORIZONTAL_ALIGNMENT_LEFT,-1,16,START_COLOR)
	draw_circle(Vector2(16,291),4.5,BALL_COLOR)
	draw_string(font,Vector2(29,296),"Ball   %.2f m high" % ball.y,HORIZONTAL_ALIGNMENT_LEFT,-1,16,BALL_COLOR)
