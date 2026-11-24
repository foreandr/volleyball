extends ColorRect

const Xbox = preload("res://scripts/xbox_controls.gd")
var game: Control
var body := VBoxContainer.new()
var categories := HBoxContainer.new()
var section := "Camera"
var primary := Button.new()
var dock := PanelContainer.new()

func configure(host: Control) -> void:
	game = host
	host.add_child(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color("04101946")
	dock.anchor_bottom = 1
	dock.offset_right = 450
	var style := StyleBoxFlat.new()
	style.bg_color = Color("102431f6")
	style.border_color = Color("66d8bc")
	style.border_width_right = 2
	style.content_margin_left = 32
	style.content_margin_right = 30
	style.content_margin_top = 30
	style.content_margin_bottom = 24
	dock.add_theme_stylebox_override("panel",style)
	add_child(dock)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",14)
	dock.add_child(column)
	var sport := Label.new()
	sport.text = "MY CAREER    /    SETTER TRYOUT"
	sport.add_theme_font_size_override("font_size",14)
	sport.modulate = Color("80dfc9")
	column.add_child(sport)
	var title := Label.new()
	title.text = "Practice paused"
	title.add_theme_font_size_override("font_size",38)
	column.add_child(title)
	column.add_child(categories)
	for caption in ["Camera","Audio","Controls"]:
		var tab := Button.new()
		tab.text = caption
		tab.toggle_mode = true
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		categories.add_child(tab)
		tab.pressed.connect(show_section.bind(caption))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",12)
	scroll.add_child(body)
	primary.text = "Resume practice"
	primary.custom_minimum_size.y = 46
	primary.pressed.connect(hide)
	column.add_child(primary)
	var actions := HBoxContainer.new()
	column.add_child(actions)
	for caption in ["Watch demo","Recordings","My Career"]:
		var item := Button.new()
		item.text = caption
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(item)
		item.pressed.connect(func():
			if caption=="Recordings":
				OS.shell_open(ProjectSettings.globalize_path("user://recordings"))
				return
			hide()
			if caption == "My Career": game.leave()
			else:
				game.skip.hide()
				game.finish.hide()
				game.demonstration = true
				game.demo_index = 0
				game.reset_feed())
	for field in fields():
		apply_field(field[0],saved(field),false)
	hide()
	visibility_changed.connect(func():
		game.panel.visible = not visible
		if visible:
			show_section(section)
			primary.grab_focus()
		else:
			game.prompt_phase = ""
			game.update_prompts(game.phase)
			if game.phase=="complete": game.finish.grab_focus())

func fields() -> Array:
	return [["Camera orbit",-145,145,12,"°"],["Elevation",-12,82,18,"°"],["Distance",2,26,10," m"],["Master volume",0,100,80,"%"]]

func saved(field: Array) -> float:
	if field[0]=="Master volume": return db_to_linear(AudioServer.get_bus_volume_db(0))*100
	return StorySession.game_options.get_value("tryout_camera",field[0],field[3])

func apply_field(key: String,value: float,save: bool) -> void:
	match key:
		"Camera orbit": game.yaw = deg_to_rad(value)
		"Elevation": game.elevation = value
		"Distance": game.distance = value
		"Master volume": AudioServer.set_bus_volume_db(0,linear_to_db(value/100))
	game.apply_camera()
	if save:
		StorySession.game_options.set_value("tryout_camera",key,value)
		StorySession.save_options()

func show_section(caption: String) -> void:
	section = caption
	for tab in categories.get_children(): tab.set_pressed_no_signal(tab.text==caption)
	for item in body.get_children():
		body.remove_child(item)
		item.queue_free()
	if caption=="Controls":
		Xbox.settings(body,show_section.bind(caption))
		return
	for field in fields():
		if (field[0]=="Master volume") != (caption=="Audio"): continue
		var row := HBoxContainer.new()
		body.add_child(row)
		var label := Label.new()
		label.text = field[0]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var value := Label.new()
		value.modulate = Color("8aebd5")
		row.add_child(value)
		var slider := HSlider.new()
		slider.min_value = field[1]
		slider.max_value = field[2]
		slider.step = .25 if field[0]=="Distance" else 1.
		slider.value = saved(field)
		slider.custom_minimum_size.y = 32
		body.add_child(slider)
		var rail := StyleBoxFlat.new()
		rail.bg_color = Color("344959")
		rail.content_margin_top = 2
		rail.content_margin_bottom = 2
		slider.add_theme_stylebox_override("slider",rail)
		var fill := rail.duplicate() as StyleBoxFlat
		fill.bg_color = Color("63cbb2")
		slider.add_theme_stylebox_override("grabber_area",fill)
		slider.add_theme_stylebox_override("grabber_area_highlight",fill)
		var format_value := func(v: float): value.text = ("%.2f" % v if field[0]=="Distance" else str(roundi(v)))+str(field[4])
		format_value.call(slider.value)
		slider.value_changed.connect(func(v):
			format_value.call(v)
			apply_field(field[0],v,true))
