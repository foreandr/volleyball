extends "res://scripts/create.gd"
const EditSession = preload("res://scripts/animation_edit_session.gd")
const Groups = preload("res://scripts/animation_body_groups.gd")
const Flight = preload("res://scripts/pass_flight.gd")
const Catalog = preload("res://scripts/volleyball_animations.gd")
const ATTACK_EDITOR_OFFSET := Vector3(0.0,0.0,-0.50)
var ball_preview: Node3D
var reception_controls: VBoxContainer
var replace_body_layer := false
var angle_control: VBoxContainer
var trajectory_base: Animation
var trajectory_solver: RefCounted
var trajectory_revision := -1
var review_source: Animation
var shot_setup := {}
var floor_ball: MeshInstance3D
var dragging_floor_ball := false
const SET_MARKER_ORIGIN := Vector3(3.47,.105,2.96)
var shot_sampler: Node
var updating_shot := false
var shot_revision := 0
var review_number := 1
var review_status := Label.new()
var review_votes := ConfigFile.new()
const REVIEW_PATH := "user://spike_swing_votes.cfg"
var session: RefCounted
var entry: Dictionary
var origin_scene := ""
var frame := 0
var playhead := 0.0
var playing := false
var playback_speed := 1.0
var selected_bone := -1
var group_picker: OptionButton
var selected_group := "Both Arms"
var next_pose_button: Button
var later_pose_button: Button
var bone_picker: OptionButton
var bone_indices: Array[int] = []
var frame_field: SpinBox
var timeline: HSlider
var contact_frame_button: Button
var rotation_fields: Array[SpinBox] = []
var held_rotation_field: SpinBox
var rotation_hold_recorded := false
var rotation_press_ms := 0
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
var shoulder_drag_origin := Vector3.ZERO
var shoulder_start_offset := Vector3.ZERO

func _ready() -> void:
	origin_scene=StorySession.frame_editor_origin
	StorySession.frame_editor_origin=""
	entry = (StorySession.edit_entry if not StorySession.edit_entry.is_empty() else Catalog.ENTRIES[0]).duplicate(true)
	super._ready()
	player_controls = null
	preview_camera.fov = 42.0
	preview_camera.far = 150.0
	preview_player.animator.stop()
	preview_player.animator.active = false
	angle_control.apply_setup(preview_player)
	if is_instance_valid(reception_controls): reception_controls.apply(preview_player,replace_body_layer)
	session = EditSession.new(StorySession.edit_animation if StorySession.edit_animation != null else Catalog.load_clip(entry,preview_player),preview_player.skeleton)
	var editor_feed: Dictionary = session.source.get_meta("editor_feed",{}).duplicate()
	var spike := editor_feed.has("spike_outgoing")
	if session.source.has_meta("editor_start"):
		preview_player.set_height_cm(float(session.source.get_meta("editor_height_cm",Profile.DEFAULTS.height_cm)))
		preview_player.position = session.source.get_meta("editor_start")
		preview_player.rotation.y = float(session.source.get_meta("editor_yaw",0.0))
		if spike:
			preview_player.position += ATTACK_EDITOR_OFFSET
			editor_feed.start += ATTACK_EDITOR_OFFSET
			editor_feed.aim += ATTACK_EDITOR_OFFSET
		view_focus = preview_player.position+Vector3(0,1.85 if spike else 1.10,0)
		view_distance = 5.8 if spike else 4.6
		orbit_yaw = -2.1 if spike else 1.1
		if entry.id in ["camp_attack_arm_lift","camp_right_arm_swing"]:
			view_focus.y+=1.25
			view_distance=7.2
		if spike: preview_player.get_node("DirectionArrows").hide()
		update_camera()
	ball_preview = preload("res://scripts/animation_ball_preview.gd").new()
	ball_preview.review_feed = editor_feed
	preview_player.get_parent().add_child(ball_preview)
	ball_preview.configure(preview_player,session.source,session)
	if entry.id=="camp_right_arm_swing":
		floor_ball=MeshInstance3D.new()
		floor_ball.mesh=ball_preview.ball.mesh
		floor_ball.material_override=ball_preview.ball.material_override
		preview_player.get_parent().add_child(floor_ball)
		floor_ball.position=SET_MARKER_ORIGIN+Vector3(shot_setup.get("set_x",0.),0.,shot_setup.get("set_z",0.))
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
	if draft.get("source","") != entry.id:
		frame = int(session.source.get_meta("editor_initial_frame",0))
	refresh_ball_angle()
	select_group(draft.get("group",session.source.get_meta("editor_group","Both Arms")))
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
	if entry.get("swing_review",false):
		review_source=session.source
		review_votes.load(REVIEW_PATH)
		show_swing(int(review_votes.get_value("review","current",1)))
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--preview-frame="):
				set_playing(false)
				set_frame(argument.get_slice("=",1).to_int())
func show_swing(number: int) -> void:
	review_number=wrapi(number-1,0,50)+1
	session.replace_source(preload("res://scripts/numbered_swings.gd").make(review_source,review_number,session.rig))
	frame_field.max_value=session.last_frame
	timeline.max_value=session.last_frame
	ball_preview.configure(preview_player,session.source,session)
	undo_history.clear()
	redo_history.clear()
	refresh_history()
	copy_name.text="Swing %02d" % review_number
	review_status.text="%02d / 50   %s" % [review_number,review_votes.get_value("votes",str(review_number),"")]
	review_votes.set_value("review","current",review_number)
	if review_votes.save(REVIEW_PATH)!=OK: review_status.text+="   Save failed"
	set_frame(int(session.source.get_meta("editor_loop_start",0)))
	set_playing(true)

func add_shot_slider(box: VBoxContainer, caption: String, key: String, low: float, high: float, step_size: float, fallback: float, unit: String) -> HSlider:
	var label := Label.new()
	var slider := HSlider.new()
	slider.min_value=low
	slider.max_value=high
	slider.step=step_size
	slider.value=float(shot_setup.get(key,fallback))
	var display := func(value: float):
		shot_setup[key]=value
		label.text="%s   %s %s" % [caption,str(snappedf(value,step_size)),unit]
	display.call(slider.value)
	slider.value_changed.connect(display)
	slider.value_changed.connect(func(value):
		InteractionTrace.record("shot_setting",{"control":key,"value":value,"frame":frame,"playing":playing})
		queue_live_shot())
	box.add_child(label)
	box.add_child(slider)
	return slider

func queue_live_shot() -> void:
	shot_revision+=1
	if updating_shot: return
	updating_shot=true
	update_live_shot.call_deferred()

func update_live_shot() -> void:
	if not is_instance_valid(shot_sampler):
		var viewport := SubViewport.new()
		viewport.own_world_3d=true
		viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
		viewport.gui_disable_input=true
		add_child(viewport)
		shot_sampler=load("res://scenes/attacking_camp.tscn").instantiate()
		shot_sampler.set_meta("live_sampler",true)
		viewport.add_child(shot_sampler)
		for collider in shot_sampler.find_children("*","CollisionObject3D",true,false):
			collider.disable_mode=CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
		shot_sampler.process_mode=Node.PROCESS_MODE_DISABLED
		await get_tree().physics_frame
	while is_inside_tree():
		var revision := shot_revision
		shot_setup.z=4.+float(shot_setup.depth)
		var review := bool(entry.get("swing_review",false))
		var result: Dictionary=await shot_sampler.sample_attack_clip(true,true,float(shot_setup.x)>0.,review,shot_setup)
		var clip: Animation=result.clip
		if review:
			review_source=clip
			clip=preload("res://scripts/numbered_swings.gd").make(clip,review_number,session.rig)
		var rotations: Dictionary=session.edits.duplicate(true)
		var positions: Dictionary=session.position_edits.duplicate(true)
		InteractionTrace.record("shot_preview",{"settings":shot_sampler.review_setup.duplicate(),"contact_frame":clip.get_meta("swing_hit_frame",-1),"frame":frame,"playing":playing})
		session.replace_source(clip)
		frame_field.max_value=session.last_frame
		timeline.max_value=session.last_frame
		session.edits=rotations
		session.position_edits=positions
		preview_player.position=clip.get_meta("editor_start")
		preview_player.rotation.y=clip.get_meta("editor_yaw")
		ball_preview.configure(preview_player,clip,session)
		set_frame(frame)
		if revision!=shot_revision: continue
		StorySession.save_drill_setup("swing_review",shot_setup)
		break
	updating_shot=false

func vote_swing(choice: String) -> void:
	review_votes.set_value("votes",str(review_number),choice)
	show_swing(review_number+1)

func light_preview_stage(world: Node3D) -> void:
	preload("res://scripts/tryout_gym.gd").light_gym(world)

func build_preview_stage(world: Node3D) -> void:
	world.add_child(preload("res://scripts/tryout_gym.gd").new())
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

func build_controls(controls: VBoxContainer) -> void:
	controls.add_theme_constant_override("separation",8)
	copy_name = LineEdit.new()
	copy_name.name = "CopyName"
	copy_name.text = entry.name+" Copy"
	copy_name.max_length = 64
	copy_name.custom_minimum_size.y = 38
	copy_name.text_changed.connect(func(value): copy_button.disabled = value.strip_edges().is_empty())
	if entry.get("swing_review",false):
		controls.add_child(review_status)
		var row := HBoxContainer.new()
		controls.add_child(row)
		row.add_child(button("<",func(): show_swing(review_number-1)))
		row.add_child(button("Yes",vote_swing.bind("Yes")))
		row.add_child(button("No",vote_swing.bind("No")))
		row.add_child(button(">",func(): show_swing(review_number+1)))
	if entry.id=="camp_right_arm_swing":
		shot_setup=StorySession.load_drill_setup("swing_review")
		if not entry.get("swing_review",false):
			shot_setup=shot_setup.duplicate()
			shot_setup.x=entry.get("aim_x",-3.4)
		var settings_box := VBoxContainer.new()
		var toggle := button("Shot setup",func():
			settings_box.visible=not settings_box.visible
			if is_instance_valid(floor_ball): floor_ball.visible=settings_box.visible)
		controls.add_child(toggle)
		controls.add_child(settings_box)
		settings_box.show()
		var court := Control.new()
		court.custom_minimum_size=Vector2(0,132)
		court.mouse_filter=Control.MOUSE_FILTER_STOP
		court.tooltip_text="Click or drag to aim. The net is at the bottom."
		settings_box.add_child(court)
		shot_setup.x=shot_setup.get("x",-3.4)
		shot_setup.depth=shot_setup.get("depth",7.)
		court.draw.connect(func():
			var area := Rect2(Vector2.ONE*4.,court.size-Vector2.ONE*8.)
			court.draw_rect(area,Color("#a97548"))
			court.draw_rect(area,Color.WHITE,false,2.)
			var attack_y := area.end.y-area.size.y/3.
			court.draw_line(Vector2(area.position.x,attack_y),Vector2(area.end.x,attack_y),Color.WHITE,1.)
			court.draw_line(Vector2(area.position.x,area.end.y),area.end,Color.WHITE,4.)
			var marker := area.position+area.size*Vector2((float(shot_setup.x)+4.5)/9.,1.-float(shot_setup.depth)/9.)
			court.draw_circle(marker,6.,Color.BLACK)
			court.draw_circle(marker,4.,Color.WHITE))
		court.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed or event is InputEventMouseMotion and event.button_mask&MOUSE_BUTTON_MASK_LEFT:
				var point: Vector2=(event.position-Vector2.ONE*4.)/(court.size-Vector2.ONE*8.)
				shot_setup.x=clampf(point.x*9.-4.5,-4.4,4.4)
				shot_setup.depth=clampf((1.-point.y)*9.,.5,8.9)
				court.queue_redraw()
				queue_live_shot()
				court.accept_event())
		var hint := Label.new()
		hint.text="Drag the floor ball anywhere on the attacking side."
		settings_box.add_child(hint)
		var spin := OptionButton.new()
		for label in ["Topspin","Left spin","Right spin","No spin"]: spin.add_item(label)
		spin.select(int(shot_setup.get("spin",0)))
		spin.item_selected.connect(func(index: int):
			shot_setup.spin=index
			queue_live_shot())
		settings_box.add_child(spin)
		add_shot_slider(settings_box,"Hit power","power",9.,40.,1.,14.,"m/s")
		add_shot_slider(settings_box,"Vertical jump","jump",24.,60.,1.,33.,"in")

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
	contact_frame_button = button("",jump_to_contact_frame)
	contact_frame_button.name = "ContactFrame"
	contact_frame_button.hide()
	controls.add_child(contact_frame_button)
	var transport := HBoxContainer.new()
	controls.add_child(transport)
	play_button = button("Play",func(): set_playing(not playing))
	transport.add_child(play_button)
	var slow := button("Slow ��",func(): pass)
	slow.toggle_mode=true
	slow.toggled.connect(func(enabled: bool):
		playback_speed=.25 if enabled else 1.
		if enabled and not playing: set_playing(true))
	transport.add_child(slow)
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
		value.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
				release_rotation_arrow()
				rotation_hold_recorded=false
				held_rotation_field=value
				rotation_press_ms=Time.get_ticks_msec())
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
	if str(entry.get("id","")).begins_with("custom_") and entry.has("path"):
		controls.add_child(button("Copy animation file path",func():
			DisplayServer.clipboard_set(ProjectSettings.globalize_path(entry.path))))

func refresh_ball_angle() -> void:
	ball_preview.configure(preview_player,session.source,session)
	if is_instance_valid(reception_controls): reception_controls.show_result(session.source)
	right_panel.visible = ball_preview.active and not session.source.has_meta("editor_feed") and not session.source.has_meta("editor_ball_frames")
	if ball_preview.active and not session.source.has_meta("editor_ball_frames"):
		angle_control.sync_feed(ball_preview.feed_info)
		angle_control.sync_output(ball_preview)
	angle_control.visible = ball_preview.active and not session.source.has_meta("editor_ball_frames")
	if angle_control.visible: angle_control.display_result(float(session.source.get_meta("desired_output_angle",ball_preview.output_angle())),ball_preview.output_angle(),Flight.distance(ball_preview.impact_point,ball_preview.outgoing))

func apply_output_angle(value: float) -> void:
	if session == null or not session.source.has_meta("contact_time") or session.source.has_meta("editor_feed"): return
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
	ball_preview.tick(session.time_at(playhead if playing else float(frame)),false)

func bone_label(name_: String) -> String:
	var side := ""
	if name_.ends_with("_l"): side = "Left "; name_ = name_.trim_suffix("_l")
	elif name_.ends_with("_r"): side = "Right "; name_ = name_.trim_suffix("_r")
	var names := {"lowerarm":"forearm","upperarm":"upper arm","hand":"wrist","calf":"shin","thigh":"thigh","foot":"ankle","ball":"toes","clavicle":"shoulder","pelvis":"hips","spine_01":"lower spine","spine_02":"mid spine","spine_03":"chest","neck_01":"neck"}
	return side+str(names.get(name_,name_.replace("_0"," ").replace("_"," "))).capitalize()

func sample_editor_pose() -> void:
	session.sample(frame)
	var limited_right := preload("res://scripts/player_arm_clearance.gd").resolve(session.rig,"r")
	var limited_left := preload("res://scripts/player_arm_clearance.gd").resolve(session.rig,"l")
	if limited_right or limited_left:
		InteractionTrace.record("pose_limited_by_body_contact",{"swing":review_number,"frame":frame,"right":limited_right,"left":limited_left})

func set_frame(value: int) -> void:
	if session == null: return
	frame = clampi(value,0,session.last_frame)
	frame_field.set_value_no_signal(frame)
	timeline.set_value_no_signal(frame)
	sample_editor_pose()
	if is_instance_valid(ball_preview) and not playing:
		ball_preview.tick(session.time_at(frame),false)
		refresh_contact_frame()
	refresh_rotation()
	if is_instance_valid(next_pose_button): next_pose_button.disabled = frame >= session.last_frame
	if is_instance_valid(later_pose_button): later_pose_button.disabled = frame >= session.last_frame

func contact_frame() -> int:
	return clampi(roundi(session.frame_at_time(ball_preview.contact_time)),0,session.last_frame)

func jump_to_contact_frame() -> void:
	set_playing(false)
	set_frame(contact_frame())

func refresh_contact_frame() -> void:
	contact_frame_button.visible = ball_preview.active
	if not ball_preview.active: return
	var result := "Contact frame"
	if ball_preview.missed or not ball_preview.incoming_net.is_empty(): result = "Miss at frame"
	contact_frame_button.text = "%s %d" % [result,contact_frame()]

func step_frame(direction: int) -> void:
	set_playing(false)
	set_frame(frame+direction)

func set_playing(value: bool) -> void:
	if entry.id=="camp_right_arm_swing": InteractionTrace.record("shot_playback",{"playing":value,"frame":frame})
	playing = value
	playhead = float(frame)
	if playing and frame == 0 and ball_preview.active: playhead = minf(0,ball_preview.contact_time-ball_preview.feed_duration)*session.frame_rate
	if is_instance_valid(ball_preview): ball_preview.last_time = session.time_at(frame)
	if is_instance_valid(play_button): play_button.text = "Pause" if playing else "Play"

func release_rotation_arrow() -> void:
	if held_rotation_field:
		held_rotation_field.custom_arrow_step=0.
		held_rotation_field=null

func _process(delta: float) -> void:
	if held_rotation_field:
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or not get_window().has_focus():
			release_rotation_arrow()
		elif Time.get_ticks_msec()-rotation_press_ms>=250:
			held_rotation_field.custom_arrow_step=held_rotation_field.step*50.

	super._process(delta)
	if session == null: return
	if not session.sample_times.is_empty():
		if playing:
			var time := fposmod(session.time_at(playhead)+delta*playback_speed,session.source.length)
			playhead=session.frame_at_time(time)
			set_frame(floori(playhead))
			session.sample(playhead)
		ball_preview.tick(session.time_at(playhead if playing else float(frame)),playing)
		return
	if playing and not ball_preview.active:
		var first := float(session.source.get_meta("editor_loop_start",0))
		playhead = first+fposmod(maxf(playhead,first)-first+delta*playback_speed*session.frame_rate,session.last_frame+1.-first)
		set_frame(floori(playhead))
		session.sample(minf(playhead,session.last_frame))
	elif playing:
		var first: float = minf(0,ball_preview.contact_time-ball_preview.feed_duration)*session.frame_rate
		var last: float = ball_preview.cycle_end()*session.frame_rate
		playhead = first+fposmod(playhead-first+delta*playback_speed*session.frame_rate,last-first)
		var playback_frame: float = ball_preview.animation_time(playhead/session.frame_rate)*session.frame_rate
		set_frame(floori(playback_frame))
		session.sample(playback_frame)
	if is_instance_valid(ball_preview):
		ball_preview.tick((playhead if playing else float(frame))/session.frame_rate,playing)
		refresh_contact_frame()
	if is_instance_valid(angle_control) and angle_control.visible: angle_control.set_actual(ball_preview.output_angle(),Flight.distance(ball_preview.impact_point,ball_preview.outgoing))
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
		for frame in session.position_edits.get(name_,{}): keys[frame] = true
	timeline.set_meta("keyframes",keys.keys())
	timeline.queue_redraw()

func rotation_changed(_value: float) -> void:
	if updating or session == null or selected_bone < 0: return
	set_playing(false)
	if not held_rotation_field or not rotation_hold_recorded:
		remember_undo()
		rotation_hold_recorded=held_rotation_field!=null
	var angles := Vector3(rotation_fields[0].value,rotation_fields[1].value,rotation_fields[2].value)*PI/180.0
	apply_rotation_group(Quaternion.from_euler(angles))
	sample_editor_pose()
	refresh_keys()

func key_joint() -> void:
	if session == null or selected_bone < 0: return
	set_playing(false)
	remember_undo()
	for bone in scope_bones():
		session.set_offset(bone,frame,session.offset_at(bone,frame))
		var name_ := str(preview_player.skeleton.get_bone_name(bone))
		if session.position_edits.has(name_):
			session.position_edits[name_][frame] = session.position_offset_at(bone,frame)
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
	if name_.begins_with("clavicle_"): return rig.find_bone("upperarm_"+name_.right(1))
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
	for name_ in ["pelvis","spine_01","spine_02","spine_03","Head","clavicle_l","clavicle_r","upperarm_l","lowerarm_l","hand_l","upperarm_r","lowerarm_r","hand_r","thigh_l","calf_l","foot_l","thigh_r","calf_r","foot_r"]:
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
	if is_instance_valid(floor_ball) and floor_ball.visible:
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
			if event.pressed and preview_camera.unproject_position(floor_ball.global_position).distance_to(event.position)<18.:
				dragging_floor_ball=true
				preview.accept_event()
				return
			if not event.pressed and dragging_floor_ball:
				dragging_floor_ball=false
				preview.accept_event()
				return
		if dragging_floor_ball and event is InputEventMouseMotion:
			var hit: Variant=Plane(Vector3.UP,SET_MARKER_ORIGIN.y).intersects_ray(preview_camera.project_ray_origin(event.position),preview_camera.project_ray_normal(event.position))
			if hit is Vector3:
				shot_setup.set_x=clampf(hit.x,-4.5,4.5)-SET_MARKER_ORIGIN.x
				shot_setup.set_z=clampf(hit.z,-5.,3.9)-SET_MARKER_ORIGIN.z
				floor_ball.position=SET_MARKER_ORIGIN+Vector3(shot_setup.set_x,0.,shot_setup.set_z)
				queue_live_shot()
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
				var handle_origin := endpoint_world(index)
				drag_plane = Plane(preview_camera.global_basis.z,handle_origin)
				if str(preview_player.skeleton.get_bone_name(index)).begins_with("clavicle_"):
					var hit: Variant = drag_plane.intersects_ray(preview_camera.project_ray_origin(event.position),preview_camera.project_ray_normal(event.position))
					shoulder_drag_origin = hit if hit is Vector3 else handle_origin
					shoulder_start_offset = session.position_offset_at(index,frame)
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
	var name_ := str(rig.get_bone_name(selected_bone))
	if name_.begins_with("clavicle_"):
		var forward := preview_player.global_basis.z.normalized()
		var distance := clampf((target-shoulder_drag_origin).dot(forward),-0.15,0.15)
		var parent := rig.get_bone_parent(selected_bone)
		var parent_basis := rig.global_basis*rig.get_bone_global_pose(parent).basis
		var keys: Dictionary = session.position_edits.get(name_,{})
		keys[frame] = shoulder_start_offset+parent_basis.inverse()*(forward*distance)
		session.position_edits[name_] = keys
		sample_editor_pose()
		refresh_keys()
		return
	var pivot := bone_world(selected_bone)
	var from := endpoint_world(selected_bone)-pivot
	var to := target-pivot
	if from.length_squared() < 0.00001 or to.length_squared() < 0.00001: return
	var turn := Quaternion(from.normalized(),to.normalized())
	apply_world_turn(turn)
	sample_editor_pose()
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
	var original := entry.duplicate()
	if session.source.has_meta("editor_feed"): original.id = entry.get("source",entry.id)
	var edited: Animation = session.bake()
	edited.set_meta("editor_initial_frame",frame)
	var saved := Catalog.save_copy(edited,original,copy_name.text)
	if saved.is_empty():
		var dialog := AcceptDialog.new()
		dialog.dialog_text = "Unable to save animation."
		add_child(dialog)
		dialog.popup_centered()
		return
	StorySession.edit_animation = null
	StorySession.animation_draft.clear()
	StorySession.animation_return = {"category":saved.category,"type":saved.type,"id":saved.id}
	MenuPresentation.load_scene(origin_scene if not origin_scene.is_empty() else ("res://scenes/drills.tscn" if not StorySession.return_to_drill.is_empty() else "res://scenes/story_animations.tscn"))

func open_menu() -> void:
	if session != null:
		StorySession.animation_draft = {"source":entry.id,"animation":session.source,"edits":session.edits.duplicate(true),"position_edits":session.position_edits.duplicate(true),"name":copy_name.text,"frame":frame,"group":selected_group}
	StorySession.animation_return = {"category":entry.category,"type":entry.type,"id":entry.id}
	MenuPresentation.load_scene(origin_scene if not origin_scene.is_empty() else ("res://scenes/drills.tscn" if not StorySession.return_to_drill.is_empty() else "res://scenes/story_animations.tscn"))

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
