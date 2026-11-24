extends ColorRect

signal dismissed

func _ready() -> void:
	z_index=12
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color=Color("07151de8")
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",12)
	center.add_child(column)
	var title := Label.new()
	title.text="Reading the net"
	title.add_theme_font_size_override("font_size",34)
	column.add_child(title)
	var note := Label.new()
	note.text="The first digit calls one of seven spots along the net. The second calls the set height."
	column.add_child(note)
	var diagram := Control.new()
	diagram.custom_minimum_size=Vector2(660,245)
	column.add_child(diagram)
	diagram.draw.connect(func(): draw_diagram(diagram))
	var tip := Label.new()
	tip.text="Start with a high ball. Move RS down or sideways for medium, or up for high."
	column.add_child(tip)
	var actions := HBoxContainer.new()
	column.add_child(actions)
	var button := Button.new()
	button.icon=preload("res://scripts/xbox_controls.gd").glyph(JOY_BUTTON_A)
	button.add_theme_constant_override("icon_max_width",38)
	button.tooltip_text="Continue"
	button.custom_minimum_size=Vector2(62,40)
	actions.add_child(button)
	button.pressed.connect(func(): dismissed.emit())
	button.grab_focus()

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed and event.button_index==preload("res://scripts/xbox_controls.gd").physical(JOY_BUTTON_A):
		get_viewport().set_input_as_handled()
		dismissed.emit()

func draw_diagram(view: Control) -> void:
	var font := ThemeDB.fallback_font
	var teal := Color("83e0c3")
	for i in 7:
		var x := 8.+i*92.
		view.draw_rect(Rect2(x,39,91,45),Color("234557"))
		for n in 7: view.draw_line(Vector2(x+n*14,39),Vector2(x+n*14,84),Color("466275"))
		for n in 4: view.draw_line(Vector2(x,40+n*14),Vector2(x+91,40+n*14),Color("466275"))
		view.draw_string(font,Vector2(x,29),str(i+1),HORIZONTAL_ALIGNMENT_CENTER,91,19,Color.WHITE)
		if i in [0,2,6]:
			var call := {0:"10",2:"32",6:"72"}
			view.draw_string(font,Vector2(x,110),call[i],HORIZONTAL_ALIGNMENT_CENTER,91,21,teal)
	view.draw_line(Vector2(8,39),Vector2(651,39),Color.WHITE,3.)
	for i in 2:
		var x := 75.+i*282.
		var pts := PackedVector2Array()
		for tick in 33:
			var t := tick/32.
			pts.append(Vector2(x+t*194.,208.-[54.,84.][i]*4.*t*(1.-t)))
		view.draw_polyline(pts,teal if i==1 else Color("9bb3bf"),2.5,true)
		view.draw_circle(pts[-1],3.5,Color.WHITE)
		view.draw_string(font,Vector2(x,237),["Medium","High"][i],HORIZONTAL_ALIGNMENT_CENTER,194,17,Color.WHITE)
