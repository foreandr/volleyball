extends Control
var column: VBoxContainer

func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color("0f1a25")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	column = VBoxContainer.new()
	column.custom_minimum_size.x = 440
	column.add_theme_constant_override("separation",18)
	center.add_child(column)
	show_home()

func clear_menu(title: String) -> void:
	for child in column.get_children():
		column.remove_child(child)
		child.queue_free()
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size",42)
	heading.add_theme_color_override("font_color",Color("ffce70"))
	column.add_child(heading)

func add_button(text: String, action: Callable) -> Button:
	var result := Button.new()
	result.name = text.replace(" ","")
	result.text = text
	result.custom_minimum_size.y = 52
	result.pressed.connect(action)
	column.add_child(result)
	return result

func show_home() -> void:
	clear_menu("STORY")
	var resume := add_button("Continue",func(): StorySession.load_story(StorySession.last_id()))
	resume.disabled = StorySession.last_id().is_empty()
	var new_story := add_button("New",StorySession.begin_new)
	var load_button := add_button("Load",show_load)
	load_button.disabled = StorySession.saved_stories().is_empty()
	add_button("Back",open_menu)
	new_story.grab_focus()

func show_load() -> void:
	clear_menu("LOAD STORY")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440,330)
	column.add_child(scroll)
	var saves := VBoxContainer.new()
	saves.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	saves.add_theme_constant_override("separation",10)
	scroll.add_child(saves)
	for record in StorySession.saved_stories():
		var entry := Button.new()
		entry.text = record.profile.name
		entry.name = "Slot_"+record.id
		entry.custom_minimum_size.y = 52
		entry.pressed.connect(func():
			if not StorySession.load_story(record.id): show_load())
		saves.add_child(entry)
	add_button("Back",show_home)
	if saves.get_child_count() > 0: saves.get_child(0).grab_focus()

func open_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE: open_menu()
