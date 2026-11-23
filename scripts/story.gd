extends Control
var column: VBoxContainer

func _ready() -> void:
	column = VBoxContainer.new()
	MenuPresentation.mount_menu(self,column)
	show_home()

func clear_menu(title: String) -> void:
	for child in column.get_children():
		column.remove_child(child)
		child.queue_free()
	MenuPresentation.heading(column,"Career" if title == "CAREER" else "Load career",title)

func add_button(text: String, action: Callable) -> Button:
	var result := Button.new()
	result.name = text.replace(" ","")
	result.text = text
	result.custom_minimum_size.y = 52
	result.pressed.connect(action)
	column.add_child(result)
	return result

func show_home() -> void:
	clear_menu("CAREER")
	var resume := add_button("Continue",func(): StorySession.load_story(StorySession.last_id()))
	resume.disabled = StorySession.last_id().is_empty()
	var new_story := add_button("New",StorySession.begin_new)
	var load_button := add_button("Load",show_load)
	load_button.disabled = StorySession.saved_stories().is_empty()
	add_button("Back",open_menu)
	new_story.grab_focus()

func show_load() -> void:
	clear_menu("LOAD CAREER")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440,330)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	column.add_child(scroll)
	var saves := VBoxContainer.new()
	saves.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	saves.add_theme_constant_override("separation",10)
	scroll.add_child(saves)
	for record in StorySession.saved_stories():
		var entry := Button.new()
		entry.text = record.profile.name
		entry.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		entry.tooltip_text = entry.text
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
	if event.is_action_pressed("ui_cancel"):
		if column.has_node("Continue"): open_menu()
		else: show_home()
