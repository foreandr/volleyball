extends RefCounted
var page: Control
var active := false
var free_view := {}
var animator_active := true
var moving := false
var indicator: Label
var save_clock := 0.0
var footwork: RefCounted

func _init(host: Control) -> void:
	page = host
	footwork = preload("res://scripts/directional_footwork.gd").new(page.preview_player)
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
	if active:
		free_view = {"yaw":page.orbit_yaw,"pitch":page.orbit_pitch,"distance":page.view_distance,"focus":page.view_focus}
		animator_active = actor.animator.active
		actor.animator.active = true
		moving = false
		actor.play_action("idle")
		follow_camera()
	else:
		page.orbit_yaw = free_view.yaw
		page.orbit_pitch = free_view.pitch
		page.view_distance = free_view.distance
		page.view_focus = free_view.focus
		actor.animator.active = animator_active
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
	if not active: return
	var direction := Vector2.ZERO
	var focus := page.get_viewport().gui_get_focus_owner()
	if not (focus is LineEdit or focus is TextEdit):
		direction = Vector2(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),float(Input.is_physical_key_pressed(KEY_W))-float(Input.is_physical_key_pressed(KEY_S)))
		var pads := Input.get_connected_joypads()
		if not pads.is_empty():
			var stick := Vector2(Input.get_joy_axis(pads[0],JOY_AXIS_LEFT_X),-Input.get_joy_axis(pads[0],JOY_AXIS_LEFT_Y))
			if stick.length()>0.15: direction += stick*((stick.length()-0.15)/0.85)/stick.length()
	move_player(direction.limit_length(),delta)

func move_player(direction: Vector2, delta: float) -> void:
	var actor: Node3D = page.preview_player
	var session = page.get_node("/root/StorySession")
	var forward := (Vector3(0,0,4)-actor.position).normalized()
	forward.y = 0
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP)
	var velocity := (right*direction.x+forward*direction.y)*2.8
	var movement := velocity*delta
	actor.position.x = clampf(actor.position.x+movement.x,-4,4)
	actor.position.z = clampf(actor.position.z+movement.z,-4.5,2.5)
	actor.rotation.y = atan2(forward.x,forward.z)
	session.pass_start = Vector2(actor.position.x,actor.position.z)
	var now_moving := direction.length()>0.05
	if now_moving!=moving:
		moving = now_moving
		actor.play_action("idle")
	actor.animator.advance(delta)
	footwork.step(actor.basis.inverse()*velocity/2.8,delta)
	follow_camera()

func follow_camera() -> void:
	var actor: Node3D = page.preview_player
	var forward := (Vector3(0,0,4)-actor.position).normalized()
	forward.y = 0
	forward = forward.normalized()
	actor.rotation.y = atan2(forward.x,forward.z)
	page.preview_camera.position = actor.position-forward*7.5+Vector3.UP*4.2
	page.preview_camera.look_at(actor.position+forward*2+Vector3.UP*1.1)
