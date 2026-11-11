extends "res://scripts/attack_drill.gd"

const Underhand = preload("res://scripts/underhand_serve.gd")
const BACK_LEFT := Vector3(2.5,0.04,-3.3)
const BACK_RIGHT := Vector3(-2.5,0.04,-3.3)
const MIN_SET_APEX := 3.55
const QUICK_SET_APEX := 4.1

var server: Node3D
var serve_demo: Node3D
var serve_contact := 0.0
var serve_to_partner := false
var partner_receiving := false
var user_player: Node3D
var teammate: Node3D
var manual_set_requested := false
var carried_jump_lift := 0.0
var swing_to_set_pose: Array[Quaternion] = []
var swing_to_set_started := 0.0
var swing_to_set_duration := 0.14
var second_ball_spike_held := false
var player_second_ball_attack := false
var cpu_second_ball_attack := false
var cpu_commits_to_spike := false
var manual_set_apex := SET_APEX
var requested_set_apex := SET_APEX
var teammate_set_apex := SET_APEX
var manual_set_target := Vector3.INF
var set_preview := ImmediateMesh.new()
var set_preview_material := StandardMaterial3D.new()

func setup_demo() -> void:
	user_player = setter
	teammate = receiver
	server = make_demo_player("Server",Color("d9874e"))
	serve_demo = Underhand.new()
	add_child(serve_demo)
	serve_demo.configure(server,Vector3(0.0,0.04,13.9),PI)
	serve_demo.target = Vector3(BACK_LEFT.x,Flight.FLOOR,-4.15)
	serve_demo.aim_ring.hide()
	serve_demo.path_preview.hide()
	var preview := MeshInstance3D.new()
	preview.mesh = set_preview
	preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	set_preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	set_preview_material.albedo_color = Color("57dfff")
	add_child(preview)
	reset_feed()

func make_demo_player(role: String, color: Color) -> Node3D:
	var actor := Player.new()
	actor.name = role
	actor.team_color = color
	add_child(actor)
	actor.get_node("DirectionArrows").hide()
	actor.animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	return actor

func reset_feed() -> void:
	if is_instance_valid(serve_demo):
		partner_receiving = serve_to_partner
		setter = teammate if partner_receiving else user_player
		receiver = user_player if partner_receiving else teammate
		bump.setter = setter
		cpu_set.setter = receiver
	super.reset_feed()
	if not is_instance_valid(serve_demo): return
	release_approach_jump()
	set_preview.clear_surfaces()
	manual_set_requested = false
	carried_jump_lift = 0.0
	swing_to_set_pose.clear()
	second_ball_spike_held = false
	player_second_ball_attack = false
	cpu_second_ball_attack = false
	cpu_commits_to_spike = randf() < 0.35
	manual_set_target = Vector3.INF
	setter.position = BACK_RIGHT if partner_receiving else BACK_LEFT
	setter.rotation.y = 0.0
	receiver.position = BACK_LEFT if partner_receiving else BACK_RIGHT
	receiver.rotation.y = 0.0
	bump.destination = Vector2(receiver.position.x,3.65 if partner_receiving else -1.9)
	serve_demo.target = Vector3(setter.position.x,Flight.FLOOR,-4.15)
	bump.height = 6.8 if partner_receiving else 4.6
	serve_demo.reset()
	serve_demo.ball.show()
	serve_demo.serve()
	serve_origin = serve_demo.preview_origin
	serve_velocity = serve_demo.launch_velocity(serve_origin,serve_demo.flight_duration(serve_origin))
	serve_contact = descending_time(serve_origin,serve_velocity,1.15)
	bump.green_forearm_allowance = 0.62
	ball.hide()
	region.hide()
	approach_rings.hide()
	status.text = "Serve to teammate" if partner_receiving else "Serve to you"
	if partner_receiving:
		rally_set_target = Vector3(setter.position.x,PIN.y,Net.NET_Z-RALLY_SET_NET_CLEARANCE)
		update_manual_set_target()

func receive_cue_time() -> float:
	return super.receive_cue_time() if bump.hand_setting else serve_contact

func set_pass_aim(point: Vector3) -> void:
	if partner_receiving: return
	bump.destination = Vector2(clampf(point.x,-4.35,4.35),clampf(point.z,-4.8,3.45))

func can_adjust_manual_set() -> bool:
	return partner_receiving and stage in [Stage.SERVE,Stage.PASS] and not is_finite(cpu_set.release_time)

func aim_manual_set(point: Vector3) -> void:
	if not can_adjust_manual_set(): return
	manual_set_target = point
	update_manual_set_target()

func adjust_manual_set_height(amount: float) -> void:
	if not can_adjust_manual_set(): return
	requested_set_apex = clampf(requested_set_apex+amount,MIN_SET_APEX,7.5)

func request_manual_set(technique: int) -> void:
	var cpu_fake := cpu_second_ball_attack
	if (player_second_ball_attack or cpu_fake) and stage == Stage.SET:
		var actor := setter
		var lift := maxf(0.0,actor.position.y-BACK_LEFT.y)
		if technique == 0 and jump.active and lift > 0.03:
			carried_jump_lift = lift
			var rig: Skeleton3D = actor.skeleton
			for bone in rig.get_bone_count():
				swing_to_set_pose.append(rig.get_bone_pose_rotation(bone))
			swing_to_set_started = clock
			technique = 2
		jump.active = false
		if carried_jump_lift == 0.0: actor.position.y = BACK_LEFT.y
		actor.play_action("idle",0.0)
		setter = receiver
		receiver = actor
		stage = Stage.PASS
		player_second_ball_attack = false
		cpu_second_ball_attack = false
		approach_jump_queued = false
		approach_pressed_at = -INF
		swing_started = -INF
	if (not partner_receiving and not cpu_fake) or stage != Stage.PASS or is_finite(cpu_set.touch_time): return
	manual_set_requested = true
	second_ball_spike_held = false
	active_cpu_set_style = technique
	status.text = ["Hands set queued","Forearm set queued","Jump set queued"][technique]
	cpu_contact_time = maxf(clock-stage_start,descending_time(pass_origin,pass_motion,cpu_set_contact_height()))
	cpu_contact_point = flight_point(pass_origin,pass_motion,cpu_contact_time)
	if not swing_to_set_pose.is_empty():
		swing_to_set_duration = clampf(cpu_contact_time-(clock-stage_start)+0.055,0.075,0.16)
	var incoming := (pass_origin-cpu_contact_point).slide(Vector3.UP).normalized()
	cpu_stand = Court.clamp_setter(Vector3(cpu_contact_point.x,CPU_HOME.y,cpu_contact_point.z)-incoming*HandPose.CONTACT_FORWARD*receiver.scale.z,ATTACK_FRONT_LIMIT)
	if partner_receiving: update_manual_set_target()
	else:
		draw_set_preview(cpu_contact_point,cpu_set_launch(cpu_contact_point))
		if is_instance_valid(rally_set_call):
			show_teammate_set_call("Setting Zone %d")

func set_requested() -> bool:
	return not partner_receiving or manual_set_requested

func blend_swing_to_set() -> void:
	if swing_to_set_pose.is_empty(): return
	var age := clock-swing_to_set_started
	if age >= swing_to_set_duration or stage not in [Stage.PASS,Stage.SET]:
		swing_to_set_pose.clear()
		return
	var weight := smoothstep(0.0,swing_to_set_duration,age)
	var rig: Skeleton3D = receiver.skeleton
	for bone in rig.get_bone_count():
		var set_rotation := rig.get_bone_pose_rotation(bone)
		rig.set_bone_pose_rotation(bone,swing_to_set_pose[bone].slerp(set_rotation,weight))

func cpu_jump_set_lift() -> float:
	return carried_jump_lift if carried_jump_lift > 0.0 else super.cpu_jump_set_lift()

func cpu_jump_set_rise(lead: float) -> float:
	if carried_jump_lift > 0.0: return carried_jump_lift
	if active_cpu_set_style == 3: return cpu_jump_set_lift()*(1.0-smoothstep(0.0,0.34,lead))
	return super.cpu_jump_set_rise(lead)

func cpu_set_apex() -> float:
	return manual_set_apex if partner_receiving else teammate_set_apex

func can_adjust_teammate_set() -> bool:
	return not partner_receiving and (stage == Stage.PASS or (stage == Stage.SET and cpu_second_ball_attack)) and not is_finite(cpu_set.release_time)

func adjust_teammate_set_height(amount: float) -> void:
	if not can_adjust_teammate_set(): return
	teammate_set_apex = clampf(teammate_set_apex+amount,MIN_SET_APEX,7.5)
	var origin: Vector3 = cpu_set.platform_center() if is_finite(cpu_set.touch_time) else cpu_contact_point
	draw_set_preview(origin,cpu_set_launch(origin))
	show_teammate_set_call("If set, Zone %d" if active_cpu_set_style == 3 else "Set to Zone %d")

func show_teammate_set_call(format: String) -> void:
	if not is_instance_valid(rally_set_call): return
	rally_set_call.text = (format % ((rally_set_index+1)*10))+"  |  %.1f m" % teammate_set_apex
	rally_set_call.show()

func update_manual_set_target() -> void:
	if manual_set_target.is_finite():
		rally_set_target.x = clampf(manual_set_target.x,-5.5,5.5)
	var origin := Vector3(receiver.position.x,cpu_set_contact_height(),receiver.position.z+0.45)
	if stage == Stage.PASS:
		origin = cpu_set.platform_center() if is_finite(cpu_set.touch_time) else cpu_contact_point
	var launch := cpu_set_launch(origin)
	draw_set_preview(origin,launch)
	if is_instance_valid(rally_set_call):
		rally_set_call.text = "Set height %.1f m" % manual_set_apex
		rally_set_call.show()

func draw_set_preview(origin: Vector3, launch: Vector3) -> void:
	set_preview.clear_surfaces()
	var duration := Flight.landing_time(origin,launch)
	set_preview.surface_begin(Mesh.PRIMITIVE_LINES,set_preview_material)
	for segment in 28:
		set_preview.surface_add_vertex(flight_point(origin,launch,duration*segment/28.0))
		set_preview.surface_add_vertex(flight_point(origin,launch,duration*(segment+0.55)/28.0))
	set_preview.surface_end()

func cpu_set_launch(origin: Vector3) -> Vector3:
	var apex := cpu_set_apex()
	var contact := descending_time(origin,Vector3.UP*sqrt(2.0*Flight.GRAVITY*(apex-origin.y)),RALLY_SET_CONTACT_HEIGHT)
	var floor_time := Flight.landing_time(origin,Vector3.UP*sqrt(2.0*Flight.GRAVITY*(apex-origin.y)))
	var target_depth := Net.NET_Z-RALLY_SET_NET_CLEARANCE
	if partner_receiving and manual_set_target.is_finite():
		target_depth = clampf(manual_set_target.z,-4.75,target_depth)
	var safe_floor := Net.NET_Z-0.16
	rally_set_target.z = minf(target_depth,lerpf(origin.z,safe_floor,contact/floor_time))
	region.position = rally_set_target
	return set_toward_pin(origin,rally_set_target,apex,RALLY_SET_CONTACT_HEIGHT)

func call_rally_set(passer: Vector3) -> void:
	var candidates: Array[int] = []
	for zone in RALLY_SET_ZONES:
		if absf(rally_zone_x(zone)-passer.x) <= APPROACH_RADII[1]:
			candidates.append(zone)
	if candidates.is_empty():
		candidates.append(clampi(roundi(3.0-passer.x*RALLY_SET_ZONES/9.0),0,RALLY_SET_ZONES-1))
	if candidates.size() > 1: candidates.erase(rally_set_index)
	rally_set_index = candidates.pick_random()
	rally_set_target = Vector3(rally_zone_x(rally_set_index),PIN.y,Net.NET_Z-RALLY_SET_NET_CLEARANCE)
	if partner_receiving: update_manual_set_target()
	else: draw_set_preview(cpu_contact_point,cpu_set_launch(cpu_contact_point))
	region.show()
	if not partner_receiving:
		show_teammate_set_call("If set, Zone %d" if active_cpu_set_style == 3 else "Set to Zone %d")

func cpu_set_move_speed(distance: float) -> float:
	return 5.0 if distance > 0.85 else 3.2

func try_quick_attack(delta: float) -> void:
	if not manual_set_requested or manual_set_apex > QUICK_SET_APEX: return
	var launch := cpu_set_launch(cpu_contact_point)
	var contact := descending_time(cpu_contact_point,launch,RALLY_SET_CONTACT_HEIGHT)
	var release_delay: float = 0.0 if active_cpu_set_style == 1 else cpu_set.hand_release_delay()
	var time_to_hit := cpu_contact_time+release_delay+contact-(clock-stage_start)
	var plant_time := 0.20
	var jump_height := 1.12
	var rise := jump.flight_duration(jump_height,true)*0.46
	if time_to_hit > plant_time+rise+delta: return
	var intercept := flight_point(cpu_contact_point,launch,contact)
	var toward := (intercept-setter.position).slide(Vector3.UP)
	if toward.length() > APPROACH_RADII[0]+REGION_RADIUS: return
	approach_steps = 2
	approach_intercept = intercept
	approach_expected_hit_at = clock+time_to_hit
	approach_pressed_at = clock
	approach_jump_queued = false
	var direction := toward.normalized()
	begin_attack_jump(Vector2(-direction.x,direction.z),maxf(0.12,time_to_hit-rise),jump_height)

func try_second_ball_attack() -> void:
	var cpu_attempt := not partner_receiving and active_cpu_set_style == 3
	if manual_set_requested or stage != Stage.PASS or is_finite(cpu_set.touch_time): return
	if not second_ball_spike_held and not cpu_attempt: return
	var height_time := descending_time(pass_origin,pass_motion,3.35)
	if height_time-(clock-stage_start) > 1.05: return
	var passer := setter
	setter = receiver
	receiver = passer
	stage = Stage.SET
	var intercept := Vector3.INF
	for tier in APPROACH_RADII.size():
		intercept = find_approach_intercept(true,tier)
		if intercept.is_finite():
			approach_steps = tier+2
			break
	if not intercept.is_finite():
		receiver = setter
		setter = passer
		stage = Stage.PASS
		return
	player_second_ball_attack = not cpu_attempt
	cpu_second_ball_attack = cpu_attempt
	if cpu_attempt: aim_swing(Vector3(randf_range(-2.75,2.75),Flight.FLOOR,10.2))
	approach_pressed_at = clock
	approach_released_at = INF
	approach_set_touched_at = clock
	approach_jump_queued = true
	pin_arrival = height_time
	flight_end = Flight.landing_time(pass_origin,pass_motion)
	if not cpu_attempt:
		set_preview.clear_surfaces()
		region.hide()
	status.text = "Second-ball attack"

func advances_receiver_animation() -> bool:
	return not cpu_second_ball_attack

func tick_demo(delta: float, controls: RefCounted) -> void:
	if can_adjust_manual_set():
		manual_set_apex = move_toward(manual_set_apex,requested_set_apex,9.0*delta)
		update_manual_set_target()
	if stage == Stage.SERVE and not is_finite(serve_demo.contact_clock):
		if not partner_receiving: bump.update_aim()
		serve_demo.step(delta)
		if not is_finite(serve_demo.contact_clock): return
		serve_origin = serve_demo.origin
		serve_velocity = serve_demo.velocity
		serve_demo.ball.hide()
		ball.show()
	serve_demo.step(delta)
	try_second_ball_attack()
	if cpu_second_ball_attack and not cpu_commits_to_spike and stage == Stage.SET and is_finite(swing_started):
		if clock-swing_started >= 0.14 or clock >= approach_expected_hit_at-0.055:
			request_manual_set(0)
	if player_second_ball_attack or cpu_second_ball_attack:
		if cpu_second_ball_attack:
			controls.read_pace_input()
			var movement: Vector2 = controls.movement_input()
			if movement.y > 0.05:
				user_player.rotation.y = rotate_toward(user_player.rotation.y,atan2(-movement.x,movement.y),delta*8.0)
			controls.move_player(movement,delta,false,ball.position,1.0,0.0,false,jump.front_limit,0.0,0.0,true)
			approach_from_sprint = false
		trace_input = Vector2.ZERO
		if stage == Stage.SET and approach_jump_queued: time_approach_plant(delta)
		step_jump(delta)
		step(delta)
		if cpu_second_ball_attack and stage in [Stage.HIT,Stage.MISS]:
			set_preview.clear_surfaces()
			if is_instance_valid(rally_set_call): rally_set_call.hide()
		return
	if partner_receiving:
		if stage == Stage.SERVE and clock-stage_start >= serve_contact-0.20 and not is_finite(bump.pressed_at):
			queue_set()
		if stage in [Stage.PASS,Stage.SET] and not jump.active:
			var run_target := rally_set_target-Vector3.BACK*(0.55 if manual_set_apex <= QUICK_SET_APEX else 1.95)
			var travel := (run_target-setter.position).slide(Vector3.UP)
			approach_from_sprint = travel.length() > 0.65
			if approach_from_sprint:
				var yaw := atan2(travel.x,travel.z)
				setter.rotation.y = rotate_toward(setter.rotation.y,yaw,12.0*delta)
				setter.play_action("run")
			else:
				setter.play_action("idle")
			setter.position += travel.limit_length((5.0 if approach_from_sprint else 3.2)*delta)
			setter.animator.advance(delta)
			approach_space_held = true
			if stage == Stage.PASS and manual_set_apex <= QUICK_SET_APEX:
				try_quick_attack(delta)
			else:
				trace_input = queued_approach_input(delta)
		step_jump(delta)
		var previous_stage := stage
		step(delta)
		blend_swing_to_set()
		if previous_stage == Stage.PASS and stage != Stage.PASS: set_preview.clear_surfaces()
		if previous_stage == Stage.PASS and stage == Stage.SET:
			aim_swing(Vector3(randf_range(-3.35,3.35),Flight.FLOOR,randf_range(8.5,11.8)))
		if stage == Stage.PASS and not manual_set_requested: status.text = "E / I to set  |  Hold Space to spike"
		return
	controls.read_pace_input()
	trace_input = controls.movement_input()
	if stage in [Stage.PASS,Stage.SET]:
		trace_input = queued_approach_input(delta,controls.sprint_requested)
	approach_from_sprint = false
	trace_sprint = controls.sprint_requested
	if not jump.active and not setter_is_diving():
		var after_pass := stage in [Stage.PASS,Stage.SET]
		if after_pass and trace_input.y > 0.05:
			var heading := atan2(-trace_input.x,trace_input.y)
			setter.rotation.y = rotate_toward(setter.rotation.y,heading,delta*8.0)
		controls.move_player(trace_input,delta,false,ball.position,setter_movement_scale(),court_facing_weight(),not after_pass,jump.front_limit,0.0,0.0,after_pass)
		approach_from_sprint = after_pass and controls.sprinting
	step_jump(delta)
	var previous_stage := stage
	step(delta)
	blend_swing_to_set()
	if previous_stage == Stage.PASS and stage == Stage.SET:
		draw_set_preview(pass_origin,pass_motion)
	elif stage in [Stage.HIT,Stage.MISS,Stage.SHANK] and set_preview.get_surface_count() > 0:
		set_preview.clear_surfaces()
