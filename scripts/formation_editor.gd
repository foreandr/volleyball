extends Control

const Formation=preload("res://scripts/six_rotations.gd")
const Xbox=preload("res://scripts/xbox_controls.gd")
var setter_zone:=1
var defense:=false
var selected:=0
var marks:=PackedVector2Array()
var edges:Array[Vector3i]=[]
var board:=Control.new()
var dragging:=false
var editing:=false
var dirty:=false
var roles:=OptionButton.new()
var place:=Button.new()

func _ready() -> void:
	MenuPresentation.backdrop(self,false)
	var margin:=MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge,24)
	margin.add_theme_constant_override("margin_top",54)
	var column:=VBoxContainer.new()
	margin.add_child(column)
	var heading:=Label.new()
	heading.text="6v6 formations"
	heading.add_theme_font_size_override("font_size",30)
	column.add_child(heading)
	var bar:=HBoxContainer.new()
	column.add_child(bar)
	var rotation:=OptionButton.new()
	for i in range(1,7): rotation.add_item("Setter in "+str(i))
	bar.add_child(rotation)
	var phase:=OptionButton.new()
	phase.add_item("Serve receive")
	phase.add_item("Block defense")
	bar.add_child(phase)
	for label in Formation.SHORT: roles.add_item(label)
	bar.add_child(roles)
	bar.add_child(place)
	place.text="Move player"
	place.pressed.connect(func(): editing=true; board.grab_focus(); board.queue_redraw())
	var back:=Button.new()
	back.text="Done"
	bar.add_child(back)
	back.pressed.connect(leave)
	column.add_child(board)
	board.size_flags_vertical=Control.SIZE_EXPAND_FILL
	board.focus_mode=Control.FOCUS_ALL
	board.draw.connect(draw_board)
	board.resized.connect(board.queue_redraw)
	board.gui_input.connect(board_input)
	var hints:=HBoxContainer.new()
	column.add_child(hints)
	if Xbox.keyboard_prompts():
		var help:=Label.new()
		help.text="Drag a player or choose Move player and use the arrow keys. Enter to place."
		hints.add_child(help)
	else: Xbox.prompts(hints,[["LS","Move player"],["A","Place"],["B","Back"]])
	rotation.item_selected.connect(func(i): save(); setter_zone=i+1; refresh())
	phase.item_selected.connect(func(i): save(); defense=i==1; refresh())
	roles.item_selected.connect(func(i): selected=i; board.queue_redraw())
	refresh()
	rotation.grab_focus()

func refresh() -> void:
	edges=Formation.receive_edges(setter_zone)
	marks=Formation.layout(StorySession.game_options,setter_zone,defense)
	for i in 6:
		roles.set_item_text(i,"Libero (for %s)"%Formation.SHORT[i] if libero_mark(i) else Formation.SHORT[i])
	board.queue_redraw()

func libero_mark(role:int) -> bool:
	return Formation.back_row_libero(role,setter_zone)

func court() -> Rect2:
	var edge:=maxf(1.,minf(board.size.x-44.,board.size.y-44.))
	return Rect2((board.size-Vector2.ONE*edge)*.5,Vector2.ONE*edge)

func draw_board() -> void:
	if marks.size()!=6: return
	var r:=court()
	board.draw_rect(r,Color("#904730"))
	board.draw_rect(r,Color("#f2dfc8"),false,2.)
	board.draw_line(r.position,r.position+Vector2.RIGHT*r.size.x,Color.WHITE,5.)
	var line:=r.position+Vector2.DOWN*r.size.y/3.
	board.draw_line(line,line+Vector2.RIGHT*r.size.x,Color("#ebc9ad"),2.)
	if not defense:
		var bounds:=Formation.receive_bounds(marks,selected,edges)
		var area:=Rect2(r.position+bounds.position*r.size,bounds.size*r.size)
		board.draw_rect(area,Color("#75e0bc33"))
		board.draw_rect(area,Color("#85dbc4"),false,1.5)
	var font:=get_theme_default_font()
	board.draw_string(font,r.position+Vector2(0,-5),"NET",HORIZONTAL_ALIGNMENT_CENTER,r.size.x,14)
	for i in 6:
		var at:=r.position+marks[i]*r.size
		board.draw_circle(at,21.,Color("#f5cd78") if selected==i else (Color("#367987") if libero_mark(i) else Color("#213849")),true,-1.,true)
		board.draw_string(font,at+Vector2(-21,6),"L" if libero_mark(i) else Formation.SHORT[i],HORIZONTAL_ALIGNMENT_CENTER,42.,16,Color.BLACK if selected==i else Color.WHITE)

func move_mark(mark:Vector2) -> void:
	var bounds:=Rect2(Vector2.ONE*.035,Vector2.ONE*.93) if defense else Formation.receive_bounds(marks,selected,edges)
	marks[selected]=mark.clamp(bounds.position,bounds.end)
	dirty=true
	board.queue_redraw()

func board_input(event:InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			var r:=court()
			var best:=26.
			for i in 6:
				var distance:float=(r.position+marks[i]*r.size).distance_to(event.position)
				if distance<best:
					best=distance
					selected=i
			dragging=best<26.
			if dragging: roles.select(selected); board.queue_redraw()
		elif dragging:
			dragging=false
			save()
		board.accept_event()
	elif event is InputEventMouseMotion and dragging:
		var r:=court()
		move_mark((event.position-r.position)/r.size)
	elif editing and (event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel")):
		finish_move()
		board.accept_event()
	elif editing: board.accept_event()

func _process(delta:float) -> void:
	if not editing: return
	var direction:=Input.get_vector("ui_left","ui_right","ui_up","ui_down")
	var pads:=Input.get_connected_joypads()
	if not pads.is_empty():
		var stick:=Vector2(Input.get_joy_axis(pads[0],JOY_AXIS_LEFT_X),Input.get_joy_axis(pads[0],JOY_AXIS_LEFT_Y))
		if stick.length()>.18: direction=stick.limit_length()
	if direction.length_squared()>0.: move_mark(marks[selected]+direction*delta*.53)

func finish_move() -> void:
	editing=false
	save()
	place.grab_focus()

func save() -> void:
	if not dirty: return
	StorySession.game_options.set_value("six_rotations",Formation.key(setter_zone,defense),marks.duplicate())
	StorySession.save_options()
	dirty=false

func leave() -> void:
	save()
	MenuPresentation.return_page="Settings"
	MenuPresentation.load_scene("res://scenes/main.tscn")

func _unhandled_input(event:InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		leave()
