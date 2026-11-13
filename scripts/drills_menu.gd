extends Control

const CATEGORIES := {
	"Passing": [{"title":"Pass to Target","scene":"res://scenes/story_animations.tscn"}],
	"Setting": [{"title":"Set to Target"}],
	"Attacking": [],
	"Serving": [],
	"Digging": [],
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
var replay_panel: VBoxContainer
var frame_label: Label
var playback: Button
var previous_rep: Button
var next_rep: Button
var seek: HSlider
var camera_focus := Vector3.ZERO

func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color("102b40")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

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
	heading.add_theme_color_override("font_color",Color("ffce70"))
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
	if StorySession.return_to_set_to_target:
		StorySession.return_to_set_to_target = false
		show_category("Setting")
		open_setting_stage("Set to Target")
	elif StorySession.drill_menu_category.is_empty():
		show_categories()
	else:
		var previous := StorySession.drill_menu_category
		StorySession.drill_menu_category = ""
		show_category(previous)

func clear_list() -> void:
	for entry in list.get_children():
		list.remove_child(entry)
		entry.queue_free()
	scroll.scroll_vertical = 0

func show_categories() -> void:
	var previous := category
	category = ""
	heading.text = "Drills"
	clear_list()
	for name_ in CATEGORIES:
		var item := add_item(name_,show_category.bind(name_))
		if name_ == previous or (previous.is_empty() and list.get_child_count() == 1):
			item.grab_focus()

func show_category(name_: String) -> void:
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
				open_setting_stage(title)
				return
			StorySession.open_passing_drill = name_ == "Passing"
			get_tree().change_scene_to_file(scene_path))
	list.get_child(0).grab_focus()

func open_setting_stage(title: String) -> void:
	heading.text = title
	clear_list()
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
	preload("res://scripts/preview_court.gd").add_preview_lighting(viewport)
	viewport.add_child(preload("res://scripts/preview_court.gd").new())
	var drill := preload("res://scripts/set_to_target.gd").new()
	target_drill = drill
	viewport.add_child(drill)
	drill.configure(status)
	var launch := Button.new()
	launch.text = "Launch float feed"
	launch.custom_minimum_size.y = 48
	launch.pressed.connect(drill.launch_single)
	left.add_child(launch)
	var repeat := Button.new()
	repeat.text = "Repeat"
	repeat.toggle_mode = true
	repeat.custom_minimum_size.y = 38
	repeat.pressed.connect(drill.toggle_repeat)
	left.add_child(repeat)
	var ten := Button.new()
	ten.text = "Serve 10 times"
	ten.custom_minimum_size.y = 38
	ten.pressed.connect(drill.launch_ten)
	left.add_child(ten)
	var sweep := Button.new()
	sweep.text = "Set to all 7 positions"
	sweep.custom_minimum_size.y = 38
	sweep.pressed.connect(drill.launch_net_sweep)
	left.add_child(sweep)
	add_speed(left,"Slow motion",drill.live_speed,func(value: float): drill.live_speed = value)
	var slow_motion := left.get_child(left.get_child_count()-1) as HSlider
	slow_motion.value_changed.connect(func(_value: float): drill.save_setup())
	build_review(right)
	for button in [launch,ten,sweep]:
		button.pressed.connect(func(): repeat.set_pressed_no_signal(false))
	setting_camera = Camera3D.new()
	setting_camera.fov = 42.0
	setting_camera.far = 150.0
	setting_camera.position = Vector3(0,8.2,-12.2)
	camera_focus = Vector3(0,1.55,3.9)
	viewport.add_child(setting_camera)
	setting_camera.look_at(camera_focus)
	setting_camera.make_current()
	setting_stage.gui_input.connect(handle_setting_camera)
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
	add_speed(replay_panel,"Replay speed",replay.speed,func(value: float): replay.speed = value)
	review_control(replay_panel,"Edit setter",target_drill.edit_setter)
	update_review()

func toggle_review() -> void:
	var game: Node3D = target_drill.game
	if game.replay.active: target_drill.close_review()
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
	review_button.disabled = count == 0
	review_button.text = "Back to drill (R)" if replay.active else "Review rep (R)"
	replay_panel.visible = replay.active
	if not replay.active: return
	playback.text = "Pause (Space)" if replay.playing else "Play (Space)"
	seek.max_value = replay.frames.size()-1
	seek.set_value_no_signal(replay.index)
	frame_label.text = "Rep %d / %d | Frame %d / %d" % [target_drill.review_index+1,count,replay.index,replay.frames.size()-1]
	previous_rep.disabled = target_drill.review_index <= 0
	next_rep.disabled = target_drill.review_index >= count-1

func setting_panel(width: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = width
	var style := StyleBoxFlat.new()
	style.bg_color = Color("192938")
	style.border_color = Color("304657")
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
		get_tree().change_scene_to_file("res://scenes/main.tscn")
	else:
		show_categories()

func _input(event: InputEvent) -> void:
	if not is_instance_valid(setting_stage) or not event is InputEventKey or not event.pressed or event.echo: return
	if event.physical_keycode == KEY_R:
		toggle_review()
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_F8:
		if target_drill.game.mark_trace(): target_drill.game.info.text = "Debug marker saved"
		get_viewport().set_input_as_handled()
	elif target_drill.game.replay.active and event.physical_keycode in [KEY_LEFT,KEY_RIGHT]:
		target_drill.game.replay.step_frame(target_drill.game,-1 if event.physical_keycode == KEY_LEFT else 1)
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_SPACE and target_drill.game.replay.active:
		toggle_playback()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		go_back()
		get_viewport().set_input_as_handled()
