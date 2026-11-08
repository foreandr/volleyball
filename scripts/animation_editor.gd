extends "res://scripts/create.gd"
const EditSession = preload("res://scripts/animation_edit_session.gd")
const Catalog = preload("res://scripts/volleyball_animations.gd")
var session: RefCounted
var entry: Dictionary
var frame := 0
var playhead := 0.0
var playing := false
var selected_bone := -1
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
	preview_player.animator.stop()
	preview_player.animator.active = false
	session = EditSession.new(load(entry.path),preview_player.skeleton)
	frame_field.max_value = session.last_frame
	timeline.max_value = session.last_frame
	for index in preview_player.skeleton.get_bone_count():
		var name_ := str(preview_player.skeleton.get_bone_name(index))
		if name_.contains("leaf") or name_.to_lower() == "root": continue
		bone_indices.append(index)
		bone_picker.add_item(bone_label(name_))
	var draft: Dictionary = StorySession.animation_draft
	if draft.get("source","") == entry.id:
		session.edits = draft.edits.duplicate(true)
		copy_name.text = draft.name
		frame = draft.frame
	select_bone(preview_player.skeleton.find_bone("lowerarm_l"))
	set_frame(frame)
	overlay = preload("res://scripts/animation_editor_handles.gd").new()
	overlay.editor = self
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview.add_child(overlay)
	refresh_history()

func screen_title() -> String:
	return "EDIT ANIMATION"

func initial_profile() -> Dictionary:
	return StorySession.active.get("profile",Profile.load_profile()).duplicate(true)

func build_controls(controls: VBoxContainer) -> void:
	controls.add_theme_constant_override("separation",10)
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
	bone_picker = OptionButton.new()
	bone_picker.name = "Joint"
	bone_picker.custom_minimum_size.y = 38
	bone_picker.item_selected.connect(func(index): select_bone(bone_indices[index]))
	controls.add_child(bone_picker)
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
	keys.add_child(button("Reset joint",reset_joint))
	var space := Control.new()
	space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	controls.add_child(space)
	copy_button = button("Save copy",save_copy)
	copy_button.name = "SaveCopy"
	copy_button.custom_minimum_size.y = 44
	controls.add_child(copy_button)

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
	refresh_rotation()

func step_frame(direction: int) -> void:
	set_playing(false)
	set_frame(frame+direction)

func set_playing(value: bool) -> void:
	playing = value
	playhead = float(frame)
	if is_instance_valid(play_button): play_button.text = "Pause" if playing else "Play"

func _process(delta: float) -> void:
	if session == null: return
	if playing:
		playhead = fposmod(playhead+delta*EditSession.FPS,maxi(1,session.last_frame))
		set_frame(floori(playhead))
	if is_instance_valid(overlay): overlay.queue_redraw()

func select_bone(index: int) -> void:
	if index < 0: return
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
	var name_ := str(preview_player.skeleton.get_bone_name(selected_bone))
	timeline.set_meta("keyframes",session.edits.get(name_,{}).keys())
	timeline.queue_redraw()

func rotation_changed(_value: float) -> void:
	if updating or session == null or selected_bone < 0: return
	set_playing(false)
	remember_undo()
	var angles := Vector3(rotation_fields[0].value,rotation_fields[1].value,rotation_fields[2].value)*PI/180.0
	session.set_offset(selected_bone,frame,Quaternion.from_euler(angles))
	session.sample(frame)
	refresh_keys()

func key_joint() -> void:
	if session == null or selected_bone < 0: return
	set_playing(false)
	remember_undo()
	session.set_offset(selected_bone,frame,session.offset_at(selected_bone,frame))
	refresh_keys()

func reset_joint() -> void:
	if session == null or selected_bone < 0: return
	set_playing(false)
	remember_undo()
	session.set_offset(selected_bone,frame,Quaternion.IDENTITY)
	set_frame(frame)

func remember_undo() -> void:
	undo_history.append(session.edits.duplicate(true))
	if undo_history.size() > 100: undo_history.pop_front()
	redo_history.clear()
	refresh_history()

func undo() -> void:
	if undo_history.is_empty(): return
	set_playing(false)
	redo_history.append(session.edits.duplicate(true))
	session.edits = undo_history.pop_back()
	set_frame(frame)
	refresh_history()

func redo() -> void:
	if redo_history.is_empty(): return
	set_playing(false)
	undo_history.append(session.edits.duplicate(true))
	session.edits = redo_history.pop_back()
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
	var bones := [selected_bone]
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
			if selected == selected_bone: return selected
	return selected

func handle_preview_input(event: InputEvent) -> void:
	if session != null and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var index := pick_handle(event.position)
			if index >= 0:
				set_playing(false)
				select_bone(index)
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
	var parent := rig.get_bone_parent(selected_bone)
	var parent_basis := rig.global_basis if parent < 0 else rig.global_basis*rig.get_bone_global_pose(parent).basis
	var current_basis := rig.global_basis*rig.get_bone_global_pose(selected_bone).basis
	var local := (parent_basis.inverse()*Basis(turn)*current_basis).orthonormalized().get_rotation_quaternion()
	session.set_rotation(selected_bone,frame,local)
	session.sample(frame)
	refresh_rotation()

func zoom_view(factor: float) -> void:
	view_distance = clampf(view_distance*factor,0.3,8.0)
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
	StorySession.animation_draft.clear()
	StorySession.animation_return = {"category":saved.category,"type":saved.type,"id":saved.id}
	get_tree().change_scene_to_file("res://scenes/story_animations.tscn")

func open_menu() -> void:
	if session != null:
		StorySession.animation_draft = {"source":entry.id,"edits":session.edits.duplicate(true),"name":copy_name.text,"frame":frame}
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
