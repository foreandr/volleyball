extends Control

const Xbox = preload("res://scripts/xbox_controls.gd")
const Setup = preload("res://scripts/exhibition_setup.gd")
const SETTINGS := ["Sound","Video","Controls","Clips"]
var column := VBoxContainer.new()
var route := "Home"
var tab_index := 0
var setup: VBoxContainer
var sound_panel: VBoxContainer
var held_triggers := {}
var chooser: FileDialog
var import_status: Label

func _ready() -> void:
	if not StorySession.play_launch_consumed and "--play-match" in OS.get_cmdline_user_args():
		StorySession.play_launch_consumed = true
		show_initial_match.call_deferred()
		return
	StorySession.ensure_background_training()
	if not StorySession.demo_launch_consumed and "--demo-match" in OS.get_cmdline_user_args():
		StorySession.demo_launch_consumed = true
		StorySession.open_home_play=false
		StorySession.open_home_simulation=true
		MenuPresentation.load_scene.call_deferred("res://scenes/story_animations.tscn")
		return
	MenuPresentation.mount_menu(self,column)
	MenuPresentation.set_music(true)
	MenuPresentation.highlights.import_finished.connect(report_import)
	open_page(MenuPresentation.return_page)

func show_initial_match() -> void:
	MenuPresentation.mount_menu(self,column)
	show_roster()
	setup.launch()

func open_page(target: String) -> void:
	match target:
		"Play": show_play()
		"Offline","Match setup": show_roster()
		"Settings": show_settings()
		_: show_home()

func page(title: String, current: String) -> void:
	route=current
	for film in get_tree().get_nodes_in_group("menu_reel_surface"):
		if is_ancestor_of(film): film.visible=(current!="Match setup")
	MenuPresentation.return_page=current
	for child in column.get_children():
		column.remove_child(child)
		child.queue_free()
	setup=null
	MenuPresentation.heading(column,current,title)

func go(scene: String) -> void:
	MenuPresentation.load_scene("res://scenes/%s.tscn"%scene)

func show_home() -> void:
	page("Volleyball","Home")
	add_menu_button(column,"Career","My Career",go.bind("story")).grab_focus()
	add_menu_button(column,"Play","Play",show_play)
	add_menu_button(column,"Create","Create player",go.bind("create"))
	add_menu_button(column,"Settings","Settings",show_settings)
	add_menu_button(column,"Quit","Quit",get_tree().quit)

func show_play() -> void:
	page("Play","Play")
	add_menu_button(column,"Offline","Offline",show_roster).grab_focus()
	add_menu_button(column,"Online","Online",Callable()).disabled=true
	add_menu_button(column,"Back","Back",show_home)

func show_roster() -> void:
	page("Offline match","Match setup")
	setup=Setup.new()
	column.add_child(setup)
	setup.configure(go.bind("offline_match"),show_play)
	section_prompts(true)

func section_prompts(random:bool) -> void:
	var prompts:HBoxContainer=column.get_meta("prompts")
	if Xbox.keyboard_prompts():
		for c in prompts.get_children():
			prompts.remove_child(c)
			c.queue_free()
		var label:=Label.new()
		label.text="Enter   Select       Esc   Back       "+("       R   Random" if random else "")
		prompts.add_child(label)
	else:
		var actions: Array=[[JOY_BUTTON_A,"Select"],[JOY_BUTTON_B,"Back"],["LT","Previous"],["RT","Next"]]
		if random: actions.append([JOY_BUTTON_Y,"Random"])
		if route=="Match setup": actions=actions.filter(func(item): return item[0] not in ["LT","RT"])
		Xbox.prompts(prompts,actions)

func show_settings() -> void:
	page("Settings","Settings")
	section_prompts(false)
	var tabs:=HBoxContainer.new()
	column.add_child(tabs)
	for i in SETTINGS.size():
		var btn:=add_menu_button(tabs,"Tab%d"%i,SETTINGS[i],select_tab.bind(i))
		btn.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		btn.alignment=HORIZONTAL_ALIGNMENT_CENTER
		btn.toggle_mode=true
		btn.set_pressed_no_signal(i==tab_index)
		if i==tab_index: btn.grab_focus()
	var panel:=PanelContainer.new()
	column.add_child(panel)
	sound_panel=VBoxContainer.new()
	sound_panel.add_theme_constant_override("separation",8)
	panel.add_child(sound_panel)
	match tab_index:
		0:
			slider("Master volume",StorySession.master_volume,func(v):
				StorySession.set_master_volume(v)
				StorySession.save_options())
			slider("Menu clicks",StorySession.game_options.get_value("audio","menu_clicks",85),func(v):
				MenuPresentation.set_navigation_level(v)
				option("audio","menu_clicks",v)
				MenuPresentation.navigation.play())
			slider("Music level",StorySession.game_options.get_value("audio","music_level",65),func(v):
				MenuPresentation.set_music_level(v)
				option("audio","music_level",v))
			MenuPresentation.audio_options(sound_panel)
			add_menu_button(sound_panel,"TestSound","Test navigation sound",func(): MenuPresentation.navigation.play())
		1:
			ContactTiming.speed_options(sound_panel)
			var mode:=CheckButton.new()
			mode.text="Fullscreen"
			mode.button_pressed=DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN,DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
			sound_panel.add_child(mode)
			mode.toggled.connect(func(on):
				option("video","fullscreen",on)
				StorySession.apply_video_options())
			var sync:=CheckButton.new()
			sync.text="Vertical sync"
			sync.button_pressed=DisplayServer.window_get_vsync_mode()!=DisplayServer.VSYNC_DISABLED
			sound_panel.add_child(sync)
			sync.toggled.connect(func(on):
				option("video","vsync",on)
				StorySession.apply_video_options())
		2: Xbox.settings(sound_panel,show_settings)
		3: clip_settings()
	add_menu_button(column,"Back","Back",show_home)

func option(group:String,key:String,value:Variant) -> void:
	StorySession.game_options.set_value(group,key,value)
	StorySession.save_options()

func select_tab(i:int) -> void:
	tab_index=posmod(i,SETTINGS.size())
	show_settings()

func slider(title:String,value:float,change:Callable) -> void:
	var row:=HBoxContainer.new()
	sound_panel.add_child(row)
	var name_label:=Label.new()
	name_label.text=title
	name_label.custom_minimum_size.x=160
	row.add_child(name_label)
	var control:=HSlider.new()
	control.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	control.value=value
	control.step=1
	row.add_child(control)
	var readout:=Label.new()
	readout.custom_minimum_size.x=50
	readout.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	readout.text="%d%%"%int(value)
	row.add_child(readout)
	control.value_changed.connect(func(v):
		readout.text="%d%%"%roundi(v)
		change.call(v))

func clip_settings() -> void:
	var library=MenuPresentation.highlights
	var count:=MenuPresentation.section_label(sound_panel,"Menu rotation   ·   %d selected"%library.rotation.size())
	for id in library.entries:
		var row:=HBoxContainer.new()
		sound_panel.add_child(row)
		var still:Texture2D
		if library.TITLES.has(id): still=load("res://assets/menu/highlights/%s.jpg"%id)
		else:
			var path:String=library.entries[id].get("poster","")
			if not path.is_empty() and FileAccess.file_exists(path):
				var frame:=Image.load_from_file(path)
				if frame and not frame.is_empty(): still=ImageTexture.create_from_image(frame)
		if still:
			var image:=TextureRect.new()
			image.texture=still
			image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
			image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
			image.custom_minimum_size=Vector2(80,45)
			row.add_child(image)
		var toggle:=CheckButton.new()
		toggle.text=library.entries[id].title
		toggle.button_pressed=library.rotation.has(id)
		toggle.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		toggle.toggled.connect(func(on):
			library.include_clip(id,on)
			count.text="MENU ROTATION   ·   %d SELECTED"%library.rotation.size())
		row.add_child(toggle)
		add_menu_button(row,"Preview","Preview",preview_clip.bind(id))
		if not library.TITLES.has(id):
			add_menu_button(row,"Remove","Remove",func():
				library.remove_custom(id)
				show_settings())
	var import_button:=add_menu_button(sound_panel,"Import","Add video clip…",open_chooser)
	import_button.disabled=library.import_job>=0
	import_status=Label.new()
	import_status.text="Importing clip…" if import_button.disabled else ""
	import_status.visible=import_button.disabled
	sound_panel.add_child(import_status)

func preview_clip(id:String) -> void:
	var dialog:=AcceptDialog.new()
	dialog.title=MenuPresentation.highlights.entries[id].title
	dialog.ok_button_text="Close"
	add_child(dialog)
	var movie:=VideoStreamPlayer.new()
	movie.expand=true
	movie.loop=true
	movie.volume_db=-80.
	movie.custom_minimum_size=Vector2(640,360)
	var stream:=VideoStreamTheora.new()
	stream.file=MenuPresentation.highlights.entries[id].file
	movie.stream=stream
	dialog.add_child(movie)
	dialog.close_requested.connect(dialog.queue_free)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()
	movie.play()

func open_chooser() -> void:
	if not is_instance_valid(chooser):
		chooser=FileDialog.new()
		chooser.title="Add video clip"
		chooser.file_mode=FileDialog.FILE_MODE_OPEN_FILE
		chooser.access=FileDialog.ACCESS_FILESYSTEM
		chooser.filters=PackedStringArray(["*.ogv ; Ogg Theora video"])
		if not MenuPresentation.highlights.converter().is_empty():
			chooser.filters=PackedStringArray(["*.ogv,*.mp4,*.mov,*.avi,*.webm,*.mkv ; Video clips"])
		add_child(chooser)
		chooser.file_selected.connect(func(path):
			MenuPresentation.highlights.import_clip(path)
			if MenuPresentation.highlights.import_job>=0: show_settings())
	chooser.popup_centered_ratio(.76)

func report_import(message:String) -> void:
	if route=="Settings" and tab_index==3:
		show_settings()
		import_status.text=message
		import_status.show()

func add_menu_button(parent:Container,id:String,title:String,fn:Callable) -> Button:
	var b:=Button.new()
	b.name=id
	b.text=title
	b.alignment=HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size",23 if route=="Home" else 18)
	b.custom_minimum_size.y=51 if route=="Home" else 36
	if fn.is_valid(): b.pressed.connect(fn)
	parent.add_child(b)
	return b

func _input(event:InputEvent) -> void:
	if event is InputEventJoypadMotion:
		var key:=Vector2i(event.device,event.axis)
		if event.axis_value<.3: held_triggers.erase(key)
		elif event.axis in [Xbox.trigger(true),Xbox.trigger(false)] and event.axis_value>.65 and not held_triggers.has(key):
			held_triggers[key]=true
			if change_section(1 if event.axis==Xbox.trigger(false) else -1):
				get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_PAGEUP,KEY_PAGEDOWN]:
		if change_section(1 if event.keycode==KEY_PAGEDOWN else -1): get_viewport().set_input_as_handled()
	var random_button:bool=event is InputEventJoypadButton and event.pressed and event.button_index==Xbox.physical(JOY_BUTTON_Y)
	var random_key:bool=event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_R
	if route=="Match setup" and (random_button or random_key):
		setup.randomize_selection()
		get_viewport().set_input_as_handled()

func change_section(direction:int) -> bool:
	if is_instance_valid(MenuPresentation.loading_screen): return false
	if route=="Settings": select_tab(tab_index+direction)
	elif route=="Match setup": return false
	else: return false
	return true

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and route!="Home":
		if route=="Match setup": setup.go_back()
		else: open_page(MenuPresentation.PARENTS.get(route,"Home"))
		get_viewport().set_input_as_handled()
