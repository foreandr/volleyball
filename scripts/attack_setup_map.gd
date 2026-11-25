extends Control

const ROLES := ["Coach","Setter","Set","Hitter"]
const COLORS := [Color("ffd477"),Color("6bded3"),Color("efa6ed"),Color("91d9ff")]
const SIDELINE := 4.5
const NET := 4.0
const BASELINE := NET-9.0
const SIDE_LIMIT := SIDELINE+1.0
const BACK_LIMIT := BASELINE-1.5
var game
var dragging := -1
var preview := Vector2.ZERO
var offset := Vector2.ZERO

func _ready() -> void:
	custom_minimum_size=Vector2(300,238)
	mouse_filter=MOUSE_FILTER_STOP
	tooltip_text="Drag a marker or its label to position it for the next feed."

func court_scale() -> float:
	return minf((size.x-32.)/(2.*SIDE_LIMIT),(size.y-46.)/(NET-BACK_LIMIT))

func screen_point(point: Vector2) -> Vector2:
	return Vector2(size.x*.5,16.)+Vector2(-point.x,NET-point.y)*court_scale()

func marker(i: int) -> Vector2:
	if dragging==i: return screen_point(preview)
	var spot: Vector3=[game.coach_station,game.setter_station,game.next_set,game.hitter_start][i]
	return screen_point(Vector2(spot.x,spot.z))

func _draw() -> void:
	var left := screen_point(Vector2(SIDELINE,NET))
	var right := screen_point(Vector2(-SIDELINE,BASELINE))
	var bounds := Rect2(left,right-left)
	var outer := screen_point(Vector2(SIDE_LIMIT,NET))
	draw_rect(Rect2(outer,screen_point(Vector2(-SIDE_LIMIT,BACK_LIMIT))-outer),Color("334239"))
	draw_rect(bounds,Color("23504e"))
	draw_rect(bounds,Color.WHITE,false)
	draw_line(left,Vector2(right.x,left.y),Color.WHITE,3.)
	draw_line(screen_point(Vector2(4.5,1.)),screen_point(Vector2(-4.5,1.)),Color.WHITE)
	for i in ROLES.size():
		var x := i*size.x/ROLES.size()+8.
		draw_circle(marker(i),8.,COLORS[i])
		draw_circle(Vector2(x,size.y-13.),5.,COLORS[i])
		draw_string(get_theme_default_font(),Vector2(x+10.,size.y-7.),ROLES[i],HORIZONTAL_ALIGNMENT_LEFT,-1,16,COLORS[i])

func place(cursor: Vector2) -> void:
	var delta := (cursor+offset-screen_point(Vector2.ZERO))/court_scale()
	var max_z := [1.,3.,3.65,3.65]
	preview=Vector2(clampf(-delta.x,-SIDE_LIMIT,SIDE_LIMIT),clampf(-delta.y,BACK_LIMIT,max_z[dragging]))
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and dragging>=0:
		place(event.position)
		accept_event()
	elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			var chosen := -1
			offset=Vector2.ZERO
			if event.position.y>size.y-27.:
				chosen=clampi(int(event.position.x*ROLES.size()/size.x),0,ROLES.size()-1)
			else:
				var nearest := 15.
				for i in ROLES.size():
					var distance := marker(i).distance_to(event.position)
					if distance<nearest:
						chosen=i
						nearest=distance
				if chosen>=0: offset=marker(chosen)-event.position
			if chosen<0: return
			var initial := marker(chosen)
			dragging=chosen
			place(initial-offset)
		elif dragging>=0:
			if event.position.y<=size.y-27.:
				place(event.position)
				game.move_setup_spot(ROLES[dragging],preview)
			dragging=-1
			queue_redraw()
		accept_event()
