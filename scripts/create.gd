extends Control
const Profile = preload("res://scripts/player_profile.gd")
var profile: Dictionary = Profile.load_profile()
var name_field: LineEdit

var hand_field: OptionButton
var save_button: Button
var preview: SubViewportContainer
var preview_camera: Camera3D
var preview_player: Node3D
var orbit_yaw := 0.0
var orbit_pitch := 0.12
var view_distance := 3.8
var view_focus := Vector3(0,0.98,0)
var max_view_distance := 8.0
var pan_limits := Vector3(1.5,2.4,1.5)
var stage_camera := {}
var dragging := false
var panning := false
var ball_controls_host: VBoxContainer
var right_panel: PanelContainer
var player_controls: RefCounted

func _ready() -> void:
	profile = initial_profile()
	var background := ColorRect.new()
	background.color = Color("0f1a25")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge,24)
	add_child(margin)
	var column := VBoxContainer.new()
	column.name = "ScreenColumn"
	column.add_theme_constant_override("separation",18)
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title_block := VBoxContainer.new()
	title_block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_block)
	var title := label(screen_title(),32)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.name = "ScreenTitle"
	title.add_theme_color_override("font_color",Color("ffce70"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_block.add_child(title)
	var subtitle := screen_subtitle()
	if not subtitle.is_empty():
		var build := label(subtitle,14)
		build.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		build.tooltip_text = subtitle
		title_block.add_child(build)
	var back := button("Back",open_menu)
	back.custom_minimum_size = Vector2(110,44)
	back.size_flags_horizontal = Control.SIZE_SHRINK_END
	header.add_child(back)
	var workspace_row := HBoxContainer.new()
	workspace_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace_row.add_theme_constant_override("separation",12)
	column.add_child(workspace_row)
	var split := HSplitContainer.new()
	split.name = "Workspace"
	split.split_offset = 320
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace_row.add_child(split)
	var tools := panel()
	tools.name = "LeftPanel"
	tools.custom_minimum_size.x = 300
	split.add_child(tools)
	var tool_margin := MarginContainer.new()
	for edge in ["left","right","top","bottom"]: tool_margin.add_theme_constant_override("margin_"+edge,20)
	tools.add_child(tool_margin)
	var controls := VBoxContainer.new()
	controls.add_theme_constant_override("separation",16)
	var tool_scroll := ScrollContainer.new()
	tool_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tool_scroll.follow_focus = true
	tool_margin.add_child(tool_scroll)
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tool_scroll.add_child(controls)
	var stage := panel()
	stage.name = "RightPreview"
	stage.custom_minimum_size.x = 400
	split.add_child(stage)
	preview = SubViewportContainer.new()
	preview.name = "CharacterPreview"
	preview.stretch = true
	preview.focus_mode = Control.FOCUS_ALL
	preview.mouse_default_cursor_shape = Control.CURSOR_DRAG
	preview.gui_input.connect(handle_preview_input)
	stage.add_child(preview)
	var viewport := SubViewport.new()
	viewport.name = "CharacterViewport"
	viewport.own_world_3d = true
	viewport.size = Vector2i(880,600)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	preview.add_child(viewport)
	build_preview(viewport)
	if has_ball_controls():
		right_panel = panel()
		right_panel.name = "BallPanel"
		right_panel.custom_minimum_size.x = 300
		workspace_row.add_child(right_panel)
		var inset := MarginContainer.new()
		for edge in ["left","right","top","bottom"]: inset.add_theme_constant_override("margin_"+edge,16)
		right_panel.add_child(inset)
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.follow_focus = true
		inset.add_child(scroll)
		ball_controls_host = VBoxContainer.new()
		ball_controls_host.name = "BallControls"
		ball_controls_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ball_controls_host.add_theme_constant_override("separation",12)
		scroll.add_child(ball_controls_host)
		build_ball_controls(ball_controls_host)
	build_controls(controls)
	if has_ball_controls(): player_controls = preload("res://scripts/preview_player_control.gd").new(self)
	preview.grab_focus()

func has_ball_controls() -> bool:
	return false

func build_ball_controls(_host: VBoxContainer) -> void:
	pass

func screen_title() -> String:
	return "CREATE PLAYER"

func screen_subtitle() -> String:
	return ""

func initial_profile() -> Dictionary:
	return StorySession.draft.duplicate(true) if StorySession.creating_story else Profile.load_profile()

func build_controls(controls: VBoxContainer) -> void:
	controls.add_child(label("Name",18))
	name_field = LineEdit.new()
	name_field.name = "PlayerName"
	name_field.max_length = 32
	name_field.text = profile.name
	name_field.custom_minimum_size.y = 42
	name_field.text_changed.connect(func(value): profile.name = value; update_profile())
	controls.add_child(name_field)
	profile = Profile.clean(profile)
	add_attribute(controls,"Height (inches)","height_cm",60,84,profile.height_cm / 2.54)
	add_attribute(controls,"Vertical jump (inches)","vertical_in",10,60,profile.vertical_in)
	add_attribute(controls,"Wingspan (inches)","wingspan_in",48,96,profile.wingspan_in)
	for rating in Profile.RATINGS:
		add_attribute(controls,rating,rating,0,100,profile[rating])
	controls.add_child(label("Handedness",18))
	hand_field = OptionButton.new()
	hand_field.name = "PlayerHandedness"
	hand_field.add_item("Right")
	hand_field.add_item("Left")
	hand_field.select(1 if profile.handedness == "Left" else 0)
	hand_field.custom_minimum_size.y = 42
	hand_field.item_selected.connect(func(index): profile.handedness = "Left" if index == 1 else "Right"; update_profile())
	controls.add_child(hand_field)
	controls.add_child(button("Generate player",func():
		profile = Profile.generate()
		update_profile()
		get_tree().reload_current_scene()))
	var space := Control.new()
	space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	controls.add_child(space)
	save_button = button("Save",save_player)
	save_button.name = "SavePlayer"
	save_button.disabled = profile.name.strip_edges().is_empty()
	controls.add_child(save_button)

func add_attribute(parent: VBoxContainer, caption: String, key: String, minimum: int, maximum: int, initial: float) -> void:
	var heading := label("%s   %d" % [caption,roundi(initial)],16)
	parent.add_child(heading)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = 1
	slider.value = initial
	parent.add_child(slider)
	slider.value_changed.connect(func(value: float):
		heading.text = "%s   %d" % [caption,int(value)]
		profile[key] = value*2.54 if key == "height_cm" else value
		update_profile())

func save_player() -> void:
	profile.name = name_field.text
	profile.handedness = "Left" if hand_field.selected == 1 else "Right"
	if StorySession.creating_story:
		if StorySession.save_new(profile) == OK:
			get_tree().change_scene_to_file("res://scenes/story_animations.tscn")
		else: show_save_error()
	else:
		if Profile.save_profile(profile) == OK: open_menu()
		else: show_save_error()

func show_save_error() -> void:
	var dialog := AcceptDialog.new()
	dialog.dialog_text = "Unable to save player."
	add_child(dialog)
	dialog.popup_centered()

func build_preview(viewport: SubViewport) -> void:
	var world := Node3D.new()
	viewport.add_child(world)
	preload("res://scripts/preview_court.gd").add_preview_lighting(world)
	build_preview_stage(world)
	preview_player = preload("res://scripts/volleyball_player.gd").new()
	preview_player.name = "PreviewPlayer"
	preview_player.position.y = 0.04
	preview_player.apply_profile(profile)
	world.add_child(preview_player)
	preview_camera = Camera3D.new()
	preview_camera.name = "PreviewCamera"
	preview_camera.fov = 38.0
	preview_camera.near = 0.05
	preview_camera.far = 50
	stage_camera = {"yaw":orbit_yaw,"pitch":orbit_pitch,"distance":view_distance,"focus":view_focus}
	preview_camera.current = true
	world.add_child(preview_camera)
	update_camera()

func build_preview_stage(world: Node3D) -> void:
	var platform := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.8
	cylinder.bottom_radius = 0.8
	cylinder.height = 0.08
	platform.mesh = cylinder
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("304654")
	material.roughness = 0.9
	platform.material_override = material
	world.add_child(platform)

func handle_preview_input(event: InputEvent) -> void:
	if player_controls!=null and player_controls.active and not event is InputEventKey: return
	if event is InputEventKey and event.pressed:
		handle_keyboard(event)
		return
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_MIDDLE]: dragging = event.pressed
		if event.button_index == MOUSE_BUTTON_RIGHT: panning = event.pressed
		if event.pressed:
			preview.grab_focus()
			if event.button_index == MOUSE_BUTTON_WHEEL_UP: zoom_view(0.9)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: zoom_view(1.1)
		preview.accept_event()
	if event is InputEventMouseMotion:
		if panning:
			pan_view(event.relative)
		elif dragging:
			orbit_yaw -= event.relative.x*0.008
			orbit_pitch = clampf(orbit_pitch+event.relative.y*0.006,-0.15,1.35)
			update_camera()
		if panning or dragging: preview.accept_event()

func _process(delta: float) -> void:
	if player_controls!=null:
		player_controls.step(delta)
		if player_controls.active: return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return
	if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_ALT) or Input.is_key_pressed(KEY_META): return
	var direction := Vector2(
		float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_W))-float(Input.is_physical_key_pressed(KEY_S)))
	pan_camera(direction,delta)

func camera_pan_delta(direction: Vector2, delta: float, speed: float) -> Vector3:
	var right := preview_camera.global_basis.x
	var forward := -preview_camera.global_basis.z
	right.y = 0
	forward.y = 0
	return (right.normalized()*direction.x+forward.normalized()*direction.y)*speed*delta

func pan_camera(direction: Vector2, delta: float) -> void:
	if direction.length_squared()<0.001: return
	var speed := clampf(view_distance*0.45,1.0,30.0)
	view_focus += camera_pan_delta(direction.normalized(),delta,speed)
	view_focus.x = clampf(view_focus.x,-pan_limits.x,pan_limits.x)
	view_focus.z = clampf(view_focus.z,-pan_limits.z,pan_limits.z)
	update_camera()

func pan_view(pixels: Vector2) -> void:
	view_focus += (-preview_camera.global_basis.x*pixels.x+preview_camera.global_basis.y*pixels.y)*view_distance*0.0015
	view_focus.x = clampf(view_focus.x,-pan_limits.x,pan_limits.x)
	view_focus.y = clampf(view_focus.y,-0.2,pan_limits.y)
	view_focus.z = clampf(view_focus.z,-pan_limits.z,pan_limits.z)
	update_camera()

func zoom_view(factor: float) -> void:
	view_distance = clampf(view_distance*factor,1.4,max_view_distance)
	update_camera()

func set_view(yaw: float) -> void:
	reset_view()
	orbit_yaw = yaw
	update_camera()

func reset_view() -> void:
	orbit_yaw = stage_camera.get("yaw",0.0)
	orbit_pitch = stage_camera.get("pitch",0.12)
	view_distance = stage_camera.get("distance",3.8)
	view_focus = stage_camera.get("focus",Vector3(0,0.98,0))
	update_camera()

func update_camera() -> void:
	preview_camera.position = view_focus+Vector3(sin(orbit_yaw)*cos(orbit_pitch),sin(orbit_pitch),cos(orbit_yaw)*cos(orbit_pitch))*view_distance
	preview_camera.look_at(view_focus)

func panel() -> PanelContainer:
	var result := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("192938")
	style.border_color = Color("304657")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	result.add_theme_stylebox_override("panel",style)
	return result

func label(text: String, size: int) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size",size)
	return result

func button(text: String, action: Callable) -> Button:
	var result := Button.new()
	result.text = text
	result.custom_minimum_size = Vector2(80,38)
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.pressed.connect(action)
	return result

func update_profile() -> void:
	if StorySession.creating_story: StorySession.draft = Profile.clean(profile)
	else: Profile.save_profile(profile)
	if is_instance_valid(save_button): save_button.disabled = profile.name.strip_edges().is_empty()
	if is_instance_valid(preview_player): preview_player.apply_profile(profile)

func open_menu() -> void:
	if StorySession.creating_story:
		StorySession.cancel_creation()
		get_tree().change_scene_to_file("res://scenes/story.tscn")
	else: get_tree().change_scene_to_file("res://scenes/main.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed: handle_keyboard(event)

func handle_keyboard(event: InputEventKey) -> void:
	if player_controls!=null and player_controls.handle_key(event):
		get_viewport().set_input_as_handled()
		return
	match event.keycode:
		KEY_ESCAPE: open_menu()
		KEY_R,KEY_F: reset_view()
		KEY_PLUS,KEY_EQUAL,KEY_KP_ADD: zoom_view(0.9)
		KEY_MINUS,KEY_KP_SUBTRACT: zoom_view(1.1)
		KEY_LEFT,KEY_RIGHT,KEY_UP,KEY_DOWN:
			var direction := Vector2.ZERO
			if event.keycode == KEY_LEFT: direction.x = -1
			if event.keycode == KEY_RIGHT: direction.x = 1
			if event.keycode == KEY_UP: direction.y = -1
			if event.keycode == KEY_DOWN: direction.y = 1
			if event.shift_pressed: pan_view(direction*20)
			else:
				orbit_yaw -= direction.x*0.12
				orbit_pitch = clampf(orbit_pitch+direction.y*0.08,-0.15,1.35)
				update_camera()
		_: return
	get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode in [KEY_F1,KEY_F2] and player_controls!=null:
		handle_keyboard(event)
