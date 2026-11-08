extends Control
signal source_moved(position: Vector2)
var source_position := Vector2(0,12.5)
var player_position := Vector2.ZERO
var dragging := false
var mode := "source"
var destination_position := Vector2.INF

func _ready() -> void:
	custom_minimum_size = Vector2(240,94)
	mouse_default_cursor_shape = Control.CURSOR_DRAG

func court_rect() -> Rect2:
	return Rect2(Vector2(12,8),size-Vector2(24,16))

func point(position: Vector2) -> Vector2:
	var area := court_rect()
	return area.position+Vector2((position.x+9.0)/18.0,(44.0-position.y)/52.0)*area.size

func set_positions(source: Vector2, player: Vector2, destination := Vector2.INF) -> void:
	if source_position == source and player_position == player and destination_position == destination: return
	source_position = source
	player_position = player
	destination_position = destination
	queue_redraw()

func _draw() -> void:
	var area := court_rect()
	draw_style_box(style(),Rect2(Vector2.ZERO,size))
	draw_rect(area,Color("263e4d"))
	var court := Rect2(point(Vector2(-4.5,13)),point(Vector2(4.5,-5))-point(Vector2(-4.5,13)))
	draw_rect(court,Color("3a5967"))
	draw_rect(court,Color("91a7b2"),false,1)
	var net := point(Vector2(0,4)).y
	draw_line(Vector2(area.position.x,net),Vector2(area.end.x,net),Color("e9e3d5"),2)
	var selected := source_position if mode == "source" else destination_position
	if selected.is_finite(): draw_line(point(player_position),point(selected),Color("657f88"),1,true)
	draw_circle(point(player_position),5,Color("e6e6dd"))
	draw_circle(point(source_position),6,Color("efc66f"))
	if destination_position.is_finite(): draw_circle(point(destination_position),6,Color("41c3f4"))
	if selected.is_finite(): draw_arc(point(selected),10,0,TAU,24,Color("efc66f") if mode == "source" else Color("41c3f4"),1.5,true)

func style() -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = Color("12222f")
	result.set_corner_radius_all(5)
	return result

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		dragging = event.pressed
		if dragging: move_source(event.position)
		accept_event()
	elif event is InputEventMouseMotion and dragging:
		move_source(event.position)
		accept_event()

func move_source(position: Vector2) -> void:
	var area := court_rect()
	var uv := ((position-area.position)/area.size).clamp(Vector2.ZERO,Vector2.ONE)
	var position_ := Vector2(uv.x*18.0-9.0,44.0-uv.y*52.0)
	if mode == "source": source_position = position_
	else: destination_position = position_
	source_moved.emit(position_)
	queue_redraw()
