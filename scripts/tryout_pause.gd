extends ColorRect

const Xbox = preload("res://scripts/xbox_controls.gd")
var game
var body := VBoxContainer.new()
var categories := HBoxContainer.new()
var home := VBoxContainer.new()
var attack_setup := VBoxContainer.new()
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
	if practice and "solo_setting" in game and game.solo_setting:
		bar(home,"Sliders",open_sliders)
		if game.has_method("frame_editor_attacker") or game.has_method("frame_editor_blocker"):
			bar(home,"Replay",func():
				hide()
				game.replay_inspector.toggle())
		if game.has_method("edit_approach_frames") and not game.has_method("frame_editor_blocker"):
			dock.add_child(attack_setup)
			attack_setup.hide()
			var map := preload("res://scripts/attack_setup_map.gd").new()
			map.game=game
			attack_setup.add_child(map)
			var play := bar(attack_setup,"Play",func():
				hide()
				game.play_attack_setup())
			bar(attack_setup,"Back",show_home)
			bar(home,"Attack setup",func():
				home.hide()
				attack_setup.show()
				play.grab_focus())
		if game.has_method("frame_editor_blocker") or not game.has_method("frame_editor_attacker"):
			bar(home,"Edit blocker frames" if game.has_method("frame_editor_blocker") else "Edit set frames",open_frame_editor)
	bar(home,"Restart",restart)
	var quit_button := bar(home,"Quit",quit_gameplay)
	primary.focus_neighbor_top=primary.get_path_to(quit_button)
	quit_button.focus_neighbor_bottom=quit_button.get_path_to(primary)
	options.custom_minimum_size.x = 400
	options.add_child(categories)
	var sections := ["Camera","Audio","Controls"]
	if practice and "solo_setting" in game and game.solo_setting: sections.append("Sliders")
	for caption in sections:
		var tab := bar(categories,caption,show_section.bind(caption))
		tab.toggle_mode = true
	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
	scroll.custom_minimum_size.y = 240
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	options.add_child(scroll)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	if not game.has_method("frame_editor_attacker") or game.has_method("frame_editor_blocker"):
		bar(options,"Animation Frames",open_frame_editor)
		StorySession.add_saved_frame_picker(options,leave_for_frame_editor)
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
	attack_setup.hide()
	options.hide()
	home.show()
	primary.grab_focus()

func open_sliders() -> void:
	home.hide()
	options.show()
	show_section("Sliders")
	for control in body.get_children():
		if control is HSlider:
			control.grab_focus()
			break

func attack_blocker_controls() -> void:
	if game.scene_file_path=="res://scenes/attacking_camp.tscn":
		var count := OptionButton.new()
		for text in ["No blockers","1 blocker (right side)","2 blockers (right side + middle)","3 blockers"]: count.add_item(text)
		count.select(game.attack_blocker_count)
		count.item_selected.connect(game.set_attack_blocker_count)
		body.add_child(count)
		for i in 3:
			var title: String=["Right-side vertical","Middle vertical","Left-side vertical"][i]

			var readout := Label.new()
			var vertical := HSlider.new()
			vertical.max_value=60
			vertical.step=1
			vertical.value=game.practice_vertical[i]
			readout.text="%s  %d in" % [title,vertical.value]
			body.add_child(readout)
			body.add_child(vertical)
			vertical.value_changed.connect(func(value):
				game.set_practice_vertical(i,value)
				readout.text="%s  %d in" % [title,value]
			)

func tuning_controls() -> void:
	if "block_vertical" in game:
		var caption := Label.new()
		var slider := HSlider.new()
		slider.min_value=0
		slider.max_value=60
		slider.step=1
		slider.value=game.block_vertical
		caption.text="Block vertical    %d in" % roundi(slider.value)
		body.add_child(caption)
		body.add_child(slider)
		slider.value_changed.connect(func(v):
			game.set_block_vertical(v)
			caption.text="Block vertical    %d in" % roundi(v))
		return
	var timing_label := Label.new()
	timing_label.text="CPU release timing"
	body.add_child(timing_label)
	var timing := OptionButton.new()
	for choice in game.CPU_TIMINGS:
		timing.add_item(choice)
	timing.select(game.cpu_timing_mode)
	timing.item_selected.connect(game.set_cpu_timing_mode)
	body.add_child(timing)
	var athlete = game.setter
	var range_label := Label.new()
	var refresh := func(): range_label.text="Set range    Medium %.1f m    High %.1f m" % [game.camp_range(0),game.camp_range(1)]
	var fields := [["Current stamina",0,100,athlete.stamina.fraction()*100.,"%"],["Stamina",0,100,athlete.stamina.rating,""],["Willpower",0,100,athlete.stamina.willpower,""],["Endurance",0,100,athlete.stamina.endurance,""],["Strength",1,100,athlete.attributes.Strength,""],["Hand setting",0,100,athlete.attributes["Hand setting"],""],["Speed",0,100,athlete.attributes.Speed,""],["Jump height",10,120,game.camp_jump_height*100," cm"],["Jump ability",0,100,game.camp_jump_ability,""]]
	if "set_arc_percent" in game: fields.push_front(["Bell set height",0,3,game.height_preset(),""])
	for field in fields:
		var caption := Label.new()
		body.add_child(caption)
		var slider := HSlider.new()
		slider.name=str(field[0]).replace(" ","")
		slider.min_value=field[1]
		slider.max_value=field[2]
		slider.step=1
		slider.value=field[3]
		slider.custom_minimum_size.y=28
		body.add_child(slider)
		var format_value := func(v: float): caption.text="%s    %d%s" % [field[0],roundi(v),field[4]]
		format_value.call(slider.value)
		slider.value_changed.connect(func(v):
			format_value.call(v)
			match field[0]:
				"Bell set height": game.save_set_height(game.SET_HEIGHTS[int(v)])
				"Current stamina":
					athlete.stamina.value=v*.01*athlete.stamina.capacity()
					athlete.stamina.rested_capacity=maxf(athlete.stamina.rested_capacity,athlete.stamina.value)
					athlete.stamina.exhausted=false
				"Stamina","Endurance","Willpower":
					athlete.attributes[field[0]]=v
					athlete.stamina.set_ratings(athlete.attributes.Stamina,athlete.attributes.Endurance,athlete.attributes.Willpower)
				"Jump height":
					game.camp_jump_height=v*.01
				"Jump ability": game.camp_jump_ability=v
				_: athlete.attributes[field[0]]=v
			refresh.call())
	var arc := OptionButton.new()
	for label_ in game.TEMPOS: arc.add_item(label_+" set")
	arc.select(game.selected_tempo)
	arc.item_selected.connect(func(index): game.selected_tempo=index)
	body.add_child(arc)
	body.add_child(range_label)
	refresh.call()

func open_options() -> void:
	home.hide()
	options.show()
	show_section("Camera")
	categories.get_child(0).grab_focus()

func open_frame_editor() -> void:
	if practice and game.has_method("frame_editor_attacker"):
		game.replay_inspector.edit_setter_frames()
	elif practice and "solo_setting" in game and game.solo_setting and (game.replay_inspector.setter_frames.size()>1 or not game.replay_inspector.previous_set.is_empty()):
		game.replay_inspector.edit_setter_frames()
	else:
		StorySession.prepare_ready_frame_editor()
	leave_for_frame_editor()
	MenuPresentation.load_scene("res://scenes/animation_editor.tscn")

func leave_for_frame_editor() -> void:
	StorySession.frame_editor_origin=get_tree().current_scene.scene_file_path
	hide()

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
			if (options.visible or attack_setup.is_visible_in_tree()) and not menu: show_home()
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
	if not practice: return [["Field of view",35,85,50,"Ã‚Â°"],["Master volume",0,100,80,"%"]]
	return [["Camera orbit",-145,145,12,"\u00b0"],["Elevation",-12,82,18,"\u00b0"],["Distance",2,26,10," m"],["Master volume",0,100,80,"%"]]

func saved(field: Array) -> float:
	if field[0]=="Field of view" and active_camera(): return active_camera().fov
	if field[0]=="Master volume": return StorySession.master_volume
	return StorySession.game_options.get_value("tryout_camera",field[0],field[3])

func apply_field(key: String,value: float,save: bool) -> void:
	match key:
		"Field of view":
			if active_camera(): active_camera().fov = value
		"Camera orbit": game.yaw = deg_to_rad(value)
		"Elevation": game.elevation = value
		"Distance": game.distance = value
		"Master volume": StorySession.set_master_volume(value)
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
	if caption=="Sliders":
		attack_blocker_controls()
		tuning_controls()
		return
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
