extends "res://scripts/attack_position_map.gd"

const MARKERS := ["attacker","blocker","set"]
const MARKER_COLORS := [START_COLOR,Color("ec9eff"),BALL_COLOR]
const MARKER_LABELS := ["Attacker start","Blocker","Set target"]
const MAP_CENTER_Y := 104.0
var preview_point := Vector3.ZERO

func _ready() -> void:
	super._ready()
	custom_minimum_size.y = 250
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func court_scale() -> float:
	return minf((size.x-26.0)/11.0,10.4)

func court_point(point: Vector3) -> Vector2:
	return Vector2(size.x*0.5,MAP_CENTER_Y)+Vector2(-point.x,4.0-point.z)*court_scale()

func _draw() -> void:
	if not is_instance_valid(drill): return
	var corner := court_point(Vector3(4.5,0.0,13.0))
	var bounds := Rect2(corner,Vector2(9.0,18.0)*court_scale())
	draw_rect(bounds,Color("243b49"))
	draw_rect(bounds,COURT_COLOR,false,1.0)
	for depth in [1.0,4.0,7.0]:
		var y := court_point(Vector3(0.0,0.0,depth)).y
		draw_line(Vector2(bounds.position.x,y),Vector2(bounds.end.x,y),COURT_COLOR,2.0 if depth == 4.0 else 1.0)
	var font := get_theme_default_font()
	for i in MARKERS.size():
		var marker: String = MARKERS[i]
		var position: Vector3 = preview_point if drag_marker == marker else drill.setup_marker(marker)
		var center := court_point(position)
		var color: Color = MARKER_COLORS[i]
		draw_circle(center,7.0,Color("18232e"))
		draw_arc(center,7.0,0.0,TAU,24,color,2.0,true)
		if marker != "set": draw_circle(center,2.5,color)
		var y := 211.0+17.0*i
		draw_circle(Vector2(12.0,y-4.0),3.5,color)
		draw_string(font,Vector2(23.0,y),MARKER_LABELS[i],HORIZONTAL_ALIGNMENT_LEFT,-1,14,color)

func _gui_input(event: InputEvent) -> void:
	if not is_instance_valid(drill): return
	if event is InputEventMouseMotion and not drag_marker.is_empty():
		update_drag(event.position)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var nearest := 13.0
			for marker: String in MARKERS:
				var point: Vector3 = drill.setup_marker(marker)
				var offset: Vector2 = court_point(point)-event.position
				if offset.length() >= nearest: continue
				nearest = offset.length()
				drag_marker = marker
				drag_offset = offset
				preview_point = point
			if not drag_marker.is_empty(): accept_event()
		elif not drag_marker.is_empty():
			update_drag(event.position)
			var previous: Vector3 = drill.setup_marker(drag_marker)
			if Vector2(preview_point.x-previous.x,preview_point.z-previous.z).length() > 0.025:
				drill.move_setup_marker(drag_marker,preview_point)
			drag_marker = ""
			accept_event()

func update_drag(cursor: Vector2) -> void:
	var point := map_to_court(cursor+drag_offset)
	match drag_marker:
		"attacker": point = point.clamp(Vector3(-5.5,0.0,-4.8),Vector3(5.5,0.0,3.45))
		"blocker": point = point.clamp(Vector3(-5.5,0.0,4.50),Vector3(5.5,0.0,6.0))
		"set": point = point.clamp(Vector3(-4.4,0.0,0.8),Vector3(4.4,0.0,3.69))
	preview_point = point
