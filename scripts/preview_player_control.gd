extends RefCounted
var page: Control
var active := false
var free_view := {}
var animator_active := true
var animation_process := 0
var moving := false
var indicator: Label
var save_clock := 0.0
var footwork: RefCounted
var stamina := 100.0
var exhausted := false
var recovery_delay := 0.0
var sprinting := false
var sprint_requested := false
var locomotion := ""
var stamina_bar: ProgressBar
var side_steps: RefCounted

func _init(host: Control) -> void:
	page = host
	footwork = preload("res://scripts/directional_footwork.gd").new(page.preview_player)
	side_steps = preload("res://scripts/right_side_steps.gd").new(page.preview_player)
	indicator = Label.new()
	indicator.text = "Camera"
	indicator.add_theme_font_size_override("font_size",13)
	indicator.modulate.a = 0.55
	indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.preview.add_child(indicator)
	indicator.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	indicator.offset_left = -80
	indicator.offset_right = -12
	indicator.offset_top = 10
	indicator.offset_bottom = 30
	indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stamina_bar = ProgressBar.new()
	stamina_bar.show_percentage = false
	stamina_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stamina_bar.value = stamina
	stamina_bar.visible = false
	page.preview.add_child(stamina_bar)
	stamina_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	stamina_bar.offset_left = -124
	stamina_bar.offset_right = -14
	stamina_bar.offset_top = 35
	stamina_bar.offset_bottom = 43
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("e4ba56")
	fill.set_corner_radius_all(3)
	stamina_bar.add_theme_stylebox_override("fill",fill)
	var saved: Dictionary = page.get_node("/root/StorySession").preview_camera
	if not saved.is_empty():
		page.orbit_yaw = saved.yaw
		page.orbit_pitch = saved.pitch
		page.view_distance = saved.distance
		page.view_focus = saved.focus
		page.update_camera()

func handle_key(event: InputEventKey) -> bool:
	if not event.pressed or event.echo or not event.keycode in [KEY_F1,KEY_F2]: return false
	set_active(event.keycode==KEY_F1)
	page.preview.grab_focus()
	return true

func set_active(value: bool) -> void:
	if active==value: return
	var actor: Node3D = page.preview_player
	active = value
	side_steps.active = false
	stamina_bar.visible = active
	locomotion = ""
	sprinting = false
	if active:
		free_view = {"yaw":page.orbit_yaw,"pitch":page.orbit_pitch,"distance":page.view_distance,"focus":page.view_focus}
		animator_active = actor.animator.active
		animation_process = actor.animator.callback_mode_process
		actor.animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		actor.animator.active = true
		moving = false
		actor.play_action("idle")
		follow_camera()
	else:
		actor.model.rotation.y = 0
		page.orbit_yaw = free_view.yaw
		page.orbit_pitch = free_view.pitch
		page.view_distance = free_view.distance
		page.view_focus = free_view.focus
		actor.animator.active = animator_active
		actor.animator.callback_mode_process = animation_process
		actor.animator.speed_scale = 1.0
		if actor.animator.has_animation("custom_preview/clip"):
			actor.animator.play("custom_preview/clip",0)
			actor.animator.pause()
		page.update_camera()
		page.angle_control.pending = true
	indicator.text = "Player" if active else "Camera"
	page.get_node("/root/StorySession").save_preview_setup()

func step(delta: float) -> void:
	var session = page.get_node("/root/StorySession")
	save_clock += delta
	if save_clock>=1:
		save_clock = 0
		session.preview_camera = free_view if active else {"yaw":page.orbit_yaw,"pitch":page.orbit_pitch,"distance":page.view_distance,"focus":page.view_focus}
		session.save_preview_setup()
	if not active:
		stamina = minf(100,stamina+17*delta)
		return
	var direction := Vector2.ZERO
	var focus := page.get_viewport().gui_get_focus_owner()
	if not (focus is LineEdit or focus is TextEdit):
		direction = Vector2(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),float(Input.is_physical_key_pressed(KEY_W))-float(Input.is_physical_key_pressed(KEY_S)))
		var pads := Input.get_connected_joypads()
		if not pads.is_empty():
			var stick := Vector2(Input.get_joy_axis(pads[0],JOY_AXIS_LEFT_X),-Input.get_joy_axis(pads[0],JOY_AXIS_LEFT_Y))
			if stick.length()>0.15: direction += stick*((stick.length()-0.15)/0.85)/stick.length()
	sprint_requested = Input.is_physical_key_pressed(KEY_SHIFT)
	var connected := Input.get_connected_joypads()
	if not connected.is_empty(): sprint_requested = sprint_requested or Input.is_joy_button_pressed(connected[0],JOY_BUTTON_RIGHT_SHOULDER)
	move_player(direction.limit_length(),delta)

func move_player(direction: Vector2, delta: float) -> void:
	var actor: Node3D = page.preview_player
	var session = page.get_node("/root/StorySession")
	var forward := (Vector3(0,0,4)-actor.position).normalized()
	forward.y = 0
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP)
	if exhausted and stamina>=25: exhausted = false
	sprinting = sprint_requested and direction.y>0.3 and direction.length()>0.1 and not exhausted and stamina>0
	var speed := 4.5 if sprinting else 1.65
	var velocity := (right*direction.x+forward*direction.y)*speed
	var before := actor.position
	var movement := velocity*delta
	var right_step: bool = not sprinting and (side_steps.active or (direction.x>0.35 and absf(direction.y)<0.3))
	side_steps.sampled = false
	if right_step: movement = right*side_steps.advance(direction,delta)*actor.scale.y
	actor.position.x = clampf(actor.position.x+movement.x,-4,4)
	actor.position.z = clampf(actor.position.z+movement.z,-4.5,2.5)
	actor.rotation.y = atan2(forward.x,forward.z)
	session.pass_start = Vector2(actor.position.x,actor.position.z)
	var now_moving := actor.position.distance_to(before)>0.00001
	sprinting = sprinting and now_moving
	if sprinting:
		stamina = maxf(0,stamina-25*delta)
		recovery_delay = 0.7
		if stamina<=0: exhausted = true
	else:
		recovery_delay = maxf(0,recovery_delay-delta)
		if recovery_delay<=0: stamina = minf(100,stamina+17*delta)
	stamina_bar.value = stamina
	var action := "run" if sprinting else "idle"
	if action!=locomotion:
		locomotion = action
		actor.play_action(action)
	moving = now_moving
	actor.animator.speed_scale = 1.35 if sprinting else 1.0
	actor.animator.advance(delta)
	var local_velocity: Vector3 = actor.basis.inverse()*velocity
	var model_yaw := atan2(local_velocity.x,local_velocity.z) if sprinting else 0.0
	actor.model.rotation.y = lerp_angle(actor.model.rotation.y,model_yaw,1-exp(-delta*16))
	if right_step:
		footwork.weight = 0
		side_steps.apply_pose()
	elif sprinting:
		footwork.weight = 0
	else:
		footwork.step(local_velocity/1.65 if moving else Vector3.ZERO,delta)
	follow_camera()

func follow_camera() -> void:
	var actor: Node3D = page.preview_player
	var forward := (Vector3(0,0,4)-actor.position).normalized()
	forward.y = 0
	forward = forward.normalized()
	actor.rotation.y = atan2(forward.x,forward.z)
	page.preview_camera.position = actor.position-forward*7.5+Vector3.UP*4.2
	page.preview_camera.look_at(actor.position+forward*2+Vector3.UP*1.1)
