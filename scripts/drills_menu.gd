extends Control

const CATEGORIES := {
	"Passing": [{"title":"Pass to Target","scene":"res://scenes/story_animations.tscn"}],
	"Setting": [{"title":"Set to Target"}],
	"Attacking": [],
	"Serving": [],
	"Digging": [],
}

var heading: Label
var list: VBoxContainer
var scroll: ScrollContainer
var back: Button
var category := ""
var setting_stage: SubViewportContainer
var setting_camera: Camera3D
var camera_focus := Vector3.ZERO

func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color("102b40")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_"+side,40)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",18)
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	heading = Label.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_font_size_override("font_size",40)
	heading.add_theme_color_override("font_color",Color("ffce70"))
	header.add_child(heading)
	back = Button.new()
	back.name = "Back"
	back.text = "Back"
	back.custom_minimum_size = Vector2(104,48)
	back.pressed.connect(go_back)
	header.add_child(back)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation",8)
	scroll.add_child(list)
	if StorySession.drill_menu_category.is_empty():
		show_categories()
	else:
		var previous := StorySession.drill_menu_category
		StorySession.drill_menu_category = ""
		show_category(previous)

func clear_list() -> void:
	for entry in list.get_children():
		list.remove_child(entry)
		entry.queue_free()
	scroll.scroll_vertical = 0

func show_categories() -> void:
	var previous := category
	category = ""
	heading.text = "Drills"
	clear_list()
	for name_ in CATEGORIES:
		var item := add_item(name_,show_category.bind(name_))
		if name_ == previous or (previous.is_empty() and list.get_child_count() == 1):
			item.grab_focus()

func show_category(name_: String) -> void:
	category = name_
	heading.text = name_+" Drills"
	clear_list()
	var drills: Array = CATEGORIES[name_]
	if drills.is_empty():
		var empty := Label.new()
		empty.text = "No drills yet"
		empty.add_theme_font_size_override("font_size",20)
		list.add_child(empty)
		back.grab_focus()
		return
	for drill in drills:
		var scene_path: String = drill.get("scene","")
		var title: String = drill.title
		add_item(title,func():
			if scene_path.is_empty():
				open_setting_stage(title)
				return
			StorySession.open_passing_drill = name_ == "Passing"
			get_tree().change_scene_to_file(scene_path))
	list.get_child(0).grab_focus()

func open_setting_stage(title: String) -> void:
	heading.text = title
	clear_list()
	scroll.hide()
	setting_stage = SubViewportContainer.new()
	setting_stage.stretch = true
	setting_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.get_parent().add_child(setting_stage)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	setting_stage.add_child(viewport)
	preload("res://scripts/preview_court.gd").add_preview_lighting(viewport)
	viewport.add_child(preload("res://scripts/preview_court.gd").new())
	var player := preload("res://scripts/volleyball_player.gd").new()
	player.position = Vector3(0,0.04,1.4)
	viewport.add_child(player)
	player.get_node("DirectionArrows").hide()
	setting_camera = Camera3D.new()
	setting_camera.fov = 42.0
	setting_camera.far = 150.0
	setting_camera.position = Vector3(0,8.2,-12.2)
	camera_focus = Vector3(0,1.55,3.9)
	viewport.add_child(setting_camera)
	setting_camera.look_at(camera_focus)
	setting_camera.make_current()
	setting_stage.gui_input.connect(handle_setting_camera)
	back.grab_focus()

func _process(delta: float) -> void:
	if not is_instance_valid(setting_stage): return
	var movement := Vector2(
		float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_W))-float(Input.is_physical_key_pressed(KEY_S))).limit_length()
	pan_setting_camera(movement,delta)

func pan_setting_camera(movement: Vector2, delta: float) -> void:
	var forward := -setting_camera.global_basis.z.slide(Vector3.UP).normalized()
	var right := setting_camera.global_basis.x.slide(Vector3.UP).normalized()
	var travel := (right*movement.x+forward*movement.y)*delta*6.0
	setting_camera.position += travel
	camera_focus += travel

func handle_setting_camera(event: InputEvent) -> void:
	var offset := setting_camera.position-camera_focus
	var distance := offset.length()
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
		var yaw: float = atan2(offset.x,offset.z)-event.relative.x*0.008
		var pitch := clampf(asin(offset.y/distance)+event.relative.y*0.006,0.08,1.22)
		offset = Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*distance
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		var wheel := (1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0)*maxf(0.1,event.factor)
		offset = offset.normalized()*clampf(distance*exp(-wheel*0.17),2.8,36.0)
	else:
		return
	setting_camera.position = camera_focus+offset
	setting_camera.look_at(camera_focus)
	setting_stage.accept_event()

func add_item(title: String, action: Callable) -> Button:
	var item := Button.new()
	item.text = title
	item.custom_minimum_size.y = 58
	item.add_theme_font_size_override("font_size",23)
	item.pressed.connect(action)
	list.add_child(item)
	return item

func go_back() -> void:
	if is_instance_valid(setting_stage):
		setting_stage.queue_free()
		setting_stage = null
		scroll.show()
		show_category(category)
	elif category.is_empty():
		get_tree().change_scene_to_file("res://scenes/main.tscn")
	else:
		show_categories()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		go_back()
		get_viewport().set_input_as_handled()
