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

	MenuPresentation.mount_menu(self,column)
	MenuPresentation.set_music(true)
	open_page(MenuPresentation.return_page)

var route := "Home"

func open_page(target: String) -> void:
	match target:
		"Play": show_play()
		"Offline": show_offline()
		"Match setup": show_roster()
		"Settings": show_settings()
		_: show_home()

func page(title_text: String, current: String) -> void:
	route = current
	MenuPresentation.return_page = current
	for child in column.get_children():
		column.remove_child(child)
		child.queue_free()
	MenuPresentation.heading(column,current,title_text)

func go(scene: String) -> void:
	MenuPresentation.load_scene("res://scenes/%s.tscn" % scene)

func show_home() -> void:
	page("Andre Foreman's Volleyball","Home")
	add_menu_button(column,"Career","My Career",func(): go("story")).grab_focus()
	add_menu_button(column,"Play","Play",MenuPresentation.load_stage.bind("Play",show_play))
	add_menu_button(column,"Create","Create player",func(): go("create"))
	add_menu_button(column,"Settings","Settings",MenuPresentation.load_stage.bind("Settings",show_settings))
	add_menu_button(column,"Quit","Quit",func(): get_tree().quit())

func show_play() -> void:
	page("PLAY","Play")
	add_menu_button(column,"Offline","Offline",MenuPresentation.load_stage.bind("Offline",show_offline)).grab_focus()
	add_menu_button(column,"Online","Online",Callable()).disabled = true
	add_menu_button(column,"Simulate","Simulate",open_simulation)
	add_menu_button(column,"Back","Back",show_home)

func show_offline() -> void:
	page("OFFLINE","Offline")
	for size in range(2,7):
		var item := add_menu_button(column,"Size%d" % size,"%dv%d" % [size,size],func():
			StorySession.offline_size = size
			MenuPresentation.load_stage("Match setup",show_roster))
		if size == 2: item.grab_focus()
	add_menu_button(column,"Back","Back",show_play)

func show_roster() -> void:
	page("MATCH SETUP","Match setup")
	var profile_source = preload("res://scripts/player_profile.gd")
	if roster_pool.is_empty():
		roster_pool.append(profile_source.load_profile())
		if CareerSession.data.has_section("athletes"):
			for id in CareerSession.data.get_section_keys("athletes"):
				roster_pool.append(CareerSession.data.get_value("athletes",id))
		for i in 48: roster_pool.append(profile_source.generate())
	StorySession.offline_roster.clear()
	var ball_choice := OptionButton.new()
	ball_choice.name = "MatchBall"
	var brands := preload("res://scripts/animation_ball_preview.gd").BALL_PALETTES.keys()
	for brand in brands: ball_choice.add_item("Ball: "+str(brand))
	ball_choice.select(maxi(0,brands.find(StorySession.match_preference("ball_brand","Mikasa"))))
	ball_choice.item_selected.connect(func(index: int): StorySession.save_match_preference("ball_brand",brands[index]))
	column.add_child(ball_choice)
	var teams := HBoxContainer.new()
	column.add_child(teams)
	for side in 2:
		var slots := VBoxContainer.new()
		var panel := PanelContainer.new()
		panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var accent: Color=Color("66dfc1") if side==0 else Color("efbc74")
		panel.add_theme_stylebox_override("panel",MenuPresentation.box(Color("101f2af5"),accent,4))
		teams.add_child(panel)
		panel.add_child(slots)
		MenuPresentation.section_label(slots,"Home" if side==0 else "Away")
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
			var row := HBoxContainer.new()
			slots.add_child(row)
			choice.fit_to_longest_item=false
			choice.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			row.add_child(choice)
			var height := SpinBox.new()
			height.min_value = 60
			height.max_value = 84
			height.suffix = "in"
			height.value = roundi(roster_pool[index].height_cm / 2.54)
			row.add_child(height)
			height.value_changed.connect(func(value: float): StorySession.offline_roster[index].height_cm = value*2.54)
			choice.item_selected.connect(func(selected: int):
				StorySession.offline_roster[index] = roster_pool[selected].duplicate(true)
				height.value = roundi(roster_pool[selected].height_cm/2.54))
	add_menu_button(column,"Start","Start match",func(): open_match(true)).grab_focus()
	add_menu_button(column,"Back","Back",show_offline)

func show_settings() -> void:
	page("SETTINGS","Settings")
	MenuPresentation.section_label(column,"Audio")
	var volume := HSlider.new()
	var caption := Label.new()
	caption.text = "Master volume    %d%%" % StorySession.master_volume
	column.add_child(caption)
	volume.max_value = 100
	volume.value = StorySession.master_volume
	volume.value_changed.connect(func(value: float):
		caption.text="Master volume    %d%%" % roundi(value)
		StorySession.set_master_volume(value)
		StorySession.save_options())
	column.add_child(volume)
	volume.grab_focus()
	MenuPresentation.audio_options(column)
	MenuPresentation.section_label(column,"Controller")
	preload("res://scripts/xbox_controls.gd").settings(column,show_settings)
	add_menu_button(column,"Back","Back",show_home)

func add_menu_button(parent: VBoxContainer, id: String, title: String, action: Callable) -> Button:
	var item := Button.new()
	item.add_theme_font_size_override("font_size",23 if route=="Home" else 20)
	item.name = id
	item.text = title
	item.alignment = HORIZONTAL_ALIGNMENT_LEFT
	item.custom_minimum_size.y = 51
	if action.is_valid(): item.pressed.connect(action)
	parent.add_child(item)
	return item

func open_simulation() -> void:
	open_match(false)

func open_match(playable: bool) -> void:
	StorySession.open_home_play = playable
	StorySession.open_home_simulation = true
	MenuPresentation.load_scene.call_deferred("res://scenes/story_animations.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if route != "Home": open_page(MenuPresentation.PARENTS.get(route,"Home"))
