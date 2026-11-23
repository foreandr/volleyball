extends Control

var roster_pool: Array[Dictionary] = []
var column := VBoxContainer.new()

func _ready() -> void:
	if not StorySession.play_launch_consumed and "--play-match" in OS.get_cmdline_user_args():
		StorySession.play_launch_consumed = true
		open_match(true)
		return
	StorySession.ensure_background_training()
	if not StorySession.demo_launch_consumed and "--demo-match" in OS.get_cmdline_user_args():
		StorySession.demo_launch_consumed = true
		open_simulation()
		return

	var background := ColorRect.new()
	background.color = Color("102b40")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	column.custom_minimum_size.x = 380
	column.add_theme_constant_override("separation",8)
	center.add_child(column)
	show_home()

func page(title_text: String) -> void:
	for child in column.get_children():
		column.remove_child(child)
		child.queue_free()
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size",44)
	title.add_theme_color_override("font_color",Color("ffce70"))
	column.add_child(title)

func go(scene: String) -> void:
	get_tree().change_scene_to_file("res://scenes/%s.tscn" % scene)

func show_home() -> void:
	page("VOLLEYBALL")
	add_menu_button(column,"Career","Career",func(): go("story"))
	add_menu_button(column,"Play","Play",show_play).grab_focus()
	add_menu_button(column,"Create","Create player",func(): go("create"))
	add_menu_button(column,"Training","Training camp",func(): go("drills"))
	add_menu_button(column,"Settings","Settings",show_settings)
	add_menu_button(column,"Quit","Quit",func(): get_tree().quit())

func show_play() -> void:
	page("PLAY")
	add_menu_button(column,"Offline","Offline",show_offline).grab_focus()
	add_menu_button(column,"Online","Online",Callable()).disabled = true
	add_menu_button(column,"Simulate","Simulate",open_simulation)
	add_menu_button(column,"Back","Back",show_home)

func show_offline() -> void:
	page("OFFLINE")
	for size in range(2,7):
		var item := add_menu_button(column,"Size%d" % size,"%dv%d" % [size,size],func():
			StorySession.offline_size = size
			show_roster())
		if size == 2: item.grab_focus()
	add_menu_button(column,"Back","Back",show_play)

func show_roster() -> void:
	page("MATCH SETUP")
	var profile_source = preload("res://scripts/player_profile.gd")
	if roster_pool.is_empty():
		roster_pool.append(profile_source.load_profile())
		for i in 48: roster_pool.append(profile_source.generate())
	StorySession.offline_roster.clear()
	var teams := HBoxContainer.new()
	column.add_child(teams)
	for side in 2:
		var slots := VBoxContainer.new()
		teams.add_child(slots)
		var color := ColorPickerButton.new()
		color.text = "Home kit" if side == 0 else "Away kit"
		color.color = StorySession.kit_colors[side]
		color.color_changed.connect(func(value: Color): StorySession.kit_colors[side] = value)
		slots.add_child(color)
		for slot in StorySession.offline_size:
			var index := side*StorySession.offline_size + slot
			var choice := OptionButton.new()
			for candidate in roster_pool:
				choice.add_item("%s   %d in" % [candidate.name,roundi(candidate.height_cm/2.54)])
			choice.select(index)
			StorySession.offline_roster.append(roster_pool[index].duplicate(true))
			slots.add_child(choice)
			var height := SpinBox.new()
			height.min_value = 60
			height.max_value = 84
			height.suffix = "in"
			height.value = roundi(roster_pool[index].height_cm / 2.54)
			slots.add_child(height)
			height.value_changed.connect(func(value: float): StorySession.offline_roster[index].height_cm = value*2.54)
			choice.item_selected.connect(func(selected: int):
				StorySession.offline_roster[index] = roster_pool[selected].duplicate(true)
				height.value = roundi(roster_pool[selected].height_cm/2.54))
	add_menu_button(column,"Start","Start match",func(): open_match(true)).grab_focus()
	add_menu_button(column,"Back","Back",show_offline)

func show_settings() -> void:
	page("SETTINGS")
	var volume := HSlider.new()
	var caption := Label.new()
	caption.text = "Master volume"
	column.add_child(caption)
	volume.max_value = 100
	volume.value = db_to_linear(AudioServer.get_bus_volume_db(0))*100
	volume.value_changed.connect(func(value: float): AudioServer.set_bus_volume_db(0,linear_to_db(value/100.0)))
	column.add_child(volume)
	volume.grab_focus()
	volume.drag_ended.connect(func(_changed: bool): StorySession.save_options())
	var names := ["Serve / jump / block","Forearm receive","Hand receive","Back"]
	for i in names.size():
		var choice := OptionButton.new()
		for key in ["A","B","X","Y"]:
			choice.add_item("%s   %s" % [names[i],key])
		choice.select(StorySession.pad_bindings[i])
		column.add_child(choice)
		choice.item_selected.connect(func(selected: int):
			var other := StorySession.pad_bindings.find(selected)
			StorySession.pad_bindings[other] = StorySession.pad_bindings[i]
			StorySession.pad_bindings[i] = selected
			StorySession.save_options()
			show_settings())
	add_menu_button(column,"IterationLab","Iteration Lab",func(): go("iteration_lab"))
	add_menu_button(column,"Back","Back",show_home)

func add_menu_button(parent: VBoxContainer, id: String, title: String, action: Callable) -> Button:
	var item := Button.new()
	item.name = id
	item.text = title
	item.custom_minimum_size.y = 56
	if action.is_valid(): item.pressed.connect(action)
	parent.add_child(item)
	return item

func open_simulation() -> void:
	open_match(false)

func open_match(playable: bool) -> void:
	StorySession.open_home_play = playable
	StorySession.open_home_simulation = true
	get_tree().change_scene_to_file.call_deferred("res://scenes/story_animations.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
