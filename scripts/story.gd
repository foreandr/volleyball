extends Control

func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color("0f1a25")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var title := Label.new()
	title.text = "STORY"
	title.position = Vector2(24,24)
	title.add_theme_font_size_override("font_size",32)
	title.add_theme_color_override("font_color",Color("ffce70"))
	add_child(title)
	var back := Button.new()
	back.text = "Back to menu"
	back.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	back.offset_left = -204
	back.offset_right = -24
	back.offset_top = 24
	back.offset_bottom = 68
	back.pressed.connect(open_menu)
	add_child(back)
	back.grab_focus()

func open_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE: open_menu()
