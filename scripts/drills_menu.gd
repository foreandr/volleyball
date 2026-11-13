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
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("192936")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.65
	viewport.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52,-32,0)
	sun.shadow_enabled = true
	viewport.add_child(sun)
	viewport.add_child(preload("res://scripts/preview_court.gd").new())
	var player := preload("res://scripts/volleyball_player.gd").new()
	player.position = Vector3(0,0.04,1.4)
	viewport.add_child(player)
	player.get_node("DirectionArrows").hide()
	var camera := Camera3D.new()
	camera.position = Vector3(7.0,6.8,-10.0)
	viewport.add_child(camera)
	camera.look_at(Vector3(0,1,3.2))
	camera.make_current()
	back.grab_focus()

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
