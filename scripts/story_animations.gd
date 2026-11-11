extends "res://scripts/create.gd"
const BallPreview = preload("res://scripts/animation_ball_preview.gd")
const Court = preload("res://scripts/preview_court.gd")
const SETTING_CAMERA_FOCUS := Vector3(0,1.45,2.6)
const SERVING_CAMERA_POSITION := Vector3(0.0,3.4,-18.1)
const SERVING_CAMERA_FOCUS := Vector3(0.0,1.12,2.6)
const BallTimingRing = preload("res://scripts/ball_timing_ring.gd")
const Flight = preload("res://scripts/pass_flight.gd")
const SideKneeSlide = preload("res://scripts/side_knee_slide.gd")
const ForwardDive = preload("res://scripts/forward_reception_dive.gd")
const LOW_BOW_EDIT_ID := "low_bow_swing"
const BACKWARD_EDIT_ID := "d2_backward_from_d1"
const Catalog = preload("res://scripts/volleyball_animations.gd")
const MOVE_TYPES := {
	"Forearm reception":["Forearm"],
	"Attacking":["Line Hit","Cross Hit"],
	"Serving":["Jump Float","Spin","Hybrid","Skyball","Underhand","Standing Float","Standing Spin"],
	"Blocking":["Straight","Left","Right"],
	"Setting":["Hand setting","Bump setting"],
	"Chasing":["Forward","Back","Left","Right"]
}
const CATEGORIES := ["Forearm reception","Setting","Attacking","Serving","Blocking","Chasing"]
var content: VBoxContainer
var category_buttons: Dictionary = {}
var selected_category := ""
var blocking_practice: Node3D
var blocking_frame: Node3D
var underhand_serve: Node3D
var serve_opponents: Node3D
var serve_opponent_frame: Node3D
var serving_rally_status: Label
var serving_spin_controls: VBoxContainer
var serving_original_transform: Transform3D
var serving_position := Vector3(0.0,0.04,-6.20)
var serving_running := false
var type_indices: Dictionary = {}
var type_label: Label
var animation_list
var trigger_held := {}
var edit_button: Button
var selected_entry: Dictionary = {}
var ball_preview: Node3D
var setup_drag: RefCounted
var angle_control: VBoxContainer
var source_clip: Animation
var trajectory_solver: RefCounted
var render_clip: Animation
var preview_clock := 0.0
var build_label := ""
var cpu_receive_clock := -INF
var custom_backward_clip: Animation
var cpu_reach_offset := Vector3.INF
var cpu_start := Vector3.INF
var cpu_start_yaw := 0.0
var cpu_side_slide_pose: Array[Transform3D] = []
var cpu_side_slide_start := Vector3.ZERO
var cpu_side_slide_time := 0.0
var cpu_dive_ready: Array[Transform3D] = []
var cpu_dive_clasp: Array[Transform3D] = []
var middle_arrow := Vector2i(-1,1)
var middle_press := Vector2.ZERO
var middle_dragged := false
var drill_status: Label
var distance_status: Label
var preview_overlay: Control
var jump_height_meter: Control
var marker_popup: Label
var marker_fade: Tween
var pass_timing_cue: Node3D
var reception_review: VBoxContainer
var setting_drill: Node3D
var attack_position_panel: PanelContainer
var attack_playback_speed := 1.0
var setting_camera_focus := SETTING_CAMERA_FOCUS
var approach_drag_offset := Vector3.ZERO
var setter_original_transform: Transform3D
var setter_original_height: float
var setter_animation_process: int
var setter_animator_active: bool

func _ready() -> void:
	process_priority = 10
	build_label = current_build_label()
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_title("Volleyball | "+build_label)
	super._ready()
	preview_player.set_height_cm(preview_player.Profile.DEFAULTS.height_cm)
	preview_overlay = Control.new()
	preview_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.get_parent().add_child(preview_overlay)
	build_marker_popup()
	jump_height_meter = preload("res://scripts/jump_height_meter.gd").new()
	preview_overlay.add_child(jump_height_meter)
	pass_timing_cue = BallTimingRing.new()
	preview_player.get_parent().add_child(pass_timing_cue)
	reception_review = preload("res://scripts/reception_review.gd").new(self)
	var column := find_child("ScreenColumn",true,false)
	column.add_child(reception_review)
	column.move_child(reception_review,1)
	setup_drag = preload("res://scripts/court_setup_drag.gd").new(self)
	preview_camera.fov = 42.0
	preview_camera.far = 150.0
	if not StorySession.animation_return.is_empty():
		var destination: Dictionary = StorySession.animation_return.duplicate()
		StorySession.animation_return.clear()
		destination.category = Catalog.category_name(destination.category)
		destination.type = Catalog.type_name(destination.category,destination.type)
		if MOVE_TYPES.has(destination.category):
			type_indices[destination.category] = MOVE_TYPES[destination.category].find(destination.type)
			select_category(destination.category)
			if not is_instance_valid(animation_list): return
			for index in animation_list.item_count:
				if animation_list.get_item_metadata(index).id == destination.get("id",""):
					animation_list.select(index)
					preview_animation(index)
					break

func build_marker_popup() -> void:
	marker_popup = label("Debug marker saved",16)
	marker_popup.name = "DebugMarkerPopup"
	marker_popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	marker_popup.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	marker_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge := StyleBoxFlat.new()
	badge.bg_color = Color("152331")
	badge.border_color = Color("59d6ec")
	badge.set_border_width_all(1)
	badge.set_corner_radius_all(7)
	marker_popup.add_theme_stylebox_override("normal",badge)
	preview_overlay.add_child(marker_popup)
	marker_popup.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	marker_popup.offset_left = -112
	marker_popup.offset_right = 112
	marker_popup.offset_top = 16
	marker_popup.offset_bottom = 54
	marker_popup.hide()

func show_marker_popup() -> void:
	if marker_fade != null: marker_fade.kill()
	marker_popup.modulate.a = 1.0
	marker_popup.show()
	marker_fade = create_tween()
	marker_fade.tween_interval(0.7)
	marker_fade.tween_property(marker_popup,"modulate:a",0.0,0.35)
	marker_fade.tween_callback(marker_popup.hide)

func build_preview_stage(world: Node3D) -> void:
	world.add_child(preload("res://scripts/preview_court.gd").new())
	orbit_yaw = -2.2
	orbit_pitch = 0.26
	max_view_distance = 60.0
	pan_limits = Vector3(12,15,48)
	view_distance = 16.0
	view_focus = Vector3(0,2.0,4.0)

func has_ball_controls() -> bool:
	return true

func build_ball_controls(host: VBoxContainer) -> void:
	angle_control = preload("res://scripts/pass_angle_control.gd").new()
	angle_control.allow_dive = true
	host.add_child(angle_control)
	angle_control.angle_requested.connect(apply_output_angle)
	angle_control.feed_aim_changed.connect(update_feed_aim)

func current_build_label() -> String:
	var version := "v"+str(ProjectSettings.get_setting("application/config/version","0.1.1"))
	var root_path := ProjectSettings.globalize_path("res://")
	var git_path := root_path.path_join(".git")
	if OS.is_debug_build() and (DirAccess.dir_exists_absolute(git_path) or FileAccess.file_exists(git_path)):
		var output := []
		if OS.execute("git",["-C",root_path,"describe","--always","--dirty","--abbrev=8"],output) == 0 and not output.is_empty():
			var revision := str(output[0]).strip_edges()
			if not revision.is_empty(): return version+" | "+revision
	return version

func screen_title() -> String:
	return "ANIMATIONS"

func screen_subtitle() -> String:
	return build_label

func initial_profile() -> Dictionary:
	return StorySession.active.get("profile",Profile.load_profile()).duplicate(true)

func build_controls(controls: VBoxContainer) -> void:
	content = controls
	content.add_theme_constant_override("separation",10)
	show_categories()

func clear_content() -> void:
	stop_underhand_serve()
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	drill_status = null
	distance_status = null
	animation_list = null
	edit_button = null
	selected_entry.clear()
	type_label = null

func set_title(text: String) -> void:
	var heading := find_child("ScreenTitle",true,false) as Label
	if heading: heading.text = text

func show_categories() -> void:
	stop_blocking_practice()
	stop_serving_session()
	if is_instance_valid(pass_timing_cue): pass_timing_cue.hide()
	stop_setting_drill()
	if is_instance_valid(reception_review):
		reception_review.stop(false)
		reception_review.hide()
	if is_instance_valid(right_panel): right_panel.hide()
	if is_instance_valid(ball_preview): ball_preview.stop()
	if is_instance_valid(preview_player): preview_player.play_action("idle")
	selected_category = ""
	if is_instance_valid(preview_player): preview_player.get_node("DirectionArrows").show_dive_ring = false
	clear_content()
	set_title("ANIMATIONS")
	category_buttons.clear()
	for category in CATEGORIES:
		var entry := button(category,select_category.bind(category))
		entry.name = category
		entry.custom_minimum_size.y = 52
		entry.alignment = HORIZONTAL_ALIGNMENT_LEFT
		content.add_child(entry)
		category_buttons[category] = entry

func select_category(category: String) -> void:
	category = Catalog.category_name(category)
	if not MOVE_TYPES.has(category): return
	stop_blocking_practice()
	stop_serving_session()
	reception_review.stop(false)
	reception_review.visible = category == "Forearm reception"
	selected_category = category
	if category == "Serving":
		if player_controls.active: player_controls.set_active(false)
		serving_original_transform = preview_player.transform
		serving_position = Vector3(0.0,0.04,-6.20)
		type_indices["Serving"] = MOVE_TYPES["Serving"].find("Underhand")
		preview_player.get_node("DirectionArrows").hide()
		setting_camera_focus = SERVING_CAMERA_FOCUS
		preview_camera.position = SERVING_CAMERA_POSITION
		preview_camera.look_at(setting_camera_focus)
	preview_player.get_node("DirectionArrows").show_dive_ring = category == "Forearm reception"
	clear_content()
	set_title(category.to_upper())
	if category in ["Setting","Attacking"]:
		start_setting_drill(category == "Attacking")
		return
	if category == "Blocking":
		start_blocking_practice()
		return
	var row := HBoxContainer.new()
	row.visible = MOVE_TYPES[category].size()>1
	row.add_theme_constant_override("separation",8)
	content.add_child(row)
	var previous := button("L2 <",cycle_type.bind(-1))
	previous.name = "PreviousType"
	previous.custom_minimum_size = Vector2(52,44)
	previous.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.add_child(previous)
	type_label = label("",19)
	type_label.name = "MoveType"
	type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	type_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	type_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(type_label)
	var next := button("> R2",cycle_type.bind(1))
	next.name = "NextType"
	next.custom_minimum_size = Vector2(52,44)
	next.size_flags_horizontal = Control.SIZE_SHRINK_END
	row.add_child(next)
	if category == "Forearm reception":
		drill_status = label("F1 to play  |  WASD to move
Mouse to aim  |  Tap Q to receive
Scroll to set pass height",16)
		drill_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(drill_status)
		var arrow_hint := label("Middle-click a court arrow to aim the feed",16)
		arrow_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(arrow_hint)
		var path_hint := label("Dotted line shows aim. Solid line shows the actual pass.",16)
		path_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(path_hint)
		var arrow_labels := ["Distance 1  |  Short reach","Distance 2  |  Lunge","Distance 3  |  Dive","Distance 4  |  Pancake"]
		var arrow_colors := [Color("67e8ff"),Color("c291ff"),Color("82a8ff"),Color("57dfbc")]
		for index in arrow_labels.size():
			var legend := label(arrow_labels[index],16)
			legend.add_theme_color_override("font_color",arrow_colors[index])
			content.add_child(legend)
		distance_status = label("",16)
		distance_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(distance_status)
		content.add_child(button("Edit D2 backward lunge",open_backward_editor))
		custom_backward_clip = load_custom_backward_clip()
		if custom_backward_clip != null:
			content.add_child(button("Play my D2 lunge",reception_review.play_custom_backward))
		refresh_type()
		preview.grab_focus()
		return
	if category == "Chasing":
		content.add_child(button("Serve Bump Set Spike",start_serve_bump_set_spike))
	if category == "Serving":
		drill_status = label("Space to serve\nMove cursor to aim\nWASD to run\nMiddle drag to rotate\nScroll for arc  |  Shift + scroll to zoom",16)
		content.add_child(drill_status)
	var list := ItemList.new()
	list.name = "AnimationList"
	list.allow_reselect = true
	list.item_activated.connect(open_editor)
	list.custom_minimum_size.y = 160
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	animation_list = list
	animation_list.add_theme_font_size_override("font_size",18)
	animation_list.item_selected.connect(preview_animation)
	content.add_child(animation_list)
	edit_button = button("Edit",open_editor)
	edit_button.name = "EditAnimation"
	content.add_child(edit_button)
	refresh_type()
	animation_list.grab_focus()

func start_blocking_practice() -> void:
	if player_controls.active: player_controls.set_active(false)
	if is_instance_valid(ball_preview): ball_preview.stop()
	right_panel.hide()
	angle_control.hide()
	content.add_child(label("WASD to move camera\nSpace to jump",18))
	drill_status = label("",16)
	drill_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(drill_status)
	blocking_frame = Node3D.new()
	blocking_frame.position.z = 8.0
	blocking_frame.rotation.y = PI
	preview_player.get_parent().add_child(blocking_frame)
	blocking_practice = preload("res://scripts/blocking_practice.gd").new()
	blocking_frame.add_child(blocking_practice)
	blocking_practice.configure_block(preview_player,drill_status,build_label)
	blocking_practice.set_ball_audio_muted(StorySession.attack_ball_audio_muted)
	preview_camera.position = Vector3(0.0,4.9,-5.2)
	preview_camera.look_at(Vector3(0.0,2.1,4.6))
	preview.grab_focus()

func stop_blocking_practice() -> void:
	if not is_instance_valid(blocking_practice): return
	blocking_practice.stop_block()
	blocking_frame.queue_free()
	blocking_practice = null
	blocking_frame = null

func start_serve_bump_set_spike() -> void:
	if player_controls.active: player_controls.set_active(false)
	clear_content()
	if is_instance_valid(ball_preview): ball_preview.stop()
	set_title("SERVE BUMP SET SPIKE")
	var controls_hint := label("WASD to move  |  Q forearms  |  E / I hands\nCursor aims  |  Scroll for pass or set height\nShift + W to run  |  Hold Space to spike",16)
	controls_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(controls_hint)
	drill_status = label("",18)
	drill_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	drill_status.custom_minimum_size.y = 50
	content.add_child(drill_status)
	setter_original_transform = preview_player.transform
	setter_original_height = preview_player.height_cm
	setter_animation_process = preview_player.animator.callback_mode_process
	setter_animator_active = preview_player.animator.active
	preview_player.set_height_cm(setter_original_height+10.0)
	preview_player.animator.active = true
	preview_player.animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	preview_player.get_node("DirectionArrows").hide()
	setting_drill = preload("res://scripts/serve_bump_set_spike.gd").new()
	setting_drill.swing_practice = false
	preview_player.get_parent().add_child(setting_drill)
	setting_drill.configure(preview_player,drill_status,true,build_label)
	setting_drill.setup_demo()
	var call := label("",18)
	call.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	call.hide()
	content.add_child(call)
	setting_drill.rally_set_call = call
	var technique := OptionButton.new()
	for title in ["Hands set","Forearm set","Jump set","Spike or fake jump set"]: technique.add_item(title)
	technique.item_selected.connect(func(index: int): setting_drill.cpu_set_style = index)
	content.add_child(technique)
	var serve_side := OptionButton.new()
	serve_side.add_item("Serve to you")
	serve_side.add_item("Serve to teammate")
	serve_side.item_selected.connect(func(index: int):
		setting_drill.serve_to_partner = index == 1
		technique.disabled = index == 1
		controls_hint.text = "Aim the set with the cursor\nScroll to change set height\nQ forearms  |  E / I hands\nHold Space to spike\nF to jump set" if index == 1 else "WASD to move  |  Q forearms  |  E / I hands\nCursor aims  |  Scroll for pass or set height\nShift + W to run  |  Hold Space to spike"
		setting_drill.reset_feed())
	content.add_child(serve_side)
	content.add_child(button("Replay",setting_drill.reset_feed))
	setting_camera_focus = SETTING_CAMERA_FOCUS
	preview_camera.position = Vector3(0.0,8.0,-14.0)
	preview_camera.look_at(setting_camera_focus)
	preview.grab_focus()

func current_type() -> String:
	if selected_category.is_empty(): return ""
	return MOVE_TYPES[selected_category][type_indices.get(selected_category,0)]

func start_setting_drill(attack := false) -> void:
	if player_controls.active: player_controls.set_active(false)
	if is_instance_valid(ball_preview): ball_preview.stop()
	right_panel.hide()
	angle_control.hide()
	angle_control.pending = false
	var modes := OptionButton.new()
	modes.name = "AttackingType" if attack else "SettingType"
	var mode_category := "Attacking" if attack else "Setting"
	var mode_names: Array = ["Swing Practice","Full Rally","Approach Practice"] if attack else MOVE_TYPES["Setting"]
	for mode in mode_names: modes.add_item(mode)
	modes.select(type_indices.get(mode_category,0))
	content.add_child(modes)
	var controls_hint := label("",16)
	controls_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var show_mode := func(index: int):
		if attack:
			controls_hint.visible = index != 0
			if index == 2:
				controls_hint.text = "WASD to move  |  Hold Space when rings overlap\nHold from setter touch to spike\nMove mouse to aim\nDrag player or set ring\nCtrl-click start  |  Shift-click set"
				return
			controls_hint.text = "WASD to move  |  Q forearms  |  I / E hands\nMouse to aim  |  Shift + scroll for pass height\nHold Space from setter touch to spike"
			return
		controls_hint.text = "WASD to move  |  Tap Q to bump set\nMouse to aim  |  Scroll to change height" if index == 1 else "WASD to move  |  Tap E to set\nMouse to aim  |  Scroll to change height\nSpace jump  |  7 to 50 in"
	show_mode.call(modes.selected)
	modes.item_selected.connect(func(index: int):
		type_indices[mode_category] = index
		if attack: setting_drill.set_swing_practice(index == 0,index == 2)
		else: setting_drill.set_bump_mode(index == 1)
		show_mode.call(index)
		preview.grab_focus())
	content.add_child(controls_hint)
	var setter_call: Label
	if attack:
		setter_call = label("",20)
		setter_call.add_theme_color_override("font_color",Color("ffd278"))
		setter_call.hide()
		content.add_child(setter_call)
	drill_status = label("",16)
	drill_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(drill_status)
	setter_original_transform = preview_player.transform
	setter_original_height = preview_player.height_cm
	if attack: preview_player.set_height_cm(setter_original_height+10.0)
	setter_animation_process = preview_player.animator.callback_mode_process
	setter_animator_active = preview_player.animator.active
	preview_player.animator.active = true
	preview_player.animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	preview_player.position = Vector3(1.45,0.04,-1.8)
	preview_player.rotation.y = 0.0
	preview_player.get_node("DirectionArrows").hide()
	player_controls.locomotion = ""
	player_controls.setter_travel = Vector3.ZERO
	player_controls.setter_step_rate = player_controls.QUICK_STEP_RATE
	player_controls.show_stamina(true)
	player_controls.footwork.weight = 0.0
	player_controls.footwork.travel = Vector3.ZERO
	player_controls.side_weight = 0.0
	player_controls.side_steps.active = false
	player_controls.indicator.text = "Attacker" if attack else "Setter"
	setting_camera_focus = SETTING_CAMERA_FOCUS
	preview_camera.position = Vector3(0,7.5,-11.2)
	preview_camera.look_at(setting_camera_focus)
	setting_drill = preload("res://scripts/attack_drill.gd").new() if attack else preload("res://scripts/setting_drill.gd").new()
	if attack:
		setting_drill.rally_set_call = setter_call
		setting_drill.swing_practice = modes.selected == 0
		setting_drill.approach_practice = modes.selected == 2
		setting_drill.jump.max_height += 5.0*0.0254
	preview_player.get_parent().add_child(setting_drill)
	setting_drill.configure(preview_player,drill_status,modes.selected == 1,build_label)
	if attack:
		setting_drill.set_ball_audio_muted(StorySession.attack_ball_audio_muted)
		show_attack_positions(modes)
		var attack_tuning_start := content.get_child_count()
		setting_drill.bump.set_custom_backward(load_custom_backward_clip())
		add_low_bow_controls()
		var play_shots := button("Play",func():
			setting_drill.toggle_shot_sequence()
			preview.grab_focus())
		play_shots.name = "PlayAttackShots"
		play_shots.visible = modes.selected == 0
		content.add_child(play_shots)
		setting_drill.shot_sequence_changed.connect(func(playing: bool): play_shots.text = "Stop" if playing else "Play")
		add_attack_tuning_slider(content,"Air turn speed","AttackAirTurnSpeed","°/s",0,720,10,setting_drill.air_turn_speed,
			func(value: float): setting_drill.air_turn_speed = value)
		add_attack_pose_slider("Torso rotation","TorsoRotation",50,setting_drill.torso_rotation_scale,
			func(value: float): setting_drill.torso_rotation_scale = value)
		add_attack_pose_slider("Leg kickback","LegKickback",0,setting_drill.leg_kickback_scale,
			func(value: float): setting_drill.leg_kickback_scale = value)
		add_attack_pose_slider("Leg rotation","LegRotation",0,setting_drill.leg_rotation_scale,
			func(value: float): setting_drill.leg_rotation_scale = value)
		add_torso_lean_slider()
		var attack_tuning := content.get_children().slice(attack_tuning_start)
		var show_attack_tuning := func(index: int):
			for control in attack_tuning: control.visible = index != 2
			play_shots.visible = index == 0
		modes.item_selected.connect(show_attack_tuning)
		show_attack_tuning.call(modes.selected)
	else:
		add_torso_lean_slider()
	preview.grab_focus()

func show_attack_positions(modes: OptionButton) -> void:
	attack_position_panel = panel()
	attack_position_panel.name = "AttackPositions"
	attack_position_panel.custom_minimum_size.x = 250
	right_panel.get_parent().add_child(attack_position_panel)
	var scroll := ScrollContainer.new()
	scroll.name = "AttackPositionScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	attack_position_panel.add_child(scroll)
	var positions := VBoxContainer.new()
	positions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(positions)
	positions.add_child(label("Court positions",18))
	var map := preload("res://scripts/attack_position_map.gd").new()
	map.drill = setting_drill
	positions.add_child(map)

	var slow_motion := CheckButton.new()
	slow_motion.name = "AttackSlowMotion"
	positions.add_child(slow_motion)
	var speed := HSlider.new()
	speed.name = "AttackPlaybackSpeed"
	speed.min_value = 0.1
	speed.max_value = 0.8
	speed.step = 0.01
	speed.value = 0.4
	speed.custom_minimum_size.y = 24
	positions.add_child(speed)
	var update_speed := func():
		attack_playback_speed = speed.value if slow_motion.button_pressed else 1.0
		slow_motion.text = "Slow motion  %.2f×" % speed.value
	speed.value_changed.connect(func(_value: float):
		slow_motion.set_pressed_no_signal(true)
		update_speed.call())
	slow_motion.toggled.connect(func(_enabled: bool): update_speed.call())
	update_speed.call()

	add_attack_tuning_slider(positions,"Ball bounciness","AttackBallBounciness","%",25,400,5,setting_drill.ball_bounciness*100.0,
		func(value: float): setting_drill.ball_bounciness = value/100.0)

	var bend := add_attack_tuning_slider(positions,"Backswing bend","AttackBackswingBend","°",0,120,1,setting_drill.backswing_bend,
		func(value: float): setting_drill.backswing_bend = value)
	var reach := add_attack_tuning_slider(positions,"Backswing reach","AttackBackswingReach","cm",0,75,1,setting_drill.backswing_reach*100.0,
		func(value: float): setting_drill.backswing_reach = value/100.0)

	var set_height := add_attack_tuning_slider(positions,"Set height","ApproachSetHeight","m",4.2,7.5,0.1,setting_drill.approach_set_apex,
		func(value: float): setting_drill.approach_set_apex = value)

	var tilt := add_attack_tuning_slider(positions,"Two-step torso tilt","ApproachTorsoTilt","°",1,90,1,setting_drill.two_step_tilt,
		func(value: float): setting_drill.two_step_tilt = value)

	var delay := add_attack_tuning_slider(positions,"Draw delay","LowBowDrawDelay","ms",-220,240,5,setting_drill.draw_delay*1000.0,
		func(value: float): setting_drill.draw_delay = value/1000.0)
	var clearance := add_attack_tuning_slider(positions,"Elbow clearance","AttackElbowClearance","cm",0,36,1,setting_drill.elbow_clearance*100.0,
		func(value: float): setting_drill.elbow_clearance = value/100.0)

	var reset := button("Reset swing tuning",func():
		delay.value = setting_drill.SpikeArm.DEFAULT_DRAW_DELAY*1000.0
		clearance.value = setting_drill.SpikeArm.DEFAULT_ELBOW_CLEARANCE*100.0
		bend.value = setting_drill.DEFAULT_BACKSWING_BEND
		reach.value = setting_drill.DEFAULT_BACKSWING_REACH*100.0
		preview.grab_focus())
	reset.name = "ResetAttackTuning"
	positions.add_child(reset)
	var approach_controls := [slow_motion,speed]
	approach_controls.append_array(positions.get_children().slice(bend.get_index()-1,reach.get_index()+1))
	var approach_only_controls := positions.get_children().slice(set_height.get_index()-1,tilt.get_index()+1)
	var show_position_controls := func(index: int):
		for control in positions.get_children():
			control.visible = control in approach_controls or control in approach_only_controls if index == 2 else control not in approach_only_controls
		update_speed.call()
	modes.item_selected.connect(show_position_controls)
	show_position_controls.call(modes.selected)

func add_attack_tuning_slider(panel_content: VBoxContainer, caption: String, node_name: String, units: String, minimum: float, maximum: float, step: float, initial: float, apply: Callable) -> HSlider:
	var readout := label("",16)
	panel_content.add_child(readout)
	var slider := HSlider.new()
	slider.name = node_name
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = StorySession.attack_swing_tuning.get(node_name,initial)
	slider.custom_minimum_size.y = 24
	panel_content.add_child(slider)
	var update := func(value: float):
		StorySession.attack_swing_tuning[node_name] = value
		apply.call(value)
		var number := "%.1f" % value if step < 1.0 else str(roundi(value))
		readout.text = "%s  %s %s" % [caption,number,units]
	slider.value_changed.connect(update)
	update.call(slider.value)
	return slider

func add_low_bow_controls() -> void:
	content.add_child(label(setting_drill.SpikeArm.SWING_NAME,16))
	content.add_child(button("Open swing editor",open_low_bow_editor))

func add_torso_lean_slider() -> void:
	var readout := label("",16)
	content.add_child(readout)
	var slider := HSlider.new()
	slider.name = "TorsoLean"
	slider.min_value = -30
	slider.max_value = 20
	slider.step = 1
	slider.custom_minimum_size.y = 24
	slider.value = setting_drill.torso_lean_degrees
	var update := func(value: float):
		setting_drill.torso_lean_degrees = value
		readout.text = "Torso lean  |  %d\u00b0" % roundi(value)
	slider.value_changed.connect(update)
	update.call(slider.value)
	content.add_child(slider)

func add_attack_pose_slider(caption: String, node_name: String, minimum: float, initial: float, apply: Callable) -> void:
	var rotation_readout := label("",16)
	content.add_child(rotation_readout)
	var slider := HSlider.new()
	slider.name = node_name
	slider.min_value = minimum
	slider.max_value = 200
	slider.step = 5
	slider.custom_minimum_size.y = 24
	slider.value = initial*100.0
	var update := func(value: float):
		apply.call(value/100.0)
		rotation_readout.text = "%s  |  %d%%" % [caption,roundi(value)]
	slider.value_changed.connect(update)
	update.call(slider.value)
	content.add_child(slider)

func stop_setting_drill() -> void:
	attack_playback_speed = 1.0
	if not is_instance_valid(setting_drill): return
	if is_instance_valid(attack_position_panel):
		attack_position_panel.hide()
		attack_position_panel.queue_free()
		attack_position_panel = null
	if marker_fade != null: marker_fade.kill()
	marker_popup.hide()
	jump_height_meter.hide()
	setting_drill.restore_torso_lean(preview_player)
	setting_drill.queue_free()
	setting_drill = null
	preview_player.set_height_cm(setter_original_height)
	preview_player.transform = setter_original_transform
	preview_player.animator.callback_mode_process = setter_animation_process
	preview_player.animator.active = setter_animator_active
	preview_player.animator.speed_scale = 1.0
	preview_player.model.rotation.y = 0.0
	preview_player.get_node("DirectionArrows").show()
	player_controls.indicator.text = "Camera"
	player_controls.stamina_ring.set_airborne_lift(0.0)
	player_controls.show_stamina(false)
	update_camera()

func stop_serving_session() -> void:
	if selected_category != "Serving" or not is_instance_valid(preview_player): return
	stop_underhand_serve()
	preview_player.transform = serving_original_transform
	preview_player.animator.speed_scale = 1.0
	preview_player.get_node("DirectionArrows").show()
	serving_running = false

func stop_underhand_serve() -> void:
	if is_instance_valid(serving_spin_controls):
		content.remove_child(serving_spin_controls)
		serving_spin_controls.queue_free()
		serving_spin_controls = null
	if is_instance_valid(serving_rally_status):
		content.remove_child(serving_rally_status)
		serving_rally_status.queue_free()
		serving_rally_status = null
	if is_instance_valid(serve_opponent_frame):
		serve_opponent_frame.queue_free()
		serve_opponent_frame = null
		serve_opponents = null
	if not is_instance_valid(underhand_serve): return
	underhand_serve.stop()
	underhand_serve = null

func refresh_type() -> void:
	stop_underhand_serve()
	right_panel.hide()
	angle_control.hide()
	type_label.text = current_type()
	selected_entry.clear()
	if selected_category == "Forearm reception":
		for entry in Catalog.entries(selected_category,current_type()):
			if entry.id == preview_player.FOREARM_PLATFORM:
				preview_entry(entry)
				return
		if is_instance_valid(ball_preview): ball_preview.stop()
		return
	var serving_practice := selected_category == "Serving" and current_type() in ["Underhand","Standing Float","Jump Float","Spin"]
	animation_list.visible = not serving_practice
	edit_button.visible = not serving_practice
	if selected_category == "Serving" and is_instance_valid(drill_status):
		drill_status.text = "Space to serve\nMove cursor to aim\nWASD to run\nMiddle drag to rotate\nScroll for arc  |  Shift + scroll to zoom" if serving_practice else "WASD to run"
	if serving_practice:
		if is_instance_valid(ball_preview): ball_preview.stop()
		var serve_script := preload("res://scripts/underhand_serve.gd")
		match current_type():
			"Standing Float": serve_script = preload("res://scripts/standing_float_serve.gd")
			"Jump Float": serve_script = preload("res://scripts/jump_float_serve.gd")
			"Spin": serve_script = preload("res://scripts/spin_serve.gd")
		underhand_serve = serve_script.new()
		serving_position.z = minf(serving_position.z,underhand_serve.front_start_limit())
		preview_player.get_parent().add_child(underhand_serve)
		underhand_serve.configure(preview_player,serving_position)
		if current_type() == "Spin": add_serve_spin_controls()
		serve_opponent_frame = Node3D.new()
		serve_opponent_frame.position.z = 8.0
		serve_opponent_frame.rotation.y = PI
		preview_player.get_parent().add_child(serve_opponent_frame)
		serve_opponents = preload("res://scripts/serve_opponent_rally.gd").new()
		serve_opponents.swing_practice = false
		serve_opponent_frame.add_child(serve_opponents)
		serving_rally_status = label("",16)
		serving_rally_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(serving_rally_status)
		serve_opponents.configure_team(serving_rally_status,build_label)
		serve_opponents.set_ball_audio_muted(StorySession.attack_ball_audio_muted)
		preview.grab_focus()
		return
	if selected_category == "Serving":
		serving_running = false
		preview_player.position = serving_position
		preview_player.rotation.y = 0.0
	animation_list.clear()
	if is_instance_valid(edit_button): edit_button.disabled = true
	for entry in Catalog.entries(selected_category,current_type()):
		var index: int = animation_list.item_count
		animation_list.add_item(entry.name)
		animation_list.set_item_metadata(index,entry)
	if animation_list.item_count > 0:
		animation_list.select(0)
		preview_animation(0)
	elif is_instance_valid(preview_player):
		preview_player.play_action("idle")
		if is_instance_valid(ball_preview): ball_preview.stop()

func preview_animation(index: int) -> void:
	if is_instance_valid(animation_list):
		preview_entry(animation_list.get_item_metadata(index))

func preview_entry(entry: Dictionary) -> void:
	reception_review.stop(false)
	if not is_instance_valid(preview_player): return
	selected_entry = entry.duplicate(true)
	if is_instance_valid(edit_button): edit_button.disabled = false
	set_cpu_arrows_pinned(false)
	angle_control.apply_setup(preview_player,selected_category == "Forearm reception")
	if selected_category == "Forearm reception":
		preview_player.set_meta("reception_options",{"body":"Balanced","hands":"From platform","replace_body":false})
	source_clip = Catalog.load_clip(entry,preview_player)
	if source_clip==null: return
	trajectory_solver = preload("res://scripts/pass_trajectory_solver.gd").new(preview_player,source_clip)
	render_clip = source_clip
	if source_clip.has_meta("contact_time"):
		render_clip = trajectory_solver.solve(StorySession.pass_output_angle if StorySession.pass_output_angle >= 0 else 45.0,StorySession.pass_distance).clip
	preview_player.install_custom(render_clip,"preview",false)
	if not is_instance_valid(ball_preview):
		ball_preview = BallPreview.new()
		preview_player.get_parent().add_child(ball_preview)
	ball_preview.practice_mode = selected_category == "Forearm reception"
	reset_cpu_receive(false)
	player_controls.clear_receive_transition()
	ball_preview.configure(preview_player,render_clip)
	preview_clock = minf(0,ball_preview.contact_time-ball_preview.feed_duration)
	preview_player.animator.play("custom_preview/clip",0)
	preview_player.animator.advance(0)
	preview_player.animator.pause()
	right_panel.visible = ball_preview.active
	angle_control.visible = ball_preview.active
	if ball_preview.active: sync_ball_results(float(render_clip.get_meta("desired_output_angle",ball_preview.output_angle())))

func apply_output_angle(value: float) -> void:
	reception_review.stop(false)
	if source_clip == null or not source_clip.has_meta("contact_time"): return
	set_cpu_arrows_pinned(false)
	angle_control.apply_setup(preview_player,selected_category == "Forearm reception")
	StorySession.pass_output_angle = value
	var result: Dictionary = trajectory_solver.solve(value,StorySession.pass_distance)
	var last_contact_clock: float = ball_preview.last_time
	render_clip = result.clip
	preview_player.install_custom(render_clip,"preview",false)
	preview_player.animator.play("custom_preview/clip",0)
	preview_player.animator.seek(ball_preview.animation_time(preview_clock),true)
	preview_player.animator.advance(0)
	preview_player.animator.pause()
	reset_cpu_receive(false)
	player_controls.clear_receive_transition()
	ball_preview.configure(preview_player,render_clip)
	ball_preview.tick(preview_clock,false)
	ball_preview.last_time = last_contact_clock
	angle_control.pending = false
	sync_ball_results(value)

func update_feed_aim() -> void:
	reception_review.stop(false)
	if not is_instance_valid(ball_preview) or not ball_preview.active: return
	reset_cpu_receive(not player_controls.active)
	if not player_controls.active:
		player_controls.clear_receive_transition()
		preview_player.animator.play("custom_preview/clip",0)
		preview_player.animator.seek(0.0,true)
		preview_player.animator.pause()
	angle_control.apply_feed_aim(preview_player)
	ball_preview.recalculate()
	preview_clock = minf(0.0,ball_preview.contact_time-ball_preview.feed_duration)
	ball_preview.tick(preview_clock,false)
	sync_ball_results(angle_control.requested)

func sync_ball_results(value: float) -> void:
	if ball_preview.missed:
		angle_control.actual_label.visible = true
		angle_control.actual_label.text = "Feed aimed at a Distance %d arrow" % StorySession.receive_distance_tier
		return
	angle_control.sync_feed(ball_preview.feed_info)
	angle_control.sync_output(ball_preview)
	angle_control.display_result(value,ball_preview.output_angle(),Flight.distance(ball_preview.impact_point,ball_preview.outgoing))

func reception_drill_active() -> bool:
	return is_instance_valid(ball_preview) and ball_preview.active and ball_preview.practice_mode

func _process(delta: float) -> void:
	pass_timing_cue.hide()
	if is_instance_valid(blocking_practice):
		preview_camera.position += camera_pan_delta(player_controls.movement_input(),delta,5.0)
		blocking_practice.tick_block(delta)
		return
	if selected_category == "Serving":
		move_server(player_controls.movement_input(),delta)
		if is_instance_valid(underhand_serve):
			step_underhand_rally(delta)
			return
		if serving_running or selected_entry.is_empty(): return
	if is_instance_valid(setting_drill) and selected_category == "Chasing":
		setting_drill.tick_demo(delta,player_controls)
		return
	if is_instance_valid(setting_drill):
		if selected_category == "Attacking" and not setting_drill.approach_setup_drag.is_empty(): return
		delta *= attack_playback_speed
		setting_drill.restore_torso_lean(preview_player)
		player_controls.read_pace_input()
		setting_drill.trace_input = player_controls.movement_input()
		var approach_speed := 0.0
		var approach_rate := 0.0
		if selected_category == "Attacking" and setting_drill.uses_assisted_approach():
			setting_drill.trace_input = setting_drill.queued_approach_input(delta,player_controls.sprint_requested)
			approach_speed = setting_drill.approach_run_speed
			approach_rate = 1.45
		setting_drill.trace_sprint = player_controls.sprint_requested
		var diving: bool = setting_drill.setter_is_diving()
		setting_drill.trace_move_scale = 0.0 if diving else setting_drill.setter_movement_scale()
		var court_weight: float = setting_drill.court_facing_weight()
		if selected_category == "Attacking": setting_drill.approach_from_sprint = false
		if not diving and not setting_drill.jump.active:
			var run_after_pass: bool = selected_category == "Attacking" and setting_drill.uses_assisted_approach() and not setting_drill.approach_practice and setting_drill.stage in [setting_drill.Stage.PASS,setting_drill.Stage.SET]
			var running_forward: bool = run_after_pass and player_controls.sprint_requested and player_controls.stamina.can_sprint() and setting_drill.trace_input.y > 0.3
			var attacking_approach: bool = selected_category == "Attacking" and (setting_drill.stage == setting_drill.Stage.SET or setting_drill.approach_practice)
			if attacking_approach or running_forward:
				var approach: Vector2 = setting_drill.trace_input
				if setting_drill.approach_practice:
					var heading := atan2(-approach.x,maxf(0.65,approach.y)) if approach.y > 0.05 else 0.0
					preview_player.rotation.y = rotate_toward(preview_player.rotation.y,clampf(heading,-0.60,0.60),delta*8.0)
				elif approach.y > 0.05:
					var heading := atan2(-approach.x,approach.y)
					preview_player.rotation.y = rotate_toward(preview_player.rotation.y,heading,delta*8.0)
			var track_ball: bool = not running_forward and not attacking_approach and not setting_drill.bump.backward_reach_active()
			player_controls.move_player(setting_drill.trace_input,delta,false,setting_drill.ball.global_position,setting_drill.trace_move_scale,court_weight,track_ball,setting_drill.jump.front_limit,approach_speed,approach_rate,run_after_pass)
			if run_after_pass and player_controls.sprinting:
				setting_drill.approach_from_sprint = true
			if not player_controls.sprinting: setting_drill.apply_setter_arms(player_controls.footwork.phase,player_controls.moving,delta)
		elif setting_drill.jump.active and court_weight > 0.0:
			player_controls.track_setting_ball(preview_player,setting_drill.ball.global_position,delta,court_weight)
		setting_drill.step_jump(delta)
		if not diving: setting_drill.apply_torso_lean(preview_player)
		update_jump_height_meter()
		var jump_lift: float = preview_player.position.y-setting_drill.jump.start.y if setting_drill.jump.active else 0.0
		player_controls.stamina_ring.set_airborne_lift(jump_lift)
		var was_diving: bool = setting_drill.bump.low_save.active
		setting_drill.step(delta)
		if not was_diving and setting_drill.bump.low_save.active:
			player_controls.setter_travel = Vector3.ZERO
			player_controls.spend_dive_stamina()
		setting_drill.update_ball_ring()
		return
	if reception_review.frozen:
		var direction: Vector2 = player_controls.movement_input()
		if player_controls.active: player_controls.pan_frozen_camera(direction,delta)
		else: pan_camera(direction,delta)
		return
	if reception_review.active:
		reception_review.step(delta)
		return
	if reception_drill_active(): delta = reception_review.playback_delta(delta)
	super._process(delta)
	var in_control: bool = player_controls!=null and player_controls.active
	if not is_instance_valid(ball_preview) or not ball_preview.active:
		return
	var drill := reception_drill_active()
	set_cpu_arrows_pinned(drill and not in_control)
	var first := minf(0,ball_preview.contact_time-ball_preview.feed_duration)
	var last: float = ball_preview.cycle_end()
	if not cpu_side_slide_pose.is_empty():
		last = maxf(last,cpu_side_slide_time+SideKneeSlide.DURATION)
	if not cpu_dive_ready.is_empty():
		last = maxf(last,ball_preview.contact_time+ForwardDive.DURATION-ForwardDive.WINDUP)
	if drill and not in_control and cpu_start.is_finite() and preview_clock+delta >= last:
		if not player_controls.settle_for_next_feed(cpu_start,cpu_start_yaw,delta):
			preview_clock = last
			drill_status.text = "CPU resetting  |  F1 to take control"
			ball_preview.tick(preview_clock,false)
			ball_preview.ball.hide()
			ball_preview.update_practice_aim(true)
			return
	var previous := preview_clock
	if setup_drag.mode.is_empty() or reception_drill_active():
		preview_clock = first+fposmod(preview_clock-first+delta,last-first)
	if reception_drill_active():
		if preview_clock < previous:
			reset_cpu_receive(not in_control)
			if not in_control: player_controls.clear_receive_transition()
			ball_preview.reset_practice_serve()
			player_controls.reset_receive_attempt()
			player_controls.reset_reach()
			if in_control: drill_status.text = "Next serve  |  Tap Q just before contact"
			else: drill_status.text = "CPU receiving  |  F1 to take control"
		elif in_control:
			reset_cpu_receive(false)
			var hit := false
			if player_controls.low_save.active and player_controls.low_save.pancake:
				hit = ball_preview.try_pancake(previous,preview_clock,player_controls.receive_elapsed)
			elif player_controls.receive_pose_elapsed > 0.0:
				hit = ball_preview.try_practice_pass(previous,preview_clock,player_controls.receive_elapsed)
			if hit: drill_status.text = BallTimingRing.result_text(ball_preview.practice_grade,"pass")
			var floor_time: float = ball_preview.contact_time+ball_preview.practice_floor_time
			if ball_preview.practice_early_attempt and ball_preview.crossed(preview_clock,floor_time):
				ball_preview.finish_practice_serve()
				drill_status.text = BallTimingRing.result_text(ball_preview.practice_grade,"pass")
		else:
			step_cpu_receive(previous,delta)
		var attempted: bool = ball_preview.practice_early_attempt
		if preview_clock >= previous and ball_preview.try_body_dig(previous,preview_clock) and (not in_control or attempted):
			drill_status.text = body_dig_status()
		var approach: float = ball_preview.practice_approach(preview_clock,1.12) if in_control and ball_preview.practice_grade == BallPreview.Grade.WAITING else -1.0
		var anticipated: float = player_controls.receive_elapsed
		if approach >= 0.0: anticipated += (1.0-approach)*BallPreview.APPROACH_WINDOW
		var recent_touch: bool = ball_preview.recovery.has("spread") and preview_clock-ball_preview.contact_time-float(ball_preview.recovery.time) <= BallTimingRing.RESULT_DURATION
		ball_preview.update_practice_cone(in_control and (approach >= 0.0 or recent_touch),anticipated)
		ball_preview.update_practice_aim(true)
		update_distance_status(in_control or cpu_start.is_finite())
	else:
		if not in_control: preview_player.animator.seek(ball_preview.animation_time(preview_clock),true)
	ball_preview.tick(preview_clock,true)
	if drill and ball_preview.ball.visible:
		var source_time: float = ball_preview.contact_time-ball_preview.feed_duration
		var point: Vector3 = ball_preview.global_position
		pass_timing_cue.global_position = Vector3(point.x,0.058,point.z)
		if ball_preview.recovery.has("spread") and preview_clock-ball_preview.contact_time-float(ball_preview.recovery.time) <= BallTimingRing.RESULT_DURATION:
			pass_timing_cue.show_result(ball_preview.practice_grade)
		else:
			pass_timing_cue.update_timing(preview_clock-source_time,ball_preview.feed_duration,BallPreview.GREEN_START,BallPreview.GREEN_END,not ball_preview.recovery.is_empty() or not ball_preview.incoming_net.is_empty())

func update_jump_height_meter() -> void:
	var jump = setting_drill.jump
	if not jump.active:
		jump_height_meter.hide()
		return
	var feet := Vector3(preview_player.global_position.x,jump.start.y,preview_player.global_position.z)
	var projected := preview_camera.unproject_position(feet)*preview.size/Vector2(preview_camera.get_viewport().size)
	jump_height_meter.show_height(projected,preview.size,jump.height,jump.max_height)

func set_cpu_arrows_pinned(pinned: bool) -> void:
	var arrows: MeshInstance3D = preview_player.get_node("DirectionArrows")
	if arrows.top_level == pinned: return
	var placement := arrows.global_transform
	arrows.top_level = pinned
	if pinned:
		arrows.global_transform = placement
	else:
		arrows.transform = Transform3D.IDENTITY

func reset_cpu_receive(restore_position: bool) -> void:
	if cpu_start.is_finite():
		if restore_position:
			preview_player.position = cpu_start
			preview_player.rotation.y = cpu_start_yaw
		player_controls.reset_reach()
	cpu_start = Vector3.INF
	cpu_receive_clock = -INF
	cpu_reach_offset = Vector3.INF
	cpu_dive_ready.clear()
	cpu_side_slide_pose.clear()

func step_cpu_receive(previous: float, delta: float) -> void:
	var arrows = preview_player.get_node("DirectionArrows")
	if custom_backward_clip != null and arrows.selected_distance == 2 and arrows.selected == 5:
		if not cpu_start.is_finite():
			cpu_start = preview_player.position
			cpu_start_yaw = preview_player.rotation.y
			preview_player.install_custom(custom_backward_clip,"backward_receive",false)
		if sample_custom_backward(previous): drill_status.text = "Clean platform contact"
		return
	if arrows.selected_distance == 4:
		step_cpu_forward_dive(previous,true)
		return
	var knee_slide: bool = arrows.selected_distance == 3 and arrows.selected in [3,7]
	if arrows.selected != 0 and arrows.selected_distance == 3 and not knee_slide:
		if arrows.selected in [1,2,8]: step_cpu_forward_dive(previous)
		return
	if not cpu_side_slide_pose.is_empty():
		preview_player.pose_reception_knee_slide(cpu_side_slide_pose,
			player_controls.receive_ready_pose,cpu_side_slide_start,player_controls.reach_lead,preview_clock-cpu_side_slide_time,ball_preview.recovery)
		return
	var short_back: bool = arrows.selected_distance == 1 and arrows.selected == 5
	if not is_finite(cpu_receive_clock):
		if arrows.selected != 0:
			var direction: int = player_controls.receive_animation_direction()
			var deep_rear: bool = arrows.selected_distance == 2 and direction in [4,5,6]
			var short_straight: bool = arrows.selected_distance == 1 and direction in [1,5]
			var windup_time := 0.12 if short_back else (0.26 if deep_rear else (0.22 if short_straight or knee_slide else 0.18))
			var straight_back: bool = arrows.selected_distance == 2 and direction == 5
			var setup_step: bool = direction != arrows.selected or straight_back or short_back
			var until_contact: float = ball_preview.contact_time-preview_clock
			if not ball_preview.incoming_net.is_empty(): return
			var setup_time := 0.38 if short_back else (0.34 if direction == 7 else 0.24)
			if setup_step and until_contact <= windup_time+setup_time and until_contact > windup_time:
				if not cpu_start.is_finite():
					cpu_start = preview_player.position
					cpu_start_yaw = preview_player.rotation.y
				var setup_distance := 0.48 if short_back else (0.28 if straight_back else (0.55 if direction == 7 else 0.42))
				player_controls.step_back_for_lunge(cpu_start,arrows.global_basis.z,delta,setup_distance)
				return
			if until_contact > windup_time: return
			cpu_reach_offset = ball_preview.aim_point-ball_preview.platform(ball_preview.contact_time).ball
			if direction != arrows.selected:
				var sideways: Vector3 = arrows.global_basis.orthonormalized()*arrows.direction(direction)
				cpu_reach_offset = sideways*Vector2(cpu_reach_offset.x,cpu_reach_offset.z).length()+Vector3.UP*cpu_reach_offset.y
		else:
			var approach: float = ball_preview.practice_approach(preview_clock)
			if approach < 0.45:
				preview_player.animator.play("custom_preview/clip",0)
				preview_player.animator.seek(0.0,true)
				preview_player.animator.pause()
				return
		if not cpu_start.is_finite():
			cpu_start = preview_player.position
			cpu_start_yaw = preview_player.rotation.y
		cpu_receive_clock = preview_clock
		drill_status.text = "CPU receiving  |  F1 to take control"
	var elapsed := preview_clock-cpu_receive_clock
	if knee_slide and (not ball_preview.recovery.is_empty() or elapsed >= 0.28):
		cpu_side_slide_pose = player_controls.snapshot_receive_pose()
		cpu_side_slide_start = preview_player.position
		cpu_side_slide_time = preview_clock
		ball_preview.practice_reach_center = Vector3.INF
		if ball_preview.recovery.has("spread"):
			drill_status.text = "Clean platform contact"
			if not ball_preview.recovery_net.is_empty(): drill_status.text += "  |  Pass hit the net"
		elif ball_preview.recovery.has("body_touch"):
			drill_status.text = body_dig_status()
		else:
			drill_status.text = "Platform missed"
		return
	var after_touch := 0.0
	if ball_preview.recovery.has("spread"):
		after_touch = maxf(0.0,preview_clock-ball_preview.contact_time-float(ball_preview.recovery.time))
	var continuing: bool = after_touch < player_controls.RECEIVE_FOLLOW_TIME if ball_preview.recovery.has("spread") else elapsed <= 0.44
	if continuing and not ball_preview.recovery.has("body_touch"):
		var windup := 0.14*(1.0-smoothstep(0.0,0.12,elapsed))
		player_controls.play_receive_pose(delta,cpu_reach_offset,-windup+after_touch*1.4,short_back)
		if ball_preview.try_practice_pass(previous,preview_clock,0.16):
			drill_status.text = "CPU pass  |  F1 to take control"
	else:
		player_controls.end_receive_pose()
		player_controls.reset_reach()
		preview_player.animator.seek(0.0,true)
		player_controls.blend_receive_recovery(delta)

func body_dig_status() -> String:
	var part := str(ball_preview.recovery.get("body_part",""))
	if part.begins_with("upperarm"): return "Body dig  |  Shoulder or upper-arm deflection"
	if part == "Head": return "Body dig  |  Head deflection"
	return "Body dig  |  Deflected off the player"

func step_cpu_forward_dive(previous: float, pancake := false) -> void:
	var time: float = preview_clock-ball_preview.contact_time+ForwardDive.WINDUP
	if time < 0.0 or not ball_preview.incoming_net.is_empty(): return
	if cpu_dive_ready.is_empty():
		cpu_start = preview_player.position
		cpu_start_yaw = preview_player.rotation.y
		preview_player.animator.play("custom_preview/clip",0)
		preview_player.animator.seek(0.0,true)
		preview_player.animator.pause()
		cpu_dive_ready = player_controls.snapshot_receive_pose()
		preview_player.animator.seek(ball_preview.contact_time,true)
		cpu_dive_clasp = player_controls.snapshot_receive_pose()
		preview_player.animator.seek(0.0,true)
	var heading: Vector3 = (ball_preview.aim_point-cpu_start).slide(Vector3.UP).normalized()
	preview_player.pose_reception_dive(cpu_dive_ready,cpu_dive_clasp,cpu_start,heading,time,ball_preview.aim_point,float(ball_preview.recovery.get("time",0.07))+ForwardDive.WINDUP,pancake)
	if pancake:
		ball_preview.try_pancake(previous,preview_clock)
		drill_status.text = "Pancake save" if ball_preview.recovery.has("pancake") else "CPU pancake reach"
		return
	drill_status.text = "CPU forward dive  |  F1 to take control"
	if time >= ForwardDive.WINDUP-0.12 and time <= ForwardDive.WINDUP+0.07:
		ball_preview.update_practice_platform()
		ball_preview.try_practice_pass(previous,preview_clock,0.16)
	else:
		ball_preview.practice_reach_center = Vector3.INF

func update_distance_status(in_control: bool) -> void:
	var tier: int = player_controls.reach_tier if in_control else 1
	var arrows = preview_player.get_node("DirectionArrows")
	if not player_controls.active and arrows.selected != 0:
		tier = arrows.selected_distance
	var high: bool = player_controls.reach_height >= 0.20
	if in_control and tier == 1 and ball_preview.practice_grade == BallPreview.Grade.WAITING:
		var offset: Vector3 = ball_preview.practice_step_offset(preview_clock)
		tier = ball_preview.practice_reach_tier(offset)
		high = offset.y >= 0.20
	var names := ["Short reach","High shoulder reach" if high else "Low lunge","Dive","Pancake"]
	if tier == 3:
		if arrows.selected in [1,2,8]: names[2] = "Forward dive"
		if arrows.selected in [3,7]: names[2] = "Side knee slide"
	distance_status.text = "Distance %d  |  %s" % [tier,names[tier-1]]

func aim_pass_at_mouse(screen_point: Vector2) -> void:
	var point: Vector2 = setup_drag.screen_position(screen_point)
	var floor_hit: Variant = Plane(Vector3.UP,0.055).intersects_ray(preview_camera.project_ray_origin(point),preview_camera.project_ray_normal(point))
	if not floor_hit is Vector3: return
	var destination := Vector2(clampf(floor_hit.x,-4.5,4.5),clampf(floor_hit.z,-5.0,13.0))
	if destination.distance_squared_to(StorySession.pass_destination)<0.000225: return
	StorySession.pass_destination = destination
	StorySession.pass_distance = StorySession.pass_start.distance_to(destination)
	var target: Dictionary = preview_player.get_meta("pass_target",{})
	target.position = destination
	preview_player.set_meta("pass_target",target)
	angle_control.distance_field.set_value_no_signal(StorySession.pass_distance)
	angle_control.distance_field.get_meta("slider").set_value_no_signal(StorySession.pass_distance)
	ball_preview.update_guide()
	ball_preview.update_practice_aim(true)

func adjust_pass_height(height_delta: float) -> void:
	var minimum := maxf(0.5,ball_preview.practice_platform_center().y+0.05)
	var height := clampf(StorySession.pass_apex+height_delta,minimum,20.0)
	StorySession.pass_apex = height
	StorySession.destination_fit = "height"
	var target: Dictionary = preview_player.get_meta("pass_target",{})
	target.height = height
	target.fit = "height"
	preview_player.set_meta("pass_target",target)
	angle_control.apex_field.set_value_no_signal(height)
	angle_control.apex_field.get_meta("slider").set_value_no_signal(height)
	drill_status.text = "Pass height  |  %.1f m" % height
	ball_preview.update_practice_aim(true)

func handle_middle_arrow(event: InputEvent) -> bool:
	if not reception_drill_active(): return false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed:
			middle_arrow = Vector2i(-1,1)
			var point: Vector2 = setup_drag.screen_position(event.position)
			var hit: Variant = Plane(Vector3.UP,0.065).intersects_ray(preview_camera.project_ray_origin(point),preview_camera.project_ray_normal(point))
			if not hit is Vector3: return false
			var arrows: MeshInstance3D = preview_player.get_node("DirectionArrows")
			middle_arrow = arrows.pick(arrows.to_local(hit))
			middle_press = event.position
			middle_dragged = false
			return middle_arrow.x >= 0
		if middle_arrow.x < 0: return false
		if not middle_dragged and event.position.distance_to(middle_press) <= 5.0:
			angle_control.select_feed_aim(middle_arrow.x,middle_arrow.y)
			preview.grab_focus()
		middle_arrow = Vector2i(-1,1)
		return true
	if event is InputEventMouseMotion and middle_arrow.x >= 0:
		if not (event.button_mask & MOUSE_BUTTON_MASK_MIDDLE):
			middle_arrow = Vector2i(-1,1)
			return false
		if event.position.distance_to(middle_press) > 5.0: middle_dragged = true
		if middle_dragged:
			if player_controls.active: adjust_pass_height(-event.relative.y*0.018)
			else: pan_view(event.relative)
		return true
	return false

func attack_floor_point(screen_position: Vector2) -> Variant:
	var point: Vector2 = setup_drag.screen_position(screen_position)
	return Plane(Vector3.UP,0.055).intersects_ray(preview_camera.project_ray_origin(point),preview_camera.project_ray_normal(point))

func aim_attack_shot(screen_position: Vector2) -> void:
	var hit: Variant = attack_floor_point(screen_position)
	if hit is Vector3 and hit.z >= setting_drill.SHOT_AIM_NEAR: setting_drill.aim_swing(hit)

func begin_approach_setup_drag(event: InputEventMouseButton) -> bool:
	var hit: Variant = attack_floor_point(event.position)
	if not hit is Vector3 or hit.z >= setting_drill.SHOT_AIM_NEAR: return false
	var point: Vector3 = hit
	var cursor: Vector2 = setup_drag.screen_position(event.position)
	var feet := preview_camera.unproject_position(preview_player.position)
	var torso := preview_camera.unproject_position(preview_player.position+Vector3.UP*1.55)
	var on_player := cursor.distance_to(Geometry2D.get_closest_point_to_segment(cursor,feet,torso)) <= 18.0
	var set_gap: float = (point-setting_drill.approach_set_target).slide(Vector3.UP).length()
	var on_set: bool = set_gap <= setting_drill.REGION_RADIUS+0.10
	var direct := not (event.shift_pressed or event.ctrl_pressed)
	if direct and not (on_player or on_set): return false
	var place_set := event.shift_pressed or (direct and on_set and not on_player)
	setting_drill.approach_setup_drag = "set" if place_set else "player"
	approach_drag_offset = Vector3.ZERO
	if direct:
		var center: Vector3 = setting_drill.approach_set_target if place_set else preview_player.position
		approach_drag_offset = (center-point).slide(Vector3.UP)
	else:
		setting_drill.place_approach_setup(point,place_set,false)
	return true

func handle_preview_input(event: InputEvent) -> void:
	if is_instance_valid(underhand_serve):
		if event is InputEventMouseMotion:
			if event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
				orbit_setting_camera(event.relative)
			else:
				var point: Variant = attack_floor_point(event.position)
				if point is Vector3: underhand_serve.aim(point)
		elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			var wheel := 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
			if event.shift_pressed: zoom_attack_camera(wheel)
			else: underhand_serve.change_arc(wheel*0.35)
			preview.accept_event()
		return
	if selected_category == "Chasing" and is_instance_valid(setting_drill):
		if event is InputEventMouseMotion:
			if event.button_mask & MOUSE_BUTTON_MASK_MIDDLE: return
			elif setting_drill.can_adjust_manual_set():
				var point: Variant = attack_floor_point(event.position)
				if point is Vector3: setting_drill.aim_manual_set(point)
			elif setting_drill.can_aim_set():
				var point: Variant = attack_floor_point(event.position)
				if point is Vector3: setting_drill.set_pass_aim(point)
			elif (not setting_drill.partner_receiving or setting_drill.player_second_ball_attack) and not setting_drill.cpu_second_ball_attack and setting_drill.stage != setting_drill.Stage.SERVE: aim_attack_shot(event.position)
		elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			var wheel := 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
			var height_change := wheel*0.25*maxf(0.1,event.factor)
			if setting_drill.can_adjust_manual_set():
				setting_drill.adjust_manual_set_height(height_change)
			elif setting_drill.can_adjust_teammate_set():
				setting_drill.adjust_teammate_set_height(height_change)
			elif not setting_drill.partner_receiving and setting_drill.can_aim_set():
				adjust_bump_height(height_change)
			preview.accept_event()
		return
	if is_instance_valid(setting_drill):
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			open_menu()
		elif event is InputEventMouseMotion:
			if event.button_mask & MOUSE_BUTTON_MASK_MIDDLE and (selected_category != "Attacking" or setting_drill.approach_setup_drag.is_empty()):
				orbit_setting_camera(event.relative)
			elif selected_category == "Attacking" and setting_drill.uses_assisted_approach() and setting_drill.stage != setting_drill.Stage.SERVE:
				if setting_drill.approach_setup_drag.is_empty():
					aim_attack_shot(event.position)
				else:
					var hit: Variant = attack_floor_point(event.position)
					if hit is Vector3:
						setting_drill.place_approach_setup(hit+approach_drag_offset,setting_drill.approach_setup_drag == "set",false)
			elif selected_category == "Attacking" and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
				aim_attack_shot(event.position)
			elif setting_drill.can_aim_set():
				var point: Vector2 = setup_drag.screen_position(event.position)
				var hit: Variant = Plane(Vector3.UP,0.055).intersects_ray(preview_camera.project_ray_origin(point),preview_camera.project_ray_normal(point))
				if hit is Vector3:
					if selected_category == "Attacking": setting_drill.set_pass_aim(hit)
					else: setting_drill.bump.destination = Court.clamp_set_aim(hit)
		elif event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT and selected_category == "Attacking":
				if setting_drill.approach_practice and begin_approach_setup_drag(event):
					preview.accept_event()
					return
				aim_attack_shot(event.position)
				setting_drill.swing_input(true)
			elif event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
				var wheel := (1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0)*maxf(0.1,event.factor)
				if selected_category == "Attacking" and not event.shift_pressed:
					zoom_attack_camera(wheel)
					preview.accept_event()
				elif setting_drill.can_aim_set():
					adjust_bump_height(0.25*wheel)
		return
	if reception_review.active:
		super.handle_preview_input(event)
		return
	if handle_middle_arrow(event):
		preview.accept_event()
		return
	if player_controls!=null and player_controls.active:
		if reception_drill_active():
			if event is InputEventMouseButton:
				if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
					if event.pressed:
						var direction := 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
						adjust_pass_height(direction*0.25*maxf(0.1,event.factor))
					preview.accept_event()
					return
				if event.button_index == MOUSE_BUTTON_MIDDLE:
					preview.accept_event()
					return
			if event is InputEventMouseMotion:
				if event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
					adjust_pass_height(-event.relative.y*0.018)
				else:
					aim_pass_at_mouse(event.position)
				preview.accept_event()
				return
		super.handle_preview_input(event)
		return
	if setup_drag != null and setup_drag.handle(event):
		preview.accept_event()
		return
	super.handle_preview_input(event)

func add_serve_spin_controls() -> void:
	serving_spin_controls = VBoxContainer.new()
	content.add_child(serving_spin_controls)
	var readout := label("Sidespin  0%",16)
	serving_spin_controls.add_child(readout)
	var slider := HSlider.new()
	slider.min_value = -100.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = 0.0
	slider.focus_mode = Control.FOCUS_NONE
	slider.tooltip_text = "Left to right curve"
	slider.value_changed.connect(func(value: float):
		underhand_serve.set_sidespin(value/100.0)
		readout.text = "Sidespin  %+.0f%%" % value)
	serving_spin_controls.add_child(slider)
	var lean_readout := label("Torso forward lean  %+.0f deg" % underhand_serve.forward_lean_degrees,16)
	serving_spin_controls.add_child(lean_readout)
	var lean_slider := HSlider.new()
	lean_slider.min_value = -20.0
	lean_slider.max_value = 40.0
	lean_slider.step = 1.0
	lean_slider.value = underhand_serve.forward_lean_degrees
	lean_slider.focus_mode = Control.FOCUS_NONE
	lean_slider.value_changed.connect(func(value: float):
		underhand_serve.set_forward_lean(value)
		lean_readout.text = "Torso forward lean  %+.0f deg" % value)
	serving_spin_controls.add_child(lean_slider)

	add_spin_slider("Serve speed",65.0,155.0,1.0,underhand_serve.serve_speed*100.0,"%.0f%%",
		func(value: float): underhand_serve.set_serve_speed(value/100.0))
	add_spin_slider("Jump height",0.75,1.48,0.01,underhand_serve.jump_height,"%.2f m",
		func(value: float): underhand_serve.set_jump_height(value))
	var carry := CheckButton.new()
	carry.text = "Higher jump carries forward"
	carry.button_pressed = underhand_serve.jump_carry_enabled
	carry.focus_mode = Control.FOCUS_NONE
	carry.toggled.connect(func(enabled: bool): underhand_serve.set_jump_carry(enabled))
	serving_spin_controls.add_child(carry)

func add_spin_slider(title: String, minimum: float, maximum: float, increment: float, value: float, display: String, changed: Callable) -> void:
	var readout := label(title+"  "+(display % value),16)
	serving_spin_controls.add_child(readout)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = increment
	slider.value = value
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(func(next: float):
		changed.call(next)
		readout.text = title+"  "+(display % next))
	serving_spin_controls.add_child(slider)

func step_underhand_rally(delta: float) -> void:
	var was_ready: bool = underhand_serve.elapsed < 0.0
	underhand_serve.step(delta)
	if is_finite(underhand_serve.contact_clock) and not underhand_serve.external_rally and underhand_serve.net_hit.is_empty():
		var target: Vector3 = underhand_serve.launch_target
		if absf(target.x) <= 4.5001 and target.z <= 13.0001:
			underhand_serve.external_rally = true
			underhand_serve.ball.hide()
			serve_opponents.receive_serve(underhand_serve.to_global(underhand_serve.origin),underhand_serve.global_basis*underhand_serve.velocity,underhand_serve)
		elif underhand_serve.elapsed >= underhand_serve.contact_clock+underhand_serve.landing_time:
			serving_rally_status.text = "Serve out"
	if underhand_serve.external_rally:
		serve_opponents.tick_opponents(delta)
		if serve_opponents.rally_active and serve_opponents.stage == serve_opponents.Stage.SERVE:
			serve_opponents.ball.global_rotation = underhand_serve.ball.global_rotation
		if not serve_opponents.rally_active: underhand_serve.reset()
	if not was_ready and underhand_serve.elapsed < 0.0:
		serving_rally_status.text = "Space to serve"
		serving_position = underhand_serve.serve_start
		serving_running = false

func move_server(direction: Vector2, delta: float) -> void:
	var after_contact: bool = is_instance_valid(underhand_serve) and underhand_serve.can_run_after_contact()
	if is_instance_valid(underhand_serve) and underhand_serve.elapsed >= 0.0 and not after_contact: return
	if after_contact: serving_position = preview_player.position
	var run_speed := 7.0 if after_contact else 5.7
	var next := serving_position+Vector3(-direction.x,0.0,direction.y)*run_speed*delta
	next.x = clampf(next.x,-6.5,6.5)
	var start_limit: float = underhand_serve.front_start_limit() if is_instance_valid(underhand_serve) else -5.20
	next.z = clampf(next.z,-10.0,3.50 if after_contact else start_limit)
	var moving := not next.is_equal_approx(serving_position)
	if moving:
		var travel := next-serving_position
		serving_position = next
		var yaw := atan2(travel.x,travel.z)
		if is_instance_valid(underhand_serve):
			underhand_serve.run_to(next,yaw,delta,1.48 if after_contact else 1.26)
		else:
			preview_player.position = next
			preview_player.rotation.y = yaw
			preview_player.animator.speed_scale = 1.26
			preview_player.play_action("run")
	elif serving_running:
		if is_instance_valid(underhand_serve): underhand_serve.settle_run()
		else:
			preview_player.rotation.y = 0.0
			preview_player.animator.speed_scale = 1.0
			preview_player.play_action("idle")
	serving_running = moving

func orbit_setting_camera(pixels: Vector2) -> void:
	var offset := preview_camera.position-setting_camera_focus
	var distance := offset.length()
	var yaw := atan2(offset.x,offset.z)-pixels.x*0.008
	var pitch := clampf(asin(offset.y/distance)+pixels.y*0.006,0.08,1.22)
	preview_camera.position = setting_camera_focus+Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*distance
	preview_camera.look_at(setting_camera_focus)

func zoom_attack_camera(wheel: float) -> void:
	var offset := preview_camera.position-setting_camera_focus
	var distance := clampf(offset.length()*exp(-wheel*0.17),2.8,24.0)
	var actor_focus := preview_player.position+Vector3.UP*2.0
	if is_instance_valid(setting_drill) and setting_drill.jump.active:
		actor_focus = setting_drill.jump.start+Vector3(0.0,2.0,0.45)
	if not is_instance_valid(underhand_serve):
		setting_camera_focus = SETTING_CAMERA_FOCUS.lerp(actor_focus,1.0-smoothstep(4.0,14.0,distance))
	preview_camera.position = setting_camera_focus+offset.normalized()*distance
	preview_camera.look_at(setting_camera_focus)

func adjust_bump_height(amount: float) -> void:
	setting_drill.bump.height = clampf(setting_drill.bump.height+amount,1.25,20.0)

func open_low_bow_editor() -> void:
	var shot_target: Vector3 = setting_drill.swing_aim
	var crosscourt: bool = setting_drill.shot_line_weight(shot_target,setting_drill.practice_set_target) < 0.5
	var id := LOW_BOW_EDIT_ID
	var title: String = setting_drill.SpikeArm.SWING_NAME
	if crosscourt:
		id += "_cross"
		title += " Crosscourt"
	StorySession.edit_entry = {"id":id,"name":title,"category":"Attacking","type":"Cross Hit" if crosscourt else "Line Hit"}
	for entry in Catalog.custom_entries():
		if entry.get("source") == id: StorySession.edit_entry = entry.duplicate(true)
	if StorySession.edit_entry.has("path"):
		StorySession.edit_animation = Catalog.load_clip(StorySession.edit_entry,preview_player)
	else:
		StorySession.edit_animation = bake_low_bow_starter(shot_target)
	get_tree().change_scene_to_file("res://scenes/animation_editor.tscn")

func bake_low_bow_starter(shot_target: Vector3) -> Animation:
	var drill = setting_drill
	drill.mute_net = true
	drill.set_swing_practice(true)
	drill.aim_swing(shot_target)
	var start := preview_player.position
	var rig: Skeleton3D = preview_player.skeleton
	# The editor starts with zero actor yaw; bake the incoming heading into the root track.
	var start_heading := preview_player.rotation.y
	preview_player.rotation.y = 0.0
	var start_inverse := rig.global_transform.affine_inverse()
	preview_player.rotation.y = start_heading
	var source: Vector3 = drill.pass_origin
	var velocity: Vector3 = drill.pass_motion
	var poses: Array = []
	var contact := 0.60
	var aim: Vector3
	var outgoing := Vector3.ZERO
	for tick in range(127):
		if tick > 0:
			drill.restore_torso_lean(preview_player)
			drill.step_jump(1.0/120.0)
			drill.apply_torso_lean(preview_player)
			drill.step(1.0/120.0)
		if drill.stage == drill.Stage.HIT and outgoing.is_zero_approx():
			contact = float(tick)/120.0
			aim = drill.swing_contact
			outgoing = drill.pass_motion
		var pose: Array[Transform3D] = player_controls.snapshot_receive_pose()
		pose[0] = start_inverse*rig.global_transform*pose[0]
		poses.append(pose)
	if outgoing.is_zero_approx(): aim = drill.flight_point(source,velocity,contact)
	var sample := func(time: float) -> Array:
		return poses[mini(roundi(time*120.0),poses.size()-1)]
	var clip: Animation = preview_player.get_pose_author().bake({"name":drill.SpikeArm.SWING_NAME,"duration":contact*14.0/9.0,"contact_time":contact},sample)
	clip.set_meta("editor_start",start)
	clip.set_meta("editor_group","Right Arm")
	clip.set_meta("editor_frame_count",15)
	clip.set_meta("editor_feed",{"aim":aim,"incoming":velocity+Vector3.DOWN*Flight.GRAVITY*contact,
		"acceleration":Vector3.DOWN*Flight.GRAVITY,"duration":contact,"start":source,
		"side":Vector3.RIGHT,"valid":true,"spike_outgoing":outgoing})
	drill.mute_net = false
	return clip

func load_custom_backward_clip() -> Animation:
	var copies := Catalog.custom_entries()
	for index in range(copies.size()-1,-1,-1):
		if copies[index].get("source") == BACKWARD_EDIT_ID:
			return Catalog.load_clip(copies[index],preview_player)
	return null

func sample_custom_backward(previous: float) -> bool:
	var elapsed: float = preview_clock-ball_preview.contact_time
	var contact := float(custom_backward_clip.get_meta("contact_time"))
	preview_player.animator.play("custom_backward_receive/clip",0)
	preview_player.animator.seek(clampf(elapsed+contact,0.0,custom_backward_clip.length),true)
	preview_player.animator.pause()
	ball_preview.update_practice_platform()
	return absf(elapsed) <= 0.16 and ball_preview.try_practice_pass(previous,preview_clock,0.16)

func open_backward_editor() -> void:
	reception_review.stop(false)
	StorySession.edit_entry = {"id":BACKWARD_EDIT_ID,"name":"D2 backward lunge","category":"Forearm reception","type":"Forearm"}
	for entry in Catalog.custom_entries():
		if entry.get("source") == BACKWARD_EDIT_ID: StorySession.edit_entry = entry.duplicate(true)
	if StorySession.edit_entry.has("path"):
		StorySession.edit_animation = Catalog.load_clip(StorySession.edit_entry,preview_player)
	else:
		StorySession.edit_animation = bake_backward_starter()
	StorySession.edit_animation.set_meta("editor_frame_count",15)
	get_tree().change_scene_to_file("res://scenes/animation_editor.tscn")

func bake_backward_starter() -> Animation:
	reception_review.toggle_play()
	reception_review.load_case(reception_review.SHORT_BACK)
	var actor := preview_player
	var start := actor.position
	var rig: Skeleton3D = actor.skeleton
	var start_inverse := rig.global_transform.affine_inverse()
	var chest := rig.find_bone("spine_03")
	var contact: float = reception_review.FEED_TIME
	var contact_point := [Vector3.ZERO]
	var sample := func(time: float) -> Array[Transform3D]:
		if time > 0.0: reception_review.step(1.0/60.0)
		if is_equal_approx(time,contact):
			contact_point[0] = rig.to_global(rig.get_bone_global_pose(chest).origin)+Vector3(0.0,0.12,0.24)
		var pose: Array[Transform3D] = player_controls.snapshot_receive_pose()
		# Preserve the D1 shuffle's root travel and facing in the editor timeline.
		pose[0] = start_inverse*rig.global_transform*pose[0]
		return pose
	var clip: Animation = actor.get_pose_author().bake({"name":"D2 backward lunge","duration":1.4,"contact_time":contact},sample)
	reception_review.stop(false)
	var incoming := Vector3(0.0,-4.6,-5.0)
	var acceleration := Vector3.DOWN*Flight.GRAVITY
	var duration := 0.55
	var aim: Vector3 = contact_point[0]
	clip.set_meta("editor_start",start)
	clip.set_meta("editor_feed",{"aim":aim,"incoming":incoming,"acceleration":acceleration,"duration":duration,
		"start":aim-incoming*duration+acceleration*0.5*duration*duration,"side":Vector3.RIGHT,"valid":true,"require_platform":true})
	return clip

func open_editor(index := -1) -> void:
	if selected_category == "Forearm reception": return
	reception_review.stop(false)
	if index >= 0: preview_animation(index)
	if selected_entry.is_empty(): return
	StorySession.edit_entry = selected_entry.duplicate(true)
	StorySession.edit_animation = render_clip
	StorySession.animation_return = {"category":selected_category,"type":current_type(),"id":selected_entry.id}
	get_tree().change_scene_to_file("res://scenes/animation_editor.tscn")

func cycle_type(direction: int) -> void:
	if is_instance_valid(blocking_practice) or is_instance_valid(setting_drill) or selected_category.is_empty() or selected_category in ["Setting","Attacking"]: return
	type_indices[selected_category] = posmod(int(type_indices.get(selected_category,0))+direction,MOVE_TYPES[selected_category].size())
	refresh_type()

func open_menu() -> void:
	if not selected_category.is_empty():
		var previous := selected_category
		show_categories()
		category_buttons[previous].grab_focus()
	else: get_tree().change_scene_to_file("res://scenes/story.tscn")

func _input(event: InputEvent) -> void:
	if is_instance_valid(blocking_practice) and event is InputEventKey:
		if event.pressed and not event.echo:
			if event.keycode == KEY_SPACE: blocking_practice.queue_block()
			elif event.keycode == KEY_ESCAPE: open_menu()
		return
	if selected_category == "Chasing" and is_instance_valid(setting_drill):
		if event.is_action_pressed("ui_cancel"): open_menu()
		elif event is InputEventKey and not event.echo:
			if setting_drill.partner_receiving:
				match event.keycode:
					KEY_Q:
						if event.pressed: setting_drill.request_manual_set(1)
					KEY_E, KEY_I:
						if event.pressed: setting_drill.request_manual_set(0)
					KEY_F:
						if event.pressed: setting_drill.request_manual_set(2)
					KEY_SPACE:
						setting_drill.second_ball_spike_held = event.pressed
				return
			if event.keycode == KEY_Q and event.pressed: setting_drill.queue_set()
			elif event.keycode in [KEY_E,KEY_I] and event.pressed: setting_drill.queue_hand_receive()
			elif event.keycode == KEY_SPACE:
				if event.pressed: setting_drill.queue_jump(Vector2.ZERO)
				else: setting_drill.release_approach_jump()
		return
	if is_instance_valid(underhand_serve) and event is InputEventKey and event.keycode == KEY_SPACE:
		if event.pressed and not event.echo: underhand_serve.serve()
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(setting_drill) and selected_category == "Attacking" and event is InputEventKey and event.keycode == KEY_M and event.pressed and not event.echo:
		StorySession.attack_ball_audio_muted = not StorySession.attack_ball_audio_muted
		setting_drill.set_ball_audio_muted(StorySession.attack_ball_audio_muted)
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(setting_drill) and selected_category == "Attacking" and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if not setting_drill.approach_setup_drag.is_empty():
			setting_drill.reset_feed()
			get_viewport().set_input_as_handled()
			return
		setting_drill.swing_input(false)
	if is_instance_valid(setting_drill) and selected_category == "Attacking" and event is InputEventKey and event.keycode == KEY_I:
		if event.pressed and not event.echo: setting_drill.queue_hand_receive()
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(setting_drill) and event is InputEventKey and event.keycode == KEY_SPACE:
		if event.pressed and not event.echo:
			setting_drill.queue_jump(player_controls.movement_input())
			if selected_category != "Attacking" or not setting_drill.uses_assisted_approach() or (setting_drill.approach_jump_queued and not player_controls.sprint_requested):
				player_controls.setter_travel = Vector3.ZERO
		elif not event.pressed:
			if selected_category == "Attacking" and setting_drill.uses_assisted_approach():
				setting_drill.release_approach_jump()
			else:
				setting_drill.jump.release()
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(setting_drill) and event is InputEventKey and event.keycode == KEY_F8 and event.pressed and not event.echo:
		if setting_drill.mark_trace(): show_marker_popup()
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(setting_drill) and event is InputEventKey and event.keycode in [KEY_F1,KEY_F2,KEY_Q,KEY_E]:
		var set_key: int = setting_drill.set_key()
		if event.pressed and not event.echo:
			if selected_category == "Attacking" and event.keycode == KEY_E and set_key == KEY_Q:
				setting_drill.queue_hand_receive()
			elif event.keycode == set_key:
				setting_drill.queue_set()
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(reception_review) and event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_F1,KEY_F2]:
		reception_review.stop(false)
	super._input(event)
	if event is InputEventKey and event.keycode in [KEY_F1,KEY_F2]: return
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B:
		open_menu()
		get_viewport().set_input_as_handled()
		return
	if selected_category.is_empty(): return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_Q and not (event.ctrl_pressed or event.alt_pressed or event.meta_pressed):
			if player_controls.queue_receive():
				get_viewport().set_input_as_handled()
				return
		if event.keycode == KEY_Z and event.ctrl_pressed and not (event.shift_pressed or event.alt_pressed or event.meta_pressed):
			var focus := get_viewport().gui_get_focus_owner()
			if not (focus is LineEdit or focus is TextEdit) and not player_controls.active and angle_control.visible:
				if angle_control.undo_placement(): get_viewport().set_input_as_handled()
			return
		if event.keycode in [KEY_Q,KEY_E] and selected_category != "Forearm reception":
			cycle_type(-1 if event.keycode == KEY_Q else 1)
			get_viewport().set_input_as_handled()
	if event is InputEventJoypadMotion and event.axis in [JOY_AXIS_TRIGGER_LEFT,JOY_AXIS_TRIGGER_RIGHT]:
		var key := str(event.device)+":"+str(event.axis)
		if event.axis_value <= 0.25: trigger_held[key] = false
		elif event.axis_value >= 0.6 and not trigger_held.get(key,false):
			trigger_held[key] = true
			cycle_type(-1 if event.axis == JOY_AXIS_TRIGGER_LEFT else 1)
			get_viewport().set_input_as_handled()
