extends Control

const START_COLOR := Color("62d9f0")
const BALL_COLOR := Color("ffd477")
const COURT_COLOR := Color("8caebc")

var drill: Node3D
var drag_marker := ""
var drag_start := Vector2.ZERO
var drag_offset := Vector2.ZERO

func _ready() -> void:
	custom_minimum_size.y = 336
	mouse_filter = Control.MOUSE_FILTER_STOP

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(drill): return
	var scale_ := court_scale()
	var center := Vector2(size.x*0.5,126.0)
	var bounds := Rect2(center-Vector2(4.5,9.0)*scale_,Vector2(9.0,18.0)*scale_)
	draw_rect(bounds,Color("243b49"))
	draw_rect(bounds,COURT_COLOR,false,1.0)
	for z in [1.0,4.0,7.0]:
		var y: float = center.y-(z-4.0)*scale_
		draw_line(Vector2(bounds.position.x,y),Vector2(bounds.end.x,y),COURT_COLOR,2.0 if z == 4.0 else 1.0)
	var start: Vector3 = drill.jump.start if drill.swing_practice or drill.jump.active else drill.RECEIVE_START
	var ball: Vector3 = drill.ball.position
	var start_marker := court_point(start)
	var ball_marker := court_point(ball)
	var map_bounds := bounds.grow(10.0)
	ball_marker = ball_marker.clamp(map_bounds.position,map_bounds.end)
	if drag_marker == "start": start_marker = drag_start+drag_offset
	if drill.swing_practice:
		var target := court_point(drill.practice_set_target)
		if drag_marker == "target": target = drag_start+drag_offset
		draw_arc(target,7.0,0.0,TAU,24,BALL_COLOR,2.0,true)
	draw_circle(ball_marker,4.5,BALL_COLOR)
	draw_arc(start_marker,8.0,0.0,TAU,24,START_COLOR,2.0,true)
	var font := get_theme_default_font()
	if drill.swing_practice:
		draw_arc(Vector2(16,317),4.5,0.0,TAU,24,BALL_COLOR,1.5,true)
		draw_string(font,Vector2(29,322),"Set target",HORIZONTAL_ALIGNMENT_LEFT,-1,16,BALL_COLOR)
	draw_circle(Vector2(16,265),4.5,START_COLOR)
	draw_string(font,Vector2(29,270),"Attacker start",HORIZONTAL_ALIGNMENT_LEFT,-1,16,START_COLOR)
	draw_circle(Vector2(16,291),4.5,BALL_COLOR)
	draw_string(font,Vector2(29,296),"Ball   %.2f m high" % ball.y,HORIZONTAL_ALIGNMENT_LEFT,-1,16,BALL_COLOR)

func court_scale() -> float:
	return minf((size.x-24.0)/13.5,10.0)

func court_point(point: Vector3) -> Vector2:
	return Vector2(size.x*0.5,126.0)+Vector2(-point.x,4.0-point.z)*court_scale()

func _gui_input(event: InputEvent) -> void:
	if not is_instance_valid(drill) or not drill.swing_practice: return
	if event is InputEventMouseMotion and not drag_marker.is_empty():
		drag_offset += event.relative
		accept_event()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var start := court_point(drill.practice_takeoff)
			var target := court_point(drill.practice_set_target)
			var start_distance: float = event.position.distance_to(start)
			var target_distance: float = event.position.distance_to(target)
			if minf(start_distance,target_distance) > 12.0: return
			drag_marker = "target" if target_distance < start_distance else "start"
			drag_start = target if drag_marker == "target" else start
			drag_offset = Vector2.ZERO
		elif not drag_marker.is_empty():
			var shift := Vector3(-drag_offset.x,0.0,-drag_offset.y)/court_scale()
			if shift.length_squared() > 0.0001:
				if drag_marker == "start":
					drill.practice_takeoff = drill.Court.clamp_setter(drill.practice_takeoff+shift,drill.ATTACK_FRONT_LIMIT)
				else:
					var point: Vector3 = drill.practice_set_target+shift
					point.x = clampf(point.x,-4.5,4.5)
					point.z = clampf(point.z,-5.0,4.0)
					drill.practice_set_target = point
				drill.reset_feed()
			drag_marker = ""
		accept_event()
