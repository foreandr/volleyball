extends Control

func _ready() -> void:
	StorySession.ensure_background_training()
	if not StorySession.demo_launch_consumed and "--demo-match" in OS.get_cmdline_user_args():
		StorySession.demo_launch_consumed = true
		open_simulation()
		return

	var background := ColorRect.new()
	background.color = Color("102b40")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",20)
	center.add_child(column)
	var title := Label.new()
	title.text = "VOLLEYBALL"
	title.add_theme_font_size_override("font_size",72)
	title.add_theme_color_override("font_color",Color("ffce70"))
	column.add_child(title)

	var simulate := add_menu_button(column,"Simulate","Simulate",open_simulation)
	add_menu_button(column,"Drills","Drills",func(): get_tree().change_scene_to_file("res://scenes/drills.tscn"))
	add_menu_button(column,"IterationLab","Iteration Lab",func(): get_tree().change_scene_to_file("res://scenes/iteration_lab.tscn"))
	add_menu_button(column,"Quit","Quit",func(): get_tree().quit())
	simulate.grab_focus()

func add_menu_button(parent: VBoxContainer, id: String, title: String, action: Callable) -> Button:
	var item := Button.new()
	item.name = id
	item.text = title
	item.custom_minimum_size.y = 56
	item.pressed.connect(action)
	parent.add_child(item)
	return item

func open_simulation() -> void:
	StorySession.open_home_simulation = true
	get_tree().change_scene_to_file.call_deferred("res://scenes/story_animations.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
