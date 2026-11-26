extends Control

const Replay = preload("res://scripts/match_replay.gd")

const CATEGORIES := {
	"Passing": [{"title":"Pass to Target","scene":"res://scenes/story_animations.tscn"}],
	"Setting": [{"title":"Set to Target","scene":"res://scenes/setting_camp.tscn"}],
	"Attacking": [{"title":"Approach and Spike","scene":"res://scenes/attacking_camp.tscn"},{"title":"Butterfly"}],
	"Serving": [{"title":"Serve and Receive","scene":"res://scenes/serving_camp.tscn"},{"title":"Spin Serve"}],
	"Digging": [{"title":"Dig from Five","scene":"res://scenes/digging_camp.tscn"}],
	"Blocking": [{"title":"Block at the Net","scene":"res://scenes/blocking_camp.tscn"}],
}

var heading: Label
var list: VBoxContainer
var scroll: ScrollContainer
var back: Button
var category := ""
var setting_stage: SubViewportContainer
var setting_camera: Camera3D
var setting_row: HBoxContainer
var target_drill: Node3D
var review_button: Button
var launch_button: Button
var replay_panel: VBoxContainer
var frame_label: Label
var marker_popup: Label
var playback: Button
var previous_rep: Button
var next_rep: Button
var seek: HSlider
var camera_focus := Vector3.ZERO

func _ready() -> void:
	MenuPresentation.backdrop(self,false)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_"+side,40)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",18)
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	heading = Label.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_font_size_override("font_size",40)
	heading.add_theme_color_override("font_color",Color("73e1d2"))
	header.add_child(heading)
	back = Button.new()
	back.name = "Back"
	back.text = "Back"
	back.custom_minimum_size = Vector2(104,48)
	back.pressed.connect(go_back)
	header.add_child(back)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation",8)
	scroll.add_child(list)
	if not StorySession.return_to_drill.is_empty():
		var drill := StorySession.return_to_drill
		StorySession.return_to_drill = ""
		for name_ in CATEGORIES:
			if CATEGORIES[name_].any(func(entry): return entry.title == drill):
				show_category(name_)
				break
		if drill=="Approach and Spike": MenuPresentation.load_scene("res://scenes/attacking_camp.tscn")
		elif drill=="Set to Target": MenuPresentation.load_scene("res://scenes/setting_camp.tscn")
		else: open_setting_stage(drill)
	elif StorySession.drill_menu_category.is_empty():
		show_categories()
	else:
		var previous := StorySession.drill_menu_category
		StorySession.drill_menu_category = ""
		show_category(previous)

func clear_list() -> void:
	MenuPresentation.sweep()
	MenuPresentation.reveal(list)
	MenuPresentation.reveal(heading)
	for entry in list.get_children():
		list.remove_child(entry)
		entry.queue_free()
	scroll.scroll_vertical = 0

func show_categories() -> void:
	var previous := category
	category = ""
	heading.text = "TRAINING CAMP"
	clear_list()
	for name_ in CATEGORIES:
		var action := show_category.bind(name_)
		if name_ == "Blocking":
			action = MenuPresentation.load_scene.bind(CATEGORIES[name_][0].scene)
		var item := add_item(name_,action)
		if name_ == previous or (previous.is_empty() and list.get_child_count() == 1):
			item.grab_focus()

func show_category(name_: String) -> void:
	MenuPresentation.set_music(true)
	category = name_
	heading.text = name_+" Drills"
	clear_list()
	var drills: Array = CATEGORIES[name_]
	if drills.is_empty():
		var empty := Label.new()
		empty.text = "No drills yet"
		empty.add_theme_font_size_override("font_size",20)
		list.add_child(empty)
		back.grab_focus()
		return
	for drill in drills:
		var scene_path: String = drill.get("scene","")
		var title: String = drill.title
		add_item(title,func():
			if scene_path.is_empty():
				MenuPresentation.load_stage(title,open_setting_stage.bind(title))
				return
			StorySession.open_passing_drill = name_ == "Passing"
			MenuPresentation.load_scene(scene_path))
	list.get_child(0).grab_focus()

func open_setting_stage(title: String) -> void:
	heading.text = title
	clear_list()
	MenuPresentation.set_music(false)
	scroll.hide()
	setting_stage = SubViewportContainer.new()
	setting_stage.stretch = true
	setting_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	setting_row = HBoxContainer.new()
	setting_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.get_parent().add_child(setting_row)
	var left := setting_panel(290)
	setting_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	setting_row.add_child(setting_stage)
	var right := setting_panel(250)
	var status := Label.new()
	right.add_child(status)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	setting_stage.add_child(viewport)
	var gym := preload("res://scripts/tryout_gym.gd").new()
	viewport.add_child(gym)
	gym.light_gym(gym)
	var spin_serve := title == "Spin Serve"
	var butterfly := title == "Butterfly"
	var drill: Node3D
	match title:
		"Spin Serve": drill = preload("res://scripts/spin_serve_drill.gd").new()
		"Butterfly": drill = preload("res://scripts/butterfly_drill.gd").new()
		_: drill = preload("res://scripts/set_to_target.gd").new()
	target_drill = drill
	viewport.add_child(drill)
	drill.configure(status)
	var launch := Button.new()
	launch.text = "Spin serve" if spin_serve else ("Underhand serve" if butterfly else "Launch float feed")
	launch.custom_minimum_size.y = 48
	launch.pressed.connect(drill.launch_single)
	left.add_child(launch)
	launch_button = launch
	var repeat := Button.new()
	repeat.text = "Repeat"
	repeat.toggle_mode = true
	repeat.custom_minimum_size.y = 38
	repeat.pressed.connect(drill.toggle_repeat)
	left.add_child(repeat)
	var ten := Button.new()
	ten.text = "Run 10 reps" if butterfly or spin_serve else "Serve 10 times"
	ten.custom_minimum_size.y = 38
	ten.pressed.connect(drill.launch_ten)
	left.add_child(ten)
	var batch_buttons := [launch,ten]
	if not spin_serve:
		var sweep := review_control(left,"Set to all 7 positions",drill.launch_net_sweep)
		batch_buttons.append(sweep)
	add_speed(left,"Slow motion",drill.live_speed,func(value: float): drill.live_speed = value)
	var slow_motion := left.get_child(left.get_child_count()-1) as HSlider
	slow_motion.value_changed.connect(func(_value: float): drill.save_setup())
	if butterfly:
		add_drill_value(left,"Serve apex",3.5,9.0,"serve_apex")
		add_drill_value(left,"Pass height",2.3,6.0,"pass_height")
		add_drill_value(left,"Set apex",3.35,7.0,"set_apex")
		add_drill_value(left,"Spike pace",0.5,1.4,"spike_pace","×")
		add_drill_value(left,"Spike jump height",30,65,"spike_jump_height"," in",1.0)
	if spin_serve:
		add_drill_value(left,"Serve apex",3.5,9.0,"apex")
		add_drill_value(left,"Serve speed",0.65,1.55,"speed","×")
		add_drill_value(left,"Jump height",0.75,1.48,"jump_height"," m",0.01)
		add_drill_value(left,"Forward lean",-45.0,45.0,"lean","°",1.0)
		add_drill_value(left,"Sidespin",-100.0,100.0,"sidespin","%",1.0)
		var carry := CheckButton.new()
		carry.text = "Forward carry"
		carry.button_pressed = drill.jump_carry
		carry.toggled.connect(drill.set_jump_carry)
		left.add_child(carry)
	build_review(right)
	for button in batch_buttons:
		button.pressed.connect(func(): repeat.set_pressed_no_signal(false))
	setting_camera = Camera3D.new()
	setting_camera.fov = 42.0
	setting_camera.far = 150.0
	setting_camera.position = Vector3(0,8.2,-12.2)
	camera_focus = Vector3(0,1.55,3.9)
	if spin_serve:
		setting_camera.position = Vector3(-9.0,5.2,-15.0)
		camera_focus = Vector3(0,1.8,-4.4)
	viewport.add_child(setting_camera)
	setting_camera.look_at(camera_focus)
	setting_camera.make_current()
	setting_stage.gui_input.connect(handle_setting_camera)
	marker_popup = preload("res://scripts/debug_marker_popup.gd").new()
	setting_stage.add_child(marker_popup)
	back.grab_focus()

func _process(delta: float) -> void:
	if not is_instance_valid(setting_stage): return
	var movement := Vector2(
		float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_W))-float(Input.is_physical_key_pressed(KEY_S))).limit_length()
	pan_setting_camera(movement,delta)
	update_review()

func pan_setting_camera(movement: Vector2, delta: float) -> void:
	var forward := -setting_camera.global_basis.z.slide(Vector3.UP).normalized()
	var right := setting_camera.global_basis.x.slide(Vector3.UP).normalized()
	var travel := (right*movement.x+forward*movement.y)*delta*6.0
	setting_camera.position += travel
	camera_focus += travel

func handle_setting_camera(event: InputEvent) -> void:
	if target_drill.handle_setup_input(event,setting_camera):
		setting_stage.accept_event()
		return
	var offset := setting_camera.position-camera_focus
	var distance := offset.length()
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
		var yaw: float = atan2(offset.x,offset.z)-event.relative.x*0.008
		var pitch := clampf(asin(offset.y/distance)+event.relative.y*0.006,0.08,1.22)
		offset = Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*distance
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		var wheel := (1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0)*maxf(0.1,event.factor)
		offset = offset.normalized()*clampf(distance*exp(-wheel*0.17),2.8,36.0)
	else:
		return
	setting_camera.position = camera_focus+offset
	setting_camera.look_at(camera_focus)
	setting_stage.accept_event()

func add_speed(panel: VBoxContainer, title: String, initial: float, apply: Callable) -> void:
	var caption := Label.new()
	panel.add_child(caption)
	var slider := HSlider.new()
	slider.min_value = 0.1
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = initial
	panel.add_child(slider)
	var update := func(value: float):
		caption.text = "%s %.2fx" % [title,value]
		apply.call(value)
	slider.value_changed.connect(update)
	update.call(initial)

func add_drill_value(panel: VBoxContainer, title: String, minimum: float, maximum: float, key: String, units := " m", step := 0.05) -> void:
	var drill := target_drill
	var caption := Label.new()
	panel.add_child(caption)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	panel.add_child(slider)
	var sync := func():
		var value: float = drill.trajectory_value(key)
		slider.set_value_no_signal(value)
		caption.text = ("%s %.0f%s" if step == 1.0 else "%s %.2f%s") % [title,value,units]
	drill.trajectory_changed.connect(sync)
	slider.value_changed.connect(func(value: float): drill.set_trajectory_value(key,value))
	sync.call()

func review_control(panel: Container, title: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size.y = 38
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	panel.add_child(button)
	return button

func build_review(panel: VBoxContainer) -> void:
	var game: Node3D = target_drill.game
	var replay = game.replay
	review_button = review_control(panel,"Review rep (R)",toggle_review)
	review_control(panel,"Open latest save",open_latest_saved_rep)
	replay_panel = VBoxContainer.new()
	panel.add_child(replay_panel)
	playback = review_control(replay_panel,"Play (Space)",toggle_playback)
	seek = HSlider.new()
	seek.step = 1.0
	seek.focus_mode = Control.FOCUS_NONE
	seek.drag_started.connect(func(): replay.playing = false)
	seek.value_changed.connect(func(value: float):
		replay.playing = false
		replay.seek_frame(game,roundi(value)))
	replay_panel.add_child(seek)
	frame_label = Label.new()
	replay_panel.add_child(frame_label)
	var steps := HBoxContainer.new()
	replay_panel.add_child(steps)
	review_control(steps,"Previous frame",func(): replay.step_frame(game,-1))
	review_control(steps,"Next frame",func(): replay.step_frame(game,1))
	var reps := HBoxContainer.new()
	replay_panel.add_child(reps)
	previous_rep = review_control(reps,"Previous rep",func(): target_drill.open_review(target_drill.review_index-1,true))
	next_rep = review_control(reps,"Next rep",func(): target_drill.open_review(target_drill.review_index+1,true))
	review_control(replay_panel,"Save replay",save_reviewed_rep)
	add_speed(replay_panel,"Replay speed",replay.speed,func(value: float): replay.speed = value)
	if target_drill.drill_title() == "Spin Serve":
		review_control(replay_panel,"Edit server",target_drill.edit_server)
	else:
		review_control(replay_panel,"Edit setter",target_drill.edit_setter)
	if target_drill.drill_title() == "Butterfly":
		review_control(replay_panel,"Edit server",target_drill.edit_role.bind(2,"Butterfly serve","Serving","Underhand","server",true))
		review_control(replay_panel,"Edit passer",target_drill.edit_role.bind(1,"Butterfly pass","Forearm reception","Forearm","passer",true))
		review_control(replay_panel,"Edit hitter",target_drill.edit_role.bind(1,"Butterfly spike","Attacking","Line Hit","hitter",true))
	update_review()

func save_reviewed_rep() -> void:
	var rep: int = target_drill.game.replay.saved_evidence.get("rep",target_drill.review_index+1)
	var path: String = target_drill.game.save_reviewed_rep(target_drill.drill_title(),rep,setting_camera,camera_focus)
	marker_popup.flash("Replay saved" if not path.is_empty() else "Could not save replay")

func open_latest_saved_rep() -> void:
	var record := Replay.latest_saved(target_drill.drill_title())
	if record.is_empty():
		marker_popup.flash("No saved replay")
		return
	var game: Node3D = target_drill.game
	if game.replay.open_saved(game,record,setting_camera):
		camera_focus = record.evidence.get("camera_focus",camera_focus)
		target_drill.show_rep_target(game.replay.frames)
		update_review()

func toggle_review() -> void:
	var game: Node3D = target_drill.game
	if game.replay.active:
		target_drill.close_review()
	else: target_drill.open_review(target_drill.review_count()-1)
	update_review()

func toggle_playback() -> void:
	var game: Node3D = target_drill.game
	var replay = game.replay
	if not replay.active: return
	if not replay.playing and replay.clock >= replay.duration(): replay.seek(game,0.0)
	replay.playing = not replay.playing

func update_review() -> void:
	var replay = target_drill.game.replay
	var count: int = target_drill.review_count()
	review_button.disabled = count == 0 and not replay.active
	review_button.text = "Back to drill (R)" if replay.active else "Review rep (R)"
	replay_panel.visible = replay.active
	if not replay.active: return
	playback.text = "Pause (Space)" if replay.playing else "Play (Space)"
	seek.max_value = replay.frames.size()-1
	seek.set_value_no_signal(replay.index)
	frame_label.text = "Rep %d / %d | Frame %d / %d" % [target_drill.review_index+1,count,replay.index,replay.frames.size()-1]
	var showing_saved_rep: bool = not replay.saved_evidence.is_empty()
	if showing_saved_rep:
		frame_label.text = "Saved rep %d | Frame %d / %d" % [replay.saved_evidence.rep,replay.index,replay.frames.size()-1]
	previous_rep.disabled = showing_saved_rep or target_drill.review_index <= 0
	next_rep.disabled = showing_saved_rep or target_drill.review_index >= count-1

func setting_panel(width: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = width
	var style := StyleBoxFlat.new()
	style.bg_color = Color("132a39")
	style.border_color = Color("345661")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel",style)
	setting_row.add_child(panel)
	var scrolling := ScrollContainer.new()
	scrolling.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scrolling)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scrolling.add_child(content)
	return content

func add_item(title: String, action: Callable) -> Button:
	var item := Button.new()
	item.text = title
	item.custom_minimum_size.y = 58
	item.add_theme_font_size_override("font_size",23)
	item.pressed.connect(action)
	list.add_child(item)
	return item

func go_back() -> void:
	if is_instance_valid(setting_stage):
		setting_row.queue_free()
		setting_stage = null
		scroll.show()
		show_category(category)
	elif category.is_empty():
		MenuPresentation.load_scene("res://scenes/main.tscn")
	else:
		show_categories()

func _input(event: InputEvent) -> void:
	if not is_instance_valid(setting_stage) or not event is InputEventKey or not event.pressed or event.echo: return
	if event.physical_keycode == KEY_R:
		toggle_review()
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_F8:
		if target_drill.game.mark_trace(): marker_popup.flash()
		get_viewport().set_input_as_handled()
	elif target_drill.game.replay.active and event.physical_keycode in [KEY_LEFT,KEY_RIGHT]:
		target_drill.game.replay.step_frame(target_drill.game,-1 if event.physical_keycode == KEY_LEFT else 1)
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_SPACE:
		if target_drill.game.replay.active: toggle_playback()
		elif target_drill.drill_title() == "Spin Serve": launch_button.pressed.emit()
		else: return
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		go_back()
		get_viewport().set_input_as_handled()
