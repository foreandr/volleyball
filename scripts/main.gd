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
	column.add_theme_constant_override("separation",32)
	center.add_child(column)
	var title := Label.new()
	title.text = "VOLLEYBALL"
	title.add_theme_font_size_override("font_size",72)
	title.add_theme_color_override("font_color",Color("ffce70"))
	column.add_child(title)
	var quit := Button.new()
	quit.text = "Quit"
	quit.custom_minimum_size.y = 48
	quit.pressed.connect(func(): get_tree().quit())
	column.add_child(quit)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()
