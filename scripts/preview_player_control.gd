extends RefCounted
const QUICK_STEP_RATE := 1.5
const PlatformPose = preload("res://scripts/reception_platform_pose.gd")
const PassDrive = preload("res://scripts/reception_pass_drive.gd")
var page: Control
var active := false
var free_view := {}
var animator_active := true
var animation_process := 0
var moving := false
var receive_elapsed := 0.0
var receive_queued := false
var receive_camera_pan := Vector3.ZERO
var receive_entry_pose: Array[Transform3D] = []
var receive_entry_elapsed := 0.0
var receive_exit_pose: Array[Transform3D] = []
var receive_exit_elapsed := 0.0
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
var side_weight := 0.0
var shuffle_heading := Vector3.ZERO

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
	receive_elapsed = 0.0
	receive_queued = false
	receive_camera_pan = Vector3.ZERO
	clear_receive_transition()
	reset_reach()
	side_steps.active = false
	side_weight = 0
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
		stamina = minf(100,stamina+17*delta)
		return
	var direction := movement_input()
	sprint_requested = Input.is_physical_key_pressed(KEY_SHIFT)
	var connected := Input.get_connected_joypads()
	if not connected.is_empty(): sprint_requested = sprint_requested or Input.is_joy_button_pressed(connected[0],JOY_BUTTON_RIGHT_SHOULDER)
	if receive_queued:
		receive_elapsed = delta
		receive_queued = false
	elif receive_elapsed > 0.0:
		receive_elapsed += delta
	var drill := reception_drill_active()
	if drill and receive_elapsed > 0.0:
		var ball = page.ball_preview
		var after_touch := 0.0
		if ball.recovery.has("spread"):
			after_touch = maxf(0.0,page.preview_clock-ball.contact_time-float(ball.recovery.time))
		if receive_elapsed <= 0.44 and after_touch < 0.18:
			var windup := 0.14*(1.0-smoothstep(0.0,0.085,receive_elapsed))
			receive_camera_pan = (receive_camera_pan+page.camera_pan_delta(direction,delta,3.5)).limit_length(4.0)
			play_receive_pose(delta,Vector3.INF,-windup+after_touch*1.4)
			follow_camera()
			return
		if receive_elapsed > 0.44: ball.practice_early_attempt = true
	receive_elapsed = 0.0
	receive_camera_pan = Vector3.ZERO
	end_receive_pose()
	reset_reach()
	move_player(direction,delta)
	blend_receive_recovery(delta)

func pan_frozen_camera(direction: Vector2, delta: float) -> void:
	if direction.is_zero_approx(): return
	receive_camera_pan = (receive_camera_pan+page.camera_pan_delta(direction,delta,3.5)).limit_length(4.0)
	follow_camera()

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

func queue_receive() -> bool:
	if not active or not reception_drill_active(): return false
	var focus := page.get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return false
	if receive_elapsed == 0.0: receive_queued = true
	return true

func play_receive_pose(delta: float, review_offset := Vector3.INF, pose_offset := 0.0) -> void:
	var actor: Node3D = page.preview_player
	if receive_entry_pose.is_empty():
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
	face_ball()
	actor.animator.play("custom_preview/clip",0)
	actor.animator.seek(maxf(0.0,page.ball_preview.contact_time+pose_offset),true)
	actor.animator.pause()
	step_into_receive(delta,review_offset)
	var ball = page.ball_preview
	var struck: bool = ball.recovery.has("spread")
	var outgoing: Vector3 = ball.recovery.velocity if struck else ball.practice_pass_velocity(ball.practice_platform_center(),0.0)
	var incoming: Vector3 = ball.incoming
	if struck: incoming += ball.feed_info.acceleration*float(ball.recovery.time)
	var power := PassDrive.effort(incoming,outgoing)
	PassDrive.apply(actor.skeleton,footwork.author,outgoing,power,pose_offset,struck,incoming)
	if receive_entry_elapsed < 0.10:
		receive_entry_elapsed += delta
		blend_pose_from(receive_entry_pose,smoothstep(0.0,0.10,receive_entry_elapsed))
		if not reach_step.is_zero_approx() or reach_height != 0.0:
			ball.update_practice_platform()

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
	if receive_exit_elapsed >= 0.17:
		receive_exit_pose.clear()
		return
	blend_pose_from(receive_exit_pose,smoothstep(0.0,0.17,receive_exit_elapsed))

func clear_receive_transition() -> void:
	receive_entry_pose.clear()
	receive_exit_pose.clear()

func reset_reach() -> void:
	if reach_step.is_zero_approx() and reach_height == 0.0: return
	reach_step = Vector3.ZERO
	reach_height = 0.0
	reach_side_lunge = false
	reach_forward_lunge = false
	reach_back = false
	reach_tier = 1
	reach_travel = Vector3.ZERO
	reach_progress = 0.0
	high_adjustment = Vector3.ZERO
	if reception_drill_active(): page.ball_preview.practice_reach_center = Vector3.INF

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
		var directional_cpu: bool = not active and review_offset.is_finite() and not page.reception_review.active
		if directional_cpu:
			tier = arrows.selected_distance
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
		reach_side_lunge = tier == 2 and absf(local.x) > absf(local.z)*1.4
		reach_forward_lunge = local.z > absf(local.x)*1.4
		if directional_cpu and tier == 2 and arrows.selected in [2,3,7,8]:
			reach_side_lunge = true
			reach_forward_lunge = false
		var horizontal := Vector3(offset.x,0.0,offset.z)
		var step_limit := 0.68 if reach_side_lunge else (0.75 if tier == 2 else 0.46)
		var stride := 1.0 if reach_back and tier == 2 else 0.78
		reach_step = horizontal.limit_length(step_limit)*stride
		reach_lead = "l" if local.x >= 0.0 else "r"
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
	face_ball()
	var local_step := actor.basis.inverse()*reach_step
	var local_travel := actor.basis.inverse()*reach_travel
	pose_receive_step(actor,local_step,local_travel,amount)
	ball.update_practice_platform()

func pose_receive_step(actor: Node3D, step: Vector3, travel: Vector3, weight: float) -> void:
	var rig: Skeleton3D = actor.skeleton
	var author: RefCounted = footwork.author
	var pose: Array = []
	for bone in rig.get_bone_count(): pose.append(rig.get_bone_pose(bone))
	var scale_: float = rig.global_basis.get_scale().y
	var back := clampf(-step.z/0.32,0.0,1.0)
	var side_lean := clampf(step.x/0.32,-1.0,1.0)
	var shoulder_side := 1.0 if reach_lead == "l" else -1.0
	author.rotate_world(pose,"spine_02",Vector3.BACK,-side_lean*0.27*weight)
	var side_receive := not reach_back and absf(step.x)>0.10 and absf(step.x)>absf(step.z)*0.55
	if side_receive:
		# Open the shoulders toward the ball and lower the opposite shoulder.
		var roll := 0.56 if reach_tier == 2 else 0.43
		if reach_side_lunge:
			# Roll the ribcage down with the trailing shoulder.
			author.rotate_world(pose,"spine_02",Vector3.BACK,side_lean*0.24*weight)
			author.rotate_world(pose,"spine_02",Vector3.RIGHT,0.10*weight)
			roll -= 0.15
		author.rotate_world(pose,"spine_03",Vector3.BACK,side_lean*roll*weight)
		author.rotate_world(pose,"spine_02",Vector3.UP,side_lean*0.08*weight)
		author.rotate_world(pose,"spine_03",Vector3.UP,side_lean*0.19*weight)
	author.rotate_world(pose,"spine_02",Vector3.RIGHT,-back*0.14*weight)
	author.rotate_world(pose,"spine_03",Vector3.UP,shoulder_side*back*(0.18 if reach_tier == 2 else 0.31)*weight)
	var deep := reach_tier == 2 and reach_height < 0.20
	var high := reach_height >= 0.20
	var pelvis := rig.find_bone("pelvis")
	var hips: Transform3D = pose[pelvis]
	if high or (reach_back and reach_tier == 2):
		# Clear the incoming path by turning the ribcage, leaving the joined platform out in front.
		var turn := (shoulder_side*0.50 if high else side_lean*0.12)*weight
		author.rotate_world(pose,"spine_02",Vector3.UP,turn*0.55)
		author.rotate_world(pose,"spine_03",Vector3.UP,turn*0.45)
		if high:
			author.rotate_world(pose,"spine_02",Vector3.RIGHT,-0.19*weight)
			author.rotate_world(pose,"spine_02",Vector3.BACK,shoulder_side*0.15*weight)
			author.rotate_world(pose,"spine_03",Vector3.BACK,-shoulder_side*0.07*weight)
	if deep:
		author.rotate_world(pose,"spine_02",Vector3.BACK,-side_lean*0.12*weight)
		author.rotate_world(pose,"spine_02",Vector3.RIGHT,0.14*weight)
	if deep or reach_side_lunge:
		var parent := rig.get_bone_parent(pelvis)
		var drop := (0.22 if reach_forward_lunge else 0.36)*weight
		if reach_side_lunge:
			# Set pelvis height from the planted trailing ankle and a nearly straight knee.
			var trail := "r" if reach_lead == "l" else "l"
			var hip: Vector3 = author.point(pose,"thigh_"+trail)
			var knee: Vector3 = author.point(pose,"calf_"+trail)
			var foot: Vector3 = author.point(pose,"foot_"+trail)
			var leg_length := hip.distance_to(knee)+knee.distance_to(foot)
			var planted_offset := hip-(foot-travel/scale_)
			var horizontal := Vector2(planted_offset.x,planted_offset.z).length()
			var extension := lerpf(hip.distance_to(foot),leg_length*0.998,weight)
			var hip_height := sqrt(maxf(0.0,extension*extension-horizontal*horizontal))
			drop = clampf(planted_offset.y-hip_height,-0.13*weight,0.43*weight)
		pose[pelvis].origin -= author.world_pose(pose,parent).basis.inverse()*Vector3.UP*drop
	if reach_forward_lunge and reach_tier == 1 and not high:
		var parent := rig.get_bone_parent(pelvis)
		pose[pelvis].origin -= author.world_pose(pose,parent).basis.inverse()*Vector3.UP*0.11*weight
		author.rotate_world(pose,"spine_02",Vector3.RIGHT,0.12*weight)
	var leg_pose := pose.duplicate()
	leg_pose[pelvis] = hips
	for side in ["l","r"]:
		var foot_name: String = "foot_"+side
		var foot: Transform3D = author.world_pose(leg_pose,rig.find_bone(foot_name))
		var target := foot.origin-travel/scale_
		if side == reach_lead:
			var extension := 0.98 if reach_side_lunge or reach_forward_lunge else (1.18 if deep else 1.32)
			target += step/scale_*weight*extension+Vector3.UP*sin(PI*reach_progress)*0.08
			if reach_side_lunge: target.z += 0.28*weight
			if reach_forward_lunge: target.z += (0.12 if reach_tier == 2 else 0.07)*weight
		var pole: Vector3 = author.point(leg_pose,"calf_"+side)-author.point(leg_pose,"thigh_"+side)
		if reach_side_lunge and side == reach_lead:
			# Load the knee over the lead foot as the other leg extends.
			var hip: Vector3 = author.point(pose,"thigh_"+side)
			var knee_over_foot := target+Vector3(shoulder_side*0.08,0.28,0.32)-hip
			pole = pole.normalized().lerp(knee_over_foot.normalized(),weight)
		author.limb(pose,"thigh_"+side,"calf_"+side,foot_name,target,pole)
		author.set_world_basis(pose,foot_name,foot.basis)
	if high or reach_tier == 2 or side_receive or reach_forward_lunge or reach_back:
		var extension := 0.17 if reach_forward_lunge else (0.10 if reach_side_lunge else 0.05)
		if reach_back: extension = 0.22
		var arms := Vector3(step.x,0.0,step.z).normalized()*extension*weight
		if reach_forward_lunge: arms.y = 0.07*weight
		var center: Vector3 = (author.point(pose,"hand_l")+author.point(pose,"hand_r"))*0.5
		if high:
			var shoulder_height: float = (author.point(pose,"upperarm_l").y+author.point(pose,"upperarm_r").y)*0.5
			arms.y = maxf(0.0,shoulder_height-center.y-0.02)*weight
			var intercept: Dictionary = page.ball_preview.practice_shoulder_intercept()
			if not intercept.is_empty():
				var contact: Vector3 = intercept.point
				if not active and not page.reception_review.active and actor.get_node("DirectionArrows").selected != 0:
					contact = page.ball_preview.aim_point
				var ball_point := rig.global_transform.affine_inverse()*contact
				var wrist_target := ball_point+Vector3(0.0,-0.24,0.22)
				arms = arms.lerp(wrist_target-center,weight*0.85)
		elif not reach_back:
			arms.x -= side_lean*0.05*weight
		PlatformPose.connect_arms(pose,author,center+arms,smoothstep(0.0,0.68,weight))
	rig.set_bone_pose_position(pelvis,pose[pelvis].origin)
	for bone in rig.get_bone_count():
		rig.set_bone_pose_rotation(bone,pose[bone].basis.get_rotation_quaternion())



func move_cpu_toward(travel: Vector3, delta: float) -> void:
	var actor: Node3D = page.preview_player
	var forward := Vector3(0,0,4)-actor.position
	forward.y = 0.0
	forward = forward.normalized()
	var distance := travel.length()
	var direction := travel.normalized()*minf(1.0,distance/0.27)
	sprint_requested = distance>0.85
	move_player(Vector2(direction.dot(forward.cross(Vector3.UP)),direction.dot(forward)),delta)

func move_player(direction: Vector2, delta: float) -> void:
	var actor: Node3D = page.preview_player
	var session = page.get_node("/root/StorySession")
	var forward := (Vector3(0,0,4)-actor.position).normalized()
	forward.y = 0
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP)
	var drill := reception_drill_active()
	var travel := right*direction.x+forward*direction.y
	var step_direction := direction
	if drill:
		face_ball()
		var facing := actor.basis.z.normalized()
		step_direction = Vector2(travel.dot(facing.cross(Vector3.UP)),travel.dot(facing))
	if exhausted and stamina>=25: exhausted = false
	var quick_pace := sprint_requested and direction.length()>0.1 and not exhausted and stamina>0
	sprinting = quick_pace and step_direction.y>0.3
	var step_rate := QUICK_STEP_RATE if quick_pace else 1.0
	var speed := 4.5 if sprinting else 1.65*step_rate
	var velocity := travel*speed
	var before := actor.position
	var movement := velocity*delta
	var lateral := absf(step_direction.x)>0.3
	var shuffle_step: bool = not sprinting and (side_steps.active or lateral)
	side_steps.sampled = false
	if shuffle_step:
		if lateral: shuffle_heading = travel.normalized()
		var distance_: float = side_steps.advance(step_direction,delta*step_rate)*actor.scale.y
		movement = shuffle_heading*distance_
	else: side_steps.active = false
	actor.position.x = clampf(actor.position.x+movement.x,-4,4)
	actor.position.z = clampf(actor.position.z+movement.z,-4.5,2.5)
	if drill:
		face_ball()
	else:
		actor.rotation.y = atan2(forward.x,forward.z)
		session.pass_start = Vector2(actor.position.x,actor.position.z)
	var now_moving := actor.position.distance_to(before)>0.00001
	sprinting = sprinting and now_moving
	if quick_pace and now_moving:
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
	var model_yaw := atan2(local_velocity.x,local_velocity.z) if sprinting and not drill else 0.0
	actor.model.rotation.y = lerp_angle(actor.model.rotation.y,model_yaw,1-exp(-delta*16))
	side_weight = move_toward(side_weight,1.0 if shuffle_step else 0.0,delta*9)
	if shuffle_step or sprinting:
		footwork.weight = 0
	else:
		footwork.step(local_velocity/(1.65*step_rate) if moving else Vector3.ZERO,delta,step_rate)
	if side_weight>0: side_steps.apply_pose(side_weight)
	if active: follow_camera()

func face_ball() -> void:
	if not reception_drill_active(): return
	var actor: Node3D = page.preview_player
	var ball: Node3D = page.ball_preview
	var target: Vector3 = ball.global_position if ball.ball.visible else ball.source_ball.global_position
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
