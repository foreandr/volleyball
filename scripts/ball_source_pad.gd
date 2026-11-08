extends Control
signal source_moved(position: Vector2)
var source_position := Vector2(0,12.5)
var player_position := Vector2.ZERO
var dragging := false

func _ready() -> void:
	custom_minimum_size = Vector2(240,94)
	mouse_default_cursor_shape = Control.CURSOR_DRAG

func court_rect() -> Rect2:
	return Rect2(Vector2(12,8),size-Vector2(24,16))

func point(position: Vector2) -> Vector2:
	var area := court_rect()
	return area.position+Vector2((position.x+9.0)/18.0,(44.0-position.y)/52.0)*area.size

func set_positions(source: Vector2, player: Vector2) -> void:
	if source_position == source and player_position == player: return
	source_position = source
	player_position = player
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
	draw_line(point(player_position),point(source_position),Color("657f88"),1,true)
	draw_circle(point(player_position),5,Color("41c3f4"))
	draw_circle(point(source_position),8,Color("efc66f"))
	draw_arc(point(source_position),11,0,TAU,24,Color("f5e5b7"),1.5,true)

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
	source_position = Vector2(uv.x*18.0-9.0,44.0-uv.y*52.0)
	source_moved.emit(source_position)
	queue_redraw()
