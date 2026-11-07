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
	play.disabled = true
	play.custom_minimum_size.y = 56
	play.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/court.tscn"))
	column.add_child(play)
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
	column.move_child(story,1)
	story.grab_focus()
	var quit := Button.new()
	quit.text = "Quit"
	quit.custom_minimum_size.y = 48
	quit.pressed.connect(func(): get_tree().quit())
	column.add_child(quit)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()
