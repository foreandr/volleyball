extends ColorRect

const Xbox = preload("res://scripts/xbox_controls.gd")
var game
var body := VBoxContainer.new()
var categories := HBoxContainer.new()
var home := VBoxContainer.new()
var options := VBoxContainer.new()
var primary: Button
var options_button: Button
var practice := false
var section := "Camera"
var panel_was_visible := false

func configure(host: Node, layer: Node = null) -> void:
	game = host
	practice = host.has_method("reset_drill")
	(layer if layer else host).add_child(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 110
	process_mode = Node.PROCESS_MODE_ALWAYS
	color = Color("06121bc8")
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dock := PanelContainer.new()
	dock.add_theme_stylebox_override("panel",MenuPresentation.box(Color("102431f7"),Color("66d8bc"),3))
	center.add_child(dock)
	dock.add_child(home)
	dock.add_child(options)
	home.custom_minimum_size.x = 310
	home.add_theme_constant_override("separation",8)
	primary = bar(home,"Resume",hide)
	options_button = bar(home,"Options",open_options)
	bar(home,"Restart",restart)
	bar(home,"Quit",quit_gameplay)
	options.custom_minimum_size.x = 400
	options.add_child(categories)
	for caption in ["Camera","Audio","Controls"]:
		var tab := bar(categories,caption,show_section.bind(caption))
		tab.toggle_mode = true
	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
	scroll.custom_minimum_size.y = 240
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	options.add_child(scroll)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	bar(options,"Back",show_home)
	if practice:
		for field in fields(): apply_field(field[0],saved(field),false)
	hide()
	visibility_changed.connect(func():
		if visible:
			if practice:
				panel_was_visible = game.panel.visible
				game.panel.hide()
			get_tree().paused = true
			show_home()
		else:
			get_tree().paused = false
			if practice:
				game.panel.visible = panel_was_visible
				game.prompt_phase = ""
				game.update_prompts(game.phase)
				if game.phase == "complete":
					if game.finish.disabled: game.retry.grab_focus()
					else: game.finish.grab_focus())

func bar(parent: Container, caption: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size.y = 44
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(button)
	button.pressed.connect(action)
	return button

func show_home() -> void:
	options.hide()
	home.show()
	primary.grab_focus()

func open_options() -> void:
	home.hide()
	options.show()
	show_section("Camera")
	categories.get_child(0).grab_focus()

func restart() -> void:
	hide()
	if practice: game.reset_drill()
	elif game.has_method("open_setting_stage") and is_instance_valid(game.setting_stage):
		var drill_name: String = game.heading.text
		game.go_back()
		game.open_setting_stage(drill_name)
	elif game.has_method("restart_activity"): game.restart_activity()
	else: MenuPresentation.load_scene(game.scene_file_path)

func quit_gameplay() -> void:
	hide()
	MenuPresentation.load_scene("res://scenes/main.tscn")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo: return
	var menu: bool = event is InputEventJoypadButton and event.button_index == Xbox.physical(JOY_BUTTON_START) and event.pressed
	var escape: bool = event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed
	if visible:
		if menu or event.is_action_pressed("ui_cancel"):
			if options.visible and not menu: show_home()
			else: hide()
			get_viewport().set_input_as_handled()
	elif not practice and not get_tree().paused and (menu or escape):
		if game.has_method("open_setting_stage") and not is_instance_valid(game.setting_stage): return
		show()
		get_viewport().set_input_as_handled()

func active_camera() -> Camera3D:
	for key in ["setting_camera","preview_camera","camera"]:
		if key in game and is_instance_valid(game.get(key)): return game.get(key)
	return get_viewport().get_camera_3d()

func fields() -> Array:
	if not practice: return [["Field of view",35,85,50,"°"],["Master volume",0,100,80,"%"]]
	return [["Camera orbit",-145,145,12,"°"],["Elevation",-12,82,18,"°"],["Distance",2,26,10," m"],["Master volume",0,100,80,"%"]]

func saved(field: Array) -> float:
	if field[0]=="Field of view" and active_camera(): return active_camera().fov
	if field[0]=="Master volume": return db_to_linear(AudioServer.get_bus_volume_db(0))*100
	return StorySession.game_options.get_value("tryout_camera",field[0],field[3])

func apply_field(key: String,value: float,save: bool) -> void:
	match key:
		"Field of view":
			if active_camera(): active_camera().fov = value
		"Camera orbit": game.yaw = deg_to_rad(value)
		"Elevation": game.elevation = value
		"Distance": game.distance = value
		"Master volume": AudioServer.set_bus_volume_db(0,linear_to_db(value/100))
	if practice: game.apply_camera()
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
