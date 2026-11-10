extends RefCounted
const QUICK_STEP_RATE := 1.5
const Court = preload("res://scripts/preview_court.gd")
const Stamina = preload("res://scripts/player_stamina.gd")
const LowSave = preload("res://scripts/player_reception_save.gd")
const PassDrive = preload("res://scripts/reception_pass_drive.gd")
var page: Control
var active := false
var free_view := {}
var animator_active := true
var animation_process := 0
var moving := false
var receive_elapsed := 0.0
const RECEIVE_FOLLOW_TIME := 0.25
const RECEIVE_RECOVERY_BLEND := 0.29
var receive_pose_elapsed := 0.0
var low_save := LowSave.new()
var receive_queued := false
var receive_camera_pan := Vector3.ZERO
var receive_entry_pose: Array[Transform3D] = []
var receive_entry_elapsed := 0.0
var receive_ready_pose: Array[Transform3D] = []
var receive_exit_pose: Array[Transform3D] = []
var receive_exit_elapsed := 0.0
var neutral_hold := 0.0
var return_started := false
var reach_step := Vector3.ZERO
var reach_progress := 0.0
var high_adjustment := Vector3.ZERO
var reach_travel := Vector3.ZERO
var reach_lead := "l"
var reach_tier := 1
var reach_height := 0.0
var reach_side_lunge := false
var reach_forward_lunge := false
var reach_back := false
var reach_short_straight_back := false
var reach_rear_diagonal := false
var indicator: Label
var save_clock := 0.0
var footwork: RefCounted
var stamina := Stamina.new()
var sprinting := false
var sprint_requested := false
var locomotion := ""
var stamina_ring: MeshInstance3D
var side_steps: RefCounted
var side_weight := 0.0
var shuffle_heading := Vector3.ZERO
var setter_travel := Vector3.ZERO
var setter_step_rate := QUICK_STEP_RATE

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
	stamina_ring = preload("res://scripts/player_stamina_ring.gd").new()
	page.preview_player.add_child(stamina_ring)
	stamina_ring.hide()
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
	reset_receive_attempt()
	receive_camera_pan = Vector3.ZERO
	clear_receive_transition()
	reset_reach()
	side_steps.active = false
	side_weight = 0
	show_stamina(active)
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
		face_ball()
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
		if not reception_drill_active(): page.angle_control.pending = true
	indicator.text = "Player" if active else "Camera"
	page.get_node("/root/StorySession").save_preview_setup()

func reception_drill_active() -> bool:
	return page.has_method("reception_drill_active") and page.reception_drill_active()

func step(delta: float) -> void:
	var session = page.get_node("/root/StorySession")
	save_clock += delta
	if save_clock>=1:
		save_clock = 0
		session.preview_camera = free_view if active else {"yaw":page.orbit_yaw,"pitch":page.orbit_pitch,"distance":page.view_distance,"focus":page.view_focus}
		session.save_preview_setup()
	if not active:
		stamina.recover(delta)
		return
	var direction := movement_input()
	read_pace_input()
	if receive_queued:
		receive_elapsed = delta
		receive_queued = false
	elif receive_elapsed > 0.0:
		receive_elapsed += delta
	var drill := reception_drill_active()
	if drill and receive_elapsed > 0.0:
		var ball = page.ball_preview
		var time: float = page.preview_clock+delta-ball.contact_time
		var path := func(t): return ball.practice_position(t)
		if not low_save.active and ball.practice_grade == ball.Grade.WAITING and ball.incoming_net.is_empty():
			if low_save.plan(page.preview_player,path,time,ball.practice_floor_time,ball.clip): spend_dive_stamina()
		if low_save.active:
			if not low_save.finished(time):
				var release := float(ball.recovery.get("time",low_save.contact_time+0.07))
				var actor: Node3D = page.preview_player
				actor.animator.pause()
				actor.model.rotation.y = 0.0
				low_save.sample(actor,time,release)
				receive_pose_elapsed += delta
				ball.update_practice_platform()
				follow_camera()
				return
			locomotion = ""
			reset_receive_attempt()
		var after_touch := 0.0
		if ball.recovery.has("spread"):
			after_touch = maxf(0.0,page.preview_clock-ball.contact_time-float(ball.recovery.time))
		var approaching: bool = ball.practice_approach(page.preview_clock+delta,1.12) >= 0.0
		if (ball.practice_grade == ball.Grade.WAITING and (approaching or receive_pose_elapsed > 0.0)) or (ball.recovery.has("spread") and after_touch < RECEIVE_FOLLOW_TIME):
			receive_pose_elapsed += delta
			var windup := 0.14*(1.0-smoothstep(0.0,0.11,receive_pose_elapsed))
			receive_camera_pan = (receive_camera_pan+page.camera_pan_delta(direction,delta,3.5)).limit_length(4.0)
			play_receive_pose(delta,Vector3.INF,-windup+after_touch*1.4)
			follow_camera()
			return
		if ball.practice_grade != ball.Grade.WAITING: reset_receive_attempt()
	receive_camera_pan = Vector3.ZERO
	end_receive_pose()
	reset_reach()
	move_player(direction,delta)
	blend_receive_recovery(delta)

func pan_frozen_camera(direction: Vector2, delta: float) -> void:
	if direction.is_zero_approx(): return
	receive_camera_pan = (receive_camera_pan+page.camera_pan_delta(direction,delta,3.5)).limit_length(4.0)
	follow_camera()

func show_stamina(value: bool) -> void:
	stamina_ring.visible = value
	if value: update_stamina_ring()

func spend_dive_stamina() -> void:
	stamina.spend(Stamina.DIVE_COST)
	update_stamina_ring()

func update_stamina_ring() -> void:
	if stamina_ring.visible: stamina_ring.set_fraction(stamina.value/100.0)

func read_pace_input() -> void:
	sprint_requested = Input.is_physical_key_pressed(KEY_SHIFT)
	var connected := Input.get_connected_joypads()
	if not connected.is_empty(): sprint_requested = sprint_requested or Input.is_joy_button_pressed(connected[0],JOY_BUTTON_RIGHT_SHOULDER)

func movement_input() -> Vector2:
	var direction := Vector2.ZERO
	var focus := page.get_viewport().gui_get_focus_owner()
	if not (focus is LineEdit or focus is TextEdit):
		direction = Vector2(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),float(Input.is_physical_key_pressed(KEY_W))-float(Input.is_physical_key_pressed(KEY_S)))
		var pads := Input.get_connected_joypads()
		if not pads.is_empty():
			var stick := Vector2(Input.get_joy_axis(pads[0],JOY_AXIS_LEFT_X),-Input.get_joy_axis(pads[0],JOY_AXIS_LEFT_Y))
			if stick.length()>0.15: direction += stick*((stick.length()-0.15)/0.85)/stick.length()
	return direction.limit_length()

func reset_receive_attempt() -> void:
	if low_save.active: locomotion = ""
	receive_elapsed = 0.0
	receive_pose_elapsed = 0.0
	low_save.active = false
	receive_queued = false

func queue_receive() -> bool:
	if not active or not reception_drill_active(): return false
	var focus := page.get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return false
	if receive_elapsed == 0.0 and page.ball_preview.practice_grade == page.ball_preview.Grade.WAITING:
		receive_queued = true
		page.ball_preview.practice_early_attempt = true
	return true

func play_receive_pose(delta: float, review_offset := Vector3.INF, pose_offset := 0.0, planted := false) -> void:
	var actor: Node3D = page.preview_player
	var entering := receive_entry_pose.is_empty()
	if entering:
		receive_entry_pose = snapshot_receive_pose()
		receive_entry_elapsed = 0.0
		receive_exit_pose.clear()
	side_steps.active = false
	side_steps.hold = 0.0
	side_weight = 0.0
	locomotion = ""
	sprinting = false
	moving = false
	actor.model.rotation.y = 0.0
	var ball = page.ball_preview
	if ball.recovery.is_empty(): face_ball()
	actor.animator.play("custom_preview/clip",0)
	if entering:
		actor.animator.seek(0.0,true)
		receive_ready_pose = snapshot_receive_pose()
	actor.animator.seek(maxf(0.0,page.ball_preview.contact_time+pose_offset),true)
	actor.animator.pause()
	if not planted: step_into_receive(delta,review_offset)
	var struck: bool = ball.recovery.has("spread")
	var outgoing: Vector3 = ball.recovery.velocity if struck else ball.practice_pass_velocity(ball.practice_platform_center(),0.0)
	var incoming: Vector3 = ball.incoming
	if struck: incoming += ball.feed_info.acceleration*float(ball.recovery.time)
	var power := PassDrive.effort(incoming,outgoing)
	var origin: Vector3 = ball.recovery.point if struck else ball.practice_platform_center()
	PassDrive.apply(actor.skeleton,footwork.author,outgoing,power,pose_offset,struck,incoming,PassDrive.swing_effort(origin,outgoing))
	if planted:
		var rig: Skeleton3D = actor.skeleton
		for name_ in ["pelvis","thigh_l","thigh_r","calf_l","calf_r","foot_l","foot_r","ball_l","ball_r"]:
			var bone := rig.find_bone(name_)
			if bone < 0: continue
			rig.set_bone_pose_position(bone,receive_ready_pose[bone].origin)
			rig.set_bone_pose_rotation(bone,receive_ready_pose[bone].basis.get_rotation_quaternion())
	var entry_duration := 0.11 if planted else 0.15
	if receive_entry_elapsed < entry_duration:
		receive_entry_elapsed += delta
		blend_pose_from(receive_entry_pose,smoothstep(0.0,entry_duration,receive_entry_elapsed))
		if not planted and (not reach_step.is_zero_approx() or reach_height != 0.0):
			ball.update_practice_platform()
	if planted: ball.update_practice_platform()

func snapshot_receive_pose() -> Array[Transform3D]:
	var rig: Skeleton3D = page.preview_player.skeleton
	var result: Array[Transform3D] = []
	for bone in rig.get_bone_count(): result.append(rig.get_bone_pose(bone))
	return result

func blend_pose_from(start: Array[Transform3D], weight: float) -> void:
	var rig: Skeleton3D = page.preview_player.skeleton
	for bone in rig.get_bone_count():
		var current := rig.get_bone_pose(bone)
		rig.set_bone_pose_position(bone,start[bone].origin.lerp(current.origin,weight))
		rig.set_bone_pose_rotation(bone,start[bone].basis.get_rotation_quaternion().slerp(current.basis.get_rotation_quaternion(),weight))

func end_receive_pose() -> void:
	if receive_entry_pose.is_empty(): return
	receive_entry_pose.clear()
	receive_exit_pose = snapshot_receive_pose()
	receive_exit_elapsed = 0.0

func blend_receive_recovery(delta: float) -> void:
	if receive_exit_pose.is_empty(): return
	receive_exit_elapsed += delta
	if receive_exit_elapsed >= RECEIVE_RECOVERY_BLEND:
		receive_exit_pose.clear()
		return
	blend_pose_from(receive_exit_pose,smoothstep(0.0,RECEIVE_RECOVERY_BLEND,receive_exit_elapsed))

func clear_receive_transition() -> void:
	receive_entry_pose.clear()
	receive_exit_pose.clear()
	neutral_hold = 0.0
	return_started = false

func settle_for_next_feed(start: Vector3, yaw: float, delta: float) -> bool:
	var actor: Node3D = page.preview_player
	end_receive_pose()
	reset_reach()
	var return_path := start-actor.position
	if return_path.length_squared() > 0.0025:
		if not return_started:
			return_started = true
			receive_exit_pose = snapshot_receive_pose()
			receive_exit_elapsed = 0.0
		actor.rotation.y = lerp_angle(actor.rotation.y,yaw,1-exp(-16.0*delta))
		move_cpu_toward(return_path,delta,false)
		blend_receive_recovery(delta)
		return false
	actor.position = start
	actor.rotation.y = yaw
	actor.model.rotation.y = 0.0
	side_steps.active = false
	side_steps.sampled = false
	side_weight = 0.0
	footwork.weight = 0.0
	locomotion = ""
	sprinting = false
	sprint_requested = false
	moving = false
	actor.animator.speed_scale = 1.0
	actor.animator.play("custom_preview/clip",0)
	actor.animator.seek(0.0,true)
	actor.animator.pause()
	blend_receive_recovery(delta)
	if not receive_exit_pose.is_empty(): return false
	neutral_hold += delta
	return neutral_hold >= 0.16

func reset_reach() -> void:
	if reach_step.is_zero_approx() and reach_height == 0.0: return
	reach_step = Vector3.ZERO
	reach_height = 0.0
	reach_side_lunge = false
	reach_forward_lunge = false
	reach_back = false
	reach_short_straight_back = false
	reach_rear_diagonal = false
	reach_tier = 1
	reach_travel = Vector3.ZERO
	reach_progress = 0.0
	high_adjustment = Vector3.ZERO
	if reception_drill_active(): page.ball_preview.practice_reach_center = Vector3.INF

func cpu_knee_slide() -> bool:
	var arrows = page.preview_player.get_node("DirectionArrows")
	return not active and arrows.selected_distance == 3 and arrows.selected in [3,7]

func receive_animation_direction() -> int:
	var arrows = page.preview_player.get_node("DirectionArrows")
	if arrows.selected_distance == 2:
		if arrows.selected == 4: return 3
		if arrows.selected == 6: return 7
	return arrows.selected

func step_into_receive(delta: float, review_offset: Vector3) -> void:
	var actor: Node3D = page.preview_player
	var ball = page.ball_preview
	if reach_step.is_zero_approx() and reach_height == 0.0:
		var offset: Vector3 = review_offset if review_offset.is_finite() else ball.practice_step_offset(page.preview_clock)
		if not review_offset.is_finite() and active:
			var high: Dictionary = ball.practice_shoulder_intercept()
			if not high.is_empty() and absf(float(high.time)-page.preview_clock-0.09)<0.15:
				var center: Vector3 = ball.practice_platform_center()
				var up_close: Vector3 = high.point-center
				if up_close.y>=0.29 and up_close.y<=0.62 and Vector2(up_close.x,up_close.z).length()<0.58:
					offset = up_close
		if offset.is_zero_approx(): return
		var tier: int = ball.practice_reach_tier(offset)
		var arrows = actor.get_node("DirectionArrows")
		var animation_direction := receive_animation_direction()
		var directional_cpu: bool = not active and review_offset.is_finite() and (not page.reception_review.active or arrows.selected_distance == 3)
		if directional_cpu:
			tier = 2 if arrows.selected_distance == 3 and animation_direction in [3,7] else arrows.selected_distance
		if tier == 3: return
		var local := actor.basis.inverse()*offset
		if tier == 1 and absf(local.x)<0.12 and absf(local.z)<0.12: return
		reach_tier = tier
		var court_forward := Vector3(0,actor.position.y,4)-actor.position
		court_forward = court_forward.normalized()
		var forward_offset := offset.dot(court_forward)
		var side_offset := offset.dot(court_forward.cross(Vector3.UP))
		reach_back = forward_offset < -absf(side_offset)*0.65
		reach_height = offset.y if tier == 2 or directional_cpu else 0.0
		reach_short_straight_back = tier == 1 and reach_height < 0.20 and reach_back and -local.z > absf(local.x)*1.4
		if directional_cpu:
			reach_short_straight_back = tier == 1 and reach_height < 0.20 and animation_direction == 5
		reach_side_lunge = tier == 2 and absf(local.x) > absf(local.z)*1.4
		reach_forward_lunge = local.z > absf(local.x)*1.4
		if directional_cpu and tier == 2 and animation_direction in [2,3,7,8]:
			reach_side_lunge = true
			reach_forward_lunge = false
		var horizontal := Vector3(offset.x,0.0,offset.z)
		var step_limit := 0.68 if reach_side_lunge else (0.75 if tier == 2 else 0.46)
		var stride := 1.0 if reach_back and tier == 2 else 0.78
		reach_step = horizontal.limit_length(step_limit)*stride
		if directional_cpu and tier == 1 and animation_direction in [1,5]:
			reach_step = offset.slide(Vector3.UP).normalized()*0.48
		if directional_cpu and ((tier == 1 and animation_direction == 6) or (tier == 2 and animation_direction == 3)):
			# Keep the shoulder inside the ball's lane while the platform reaches across it.
			reach_step -= actor.basis.x*reach_step.dot(actor.basis.x)*0.32
		if directional_cpu and arrows.selected_distance == 3 and animation_direction in [3,7]:
			reach_step += horizontal.normalized()*0.43
		if directional_cpu and tier == 2 and animation_direction in [4,5,6]:
			reach_back = true
			reach_side_lunge = false
			reach_forward_lunge = false
			var clearance_side := -1.0 if animation_direction == 4 else 1.0
			if reach_height >= 0.20 and animation_direction != 5: clearance_side *= -1.0
			var clearance := 0.24
			if reach_height < 0.20 and animation_direction != 5:
				clearance = 0.0 if animation_direction == 4 else 0.10
			reach_step = horizontal-court_forward*0.32-court_forward.cross(Vector3.UP)*clearance_side*clearance
			var remaining := 1.20
			if animation_direction == 5 and page.cpu_start.is_finite():
				remaining -= actor.position.distance_to(page.cpu_start)
			reach_step = reach_step.limit_length(remaining)
		reach_rear_diagonal = tier == 2 and reach_back and absf(local.x)>0.20
		if directional_cpu: reach_rear_diagonal = tier == 2 and animation_direction in [4,6]
		reach_lead = "l" if local.x >= 0.0 else "r"
		if tier == 1 and (reach_forward_lunge or reach_short_straight_back): reach_lead = "r"
	var before := smoothstep(0.0,1.0,reach_progress)
	reach_progress = minf(1.0,reach_progress+delta/(0.19 if reach_tier == 2 else 0.15))
	var amount := smoothstep(0.0,1.0,reach_progress)
	var next := actor.position+reach_step*(amount-before)
	if reach_height >= 0.29 and ball.recovery.is_empty() and ball.practice_reach_center.is_finite():
		var intercept: Dictionary = ball.practice_intercept(ball.practice_reach_center.y)
		if not active and review_offset.is_finite() and not page.reception_review.active:
			intercept = {"point":ball.aim_point,"time":ball.contact_time}
		if not intercept.is_empty() and float(intercept.time)>=page.preview_clock-delta:
			var correction: Vector3 = intercept.point-ball.practice_reach_center
			correction.y = 0.0
			var adjusted := (high_adjustment+correction.limit_length(delta*3.5)).limit_length(0.32)
			next += adjusted-high_adjustment
			high_adjustment = adjusted
	var previous := actor.position
	actor.position.x = clampf(next.x,-4.0,4.0)
	actor.position.z = clampf(next.z,-4.5,2.5)
	reach_travel += actor.position-previous
	if ball.recovery.is_empty(): face_ball()
	var local_step := actor.basis.inverse()*reach_step
	var local_travel := actor.basis.inverse()*reach_travel
	pose_receive_step(actor,local_step,local_travel,amount)
	ball.update_practice_platform()

func pose_receive_step(actor: Node3D, step: Vector3, travel: Vector3, weight: float) -> void:
	var ball = page.ball_preview
	var cpu_direction := receive_animation_direction() if not active and not page.reception_review.active else 0
	var knee_slide := cpu_knee_slide()
	var contact := Vector3.INF
	if knee_slide and cpu_direction != 0:
		contact = ball.aim_point
	elif reach_height >= 0.20:
		var intercept: Dictionary = ball.practice_shoulder_intercept()
		if not intercept.is_empty():
			contact = intercept.point
			if cpu_direction != 0: contact = ball.aim_point
	actor.pose_reception_reach(step,travel,weight,reach_progress,receive_ready_pose,{
		"tier":reach_tier,"back":reach_back,"rear_diagonal":reach_rear_diagonal,
		"short_straight_back":reach_short_straight_back,"forward_lunge":reach_forward_lunge,
		"lead":reach_lead,"side_lunge":reach_side_lunge,"height":reach_height,
	},knee_slide,cpu_direction,contact)

func step_back_for_lunge(start: Vector3, forward: Vector3, delta: float, distance := 0.42) -> void:
	var target := start-forward.normalized()*distance
	move_cpu_toward(target-page.preview_player.position,delta)

func move_cpu_toward(travel: Vector3, delta: float, track_ball := true) -> void:
	var actor: Node3D = page.preview_player
	var forward := Vector3(0,0,4)-actor.position
	forward.y = 0.0
	forward = forward.normalized()
	var distance := travel.length()
	var direction := travel.normalized()*minf(1.0,distance/0.27)
	sprint_requested = distance>0.85
	move_player(Vector2(direction.dot(forward.cross(Vector3.UP)),direction.dot(forward)),delta,track_ball)

func move_player(direction: Vector2, delta: float, track_ball := true, setting_target := Vector3.INF, movement_scale := 1.0, court_weight := 0.0, turn_with_ball := true, front_limit := 2.5) -> void:
	var actor: Node3D = page.preview_player
	var session = page.get_node("/root/StorySession")
	var setting := setting_target.is_finite()
	var forward := Vector3.BACK if setting else (Vector3(0,0,4)-actor.position).normalized()
	forward.y = 0
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP)
	var drill := reception_drill_active()
	var travel := right*direction.x+forward*direction.y
	if setting:
		setter_travel = setter_travel.move_toward(travel*movement_scale,delta*8.0).limit_length(movement_scale)
		travel = setter_travel
	var step_direction := direction
	if setting and turn_with_ball: track_setting_ball(actor,setting_target,delta,court_weight)
	elif not setting and drill and track_ball: face_ball()
	if drill or setting:
		var facing := actor.basis.z.normalized()
		step_direction = Vector2(travel.dot(facing.cross(Vector3.UP)),travel.dot(facing))
	var quick_pace := sprint_requested and direction.length()>0.1 and stamina.can_sprint()
	sprinting = not setting and quick_pace and step_direction.y>0.3
	var step_rate := QUICK_STEP_RATE if quick_pace else 1.0
	if setting:
		setter_step_rate = move_toward(setter_step_rate,QUICK_STEP_RATE*step_rate,delta*7.0)
		step_rate = setter_step_rate
	var speed := 4.5 if sprinting else 1.65*step_rate
	var velocity := travel*speed
	var before := actor.position
	var movement := velocity*delta
	var lateral := absf(step_direction.x)>0.3
	var shuffle_step: bool = not setting and not sprinting and (side_steps.active or lateral)
	side_steps.sampled = false
	if shuffle_step:
		if lateral: shuffle_heading = travel.normalized()
		var distance_: float = side_steps.advance(step_direction,delta*step_rate)*actor.scale.y
		movement = shuffle_heading*distance_
	else: side_steps.active = false
	if setting:
		actor.position = Court.clamp_setter(actor.position+movement,front_limit)
	else:
		actor.position.x = clampf(actor.position.x+movement.x,-4,4)
		actor.position.z = clampf(actor.position.z+movement.z,-4.5,2.5)
	if not setting:
		if drill:
			if track_ball: face_ball()
		else:
			actor.rotation.y = atan2(forward.x,forward.z)
			session.pass_start = Vector2(actor.position.x,actor.position.z)
	var now_moving := actor.position.distance_to(before)>0.00001
	sprinting = sprinting and now_moving
	if quick_pace and now_moving:
		stamina.spend(Stamina.SPRINT_DRAIN*delta)
	else:
		stamina.recover(delta)
	update_stamina_ring()
	var action := "run" if sprinting else "idle"
	if action!=locomotion:
		locomotion = action
		actor.play_action(action)
	moving = now_moving
	actor.animator.speed_scale = 1.35 if sprinting else 1.0
	actor.animator.advance(delta)
	var local_velocity: Vector3 = actor.basis.inverse()*velocity
	var model_yaw := atan2(local_velocity.x,local_velocity.z) if sprinting and not drill else 0.0
	actor.model.rotation.y = lerp_angle(actor.model.rotation.y,model_yaw,1-exp(-delta*16))
	side_weight = move_toward(side_weight,1.0 if shuffle_step else 0.0,delta*9)
	if shuffle_step or sprinting:
		footwork.weight = 0
	else:
		footwork.step(local_velocity/(1.65*step_rate) if moving else Vector3.ZERO,delta,step_rate,setting)
	if side_weight>0: side_steps.apply_pose(side_weight)
	if active: follow_camera()

func track_setting_ball(actor: Node3D, target: Vector3, delta: float, court_weight := 0.0) -> void:
	var toward := (target-actor.global_position).slide(Vector3.UP)
	# At overhead contact, tiny changes in position should not spin the setter around.
	var turn_rate := 8.0*smoothstep(0.25,0.95,toward.length())
	if turn_rate > 0.0:
		var ball_yaw := atan2(toward.x,toward.z)
		var net_bias := clampf(angle_difference(ball_yaw,0.0)*0.15,-deg_to_rad(8.0),deg_to_rad(8.0))
		var yaw := ball_yaw+net_bias
		if court_weight > 0.0:
			var court := Vector3(0.0,0.0,8.5)-actor.global_position
			yaw = lerp_angle(ball_yaw,atan2(court.x,court.z),court_weight)
		actor.rotation.y = rotate_toward(actor.rotation.y,yaw,delta*turn_rate)

func face_ball() -> void:
	if not reception_drill_active(): return
	var actor: Node3D = page.preview_player
	var ball: Node3D = page.ball_preview
	var target: Vector3 = ball.global_position if ball.ball.visible else ball.source_ball.global_position
	if cpu_knee_slide() and not page.reception_review.active:
		target = ball.practice_position(page.preview_clock-ball.contact_time)
	var toward := target-actor.global_position
	if Vector2(toward.x,toward.z).length_squared()>0.01:
		var ball_yaw := atan2(toward.x,toward.z)
		var court_forward := Vector3(0,0,4)-actor.position
		var court_yaw := atan2(court_forward.x,court_forward.z)
		var forward_bias := clampf(angle_difference(ball_yaw,court_yaw)*0.24,-deg_to_rad(12.0),deg_to_rad(12.0))
		actor.rotation.y = ball_yaw+forward_bias

func follow_camera() -> void:
	var actor: Node3D = page.preview_player
	var forward := (Vector3(0,0,4)-actor.position).normalized()
	forward.y = 0
	forward = forward.normalized()
	page.preview_camera.position = actor.position-forward*7.5+Vector3.UP*4.2+receive_camera_pan
	page.preview_camera.look_at(actor.position+forward*2+Vector3.UP*1.1+receive_camera_pan)
