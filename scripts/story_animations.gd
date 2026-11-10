extends "res://scripts/create.gd"
const BallPreview = preload("res://scripts/animation_ball_preview.gd")
const Court = preload("res://scripts/preview_court.gd")
const SETTING_CAMERA_FOCUS := Vector3(0,1.45,2.6)
const BallTimingRing = preload("res://scripts/ball_timing_ring.gd")
const Flight = preload("res://scripts/pass_flight.gd")
const SideKneeSlide = preload("res://scripts/side_knee_slide.gd")
const ForwardDive = preload("res://scripts/forward_reception_dive.gd")
const Catalog = preload("res://scripts/volleyball_animations.gd")
const MOVE_TYPES := {
	"Forearm reception":["Forearm"],
	"Attacking":["Line Hit","Cross Hit"],
	"Serving":["Float","Spin","Hybrid","Skyball","Underhand","Standing Float","Standing Spin"],
	"Blocking":["Straight","Left","Right"],
	"Setting":["Hand setting","Bump setting"],
	"Chasing":["Forward","Back","Left","Right"]
}
const CATEGORIES := ["Forearm reception","Setting","Serving","Blocking","Attacking","Chasing"]
var content: VBoxContainer
var category_buttons: Dictionary = {}
var selected_category := ""
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
var reception_review: HBoxContainer
var setting_drill: Node3D
var setter_original_transform: Transform3D
var setter_animation_process: int
var setter_animator_active: bool

func _ready() -> void:
	process_priority = 10
	build_label = current_build_label()
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_title("Volleyball | "+build_label)
	super._ready()
	preview_overlay = Control.new()
	preview_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.get_parent().add_child(preview_overlay)
	build_marker_popup()
	jump_height_meter = preload("res://scripts/jump_height_meter.gd").new()
	preview_overlay.add_child(jump_height_meter)
	pass_timing_cue = BallTimingRing.new()
	preview_player.get_parent().add_child(pass_timing_cue)
	reception_review = preload("res://scripts/reception_review.gd").new(self)
	var column := find_child("ScreenTitle",true,false).get_parent().get_parent()
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
	return "ANIMATIONS  |  "+build_label

func initial_profile() -> Dictionary:
	return StorySession.active.get("profile",Profile.load_profile()).duplicate(true)

func build_controls(controls: VBoxContainer) -> void:
	content = controls
	show_categories()

func clear_content() -> void:
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
	if heading: heading.text = text+"  |  "+build_label

func show_categories() -> void:
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
	reception_review.stop(false)
	reception_review.visible = category == "Forearm reception"
	selected_category = category
	preview_player.get_node("DirectionArrows").show_dive_ring = category == "Forearm reception"
	clear_content()
	set_title(category.to_upper())
	if category in ["Setting","Attacking"]:
		start_setting_drill(category == "Attacking")
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
		refresh_type()
		preview.grab_focus()
		return
	var list := ItemList.new()
	list.name = "AnimationList"
	list.allow_reselect = true
	list.item_activated.connect(open_editor)
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
	modes.name = "SettingType"
	for mode in MOVE_TYPES["Setting"]: modes.add_item(mode)
	modes.select(type_indices.get("Setting",0))
	content.add_child(modes)
	modes.visible = not attack
	var controls_hint := label("",16)
	controls_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var show_mode := func(index: int):
		controls_hint.text = "WASD to move  |  Tap Q to bump set\nMouse to aim  |  Scroll to change height" if index == 1 else "WASD to move  |  Tap E to set\nMouse to aim  |  Scroll to change height\nSpace jump  |  7 to 40 in"
	if attack: controls_hint.text = "WASD to move  |  Q forearms  |  I / E hands\nMouse to aim  |  Scroll for pass height\nSpace to jump  |  Click or E to catch"
	else: show_mode.call(modes.selected)
	modes.item_selected.connect(func(index: int):
		type_indices["Setting"] = index
		setting_drill.set_bump_mode(index == 1)
		show_mode.call(index))
	content.add_child(controls_hint)
	drill_status = label("",16)
	drill_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(drill_status)
	setter_original_transform = preview_player.transform
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
	preview_camera.position = Vector3(0,7.5,-11.2)
	preview_camera.look_at(SETTING_CAMERA_FOCUS)
	setting_drill = preload("res://scripts/attack_drill.gd").new() if attack else preload("res://scripts/setting_drill.gd").new()
	preview_player.get_parent().add_child(setting_drill)
	setting_drill.configure(preview_player,drill_status,modes.selected == 1,build_label)
	preview.grab_focus()

func stop_setting_drill() -> void:
	if not is_instance_valid(setting_drill): return
	if marker_fade != null: marker_fade.kill()
	marker_popup.hide()
	jump_height_meter.hide()
	setting_drill.queue_free()
	setting_drill = null
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

func refresh_type() -> void:
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
	if is_instance_valid(setting_drill):
		player_controls.read_pace_input()
		setting_drill.trace_input = player_controls.movement_input()
		setting_drill.trace_sprint = player_controls.sprint_requested
		var diving: bool = setting_drill.setter_is_diving()
		setting_drill.trace_move_scale = 0.0 if diving else setting_drill.setter_movement_scale()
		var court_weight: float = setting_drill.court_facing_weight()
		if not diving and not setting_drill.jump.active:
			player_controls.move_player(setting_drill.trace_input,delta,false,setting_drill.ball.global_position,setting_drill.trace_move_scale,court_weight)
			setting_drill.apply_setter_arms(player_controls.footwork.phase,player_controls.moving,delta)
		elif setting_drill.jump.active and court_weight > 0.0:
			player_controls.track_setting_ball(preview_player,setting_drill.ball.global_position,delta,court_weight)
		setting_drill.step_jump(delta)
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
	jump_height_meter.show_height(projected,preview.size,jump.height,jump.FULL_HEIGHT)

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
	if elapsed <= 0.44 and after_touch < 0.18 and not ball_preview.recovery.has("body_touch"):
		var windup := 0.14*(1.0-smoothstep(0.0,0.085,elapsed))
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

func handle_preview_input(event: InputEvent) -> void:
	if is_instance_valid(setting_drill):
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			open_menu()
		elif event is InputEventMouseMotion:
			if event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
				orbit_setting_camera(event.relative)
			elif setting_drill.can_aim_set():
				var point: Vector2 = setup_drag.screen_position(event.position)
				var hit: Variant = Plane(Vector3.UP,0.055).intersects_ray(preview_camera.project_ray_origin(point),preview_camera.project_ray_normal(point))
				if hit is Vector3:
					setting_drill.bump.destination = Court.clamp_set_aim(hit)
		elif event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT and selected_category == "Attacking":
				setting_drill.queue_catch()
			elif setting_drill.can_aim_set() and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
				adjust_bump_height((0.25 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -0.25)*maxf(0.1,event.factor))
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

func orbit_setting_camera(pixels: Vector2) -> void:
	var offset := preview_camera.position-SETTING_CAMERA_FOCUS
	var distance := offset.length()
	var yaw := atan2(offset.x,offset.z)-pixels.x*0.008
	var pitch := clampf(asin(offset.y/distance)+pixels.y*0.006,0.08,1.22)
	preview_camera.position = SETTING_CAMERA_FOCUS+Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*distance
	preview_camera.look_at(SETTING_CAMERA_FOCUS)

func adjust_bump_height(amount: float) -> void:
	setting_drill.bump.height = clampf(setting_drill.bump.height+amount,1.25,20.0)

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
	if selected_category.is_empty() or selected_category in ["Setting","Attacking"]: return
	type_indices[selected_category] = posmod(int(type_indices.get(selected_category,0))+direction,MOVE_TYPES[selected_category].size())
	refresh_type()

func open_menu() -> void:
	if not selected_category.is_empty():
		var previous := selected_category
		show_categories()
		category_buttons[previous].grab_focus()
	else: get_tree().change_scene_to_file("res://scenes/story.tscn")

func _input(event: InputEvent) -> void:
	if is_instance_valid(setting_drill) and selected_category == "Attacking" and event is InputEventKey and event.keycode == KEY_I:
		if event.pressed and not event.echo: setting_drill.queue_hand_receive()
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(setting_drill) and event is InputEventKey and event.keycode == KEY_SPACE:
		if event.pressed and not event.echo:
			setting_drill.queue_jump(player_controls.movement_input())
			player_controls.setter_travel = Vector3.ZERO
		elif not event.pressed:
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
