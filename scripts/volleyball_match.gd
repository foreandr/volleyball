extends Node3D

const Player = preload("res://scripts/volleyball_player.gd")
const Bump = preload("res://scripts/bump_setting.gd")
const Attack = preload("res://scripts/match_attack.gd")
const Block = preload("res://scripts/match_block.gd")
const Jump = preload("res://scripts/setter_jump.gd")
const Flight = preload("res://scripts/pass_flight.gd")
const Net = preload("res://scripts/net_collision.gd")
const BallPreview = preload("res://scripts/animation_ball_preview.gd")
const Court = preload("res://scripts/preview_court.gd")
const SERVES := [
	preload("res://scripts/underhand_serve.gd"),
	preload("res://scripts/standing_float_serve.gd"),
	preload("res://scripts/jump_float_serve.gd"),
	preload("res://scripts/spin_serve.gd"),
]
const SERVICE_START := [-6.40,-6.40,-7.4,-8.15]
const WIN_SCORE := 7
const RECOVERY_TIME := 0.32
enum Phase { READY, LIVE, DEAD, FINISHED }

var phase := Phase.READY
var frames: Array[Node3D] = []
var players: Array[Node3D] = []
var platforms: Array[MeshInstance3D] = []
var attackers: Array[Node3D] = []
var set_jumps: Array[RefCounted] = []
var blocks := {}
var human: Node3D
var saved_transform: Transform3D
var saved_callback: int
var saved_arrows: bool
var score_label: Label
var info: Label
var ball: MeshInstance3D
var aim_ring: MeshInstance3D
var player_label: Label3D
var trajectory: ImmediateMesh
var trajectory_node: MeshInstance3D
var trajectory_style := StandardMaterial3D.new()
var preview_origin := Vector3.INF
var preview_velocity := Vector3.INF
var player_blocks := false
var match_clock := 0.0
var last_input_at := -INF
var last_input_technique := -1
var serve: Node3D
var touch_audio: AudioStreamPlayer
var floor_audio: AudioStreamPlayer
var serve_style := 0
var score := [0,0]
var server_slot := [0,0]
var service_team := 0
var rallies := 0
var ready_age := 0.0
var dead_age := 0.0
var bounce_origin := Vector3.ZERO
var bounce_velocity := Vector3.ZERO
var bounce_end := 0.0
var spectator := false
var key_labels: Array[Label3D] = []
var key_until := [0.0,0.0,0.0,0.0]
var defender_assignment := [-1,-1]
var cpu_dump := false
var jump_set_started := [false,false,false,false]
var recoveries := {}
var animated := [false,false,false,false]
var elapsed := 0.0
var origin := Vector3.ZERO
var velocity := Vector3.ZERO
var duration := 0.0
var net_hit := {}
var spin := 0.0
var flight_kind := ""
var flight_number := 0
var receiving_team := 1
var possession_team := -1
var touches := 0
var last_player := -1
var last_was_block := false
var expected_hitter := -1
var space_held := false
var requested := -1
var request_age := -INF
var cpu_choice := -1
var cpu_technique := 0
var aim_point := Vector3.INF
var pass_height := 4.6
var serve_pending := false
var crossed_net := false
var next_touch_cue := INF
var touched_tape := false
var stroke := ""

func configure(actor: Node3D, board: Label, status: Label) -> void:
	human = actor
	saved_transform = actor.transform
	saved_callback = actor.animator.callback_mode_process
	saved_arrows = actor.get_node("DirectionArrows").visible
	score_label = board
	info = status
	for side in 2:
		var frame := Node3D.new()
		if side == 1:
			frame.position.z = 2.0*Net.NET_Z
			frame.rotation.y = PI
		add_child(frame)
		frames.append(frame)
		for slot in 2:
			var avatar := actor if side == 0 and slot == 0 else Player.new()
			if avatar != actor:
				avatar.name = "Teammate" if side == 0 else "Opponent%d" % (slot+1)
				avatar.team_color = Color("287fda") if side == 0 else Color("d9874e")
				frame.add_child(avatar)
			avatar.animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			avatar.get_node("DirectionArrows").hide()
			players.append(avatar)
			avatar.play_action("forearm")
			var bump := Bump.new()
			frame.add_child(bump)
			bump.configure(avatar,avatar.animator.get_animation("custom_forearm/clip"))
			bump.green_start = 0.01
			bump.green_end = 0.55
			bump.green_forearm_allowance = 0.30
			bump.green_hand_allowance = 0.38
			bump.hide()
			platforms.append(bump)
			set_jumps.append(Jump.new())
		var driver := Attack.new()
		frame.add_child(driver)
		var hidden_status := Label.new()
		hidden_status.hide()
		add_child(hidden_status)
		driver.configure_for_match(players[side*2],hidden_status)
		driver.struck.connect(on_spike)
		attackers.append(driver)
	ball = MeshInstance3D.new()
	ball.mesh = BallPreview.make_ball()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	ball.material_override = material
	add_child(ball)
	aim_ring = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.31
	ring.outer_radius = 0.35
	aim_ring.mesh = ring
	var ring_style := StandardMaterial3D.new()
	ring_style.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_style.albedo_color = Color("62d9f0")
	aim_ring.material_override = ring_style
	add_child(aim_ring)
	player_label = Label3D.new()
	player_label.text = "YOU"
	player_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	player_label.font_size = 44
	player_label.outline_size = 12
	player_label.modulate = Color("86f2ff")
	player_label.pixel_size = 0.007
	player_label.no_depth_test = true
	add_child(player_label)
	for index in players.size():
		var key := Label3D.new()
		key.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		key.font_size = 42
		key.outline_size = 13
		key.pixel_size = 0.0065
		key.no_depth_test = true
		key.modulate = Color("ffd278")
		add_child(key)
		key_labels.append(key)
	trajectory = ImmediateMesh.new()
	trajectory_node = MeshInstance3D.new()
	trajectory_node.mesh = trajectory
	trajectory_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	trajectory_style.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trajectory_style.albedo_color = Color("62d9f0")
	add_child(trajectory_node)
	touch_audio = Net.contact_sound()
	add_child(touch_audio)
	floor_audio = AudioStreamPlayer.new()
	floor_audio.stream = AudioStreamWAV.load_from_file("res://assets/audio/pass_contact.wav")
	floor_audio.pitch_scale = 0.78
	add_child(floor_audio)
	begin_point()

func stop() -> void:
	human.transform = saved_transform
	human.animator.callback_mode_process = saved_callback
	human.get_node("DirectionArrows").visible = saved_arrows
	queue_free()

func team(index: int) -> int:
	return index >> 1

func is_human(index: int) -> bool:
	return index == 0 and not spectator

func set_spectator(value: bool) -> void:
	if spectator == value: return
	spectator = value
	reset_match()

func show_key(index: int, caption: String) -> void:
	key_labels[index].text = caption
	key_until[index] = match_clock+0.64

func server_index() -> int:
	return service_team*2+server_slot[service_team]

func reset_match() -> void:
	score = [0,0]
	service_team = 0
	server_slot = [0,0]
	rallies = 0
	begin_point()

func set_player_blocks(value: bool) -> void:
	player_blocks = value

func begin_point() -> void:
	last_input_at = -INF
	last_input_technique = -1
	bounce_end = 0.0
	key_until = [0.0,0.0,0.0,0.0]
	defender_assignment = [-1,-1]
	for index in players.size():
		var actor := players[index]
		actor.position = Vector3(-2.1 if index%2 == 0 else 2.1,0.04,-2.6)
		actor.rotation.y = 0.0
		actor.model.rotation.y = 0.0
		actor.play_action("idle",0.0)
		actor.animator.seek(0.0,true)
		set_jumps[index].active = false
	for driver in attackers:
		driver.enabled = false
		driver.jump.active = false
	blocks.clear()
	recoveries.clear()
	possession_team = -1
	touches = 0
	last_player = -1
	last_was_block = false
	expected_hitter = -1
	space_held = false
	reset_receives()
	phase = Phase.READY
	ready_age = 0.0
	ball.hide()
	aim_ring.hide()
	trajectory_node.hide()
	var style: int = serve_style if is_human(server_index()) else rallies%SERVES.size()
	prepare_serve(style)
	update_score()

func prepare_serve(style: int) -> void:
	if is_instance_valid(serve):
		serve.hide()
		serve.queue_free()
	var index := server_index()
	var side := team(index)
	serve = SERVES[style].new()
	frames[side].add_child(serve)
	var x := -1.6 if index%2 == 0 else 1.6
	serve.configure(players[index],Vector3(x,0.04,SERVICE_START[style]))
	serve.aim(Vector3(randf_range(-3.35,3.35),Flight.FLOOR,randf_range(9.2,12.4)) if not is_human(index) else Vector3(0.0,Flight.FLOOR,10.7))
	serve.aim_ring.visible = is_human(index)
	serve.path_preview.visible = is_human(index)
	serve_pending = false
	info.text = ("Blue serving" if side == 0 else "Orange serving") if spectator else ["Your serve · Space","Teammate serving","Opponents serving"][0 if index == 0 else (1 if side == 0 else 2)]

func set_serve_style(style: int) -> void:
	serve_style = style
	if phase == Phase.READY and is_human(server_index()) and not serve_pending: prepare_serve(style)

func set_aim(point: Vector3) -> void:
	if spectator: return
	aim_point = point
	if phase == Phase.READY and is_human(server_index()) and not serve_pending and point.z > Net.NET_Z:
		serve.aim(Vector3(clampf(point.x,-7.0,7.0),Flight.FLOOR,clampf(point.z,4.4,16.0)))
	if phase != Phase.LIVE: return
	var driver := attackers[0]
	if driver.enabled and driver.setter == human and point.z > Net.NET_Z:
		driver.swing_aim = frames[0].to_local(point)

func change_arc(amount: float) -> void:
	if phase == Phase.READY and is_human(server_index()) and not serve_pending: serve.change_arc(amount)
	else: pass_height = clampf(pass_height+amount,3.45,7.0)

func input_space(pressed: bool) -> void:
	if spectator: return
	space_held = pressed
	if phase == Phase.FINISHED: return
	if phase == Phase.READY and server_index() == 0 and pressed:
		start_serve()
		return
	var driver := attackers[0]
	if driver.enabled and driver.setter == human and driver.stage == driver.Stage.SET:
		if pressed:
			driver.queue_jump(Vector2.ZERO)
			show_key(0,"Space")
		else: driver.release_approach_jump()
	elif pressed and player_blocks and phase == Phase.LIVE and receiving_team == 0 and human.position.z >= 2.25:
		if flight_kind in ["spike","dump"] or (flight_kind == "pass" and possession_team == 1 and touches == 1): start_block(0)
	elif pressed and player_blocks and phase == Phase.LIVE and expected_hitter >= 2 and human.position.z >= 2.25:
		start_block(0)

func click_set() -> void:
	if phase == Phase.LIVE and receiving_team == 0 and possession_team == 0 and touches == 1 and last_player != 0:
		input_receive(1)

func input_receive(technique: int) -> void:
	if spectator: return
	if phase != Phase.LIVE: return
	var bump := platforms[0]
	if is_finite(bump.pressed_at):
		if is_finite(bump.pose_started_at): return
		if requested != technique: bump.reset()
	last_input_at = match_clock
	last_input_technique = technique
	requested = technique
	request_age = elapsed
	next_touch_cue = INF
	if receiving_team == 0 and not blocks.has(0):
		queue_receive(0,technique)

func start_serve() -> void:
	if serve_pending: return
	serve_pending = true
	show_key(server_index(),"Space")
	serve.serve()

func update_score() -> void:
	score_label.text = ("BLUE  %d  –  %d  ORANGE" if spectator else "YOU  %d  –  %d  CPU") % [score[0],score[1]]

func award(side: int, reason: String) -> void:
	if phase != Phase.LIVE: return
	score[side] += 1
	if side != service_team:
		service_team = side
		if rallies > 0: server_slot[side] = 1-int(server_slot[side])
	rallies += 1
	dead_age = 0.0
	for driver in attackers:
		if driver.enabled and driver.stage == driver.Stage.SET:
			driver.stage = driver.Stage.MISS
	for index in players.size():
		if not owns_action(index) and not recoveries.has(index): begin_recovery(index)
	update_score()
	if score[side] >= WIN_SCORE and score[side]-score[1-side] >= 2:
		phase = Phase.FINISHED
		var winner := ("Blue wins" if side == 0 else "Orange wins") if spectator else ("You win!" if side == 0 else "CPU wins")
		info.text = winner+"\nUse Reset Match to play again"
	else:
		phase = Phase.DEAD
		var winner := ("Blue point" if side == 0 else "Orange point") if spectator else ("Your point" if side == 0 else "CPU point")
		info.text = winner+" · "+reason

func reset_receives() -> void:
	for bump in platforms:
		bump.reset()
		bump.hide()
	cpu_choice = -1
	cpu_dump = false
	jump_set_started = [false,false,false,false]
	next_touch_cue = INF
	requested = -1
	request_age = -INF

func launch(point: Vector3, motion: Vector3, kind: String, from: int, spin_rate := 0.0, hitter := -1, set_pin := Vector3.ZERO) -> void:
	flight_number += 1
	origin = point
	velocity = motion
	elapsed = 0.0
	spin = spin_rate
	flight_kind = kind
	expected_hitter = hitter
	crossed_net = false
	touched_tape = false
	duration = Flight.landing_time(origin,velocity)
	net_hit = Net.first_hit(flight_point,0.0,duration)
	last_player = from
	receiving_team = team(from)
	reset_receives()
	if kind == "serve":
		receiving_team = 1-team(from)
		net_hit = serve.net_hit.duplicate()
		if not net_hit.is_empty():
			net_hit.release_point = serve.to_global(net_hit.release_point)
			net_hit.point = serve.to_global(net_hit.point)
			net_hit.velocity = serve.global_basis*net_hit.velocity
			if team(from) == 1: net_hit.side = -float(net_hit.side)
		duration = serve.planned_duration
	if kind in ["spike","free","dump"]: receiving_team = 1-team(from)
	if not spectator and kind == "pass" and from == 1 and receiving_team == 0 and match_clock-last_input_at <= 0.35:
		requested = last_input_technique
		request_age = 0.0
		queue_receive(0,requested)
	if hitter >= 0:
		var side := team(hitter)
		var frame := frames[side]
		var shot := choose_shot(hitter)
		attackers[side].start_set(players[hitter],frame.to_local(origin),frame.global_basis.inverse()*velocity,frame.to_local(set_pin),shot,0.0,is_human(hitter) and space_held)
	ball.global_position = point
	ball.show()

func flight_point(time: float) -> Vector3:
	if flight_kind == "serve" and is_instance_valid(serve): return serve.to_global(serve.flight_point(time))
	return origin+velocity*time+Vector3.DOWN*0.5*Flight.GRAVITY*time*time

func path_point(time: float) -> Vector3:
	if not net_hit.is_empty() and time >= float(net_hit.time): return Net.after_hit(net_hit,time)
	return flight_point(time)

func flight_end() -> float:
	return duration if net_hit.is_empty() else float(net_hit.end_time)

func toward_incoming(index: int, point: Vector3) -> Vector3:
	var local := frames[team(index)].global_basis.inverse()*(path_point(maxf(0.0,elapsed-0.10))-point)
	return local.slide(Vector3.UP).normalized()

func choose_shot(index: int) -> Vector3:
	if is_human(index) and aim_point.is_finite() and aim_point.z > Net.NET_Z:
		return Vector3(clampf(aim_point.x,-6.5,6.5),Flight.FLOOR,clampf(aim_point.z,4.5,15.0))
	var opposite := players[(1-team(index))*2].position.x
	return Vector3(clampf(opposite+randf_range(-1.8,1.8),-3.9,3.9),Flight.FLOOR,randf_range(8.0,12.3))

func can_touch(index: int, block := false) -> bool:
	if phase != Phase.LIVE: return false
	var side := team(index)
	if side != possession_team:
		possession_team = side
		touches = 0
	elif index == last_player and not last_was_block:
		award(1-side,"Double contact")
		return false
	if touches == 3:
		award(1-side,"Four contacts")
		return false
	touches += 1
	last_was_block = block
	return true

func on_spike(actor: Node3D, point: Vector3, motion: Vector3, spin_rate: float) -> void:
	var index := players.find(actor)
	if index < 0 or not can_touch(index): return
	play_touch()
	stroke = "Spike"
	launch(point,motion,"spike",index,spin_rate)

func play_touch() -> void:
	if not StorySession.attack_ball_audio_muted: touch_audio.play()

func set_pin_for(index: int) -> Vector3:
	var frame := frames[team(index)]
	if is_human(index) and aim_point.is_finite():
		var point := frame.to_local(aim_point)
		if point.z <= Net.NET_Z: return Vector3(clampf(point.x,-4.6,4.6),0.065,clampf(point.z,-1.6,3.62))
	var hitter := players[index^1]
	var x := clampf(hitter.position.x,-3.6,3.6)
	return Vector3(x,0.065,3.20)

func queue_receive(index: int, technique: int) -> void:
	var bump := platforms[index]
	if is_finite(bump.pressed_at): return
	bump.hand_setting = technique != 0
	bump.quick_hand_receive = technique == 1 and (team(index) != possession_team or touches == 0)
	bump.forearm_setting = team(index) == possession_team and touches == 1
	bump.green_hand_allowance = 0.50 if is_human(index) and bump.forearm_setting else 0.38
	bump.green_forearm_allowance = 0.48 if is_human(index) else 0.30
	bump.green_start = 0.0 if is_human(index) else 0.01
	bump.green_end = 0.78 if is_human(index) else 0.55
	bump.defensive_hand_dig = flight_kind in ["spike","dump"] and technique == 1
	bump.allow_auto_dive = flight_kind not in ["spike","dump"]
	bump.queue_bump(elapsed)
	show_key(index,["Q","E","F"][technique])

func aim_receive(index: int) -> void:
	var bump := platforms[index]
	var side := team(index)
	var frame := frames[side]
	var teammate := players[index^1]
	var destination := teammate.position
	destination.z = clampf(destination.z+0.65,-2.7,2.85)
	if is_human(index) and aim_point.is_finite(): destination = frame.to_local(aim_point)
	elif side == possession_team and (touches >= 2 or (cpu_dump and index == cpu_choice)): destination = choose_shot(index)
	bump.destination = Vector2(clampf(destination.x,-6.5,6.5),clampf(destination.z,-6.0,13.0))
	bump.height = pass_height if is_human(index) else (5.05 if side == possession_team and touches == 1 else 4.55)

func receive_contact(index: int, world_point: Vector3, world_motion: Vector3, technique: int) -> void:
	if frames[team(index)].to_local(world_point).z > Net.NET_Z+0.07: return
	if not can_touch(index): return
	var side := team(index)
	var frame := frames[side]
	var point := frame.to_local(world_point)
	var bump := platforms[index]
	stroke = ["Forearm","Hands","Jump set"][technique]
	begin_recovery(index)
	play_touch()
	if touches == 2 and not (cpu_dump and index == cpu_choice) and (bump.destination.y < 4.0 or (is_human(index) and technique != 0)):
		var pin := set_pin_for(index)
		var apex := maxf(4.15,bump.height)
		if is_human(index):
			var error := Bump.Accuracy.sample_offset(Bump.Accuracy.spread(0.0,velocity.length(),spin,StorySession.setting_skill,true))
			pin += error.slide(Vector3.UP)
			apex = maxf(3.55,apex+error.y)
		var driver := attackers[side]
		var motion: Vector3 = driver.set_toward_pin(point,pin,apex,3.38)
		launch(world_point,frame.global_basis*motion,"set",index,1.0,index^1,frame.to_global(pin))
		return
	var crossing := (Net.NET_Z-world_point.z)/world_motion.z if absf(world_motion.z)>0.001 else -1.0
	var over := crossing > 0.0 and crossing < Flight.landing_time(world_point,world_motion)
	launch(world_point,world_motion,("dump" if touches == 2 and technique != 0 else "free") if over else "pass",index)

func owns_action(index: int, allow_serve_move := false) -> bool:
	if blocks.has(index) or set_jumps[index].active: return true
	var actor := players[index]
	if serve.player == actor and not serve.moved_after_contact and serve.swing_time < serve.recovery_end():
		if not allow_serve_move or not serve.can_run_after_contact(): return true
	var driver := attackers[team(index)]
	return driver.enabled and driver.setter == actor and (driver.jump.active or driver.stage == driver.Stage.HIT)

func begin_recovery(index: int) -> void:
	var actor := players[index]
	var rig: Skeleton3D = actor.skeleton
	var pose: Array[Transform3D] = []
	for bone in rig.get_bone_count(): pose.append(rig.get_bone_pose(bone))
	recoveries[index] = {"started":match_clock,"pose":pose}
	actor.animator.speed_scale = 1.0
	actor.play_action("idle",0.0)

func advance_recoveries(delta: float) -> void:
	for index in recoveries.keys():
		var recovery: Dictionary = recoveries[index]
		var age := match_clock-float(recovery.started)
		if age >= RECOVERY_TIME:
			recoveries.erase(index)
			continue
		if owns_action(index): continue
		var actor := players[index]
		var rig: Skeleton3D = actor.skeleton
		actor.animator.advance(delta)
		animated[index] = true
		var weight := 1.0-smoothstep(0.0,RECOVERY_TIME,age)
		for bone in rig.get_bone_count():
			var pose: Transform3D = recovery.pose[bone]
			var idle := rig.get_bone_pose(bone)
			rig.set_bone_pose_position(bone,idle.origin.lerp(pose.origin,weight))
			var rotation := pose.basis.orthonormalized().get_rotation_quaternion().normalized()
			rig.set_bone_pose_rotation(bone,idle.basis.orthonormalized().get_rotation_quaternion().normalized().slerp(rotation,weight))

func advance_set_jumps(delta: float) -> void:
	for index in players.size():
		var jump := set_jumps[index]
		if jump.active:
			jump.step(players[index],delta,Vector2.ZERO)
			animated[index] = true

func advance_idle_players(delta: float) -> void:
	for index in players.size():
		if animated[index] or owns_action(index): continue
		var actor := players[index]
		actor.animator.speed_scale = 1.0
		actor.play_action("idle")
		actor.animator.advance(delta)

func advance_attackers(delta: float) -> void:
	for driver in attackers:
		if not driver.enabled: continue
		var index := players.find(driver.setter)
		driver.tick_attack(delta)
		if not driver.enabled and index >= 0: begin_recovery(index)

func settle_point(delta: float) -> void:
	if not serve.moved_after_contact and serve.swing_time < serve.recovery_end(): serve.step(delta)
	advance_set_jumps(delta)
	advance_attackers(delta)
	tick_blocks(delta,elapsed)
	advance_recoveries(delta)
	advance_idle_players(delta)

func move_cpu(index: int, target: Vector3, delta: float, speed := 5.3) -> void:
	if recoveries.has(index) or owns_action(index,true): return
	if serve.player == players[index]:
		if not serve.can_run_after_contact(): return
		serve.moved_after_contact = true
	var actor := players[index]
	var local := frames[team(index)].to_local(target)
	var offset := (local-actor.position).slide(Vector3.UP)
	var move := offset.limit_length(delta*speed)
	actor.position = Court.clamp_setter(actor.position+move,3.43)
	var moving := offset.length() > 0.16 and speed > 2.2
	actor.animator.speed_scale = 1.0
	actor.play_action("run" if moving else "idle",0.11 if moving else 0.065)
	actor.animator.advance(delta)
	animated[index] = true
	var incoming := toward_incoming(index,ball.global_position)
	if incoming.z > -0.5 and not incoming.is_zero_approx():
		actor.rotation.y = rotate_toward(actor.rotation.y,atan2(incoming.x,incoming.z),delta*10.0)

func arrival(height: float) -> float:
	var start := elapsed
	var end := flight_end()
	for i in range(1,26):
		var next := lerpf(elapsed,end,i/25.0)
		if path_point(start).y >= height and path_point(next).y <= height:
			for refine in 8:
				var middle := (start+next)*0.5
				if path_point(middle).y > height: start = middle
				else: next = middle
			return next
		start = next
	return end

func select_receiver() -> void:
	var side := receiving_team
	var point := path_point(arrival(1.10))
	var first := side*2
	if side == possession_team and touches > 0:
		cpu_choice = last_player^1
	elif flight_kind in ["spike","dump"] and defender_assignment[side] >= 0:
		cpu_choice = int(defender_assignment[side])^1
	elif point.distance_squared_to(players[first].global_position) <= point.distance_squared_to(players[first+1].global_position):
		cpu_choice = first
	else: cpu_choice = first+1
	if not spectator and side == 0 and cpu_choice == 0 and side != possession_team and not is_finite(platforms[0].pressed_at):
		if point.slide(Vector3.UP).distance_to(human.global_position.slide(Vector3.UP)) > 1.65: cpu_choice = 1
	cpu_technique = (rallies+touches+cpu_choice)%3
	if flight_kind in ["serve","spike","dump"]: cpu_technique = 0 if (rallies+cpu_choice)%4 != 2 else 1
	if flight_kind in ["spike","dump"]: cpu_technique = 1 if (rallies+cpu_choice)%5 == 2 else 0
	if not is_human(cpu_choice) and side == possession_team and touches == 1 and flight_kind == "pass":
		var hand_point := frames[side].to_local(path_point(arrival(2.05)))
		cpu_dump = hand_point.z >= 2.60 and hand_point.z <= 3.62 and (rallies+cpu_choice)%4 == 0
		if cpu_dump: cpu_technique = 1
	if cpu_technique != 0 and not overhead_available(cpu_choice,cpu_technique):
		cpu_technique = 0
		cpu_dump = false

func overhead_available(index: int, technique: int) -> bool:
	var height := 2.35 if technique == 2 else 1.92
	var at := arrival(height)
	var point := frames[team(index)].to_local(path_point(at))
	return point.z <= Net.NET_Z+0.05 and point.y >= height-0.12 and at < flight_end()-0.03

func tick_receive(delta: float, previous: float) -> void:
	if expected_hitter >= 0 and flight_kind == "set":
		var hitter := expected_hitter
		var driver := attackers[team(hitter)]
		if not is_human(hitter) and driver.enabled and not driver.jump.active:
			if not driver.approach_space_held:
				driver.queue_jump(Vector2.ZERO)
				show_key(hitter,"Space")
			var pin: Vector3 = driver.rally_set_target
			pin.z -= 1.25
			move_cpu(hitter,frames[team(hitter)].to_global(pin),delta)
		if not is_human(hitter) or driver.jump.active or not is_finite(platforms[0].pressed_at): return
	if cpu_choice < 0: select_receiver()
	var index := cpu_choice
	if not spectator and receiving_team == 0 and is_finite(platforms[0].pressed_at) and not blocks.has(0): index = 0
	if index < 0 or blocks.has(index) or recoveries.has(index): return
	var frame := frames[team(index)]
	var bump := platforms[index]
	var technique := requested if is_human(index) else cpu_technique
	if is_human(index) and technique < 0: return
	if is_human(index) and not is_finite(bump.pressed_at) and elapsed-request_age < 0.44: queue_receive(0,technique)
	var height: float = [1.10,1.92,2.35][technique]
	if not is_finite(next_touch_cue): next_touch_cue = arrival(height)
	var cue := next_touch_cue
	var catch_point := path_point(cue)
	var actor := players[index]
	if not is_human(index):
		if technique != 0 and not is_finite(bump.pressed_at) and not overhead_available(index,technique):
			cpu_technique = 0
			cpu_dump = false
			next_touch_cue = INF
			return
		var face := toward_incoming(index,catch_point)
		if face.is_zero_approx(): face = Vector3.BACK
		var offset := 0.52 if technique == 0 else 0.28
		if not set_jumps[index].active and not bump.low_save.active:
			var target := catch_point-frame.global_basis*face*offset
			var lead := cue-elapsed
			var speed := lerpf(1.7,5.3,smoothstep(0.035,0.24,lead))
			if is_finite(bump.pressed_at): speed = minf(speed,2.0)
			move_cpu(index,target,delta,speed)
		if elapsed >= cue-(0.34 if technique == 2 else 0.24): queue_receive(index,technique)
	if not is_finite(bump.pressed_at): return
	if technique == 2 and not jump_set_started[index] and cue-elapsed <= 0.29:
		jump_set_started[index] = true
		set_jumps[index].front_limit = 3.35
		set_jumps[index].begin_set_jump(actor,clampf(cue-elapsed-0.13,0.055,0.16))
	var end := flight_end()
	var path := func(t: float) -> Vector3: return frame.to_local(path_point(t))
	var motion := (path_point(minf(end,elapsed+0.003))-path_point(maxf(0.0,elapsed-0.003)))/0.006
	bump.setter_jumping = set_jumps[index].active
	aim_receive(index)
	if is_human(index):
		bump.show()
		bump.update_aim()
	var timing_cue := cue if is_human(index) and technique == 0 else INF
	bump.update_attempt(elapsed,previous,end,path,frame.global_basis.inverse()*motion,delta,timing_cue,spin)
	animated[index] = true
	if is_finite(bump.touch_time):
		if bump.hand_setting and not is_finite(bump.release_time):
			ball.global_position = frame.to_global(bump.platform_center())
			return
		var touch: Vector3 = bump.release_point if bump.hand_setting else bump.touch
		if not is_human(index) and technique != 0 and bump.touch.y < actor.position.y+1.45:
			bump.reset()
			cpu_technique = 0
			cpu_dump = false
			next_touch_cue = INF
			return
		receive_contact(index,frame.to_global(touch),frame.global_basis*bump.outgoing,technique)
	elif not is_human(index) and not (flight_kind in ["spike","dump"] and technique == 1) and previous <= cue and elapsed >= cue and catch_point.y > 0.55:
		var gap := (actor.global_position-catch_point).slide(Vector3.UP).length()
		var reachable_height := technique == 0 or catch_point.y >= actor.global_position.y+1.49
		if gap <= (0.66 if technique == 0 else 0.46) and cue < end-0.025 and reachable_height:
			if technique == 0: bump.apply_pose(bump.contact_frame,0.82)
			else: Bump.HandPose.apply(actor,catch_point,0.86)
			var target := {"position":bump.destination,"fit":"height","height":bump.height}
			var result := Bump.Accuracy.pass_velocity(frame.to_local(catch_point),target,45.0,Vector2(0.25,0.22))
			receive_contact(index,catch_point,frame.global_basis*result,technique)
func start_block(index: int) -> void:
	if blocks.has(index) or set_jumps[index].active: return
	if recoveries.has(index): return
	var actor := players[index]
	if serve.player == actor and not serve.can_run_after_contact(): return
	if actor.position.z < 2.25 or actor.position.z > 3.45: return
	var block := Block.new()
	block.begin(actor)
	blocks[index] = block
	show_key(index,"Space")

func tick_blocks(delta: float, previous: float) -> void:
	var incoming_spike := phase == Phase.LIVE and flight_kind in ["spike","dump"]
	for index in blocks.keys():
		var block = blocks[index]
		if not block.step(delta,ball.global_position):
			blocks.erase(index)
			continue
		animated[index] = true
		if not incoming_spike or team(index) != receiving_team: continue
		var before := path_point(previous)
		var after := ball.global_position
		for sample in 7:
			var fraction := sample/6.0
			var point := before.lerp(after,fraction)
			for hand in block.hands.size():
				var center: Vector3 = block.previous_hands[hand].lerp(block.hands[hand],fraction)
				var gap := point.distance_to(center)
				if gap > 0.27 or center.y < Net.NET_TOP or absf(point.z-Net.NET_Z) > 0.9: continue
				if not can_touch(index,true): return
				var backward := frames[team(index)].global_basis.z.normalized()
				var power := 1.0-smoothstep(0.08,0.26,gap)
				var speed := velocity.length()
				var rebound := backward*lerpf(-speed*0.19,speed*0.53,power)+Vector3.UP*lerpf(3.2,-4.5,power)
				rebound.x += (point.x-center.x)*10.0
				stroke = "Block"
				play_touch()
				var over := rebound.dot(backward) > 0.0
				launch(point,rebound,"free" if over else "block",index)
				return

func position_attack(delta: float) -> void:
	if flight_kind != "pass" or possession_team != receiving_team or touches != 1: return
	var passer := last_player
	if is_human(passer) or blocks.has(passer) or set_jumps[passer].active: return
	var pin := set_pin_for(passer^1)
	pin.z -= 1.60
	move_cpu(passer,frames[receiving_team].to_global(pin),delta,5.8)

func dig_cover_x(frame: Node3D, attacker: Vector3, blocker: Vector3, depth: float, digger_x: float) -> float:
	var attack := frame.to_local(attacker)
	var wall := frame.to_local(blocker)
	var ratio := (depth-attack.z)/minf(-0.20,wall.z-attack.z)
	var shadow := attack.x+(wall.x-attack.x)*ratio
	var clearance := lerpf(0.85,1.35,clampf((ratio-1.0)/3.0,0.0,1.0))
	var crosscourt := -signf(attack.x) if absf(attack.x) > 0.4 else (-1.0 if digger_x < shadow else 1.0)
	var preferred := shadow+crosscourt*clearance
	if absf(preferred) > 4.05: preferred = shadow-crosscourt*clearance
	return clampf(preferred,-4.05,4.05)

func position_defense(delta: float) -> void:
	if flight_kind not in ["serve","pass","set","free"]: return
	var hitter_side := receiving_team
	var defense_side := 1-hitter_side
	var frame := frames[defense_side]
	var driver := attackers[hitter_side]
	var tracking_set := flight_kind == "set" and expected_hitter >= 0
	var threat := frames[hitter_side].to_global(driver.rally_set_target) if tracking_set else path_point(arrival(2.0))
	var x := frame.to_local(threat).x
	var first := defense_side*2
	var near: int = defender_assignment[defense_side]
	if defense_side == 0 and not spectator:
		near = 0 if player_blocks else 1
	elif near < 0:
		near = first if absf(players[first].position.x-x) < absf(players[first+1].position.x-x) else first+1
	defender_assignment[defense_side] = near
	if not is_human(near) and not blocks.has(near):
		var target := frame.to_global(Vector3(clampf(x,-4.1,4.1),0.04,3.35))
		move_cpu(near,target,delta,7.3 if players[near].position.z < 2.7 else 6.2)
		players[near].rotation.y = rotate_toward(players[near].rotation.y,0.0,delta*9.0)
		var attack_ready: bool = tracking_set and is_finite(driver.swing_started) and driver.clock-driver.swing_started >= 0.16
		var dump_ready := cpu_dump and flight_kind == "pass" and is_finite(next_touch_cue) and next_touch_cue-elapsed <= 0.29
		if absf(players[near].position.x-x) < 0.66 and (attack_ready or dump_ready): start_block(near)
	var deep := near^1
	if not is_human(deep) and not blocks.has(deep) and not set_jumps[deep].active:
		var depth := -2.75
		var wall := players[near].global_position
		if players[near].position.z < 2.10: wall = frame.to_global(Vector3(clampf(x,-4.1,4.1),0.04,3.35))
		var cover := dig_cover_x(frame,threat,wall,depth,players[deep].position.x) if tracking_set else -x*0.48
		move_cpu(deep,frame.to_global(Vector3(cover,0.04,depth)),delta)

func update_player_guide() -> void:
	player_label.global_position = human.global_position+Vector3.UP*2.17
	player_label.visible = not spectator
	for index in players.size():
		key_labels[index].global_position = players[index].global_position+Vector3.UP*(2.43 if is_human(index) else 2.18)
		key_labels[index].visible = match_clock < key_until[index]
	var show_guide := not spectator and (phase == Phase.LIVE or (phase == Phase.READY and server_index() != 0))
	trajectory_node.visible = show_guide
	aim_ring.visible = show_guide
	if not show_guide: return
	var bump := platforms[0]
	aim_receive(0)
	var start: Vector3 = frames[0].to_global(bump.ready_contact())
	var target := Vector3(bump.destination.x,Flight.FLOOR,bump.destination.y)
	var launch: Vector3
	if expected_hitter == 0 and flight_kind == "set":
		var driver := attackers[0]
		var contact_at: float = driver.descending_time(origin,velocity,3.38)
		start = flight_point(clampf(contact_at,0.0,duration))
		target = driver.swing_aim
		var travel := target-start
		var air_time := maxf(0.1,travel.slide(Vector3.UP).length()/24.0)
		launch = travel/air_time+Vector3.UP*0.5*Flight.GRAVITY*air_time
	elif receiving_team == 0 and possession_team == 0 and touches == 1 and last_player == 1:
		target = set_pin_for(0)
		launch = attackers[0].set_toward_pin(start,target,pass_height,3.38)
	else:
		launch = Flight.target_velocity(start,{"position":Vector2(target.x,target.z),"fit":"height","height":pass_height},45.0)
	aim_ring.global_position = Vector3(target.x,0.066,target.z)
	if start.distance_squared_to(preview_origin) < 0.0004 and launch.distance_squared_to(preview_velocity) < 0.0004: return
	preview_origin = start
	preview_velocity = launch
	var end := Flight.landing_time(start,launch)
	trajectory.clear_surfaces()
	trajectory.surface_begin(Mesh.PRIMITIVE_LINES,trajectory_style)
	for segment in 36:
		for fraction in [0.0,0.50]:
			var time: float = end*(segment+fraction)/36.0
			trajectory.surface_add_vertex(to_local(start+launch*time+Vector3.DOWN*0.5*Flight.GRAVITY*time*time))
	trajectory.surface_end()

func check_floor(previous: float) -> void:
	if not crossed_net:
		var before := path_point(previous)
		var after := ball.global_position
		if (before.z-Net.NET_Z)*(after.z-Net.NET_Z) < 0.0:
			crossed_net = true
			var crossing := before.lerp(after,inverse_lerp(before.z,after.z,Net.NET_Z))
			if absf(crossing.x) > Net.NET_HALF_WIDTH or crossing.y < Net.NET_TOP:
				award(1-team(last_player),"Outside the crossing space")
				return
	if elapsed < flight_end(): return
	if not StorySession.attack_ball_audio_muted: floor_audio.play()
	var point := ball.global_position
	bounce_origin = point
	var before_impact := path_point(maxf(0.0,flight_end()-0.015))
	var impact_velocity := (point-before_impact)/0.015
	bounce_velocity = impact_velocity.slide(Vector3.UP)*0.37
	bounce_velocity.y = clampf(absf(impact_velocity.y)*0.55,1.85,6.35)
	bounce_end = Flight.landing_time(bounce_origin,bounce_velocity)
	var in_bounds := absf(point.x) <= 4.53 and point.z >= -5.03 and point.z <= 13.03
	if in_bounds:
		var court_side := 0 if point.z < Net.NET_Z else 1
		award(1-court_side,"Ball down")
	else:
		award(1-team(last_player),"Out")

func tick_match(delta: float, controls: RefCounted) -> void:
	match_clock += delta
	animated = [false,false,false,false]
	update_player_guide()
	if phase in [Phase.DEAD,Phase.FINISHED]:
		dead_age += delta
		settle_point(delta)
		if bounce_end > 0.0:
			var time := minf(dead_age,bounce_end)
			ball.global_position = bounce_origin+bounce_velocity*time+Vector3.DOWN*0.5*Flight.GRAVITY*time*time
		if phase == Phase.DEAD and dead_age >= maxf(0.85,bounce_end+0.15):
			var settling := false
			for index in players.size(): settling = settling or owns_action(index)
			if not settling or dead_age >= 1.55: begin_point()
		return
	if phase == Phase.READY:
		ready_age += delta
		if not is_human(server_index()) and ready_age >= 0.65: start_serve()
		if not serve_pending: return
		serve.step(delta)
		if not is_finite(serve.contact_clock): return
		serve.external_rally = true
		serve.ball.hide()
		serve.aim_ring.hide()
		serve.path_preview.hide()
		phase = Phase.LIVE
		stroke = "Serve"
		play_touch()
		launch(serve.to_global(serve.origin),serve.global_basis*serve.velocity,"serve",server_index(),serve.reception_spin_rps())
		return
	serve.step(delta)
	var previous := elapsed
	var current_flight := flight_number
	elapsed += delta
	ball.global_position = path_point(minf(elapsed,flight_end()))
	if not touched_tape and not net_hit.is_empty() and elapsed >= float(net_hit.time):
		touched_tape = true
		if net_hit.kind == "under":
			award(1-team(last_player),"Under the net")
			return
		play_touch()
		var release: Vector3 = net_hit.release_point
		var side_after_tape := 0 if release.z < Net.NET_Z else 1
		if side_after_tape != receiving_team:
			receiving_team = side_after_tape
			reset_receives()
	if spin > 0.0 and velocity.length_squared() > 0.01:
		var axis := Vector3.UP.cross(velocity).normalized()
		if not axis.is_zero_approx(): ball.rotate(axis,TAU*spin*delta)
	var player_attacking: bool = attackers[0].enabled and attackers[0].setter == human and attackers[0].jump.active
	var serving_human: bool = serve.player == human and not serve.can_run_after_contact()
	advance_set_jumps(delta)
	advance_recoveries(delta)
	var diving: bool = platforms[0].low_save.active and not platforms[0].low_save.finished(elapsed)
	if not spectator and not blocks.has(0) and not player_attacking and not serving_human and not set_jumps[0].active and not diving and not recoveries.has(0):
		controls.read_pace_input()
		var motion: Vector2 = controls.movement_input()
		if serve.player == human and motion.length() > 0.05: serve.moved_after_contact = true
		var bump := platforms[0]
		var mobility: float = bump.movement_scale(elapsed,next_touch_cue,ball.global_position)
		if is_finite(bump.pressed_at) and (is_finite(bump.pose_started_at) or next_touch_cue-elapsed <= 0.18):
			controls.sprint_requested = false
			mobility = minf(mobility,0.45)
		animated[0] = true
		controls.move_player(motion,delta,false,ball.global_position,mobility,0.85,true,3.42,0.0,0.0,true)
	advance_attackers(delta)
	if flight_number != current_flight: return
	position_attack(delta)
	position_defense(delta)
	tick_blocks(delta,previous)
	if flight_number != current_flight or phase != Phase.LIVE: return
	tick_receive(delta,previous)
	if flight_number != current_flight or phase != Phase.LIVE: return
	advance_idle_players(delta)
	check_floor(previous)
	if phase == Phase.LIVE:
		if spectator:
			info.text = "%s | %s court" % [stroke,"Blue" if receiving_team == 0 else "Orange"]
			return
		var cue := "Opponent's ball"
		if receiving_team == 0:
			cue = "Hold Space to attack" if expected_hitter == 0 else ("Set to your teammate" if possession_team == 0 and touches == 1 and last_player == 1 else "Receive or cover")
		elif flight_kind == "set": cue = "Move up to block | Space" if player_blocks else "Teammate blocking | Cover the court"
		info.text = "%s | %s" % [stroke,cue]
