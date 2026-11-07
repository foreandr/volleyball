extends Control

func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color("102b40")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var title := Label.new()
	title.text = "CREATE"
	title.position = Vector2(32,28)
	title.add_theme_font_size_override("font_size",36)
	title.add_theme_color_override("font_color",Color("ffce70"))
	add_child(title)
	var back := Button.new()
	back.text = "Back to menu"
	back.position = Vector2(1050,28)
	back.custom_minimum_size = Vector2(198,48)
	back.pressed.connect(open_menu)
	add_child(back)
	back.grab_focus()

func open_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE: open_menu()
