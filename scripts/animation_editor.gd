extends "res://scripts/create.gd"
const EditSession = preload("res://scripts/animation_edit_session.gd")
const Groups = preload("res://scripts/animation_body_groups.gd")
const Flight = preload("res://scripts/pass_flight.gd")
const Catalog = preload("res://scripts/volleyball_animations.gd")
var ball_preview: Node3D
var setup_drag: RefCounted
var reception_controls: VBoxContainer
var replace_body_layer := false
var angle_control: VBoxContainer
var trajectory_base: Animation
var trajectory_solver: RefCounted
var trajectory_revision := -1
var session: RefCounted
var entry: Dictionary
var frame := 0
var playhead := 0.0
var playing := false
var selected_bone := -1
var group_picker: OptionButton
var selected_group := "Both Arms"
var next_pose_button: Button
var later_pose_button: Button
var bone_picker: OptionButton
var bone_indices: Array[int] = []
var frame_field: SpinBox
var timeline: HSlider
var rotation_fields: Array[SpinBox] = []
var copy_name: LineEdit
var play_button: Button
var undo_button: Button
var redo_button: Button
var copy_button: Button
var updating := false
var undo_history: Array[Dictionary] = []
var redo_history: Array[Dictionary] = []
var overlay: Control
var gizmo_drag := false
var drag_plane: Plane

func _ready() -> void:
	entry = (StorySession.edit_entry if not StorySession.edit_entry.is_empty() else Catalog.ENTRIES[0]).duplicate(true)
	super._ready()
	setup_drag = preload("res://scripts/court_setup_drag.gd").new(self)
	preview_camera.fov = 42.0
	preview_camera.far = 150.0
	preview_player.animator.stop()
	preview_player.animator.active = false
	angle_control.apply_setup(preview_player)
	if is_instance_valid(reception_controls): reception_controls.apply(preview_player,replace_body_layer)
	session = EditSession.new(StorySession.edit_animation if StorySession.edit_animation != null else Catalog.load_clip(entry,preview_player),preview_player.skeleton)
	ball_preview = preload("res://scripts/animation_ball_preview.gd").new()
	preview_player.get_parent().add_child(ball_preview)
	ball_preview.configure(preview_player,session.source,session)
	if is_instance_valid(reception_controls): reception_controls.show_result(session.source)
	frame_field.max_value = session.last_frame
	timeline.max_value = session.last_frame
	for index in preview_player.skeleton.get_bone_count():
		var name_ := str(preview_player.skeleton.get_bone_name(index))
		if name_.contains("leaf") or name_.to_lower() == "root": continue
		bone_indices.append(index)
		bone_picker.add_item(bone_label(name_))
	var draft: Dictionary = StorySession.animation_draft
	if draft.get("source","") == entry.id:
		if draft.has("animation"): session.replace_source(draft.animation)
		session.edits = draft.edits.duplicate(true)
		session.position_edits = draft.get("position_edits",{}).duplicate(true)
		copy_name.text = draft.name
		frame = draft.frame
	refresh_ball_angle()
	select_group(draft.get("group","Both Arms"))
	set_frame(frame)
	if draft.get("source","") == entry.id and StorySession.edit_animation != null:
		var requested := float(StorySession.edit_animation.get_meta("desired_output_angle",-1))
		if requested >= 0 and not is_equal_approx(requested,float(session.source.get_meta("desired_output_angle",-1))): apply_output_angle(requested)
	overlay = preload("res://scripts/animation_editor_handles.gd").new()
	overlay.editor = self
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview.add_child(overlay)
	refresh_history()

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
	host.add_child(angle_control)
	angle_control.angle_requested.connect(apply_output_angle)

func screen_title() -> String:
	return "EDIT ANIMATION"

func initial_profile() -> Dictionary:
	return StorySession.active.get("profile",Profile.load_profile()).duplicate(true)

func build_controls(host: VBoxContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	host.add_child(scroll)
	var controls := VBoxContainer.new()
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.size_flags_vertical = Control.SIZE_EXPAND_FILL
	controls.add_theme_constant_override("separation",8)
	scroll.add_child(controls)
	copy_name = LineEdit.new()
	copy_name.name = "CopyName"
	copy_name.text = entry.name+" Copy"
	copy_name.max_length = 64
	copy_name.custom_minimum_size.y = 38
	copy_name.text_changed.connect(func(value): copy_button.disabled = value.strip_edges().is_empty())
	controls.add_child(copy_name)
	var frames := HBoxContainer.new()
	controls.add_child(frames)
	var previous := button("<",step_frame.bind(-1))
	previous.custom_minimum_size.x = 38
	previous.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	frames.add_child(previous)
	frame_field = SpinBox.new()
	frame_field.name = "Frame"
	frame_field.prefix = "Frame "
	frame_field.step = 1
	frame_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame_field.value_changed.connect(func(value): set_playing(false); set_frame(int(value)))
	frames.add_child(frame_field)
	var next := button(">",step_frame.bind(1))
	next.custom_minimum_size.x = 38
	next.size_flags_horizontal = Control.SIZE_SHRINK_END
	frames.add_child(next)
	timeline = preload("res://scripts/animation_frame_slider.gd").new()
	timeline.name = "Timeline"
	timeline.step = 1
	timeline.value_changed.connect(func(value): set_playing(false); set_frame(int(value)))
	controls.add_child(timeline)
	var transport := HBoxContainer.new()
	controls.add_child(transport)
	play_button = button("Play",func(): set_playing(not playing))
	transport.add_child(play_button)
	undo_button = button("Undo",undo)
	transport.add_child(undo_button)
	redo_button = button("Redo",redo)
	transport.add_child(redo_button)
	reception_controls = preload("res://scripts/reception_controls.gd").new()
	controls.add_child(reception_controls)
	reception_controls.changed.connect(func(part): replace_body_layer = part=="body"; trajectory_base = null; apply_output_angle(angle_control.requested))
	group_picker = OptionButton.new()
	group_picker.name = "BodyGroup"
	group_picker.custom_minimum_size.y = 38
	for group in Groups.NAMES: group_picker.add_item(group)
	group_picker.item_selected.connect(func(index): select_group(Groups.NAMES[index]))
	controls.add_child(group_picker)
	bone_picker = OptionButton.new()
	bone_picker.name = "Joint"
	bone_picker.custom_minimum_size.y = 38
	bone_picker.item_selected.connect(func(index): select_bone(bone_indices[index]))
	controls.add_child(bone_picker)
	bone_picker.hide()
	controls.add_child(label("Rotation",17))
	for axis in range(3):
		var value := SpinBox.new()
		value.name = "Rotation"+["X","Y","Z"][axis]
		value.prefix = ["X ","Y ","Z "][axis]
		value.min_value = -180
		value.max_value = 180
		value.step = 0.1
		value.custom_minimum_size.y = 32
		value.value_changed.connect(rotation_changed)
		controls.add_child(value)
		rotation_fields.append(value)
	var keys := HBoxContainer.new()
	controls.add_child(keys)
	keys.add_child(button("Key",key_joint))
	keys.add_child(button("Reset",reset_joint))
	var propagation := HBoxContainer.new()
	controls.add_child(propagation)
	next_pose_button = button("Copy next",propagate_pose.bind(false))
	next_pose_button.name = "CopyNext"
	propagation.add_child(next_pose_button)
	later_pose_button = button("All later",propagate_pose.bind(true))
	later_pose_button.name = "AllLater"
	propagation.add_child(later_pose_button)
	var space := Control.new()
	space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	controls.add_child(space)
	copy_button = button("Save copy",save_copy)
	copy_button.name = "SaveCopy"
	copy_button.custom_minimum_size.y = 44
	controls.add_child(copy_button)

func refresh_ball_angle() -> void:
	ball_preview.configure(preview_player,session.source,session)
	if is_instance_valid(reception_controls): reception_controls.show_result(session.source)
	right_panel.visible = ball_preview.active
	angle_control.sync_feed(ball_preview.feed_info)
	angle_control.sync_output(ball_preview)
	angle_control.visible = ball_preview.active
	if ball_preview.active: angle_control.display_result(float(session.source.get_meta("desired_output_angle",ball_preview.output_angle())),ball_preview.output_angle(),Flight.distance(ball_preview.impact_point,ball_preview.outgoing))

func apply_output_angle(value: float) -> void:
	if session == null or not session.source.has_meta("contact_time"): return
	if trajectory_base == null or trajectory_revision != session.revision:
		trajectory_base = session.bake()
		trajectory_solver = preload("res://scripts/pass_trajectory_solver.gd").new(preview_player,trajectory_base)
	angle_control.apply_setup(preview_player)
	if is_instance_valid(reception_controls): reception_controls.apply(preview_player,replace_body_layer)
	remember_undo()
	var result: Dictionary = trajectory_solver.solve(value,StorySession.pass_distance)
	session.replace_source(result.clip)
	trajectory_revision = session.revision
	replace_body_layer = false
	StorySession.pass_output_angle = value
	refresh_ball_angle()
	set_frame(frame)
	ball_preview.tick((playhead if playing else float(frame))/EditSession.FPS,false)

func bone_label(name_: String) -> String:
	var side := ""
	if name_.ends_with("_l"): side = "Left "; name_ = name_.trim_suffix("_l")
	elif name_.ends_with("_r"): side = "Right "; name_ = name_.trim_suffix("_r")
	var names := {"lowerarm":"forearm","upperarm":"upper arm","hand":"wrist","calf":"shin","thigh":"thigh","foot":"ankle","ball":"toes","clavicle":"shoulder","pelvis":"hips","spine_01":"lower spine","spine_02":"mid spine","spine_03":"chest","neck_01":"neck"}
	return side+str(names.get(name_,name_.replace("_0"," ").replace("_"," "))).capitalize()

func set_frame(value: int) -> void:
	if session == null: return
	frame = clampi(value,0,session.last_frame)
	frame_field.set_value_no_signal(frame)
	timeline.set_value_no_signal(frame)
	session.sample(frame)
	if is_instance_valid(ball_preview) and not playing: ball_preview.tick(session.time_at(frame),false)
	refresh_rotation()
	if is_instance_valid(next_pose_button): next_pose_button.disabled = frame >= session.last_frame
	if is_instance_valid(later_pose_button): later_pose_button.disabled = frame >= session.last_frame

func step_frame(direction: int) -> void:
	set_playing(false)
	set_frame(frame+direction)

func set_playing(value: bool) -> void:
	playing = value
	playhead = float(frame)
	if playing and frame == 0: playhead = minf(0,ball_preview.contact_time-ball_preview.feed_duration)*EditSession.FPS
	if is_instance_valid(ball_preview): ball_preview.last_time = session.time_at(frame)
	if is_instance_valid(play_button): play_button.text = "Pause" if playing else "Play"

func _process(delta: float) -> void:
	super._process(delta)
	if player_controls!=null and player_controls.active: return
	if session == null: return
	if playing and setup_drag.mode.is_empty():
		var first: float = minf(0,ball_preview.contact_time-ball_preview.feed_duration)*EditSession.FPS
		var last: float = ball_preview.cycle_end()*EditSession.FPS
		playhead = first+fposmod(playhead-first+delta*EditSession.FPS,last-first)
		set_frame(floori(ball_preview.animation_time(playhead/EditSession.FPS)*EditSession.FPS))
	if is_instance_valid(ball_preview): ball_preview.tick((playhead if playing else float(frame))/EditSession.FPS,playing)
	if is_instance_valid(angle_control) and ball_preview.active: angle_control.set_actual(ball_preview.output_angle(),Flight.distance(ball_preview.impact_point,ball_preview.outgoing))
	if is_instance_valid(overlay): overlay.queue_redraw()

func select_group(group: String) -> void:
	if not group in Groups.NAMES: group = "Both Arms"
	selected_group = group
	group_picker.select(Groups.NAMES.find(group))
	bone_picker.visible = group == "Individual Joint"
	if selected_bone < 0: selected_bone = preview_player.skeleton.find_bone("lowerarm_l")
	var roots := selected_roots()
	if not roots.is_empty(): selected_bone = roots[0]
	var option := bone_indices.find(selected_bone)
	if option >= 0: bone_picker.select(option)
	refresh_rotation()

func selected_roots() -> Array[int]:
	return Groups.roots(preview_player.skeleton,selected_group,selected_bone)

func scope_bones() -> Array[int]:
	return Groups.members(preview_player.skeleton,selected_group,selected_bone)

func is_selected_bone(bone: int) -> bool:
	return bone in selected_roots()

func select_bone(index: int) -> void:
	if index < 0: return
	selected_group = "Individual Joint"
	group_picker.select(Groups.NAMES.find(selected_group))
	bone_picker.show()
	selected_bone = index
	var option := bone_indices.find(index)
	if option >= 0: bone_picker.select(option)
	refresh_rotation()

func refresh_rotation() -> void:
	if session == null or selected_bone < 0: return
	updating = true
	var angles: Vector3 = session.offset_at(selected_bone,frame).get_euler()*180.0/PI
	for axis in range(3): rotation_fields[axis].set_value_no_signal(angles[axis])
	updating = false
	refresh_keys()

func refresh_keys() -> void:
	if session == null or selected_bone < 0: return
	var keys := {}
	for bone in scope_bones():
		var name_ := str(preview_player.skeleton.get_bone_name(bone))
		for frame in session.edits.get(name_,{}): keys[frame] = true
	timeline.set_meta("keyframes",keys.keys())
	timeline.queue_redraw()

func rotation_changed(_value: float) -> void:
	if updating or session == null or selected_bone < 0: return
	set_playing(false)
	remember_undo()
	var angles := Vector3(rotation_fields[0].value,rotation_fields[1].value,rotation_fields[2].value)*PI/180.0
	apply_rotation_group(Quaternion.from_euler(angles))
	session.sample(frame)
	refresh_keys()

func key_joint() -> void:
	if session == null or selected_bone < 0: return
	set_playing(false)
	remember_undo()
	for bone in scope_bones(): session.set_offset(bone,frame,session.offset_at(bone,frame))
	refresh_keys()

func reset_joint() -> void:
	if session == null or selected_bone < 0: return
	set_playing(false)
	remember_undo()
	for bone in scope_bones():
		session.set_offset(bone,frame,Quaternion.IDENTITY)
		var name_ := str(preview_player.skeleton.get_bone_name(bone))
		if session.position_edits.has(name_): session.position_edits[name_][frame] = Vector3.ZERO
	set_frame(frame)

func remember_undo() -> void:
	undo_history.append(session.state())
	if undo_history.size() > 100: undo_history.pop_front()
	redo_history.clear()
	refresh_history()

func undo() -> void:
	if undo_history.is_empty(): return
	set_playing(false)
	redo_history.append(session.state())
	session.restore(undo_history.pop_back())
	refresh_ball_angle()
	set_frame(frame)
	refresh_history()

func redo() -> void:
	if redo_history.is_empty(): return
	set_playing(false)
	undo_history.append(session.state())
	session.restore(redo_history.pop_back())
	refresh_ball_angle()
	set_frame(frame)
	refresh_history()

func refresh_history() -> void:
	undo_button.disabled = undo_history.is_empty()
	redo_button.disabled = redo_history.is_empty()

func endpoint_index(bone: int) -> int:
	var rig: Skeleton3D = preview_player.skeleton
	var name_ := str(rig.get_bone_name(bone))
	if name_.begins_with("hand_"): return rig.find_bone("middle_01_"+name_.right(1))
	var children := rig.get_bone_children(bone)
	return children[0] if not children.is_empty() else -1

func bone_world(bone: int) -> Vector3:
	var rig: Skeleton3D = preview_player.skeleton
	return rig.global_transform*rig.get_bone_global_pose(bone).origin

func endpoint_world(bone: int) -> Vector3:
	var child := endpoint_index(bone)
	if child >= 0: return bone_world(child)
	var rig: Skeleton3D = preview_player.skeleton
	return rig.global_transform*(rig.get_bone_global_pose(bone)*Vector3(0,0.08,0))

func handle_points() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if session == null: return result
	var bones := selected_roots()
	for name_ in ["pelvis","spine_02","spine_03","Head","upperarm_l","lowerarm_l","hand_l","upperarm_r","lowerarm_r","hand_r","thigh_l","calf_l","foot_l","thigh_r","calf_r","foot_r"]:
		var index: int = preview_player.skeleton.find_bone(name_)
		if index >= 0 and not index in bones: bones.append(index)
	for bone in bones:
		if bone < 0: continue
		var point := endpoint_world(bone)
		if not preview_camera.is_position_behind(point): result.append({"bone":bone,"screen":preview_camera.unproject_position(point)})
	return result

func pick_handle(position: Vector2) -> int:
	var closest := 11.0
	var selected := -1
	for handle in handle_points():
		var distance: float = position.distance_to(handle.screen)
		if distance < closest:
			closest = distance
			selected = handle.bone
			if is_selected_bone(selected): return selected
	return selected

func handle_preview_input(event: InputEvent) -> void:
	if player_controls!=null and player_controls.active:
		super.handle_preview_input(event)
		return
	if setup_drag != null and not gizmo_drag:
		var joint_click: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and pick_handle(event.position)>=0
		if (not joint_click or not setup_drag.mode.is_empty()) and setup_drag.handle(event):
			preview.accept_event()
			return
	if session != null and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var index := pick_handle(event.position)
			if index >= 0:
				set_playing(false)
				if index in selected_roots(): selected_bone = index; refresh_rotation()
				else: select_bone(index)
				remember_undo()
				gizmo_drag = true
				drag_plane = Plane(preview_camera.global_basis.z,endpoint_world(index))
				preview.grab_focus()
				preview.accept_event()
				return
		elif gizmo_drag:
			gizmo_drag = false
			preview.accept_event()
			return
	if gizmo_drag and event is InputEventMouseMotion:
		var target: Variant = drag_plane.intersects_ray(preview_camera.project_ray_origin(event.position),preview_camera.project_ray_normal(event.position))
		if target is Vector3: drag_joint(target)
		preview.accept_event()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		view_distance = maxf(0.3,view_distance*0.9)
		update_camera()
		preview.accept_event()
		return
	super.handle_preview_input(event)

func drag_joint(target: Vector3) -> void:
	var rig: Skeleton3D = preview_player.skeleton
	var pivot := bone_world(selected_bone)
	var from := endpoint_world(selected_bone)-pivot
	var to := target-pivot
	if from.length_squared() < 0.00001 or to.length_squared() < 0.00001: return
	var turn := Quaternion(from.normalized(),to.normalized())
	apply_world_turn(turn)
	session.sample(frame)
	refresh_rotation()

func apply_rotation_group(offset: Quaternion) -> void:
	var rig: Skeleton3D = preview_player.skeleton
	var parent := rig.get_bone_parent(selected_bone)
	var parent_basis := rig.global_basis if parent < 0 else rig.global_basis*rig.get_bone_global_pose(parent).basis
	var old_basis := rig.global_basis*rig.get_bone_global_pose(selected_bone).basis
	var desired := parent_basis*Basis(session.source_rotation(selected_bone,frame)*offset)
	apply_world_turn((desired*old_basis.inverse()).orthonormalized().get_rotation_quaternion())

func apply_world_turn(turn: Quaternion) -> void:
	var rig: Skeleton3D = preview_player.skeleton
	var anchor := str(rig.get_bone_name(selected_bone))
	var mirror := Basis(Vector3(-1,0,0),Vector3.UP,Vector3.BACK)
	var rig_basis := rig.global_basis.orthonormalized()
	var mirrored := rig_basis*mirror*rig_basis.inverse()*Basis(turn)*rig_basis*mirror*rig_basis.inverse()
	for bone in selected_roots():
		var name_ := str(rig.get_bone_name(bone))
		var opposite := (anchor.ends_with("_l") and name_.ends_with("_r")) or (anchor.ends_with("_r") and name_.ends_with("_l"))
		var change := mirrored if opposite else Basis(turn)
		var parent := rig.get_bone_parent(bone)
		var parent_basis := rig.global_basis if parent < 0 else rig.global_basis*rig.get_bone_global_pose(parent).basis
		var current_basis := rig.global_basis*rig.get_bone_global_pose(bone).basis
		var local := (parent_basis.inverse()*change*current_basis).orthonormalized().get_rotation_quaternion()
		session.set_rotation(bone,frame,local)

func propagate_pose(all_later: bool) -> void:
	if session == null or frame >= session.last_frame: return
	set_playing(false)
	remember_undo()
	var source_frame := frame
	session.propagate(scope_bones(),source_frame,source_frame+1,session.last_frame if all_later else source_frame+1)
	set_frame(source_frame if all_later else source_frame+1)


func zoom_view(factor: float) -> void:
	view_distance = clampf(view_distance*factor,0.3,max_view_distance)
	update_camera()

func save_copy() -> void:
	if session == null: return
	set_playing(false)
	for field in rotation_fields:
		if field.get_line_edit().has_focus(): field.apply()
	var saved := Catalog.save_copy(session.bake(),entry,copy_name.text)
	if saved.is_empty():
		var dialog := AcceptDialog.new()
		dialog.dialog_text = "Unable to save animation."
		add_child(dialog)
		dialog.popup_centered()
		return
	StorySession.edit_animation = null
	StorySession.animation_draft.clear()
	StorySession.animation_return = {"category":saved.category,"type":saved.type,"id":saved.id}
	get_tree().change_scene_to_file("res://scenes/story_animations.tscn")

func open_menu() -> void:
	if session != null:
		StorySession.animation_draft = {"source":entry.id,"animation":session.source,"edits":session.edits.duplicate(true),"position_edits":session.position_edits.duplicate(true),"name":copy_name.text,"frame":frame,"group":selected_group}
	StorySession.animation_return = {"category":entry.category,"type":entry.type,"id":entry.id}
	get_tree().change_scene_to_file("res://scenes/story_animations.tscn")

func handle_keyboard(event: InputEventKey) -> void:
	if event.ctrl_pressed and event.keycode == KEY_Z:
		if event.shift_pressed: redo()
		else: undo()
	elif event.ctrl_pressed and event.keycode == KEY_Y: redo()
	elif event.ctrl_pressed and event.keycode == KEY_S: save_copy()
	elif event.keycode == KEY_SPACE: set_playing(not playing)
	elif event.keycode == KEY_K: key_joint()
	elif event.keycode == KEY_P: propagate_pose(event.shift_pressed)
	elif event.keycode == KEY_LEFT and not event.shift_pressed: step_frame(-1)
	elif event.keycode == KEY_RIGHT and not event.shift_pressed: step_frame(1)
	elif event.keycode == KEY_F and selected_bone >= 0:
		view_focus = bone_world(selected_bone)
		view_distance = 0.65 if str(preview_player.skeleton.get_bone_name(selected_bone)).contains("_0") else 1.2
		update_camera()
	else:
		super.handle_keyboard(event)
		return
	get_viewport().set_input_as_handled()
