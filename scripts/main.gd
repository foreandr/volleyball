extends Control

func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color("102b40")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",24)
	center.add_child(column)
	var title := Label.new()
	title.text = "VOLLEYBALL"
	title.add_theme_font_size_override("font_size",72)
	title.add_theme_color_override("font_color",Color("ffce70"))
	column.add_child(title)
	var play := Button.new()
	play.name = "Play"
	play.text = "Play"
	play.custom_minimum_size.y = 56
	var match_size := OptionButton.new()
	match_size.name = "MatchSize"
	match_size.add_item("2v2",2)
	match_size.add_item("3v3",3)
	match_size.select(0)
	play.pressed.connect(func():
		StorySession.home_match_size = match_size.get_selected_id()
		get_tree().change_scene_to_file("res://scenes/story_animations.tscn"))
	var play_row := HBoxContainer.new()
	play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play_row.add_child(play)
	play_row.add_child(match_size)
	column.add_child(play_row)
	var lab := Button.new()
	lab.name = "IterationLab"
	lab.text = "Iteration Lab"
	lab.custom_minimum_size.y = 56
	lab.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/iteration_lab.tscn"))
	column.add_child(lab)
	var create := Button.new()
	create.name = "Create"
	create.text = "Create Player"
	create.disabled = true
	create.custom_minimum_size.y = 56
	create.pressed.connect(func(): StorySession.cancel_creation(); get_tree().change_scene_to_file("res://scenes/create.tscn"))
	column.add_child(create)
	var story := Button.new()
	story.name = "Story"
	story.text = "Story"
	story.custom_minimum_size.y = 56
	story.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/story.tscn"))
	column.add_child(story)
	play.grab_focus()
	var quit := Button.new()
	quit.text = "Quit"
	quit.custom_minimum_size.y = 48
	quit.pressed.connect(func(): get_tree().quit())
	column.add_child(quit)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()
