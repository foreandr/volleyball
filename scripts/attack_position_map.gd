extends Control

const START_COLOR := Color("62d9f0")
const BALL_COLOR := Color("ffd477")
const SHOT_COLOR := Color("ec9eff")
const COURT_COLOR := Color("8caebc")
const COURT_CENTER_Y := 101.0

var drill: Node3D
var drag_marker := ""
var drag_start := Vector2.ZERO
var drag_offset := Vector2.ZERO

func _ready() -> void:
	custom_minimum_size.y = 262
	mouse_filter = Control.MOUSE_FILTER_STOP

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(drill): return
	var scale_ := court_scale()
	var center := Vector2(size.x*0.5,COURT_CENTER_Y)
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
	var shot := court_point(drill.swing_aim)
	draw_arc(shot,6.0,0.0,TAU,24,SHOT_COLOR,2.0,true)
	draw_circle(shot,2.0,SHOT_COLOR)
	var font := get_theme_default_font()
	draw_arc(Vector2(16,246),4.5,0.0,TAU,24,SHOT_COLOR,1.5,true)
	draw_string(font,Vector2(29,251),"Shot target",HORIZONTAL_ALIGNMENT_LEFT,-1,16,SHOT_COLOR)
	if drill.swing_practice:
		draw_arc(Vector2(16,226),4.5,0.0,TAU,24,BALL_COLOR,1.5,true)
		draw_string(font,Vector2(29,231),"Set target",HORIZONTAL_ALIGNMENT_LEFT,-1,16,BALL_COLOR)
	draw_circle(Vector2(16,186),4.5,START_COLOR)
	draw_string(font,Vector2(29,191),"Attacker start",HORIZONTAL_ALIGNMENT_LEFT,-1,16,START_COLOR)
	draw_circle(Vector2(16,206),4.5,BALL_COLOR)
	draw_string(font,Vector2(29,211),"Ball   %.2f m high" % ball.y,HORIZONTAL_ALIGNMENT_LEFT,-1,16,BALL_COLOR)

func court_scale() -> float:
	return minf((size.x-24.0)/13.5,7.6)

func court_point(point: Vector3) -> Vector2:
	return Vector2(size.x*0.5,COURT_CENTER_Y)+Vector2(-point.x,4.0-point.z)*court_scale()

func map_to_court(position_: Vector2) -> Vector3:
	var offset := (position_-court_point(Vector3.ZERO))/court_scale()
	return Vector3(-offset.x,0.0,-offset.y)

func _gui_input(event: InputEvent) -> void:
	if not is_instance_valid(drill): return
	if event is InputEventMouseMotion and not drag_marker.is_empty():
		if drag_marker == "shot": drill.aim_swing(map_to_court(event.position))
		else: drag_offset += event.relative
		accept_event()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var point := map_to_court(event.position)
			if absf(point.x) <= drill.SHOT_AIM_HALF_WIDTH and point.z >= drill.SHOT_AIM_NEAR and point.z <= drill.SHOT_AIM_FAR:
				drag_marker = "shot"
				drill.aim_swing(point)
				accept_event()
				return
			if not drill.swing_practice: return
			var start := court_point(drill.practice_takeoff)
			var target := court_point(drill.practice_set_target)
			var start_distance: float = event.position.distance_to(start)
			var target_distance: float = event.position.distance_to(target)
			if minf(start_distance,target_distance) > 12.0: return
			drag_marker = "target" if target_distance < start_distance else "start"
			drag_start = target if drag_marker == "target" else start
			drag_offset = Vector2.ZERO
		elif drag_marker == "shot":
			drag_marker = ""
			accept_event()
		elif not drag_marker.is_empty():
			var shift := Vector3(-drag_offset.x,0.0,-drag_offset.y)/court_scale()
			if shift.length_squared() > 0.0001:
				if drag_marker == "start":
					drill.practice_takeoff = drill.Court.clamp_setter(drill.practice_takeoff+shift,drill.ATTACK_FRONT_LIMIT)
				else:
					drill.move_practice_target(drill.practice_set_target+shift)
				drill.reset_feed()
			drag_marker = ""
		accept_event()
