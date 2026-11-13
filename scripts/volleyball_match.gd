extends Node3D

const ReceiveAnimations = preload("res://scripts/volleyball_animations.gd")

const Trace = preload("res://scripts/setting_trace.gd")
const Replay = preload("res://scripts/match_replay.gd")
const Review = preload("res://scripts/match_review.gd")
signal review_flagged(caption: String)
const Player = preload("res://scripts/volleyball_player.gd")
const Bump = preload("res://scripts/bump_setting.gd")
const Attack = preload("res://scripts/match_attack.gd")
const Block = preload("res://scripts/match_block.gd")
const Jump = preload("res://scripts/setter_jump.gd")
const Flight = preload("res://scripts/pass_flight.gd")
const Net = preload("res://scripts/net_collision.gd")
const BallPreview = preload("res://scripts/animation_ball_preview.gd")
const Court = preload("res://scripts/preview_court.gd")
const Footwork = preload("res://scripts/directional_footwork.gd")
const CONTACT_SOUND = preload("res://assets/audio/pass_contact.wav")
const SPIKE_SOUND = preload("res://assets/audio/spike_smack.wav")
const SET_ZONES := [-3.75,-2.50,-1.25,0.0,1.25,2.50,3.75]
const SERVES := [
	preload("res://scripts/underhand_serve.gd"),
	preload("res://scripts/standing_float_serve.gd"),
	preload("res://scripts/jump_float_serve.gd"),
	preload("res://scripts/spin_serve.gd"),
]
const SERVICE_START := [-6.40,-6.40,-7.4,-8.15]
const CpuShots = preload("res://scripts/cpu_attack_shots.gd")
const CpuPolicy = preload("res://scripts/cpu_policy.gd")
const WIN_SCORE := 15
const RECOVERY_TIME := 0.32
const FAST_DIG_ELBOW_SPEED := 25.0
const FAST_DIG_ELBOW_DURATION := 0.32
const FAST_RECEIVE_HOLD := 0.28
const FAST_RECEIVE_RISE := 0.75
const SERVE_RUN_BLEND := 0.15
const PLAYER_GROUND_Y := 0.04
const CPU_HAND_RECEIVE_MAX_SPEED := 16.0
const RUSHED_RECEIVE_WINDOW := 0.35
const CPU_SPRINT_SPEED := 6.05
const CPU_SHUFFLE_SPEED_SCALE := 0.75
const HAND_DIG_REACH := 0.46
const FOREARM_DIG_REACH := 0.66
const BODY_CONTACT_SEGMENTS := [
	["pelvis","spine_02",0.15],["spine_02","neck_01",0.17],["neck_01","Head",0.105],
	["thigh_l","calf_l",0.095],["thigh_r","calf_r",0.095],["calf_l","foot_l",0.070],["calf_r","foot_r",0.070],
	["upperarm_l","lowerarm_l",0.063],["upperarm_r","lowerarm_r",0.063],
]
enum Phase { READY, LIVE, DEAD, FINISHED }

var phase := Phase.READY
var frames: Array[Node3D] = []
var players: Array[Node3D] = []
var platforms: Array[MeshInstance3D] = []
var attackers: Array[Node3D] = []
var set_jumps: Array[RefCounted] = []
var blocks := {}
var footwork: Array[RefCounted] = []
var called_pin := Vector3.ZERO
var called_pin_flight := -1
var attack_aim_flight := -1
var attack_aim_read_at := -INF
var last_called_set_x := [INF,INF]
var transition_possession := [false,false]
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
var set_audio: AudioStreamPlayer
var spike_audio: AudioStreamPlayer
var net_audio: AudioStreamPlayer
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
var bounce_start := 0.0
var dead_flight_from := INF
var spectator := false
var squat_rise_duration := 0.20
var receive_animation_labels := {}
var animation_labels: Array[Label3D] = []
var key_labels: Array[Label3D] = []
var key_until := [0.0,0.0,0.0,0.0]
var defender_assignment := [-1,-1]
var cpu_dump := false
var cpu_second_spike := false
var cpu_fake_dump := false
var second_ball_options := 0
var block_calls := [0,0]
var block_crossing_reads: Array[Dictionary] = [{},{}]
var jump_set_started := [false,false,false,false]
var recoveries := {}
var trace := Trace.new()
var block_lane_flight := [-1,-1]
var opponent_shot_reads: Array[Dictionary] = [{},{}]
var repeated_shot_landings: Array[Dictionary] = [{},{}]
var carried_shot_reads: Array[Dictionary] = [{},{}]
var completed_read_matches := 0
var cpu_policy := CpuPolicy.new()
var block_line := [true,true]
var pocket_x := [0.0,0.0]
var last_set_apex := 0.0
var animated := [false,false,false,false]
var elapsed := 0.0
var origin := Vector3.ZERO
var velocity := Vector3.ZERO
var duration := 0.0
var net_hit := {}
var spin := 0.0
var ball_spin := Vector3.ZERO
var flight_kind := ""
var flight_number := 0
var receiving_team := 1
var possession_team := -1
var serve_run_started := -INF
var serve_run_rotations := {}
var touches := 0
var last_player := -1
var last_was_block := false
var expected_hitter := -1
var kick_pressed_until := -INF
var space_held := false
var requested := -1
var request_age := -INF
var cpu_choice := -1
var cpu_technique := 0
var aim_point := Vector3.INF
var pass_height := 4.6
var attack_vertical := 45.0
var passing_skill := 25.0
var setting_skill := 40.0
var held_ball := false
var last_point := {}
var replay := Replay.new()
var next_replay_sample := 0.0
var overpass_flight := -1
var overpass_plan_flight := -1
var overpass_player := -1
var rear_chaser := -1
var backshuffle_receiver := -1
var dig_switch_at := -INF
var block_vertical := 30.0
var serve_vertical := 30.0
var live_speed := 1.0
var drill_pass_target := Vector3.INF
var drill_set_pin := Vector3.INF
var drill_force_forearm_serve_receive := false
var drill_spike_target := Vector3.INF
var drill_spike_pace := 1.0
var drill_set_apex := INF
var drill_feed_acceleration := Vector3.INF
var attack_lift_lean := 66.0
var spike_strength := 0.70
var serve_pending := false
var crossed_net := false
var next_touch_cue := INF
var touched_tape := false
var stroke := ""
var team_size := 2
var win_score := WIN_SCORE
var auto_rematch := false
var review := Review.new()
var rally_setter := -1
var rally_hitter := -1
var deep_defenders := [-1,-1]
var support_lanes := [0.0,0.0]

func configure(actor: Node3D, board: Label, status: Label, build := "", players_per_team := 2, learn_from_demo := false, mirror_blue_right := true) -> void:
	team_size = clampi(players_per_team,2,3)
	key_until.resize(team_size*2)
	jump_set_started.resize(team_size*2)
	animated.resize(team_size*2)
	trace.open(build)
	cpu_policy.demo_recording = learn_from_demo
	if not learn_from_demo: cpu_policy.load_profile()
	human = actor
	saved_transform = actor.transform
	saved_callback = actor.animator.callback_mode_process
	saved_arrows = actor.get_node("DirectionArrows").visible
	score_label = board
	info = status
	var backward_clip: Animation
	var copies := ReceiveAnimations.custom_entries()
	for i in range(copies.size()-1,-1,-1):
		if copies[i].get("source") == "d2_backward_from_d1":
			backward_clip = load(copies[i].path) as Animation
			if backward_clip != null: break
	for side in 2:
		var frame := Node3D.new()
		if side == 1:
			frame.position.z = 2.0*Net.NET_Z
			frame.rotation.y = PI
		add_child(frame)
		frames.append(frame)
		for slot in team_size:
			var avatar := actor if side == 0 and slot == 0 else Player.new()
			if avatar != actor:
				avatar.name = ("Teammate" if slot == 1 else "Teammate2") if side == 0 else "Opponent%d" % (slot+1)
				avatar.team_color = Color("287fda") if side == 0 else Color("d9874e")
				if side == 0 and slot == 1 and mirror_blue_right:
					avatar.handedness = "Left"
					avatar.mirror_animation = true
				frame.add_child(avatar)
			avatar.animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			avatar.get_node("DirectionArrows").hide()
			players.append(avatar)
			footwork.append(Footwork.new(avatar))
			avatar.play_action("forearm")
			var bump := Bump.new()
			frame.add_child(bump)
			bump.configure(avatar,avatar.animator.get_animation("custom_forearm/clip"))
			bump.set_custom_backward(backward_clip)
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
		driver.configure_for_match(players[side*team_size],hidden_status)
		driver.struck.connect(on_spike)
		driver.lift_lean_back_degrees = attack_lift_lean
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
		var animation_label := key.duplicate() as Label3D
		animation_label.modulate = Color("86f2ff")
		add_child(animation_label)
		animation_labels.append(animation_label)
	trajectory = ImmediateMesh.new()
	trajectory_node = MeshInstance3D.new()
	trajectory_node.mesh = trajectory
	trajectory_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	trajectory_style.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trajectory_style.albedo_color = Color("62d9f0")
	add_child(trajectory_node)
	route_ball_sound()
	touch_audio = make_ball_audio(CONTACT_SOUND,3.0)
	set_audio = make_ball_audio(preload("res://assets/audio/set_touch.wav"),3.5)
	spike_audio = make_ball_audio(SPIKE_SOUND,2.0)
	floor_audio = make_ball_audio(preload("res://assets/audio/ball_floor.wav"),1.5)
	net_audio = Net.contact_sound()
	add_child(net_audio)
	if learn_from_demo: reset_match()
	else: begin_point()

func stop() -> void:
	if replay.active: toggle_replay()
	human.transform = saved_transform
	human.animator.callback_mode_process = saved_callback
	human.get_node("DirectionArrows").visible = saved_arrows
	queue_free()

func team(index: int) -> int:
	return floori(float(index)/team_size)

func nearest_on_team(side: int, target: Vector3, exclude := -1, also_exclude := -1) -> int:
	var best := -1
	var best_cost := INF
	for index in range(side*team_size,(side+1)*team_size):
		if index == exclude or index == also_exclude: continue
		var cost := players[index].global_position.distance_squared_to(target)
		if blocks.has(index) or recoveries.has(index): cost += 2.0
		if cost < best_cost:
			best = index
			best_cost = cost
	return best

func setter_for_pass(passer: int) -> int:
	if team_size == 2: return passer^1
	if rally_setter >= 0 and team(rally_setter) == team(passer) and rally_setter != passer:
		return rally_setter
	return nearest_on_team(team(passer),path_point(arrival(1.92)),passer)

func hitter_for_set(setter: int) -> int:
	if team_size == 2: return setter^1
	if rally_hitter >= 0 and team(rally_hitter) == team(setter) and rally_hitter != setter:
		return rally_hitter
	var side := team(setter)
	return nearest_on_team(side,frames[side].to_global(Vector3(0.0,0.04,1.45)),setter)

func human_can_set() -> bool:
	return last_player > 0 and team(last_player) == 0 and (team_size == 2 or rally_setter == 0)

func is_human(index: int) -> bool:
	return index == 0 and not spectator

func set_spectator(value: bool) -> void:
	if spectator == value: return
	spectator = value
	carried_shot_reads = [{},{}]
	repeated_shot_landings = [{},{}]
	completed_read_matches = 0
	reset_match()

func show_key(index: int, caption: String) -> void:
	key_labels[index].text = caption
	key_until[index] = match_clock+0.64

func server_index() -> int:
	return service_team*team_size+server_slot[service_team]

func starting_lane(index: int) -> float:
	var lane: float = [-1.0,1.0,0.0][index%team_size]
	return -lane if team(index) == 0 else lane

func reset_match() -> void:
	if replay.active: toggle_replay()
	if cpu_policy.demo_recording:
		cpu_policy.load_profile()
		cpu_policy.load_demo(team_size,spectator)
		cpu_policy.demo_exploring = spectator
		completed_read_matches = cpu_policy.demo_matches
		carried_shot_reads = [{},{}]
		for side in mini(2,cpu_policy.demo_shot_history.size()):
			var history: Dictionary = cpu_policy.demo_shot_history[side]
			for zone in history:
				var sample: Array = history[zone]
				carried_shot_reads[side][int(zone)] = Vector2(float(sample[0]),float(sample[1]))
	replay.reset()
	last_point.clear()
	last_called_set_x = [INF,INF]
	block_calls = [0,0]
	opponent_shot_reads = carried_shot_reads.duplicate(true)
	second_ball_options = 0
	score = [0,0]
	service_team = 0
	server_slot = [0,0]
	rallies = 0
	begin_point()

func set_player_blocks(value: bool) -> void:
	player_blocks = value

func begin_point() -> void:
	cpu_policy.begin_point()
	review.reset()
	replay.finish_point()
	last_input_at = -INF
	kick_pressed_until = -INF
	last_input_technique = -1
	bounce_end = 0.0
	bounce_start = 0.0
	dead_flight_from = INF
	key_until.fill(0.0)
	rally_setter = -1
	rally_hitter = -1
	deep_defenders.fill(-1)
	defender_assignment = [-1,-1]
	block_lane_flight = [-1,-1]
	last_set_apex = 0.0
	for index in players.size():
		var actor := players[index]
		var slot := index%team_size
		actor.position = Vector3(2.1*starting_lane(index),0.04,0.70 if slot == 2 else -2.6)
		actor.rotation.y = 0.0
		actor.model.rotation.y = 0.0
		actor.play_action("idle",0.0)
		actor.animator.seek(0.0,true)
		set_jumps[index].active = false
		footwork[index].weight = 0.0
	for driver in attackers:
		driver.enabled = false
		driver.jump.active = false
	blocks.clear()
	recoveries.clear()
	possession_team = -1
	transition_possession = [false,false]
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
	var server := server_index()
	var style: int = serve_style if is_human(server) else cpu_policy.choose_serve(team(server))
	prepare_serve(style)
	update_score()
	trace.begin_feed({"mode":"demo_match","score":score,"server":server_index(),"spectator":spectator,"team_size":team_size})

func prepare_serve(style: int) -> void:
	serve_run_rotations.clear()
	if is_instance_valid(serve):
		serve.hide()
		serve.queue_free()
	var index := server_index()
	var side := team(index)
	serve = SERVES[style].new()
	frames[side].add_child(serve)
	var x := 1.6*starting_lane(index)
	serve.configure(players[index],Vector3(x,0.04,SERVICE_START[style]))
	if style == 3: serve.set_serve_speed(1.12)
	if serve.has_method("set_jump_height"): serve.set_jump_height(serve_vertical*0.0254)
	var aim := Vector3(0.0,Flight.FLOOR,10.7)
	if not is_human(index):
		var placement := cpu_policy.choose(side,"serve lane",[0,-1,1],0)
		aim.x = randf_range(-3.35,3.35)
		if placement != 0: aim.x = clampf(aim.x*0.35+placement*2.45,-3.35,3.35)
		aim.z = randf_range(9.2,12.4)
	serve.aim(aim)
	serve.aim_ring.visible = is_human(index)
	serve.path_preview.visible = is_human(index)
	serve_pending = false
	info.text = ("Blue serving" if side == 0 else "Orange serving") if spectator else ["Your serve · Space","Teammate serving","Opponents serving"][0 if index == 0 else (1 if side == 0 else 2)]

func set_attack_vertical(inches: float) -> void:
	attack_vertical = inches
	for driver in attackers: driver.jump.max_height = inches*0.0254+0.2032

func set_serve_vertical(inches: float) -> void:
	serve_vertical = inches
	if phase == Phase.READY and not serve_pending and serve.has_method("set_jump_height"):
		serve.set_jump_height(inches*0.0254)

func set_live_speed(percent: float) -> void:
	live_speed = clampf(percent*0.01,0.10,1.0)

func set_attack_lift_lean(degrees: float) -> void:
	attack_lift_lean = clampf(degrees,0.0,110.0)
	for driver in attackers:
		driver.lift_lean_back_degrees = attack_lift_lean

func set_spike_strength(percent: float) -> void:
	spike_strength = percent*0.01
	for driver in attackers: driver.spike_strength = spike_strength

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
	else: pass_height = clampf(pass_height+amount,2.75,8.5)

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
		if flight_kind in ["spike","dump"] or (flight_kind == "pass" and possession_team == 1 and touches == 1): start_block(0,INF,flight_kind == "pass")
	elif pressed and player_blocks and phase == Phase.LIVE and expected_hitter >= 0 and team(expected_hitter) == 1 and human.position.z >= 2.25:
		start_block(0)

func click_set() -> void:
	if phase == Phase.LIVE and receiving_team == 0 and possession_team == 0 and touches == 1 and last_player != 0:
		input_receive(1)

func can_play_forearms(index: int) -> bool:
	return players[index].position.y <= PLAYER_GROUND_Y+0.02

func input_receive(technique: int) -> void:
	if spectator or (technique == 0 and not can_play_forearms(0)): return
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
	var serving_side := team(server_index())
	if not is_human(server_index()):
		cpu_policy.used(serving_side,"serve type")
		cpu_policy.used(serving_side,"serve lane")
	show_key(server_index(),"Space")
	serve.serve()

func update_score() -> void:
	score_label.text = ("BLUE  %d  –  %d  ORANGE" if spectator else "YOU  %d  –  %d  CPU") % [score[0],score[1]]

func award(side: int, reason: String) -> void:
	if phase != Phase.LIVE: return
	score[side] += 1
	cpu_policy.finish_point(side)
	if side != service_team:
		service_team = side
		if rallies > 0: server_slot[side] = (int(server_slot[side])+1)%team_size
	rallies += 1
	dead_age = 0.0
	if bounce_end <= 0.0 and elapsed < flight_end(): dead_flight_from = elapsed
	last_point = {"reason":reason,"ball":Trace.json_value(ball.global_position),"flight":flight_kind,
		"net":net_hit.get("kind",""),"winner":side,"time":match_clock}
	trace.write("point",match_clock,last_point,true)
	for driver in attackers:
		if driver.enabled and driver.stage == driver.Stage.SET:
			driver.stage = driver.Stage.MISS
	for index in players.size():
		if not owns_action(index) and not recoveries.has(index): begin_recovery(index)
	update_score()
	if score[side] >= win_score and score[side]-score[1-side] >= 2:
		phase = Phase.FINISHED
		remember_opponent_reads()
		if cpu_policy.demo_recording:
			var error: Error = cpu_policy.save_demo(team_size,spectator,carried_shot_reads)
			trace.write("demo_learning_saved",match_clock,{"error":error},true)
			if error != OK: push_warning("Could not save Demo Match learning: "+error_string(error))
		var winner := ("Blue wins" if side == 0 else "Orange wins") if spectator else ("You win!" if side == 0 else "CPU wins")
		info.text = winner+("\nRematch starting soon" if auto_rematch and spectator else "\nUse Reset Match to play again")
	else:
		phase = Phase.DEAD
		var winner := ("Blue point" if side == 0 else "Orange point") if spectator else ("Your point" if side == 0 else "CPU point")
		info.text = winner+" · "+reason

func reset_receives() -> void:
	receive_animation_labels.clear()
	dig_switch_at = -INF
	rear_chaser = -1
	backshuffle_receiver = -1
	held_ball = false
	cpu_second_spike = false
	for bump in platforms:
		bump.reset()
		bump.knee_bend_depth = 0.0
		bump.hide()
	cpu_choice = -1
	cpu_dump = false
	cpu_fake_dump = false
	jump_set_started.fill(false)
	next_touch_cue = INF
	requested = -1
	request_age = -INF

func launch(point: Vector3, motion: Vector3, kind: String, from: int, spin_rate := 0.0, hitter := -1, set_pin := Vector3.ZERO, feed_acceleration := Vector3.INF, angular_spin := Vector3.INF) -> void:
	# A deflection changes the ball's flight immediately, even during a player's slide.
	for index in players.size():
		var save: RefCounted = platforms[index].low_save
		if save.active and not save.finished(elapsed): begin_recovery(index)
	flight_number += 1
	origin = point
	velocity = motion
	elapsed = 0.0
	ball_spin = angular_spin if angular_spin.is_finite() else Flight.spin_axis(motion,"Topspin")*spin_rate
	spin = spin_rate
	flight_kind = kind
	drill_feed_acceleration = feed_acceleration
	expected_hitter = hitter
	crossed_net = false
	touched_tape = false
	duration = Flight.landing_time(origin,velocity,flight_gravity())
	net_hit = Net.first_hit(flight_point,0.0,duration)
	last_player = from
	receiving_team = team(from)
	reset_receives()
	if kind == "serve" and not feed_acceleration.is_finite():
		receiving_team = 1-team(from)
		net_hit = serve.net_hit.duplicate()
		if not net_hit.is_empty():
			net_hit.release_point = serve.to_global(net_hit.release_point)
			net_hit.point = serve.to_global(net_hit.point)
			net_hit.velocity = serve.global_basis*net_hit.velocity
			if team(from) == 1: net_hit.side = -float(net_hit.side)
		duration = serve.planned_duration
	if kind in ["spike","free","dump"]: receiving_team = 1-team(from)
	if last_was_block and kind in ["block","free"]:
		receiving_team = 0 if path_point(flight_end()).z < Net.NET_Z else 1
	if team_size == 3 and kind == "pass" and touches == 1 and possession_team == receiving_team:
		rally_setter = nearest_on_team(receiving_team,path_point(arrival(1.92)),from)
		rally_hitter = -1
		rally_hitter = hitter_for_set(rally_setter)
	if not spectator and kind == "pass" and human_can_set() and receiving_team == 0 and match_clock-last_input_at <= 0.35:
		requested = last_input_technique
		request_age = 0.0
		queue_receive(0,requested)
	if hitter >= 0:
		var side := team(hitter)
		var frame := frames[side]
		var shot := frame.to_local(drill_spike_target) if drill_spike_target.is_finite() else choose_shot(hitter)
		if drill_spike_target.is_finite():
			attackers[side].spike_strength = drill_spike_pace
		else: set_cpu_swing_power(hitter)
		attackers[side].start_set(players[hitter],frame.to_local(origin),frame.global_basis.inverse()*velocity,frame.to_local(set_pin),shot,0.0,is_human(hitter) and space_held)
	ball.global_position = point
	ball.show()

func advance_ball_spin(delta: float) -> void:
	if not ball_spin.is_zero_approx():
		ball.global_rotate(ball_spin.normalized(),TAU*ball_spin.length()*delta)

func flight_gravity() -> float:
	if drill_feed_acceleration.is_finite(): return -drill_feed_acceleration.y
	return Flight.spike_gravity(spin) if flight_kind == "spike" else Flight.GRAVITY

func flight_point(time: float) -> Vector3:
	if flight_kind == "serve" and not drill_feed_acceleration.is_finite() and is_instance_valid(serve): return serve.to_global(serve.flight_point(time))
	var acceleration := drill_feed_acceleration if drill_feed_acceleration.is_finite() else Vector3.DOWN*flight_gravity()
	return origin+velocity*time+acceleration*0.5*time*time

func path_point(time: float) -> Vector3:
	if not net_hit.is_empty() and time >= float(net_hit.time): return Net.after_hit(net_hit,time)
	return flight_point(time)

func flight_end() -> float:
	return duration if net_hit.is_empty() else float(net_hit.end_time)

func toward_incoming(index: int, point: Vector3) -> Vector3:
	var local := frames[team(index)].global_basis.inverse()*(path_point(maxf(0.0,elapsed-0.10))-point)
	return local.slide(Vector3.UP).normalized()

func choose_shot(index: int, contact := Vector3.INF, block_at := Vector3.INF, previous_shot := Vector3.INF) -> Vector3:
	if is_human(index) and aim_point.is_finite() and aim_point.z > Net.NET_Z:
		return Vector3(clampf(aim_point.x,-6.5,6.5),Flight.FLOOR,clampf(aim_point.z,4.5,15.0))
	var side := team(index)
	var frame := frames[side]
	var defending := 1-side
	var blocker: int = defender_assignment[defending]
	var defender := (blocker^1) if team_size == 2 and blocker >= 0 else defending*team_size
	if defender == blocker: defender += 1
	var backcourt := frame.to_local(players[defender].global_position)
	if not contact.is_finite():
		return Vector3(clampf(-backcourt.x,-3.8,3.8),Flight.FLOOR,10.7)
	var best := Vector3(0.0,Flight.FLOOR,10.7)
	var best_score := -INF
	var depth_bias := cpu_policy.choose(side,"attack depth",[0,-1,1],0) if not is_human(index) else 0
	var lanes: Array[float] = [-4.02,-2.55,0.0,2.55,4.02]
	var line_x := clampf(contact.x,-4.02,4.02)
	if absf(contact.x) > 2.4: lanes.append(line_x)
	for x in lanes:
		for depth in [5.2,6.55,7.35,9.8,12.1]:
			var target := Vector3(x,Flight.FLOOR,depth)
			var crossing := lane_at_depth(contact,target,Net.NET_Z)
			if absf(crossing) > Net.NET_HALF_WIDTH-Net.RADIUS-0.12: continue
			var defender_gap := (target-backcourt).slide(Vector3.UP).length()
			if team_size == 3:
				for index_ in range(defending*team_size,(defending+1)*team_size):
					if index_ == blocker: continue
					var cover := frame.to_local(players[index_].global_position)
					defender_gap = minf(defender_gap,(target-cover).slide(Vector3.UP).length())
			var shot_score := minf(5.0,defender_gap)*0.19
			shot_score -= absf(x)*0.038
			if previous_shot.is_finite():
				var change := (target-contact).slide(Vector3.UP).angle_to((previous_shot-contact).slide(Vector3.UP))
				shot_score -= change*0.55
			var clear_block := 1.0
			if block_at.is_finite():
				var through := lane_at_depth(contact,target,block_at.z)
				var gap := absf(through-block_at.x)
				clear_block = smoothstep(0.65,1.2,gap)
				shot_score += minf(1.6,gap)*3.4
				shot_score -= 1.6*(1.0-smoothstep(0.22,0.66,gap))
			var distance := (target-contact).slide(Vector3.UP).length()
			var travel := distance/maxf(6.0,22.0*spike_strength)
			var net_time := travel*clampf((Net.NET_Z-contact.z)/(depth-contact.z),0.0,1.0)
			var net_height := lerpf(contact.y,Flight.FLOOR,net_time/travel)+0.5*Flight.spike_gravity(9.0)*net_time*(travel-net_time)
			shot_score -= 17.0*(1.0-smoothstep(Net.NET_TOP+Net.RADIUS,Net.NET_TOP+0.25,net_height))
			var near_pin := smoothstep(1.9,3.0,absf(contact.x))
			var down_line := 1.0-smoothstep(0.28,1.25,absf(target.x-line_x))
			var open_line := smoothstep(1.55,3.0,defender_gap)*clear_block
			var safe_line := smoothstep(Net.NET_TOP+0.24,Net.NET_TOP+0.43,net_height)
			shot_score += 2.05*near_pin*down_line*open_line*safe_line
			if depth < Net.NET_Z+3.0:
				var clearance := smoothstep(Net.NET_TOP+0.25,Net.NET_TOP+0.47,net_height)
				var open_floor := smoothstep(1.3,2.8,defender_gap)
				var closeness := 1.0-smoothstep(1.60,7.10,distance)
				shot_score += (0.75+1.85*closeness)*clearance*clear_block*open_floor
			if depth_bias != 0:
				shot_score += depth_bias*0.23*clampf((depth-8.0)/3.0,-1.0,1.0)
			if shot_score > best_score:
				best_score = shot_score
				best = target
	return best

func cpu_spike_has_lane(contact: Vector3) -> bool:
	if contact.z >= Net.NET_Z: return false
	for x in [-4.02,0.0,4.02]:
		for depth in [5.2,7.35,9.8,12.1]:
			var target := Vector3(x,Flight.FLOOR,depth)
			var fraction: float = (Net.NET_Z-contact.z)/(depth-contact.z)
			if absf(lerpf(contact.x,x,fraction)) > Net.NET_HALF_WIDTH-Net.RADIUS-0.12: continue
			var speed := maxf(7.0,22.0*spike_strength)*0.64
			var time := (target-contact).slide(Vector3.UP).length()/speed
			var height := lerpf(contact.y,Flight.FLOOR,fraction)+0.5*Flight.spike_gravity(9.0)*time*time*fraction*(1.0-fraction)
			if height >= Net.NET_TOP+Net.RADIUS: return true
	return false

func cpu_free_ball_motion(contact: Vector3, planned: Vector3) -> Vector3:
	var landing := Flight.landing_time(contact,planned)
	if planned.z > 0.01:
		var cross := (Net.NET_Z-contact.z)/planned.z
		var at_net := contact+planned*cross+Vector3.DOWN*0.5*Flight.GRAVITY*cross*cross
		var finish := contact+planned*landing
		if cross > 0.0 and cross < landing and absf(at_net.x) < Net.NET_HALF_WIDTH-Net.RADIUS-0.12 and at_net.y > Net.NET_TOP+Net.RADIUS and absf(finish.x) <= 4.35 and finish.z <= 12.8:
			return planned
	if contact.z >= Net.NET_Z: return planned
	for depth in [9.8,7.0,5.05]:
		var fraction: float = (Net.NET_Z-contact.z)/(depth-contact.z)
		var x := clampf(-contact.x*0.64,-4.0,4.0)
		if absf(lerpf(contact.x,x,fraction)) > Net.NET_HALF_WIDTH-Net.RADIUS-0.12: continue
		var clearance := Net.NET_TOP+Net.RADIUS+0.22-lerpf(contact.y,Flight.FLOOR,fraction)
		var time := maxf(1.10,sqrt(maxf(0.0,2.0*clearance/(Flight.GRAVITY*fraction*(1.0-fraction)))))
		return (Vector3(x,Flight.FLOOR,depth)-contact)/time+Vector3.UP*0.5*Flight.GRAVITY*time
	return planned

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

func controlled_spike_motion(contact: Vector3, motion: Vector3, target: Vector3, spin_rate: float) -> Vector3:
	var gravity := Flight.spike_gravity(spin_rate)
	var limit := motion.slide(Vector3.UP).length()
	if limit < 1.0: return motion
	var flight_time := Flight.landing_time(contact,motion,gravity)
	if Net.first_hit(func(t): return contact+motion*t+Vector3.DOWN*0.5*gravity*t*t,0.0,flight_time).is_empty(): return motion
	for aim in [target,Vector3(clampf(target.x,-2.8,2.8),Flight.FLOOR,11.4),Vector3(0.0,Flight.FLOOR,10.1)]:
		var offset: Vector3 = aim-contact
		var time_to_net := (Net.NET_Z-contact.z)/maxf(0.01,offset.z)
		if time_to_net <= 0.0 or time_to_net >= 1.0 or absf(contact.x+offset.x*time_to_net) > Net.NET_HALF_WIDTH-Net.RADIUS-0.12: continue
		for power in [1.0,0.86,0.72,0.58]:
			var time: float = offset.slide(Vector3.UP).length()/(limit*power)
			var candidate := offset/time+Vector3.UP*0.5*gravity*time
			if Net.first_hit(func(t): return contact+candidate*t+Vector3.DOWN*0.5*gravity*t*t,0.0,time).is_empty():
				return candidate
	return motion

func set_cpu_swing_power(hitter: int) -> void:
	var side := team(hitter)
	var effort := cpu_policy.choose(side,"attack effort",[0,1,2],0) if not is_human(hitter) else 0
	attackers[side].spike_strength = spike_strength*(1.0-0.075*effort)

func on_spike(actor: Node3D, point: Vector3, motion: Vector3, spin_rate: float) -> void:
	var index := players.find(actor)
	if index < 0 or not can_touch(index): return
	play_touch(true)
	if drill_spike_target.is_finite():
		stroke = "Spike"
		launch(point,motion,"spike",index,spin_rate)
		return
	stroke = "Second-ball spike" if cpu_second_spike and overpass_flight != flight_number else "Spike"
	if not is_human(index):
		var frame := frames[team(index)]
		var start := frame.to_local(point)
		var local_motion := frame.global_basis.inverse()*motion
		var shot: Vector3 = attackers[team(index)].swing_aim
		var tactic := choose_contact_attack(index,start,shot,local_motion,spin_rate)
		if tactic.is_empty():
			local_motion = controlled_spike_motion(start,local_motion,shot,spin_rate)
		else:
			local_motion = tactic.motion
			trace.write("cpu_attack_choice",match_clock,{"type":tactic.type,"contact":start,"target":tactic.target,"motion":local_motion})
		motion = frame.global_basis*local_motion
		var cross := (Net.NET_Z-start.z)/maxf(0.01,local_motion.z)
		var gravity := Flight.spike_gravity(spin_rate)
		var at_net := start+local_motion*cross+Vector3.DOWN*0.5*gravity*cross*cross
		if cross > 0.0 and (absf(at_net.x) > Net.NET_HALF_WIDTH-Net.RADIUS-0.12 or at_net.y < Net.NET_TOP+Net.RADIUS):
			var safe := cpu_free_ball_motion(start,local_motion)
			if not safe.is_equal_approx(local_motion):
				stroke = "Free ball"
				launch(point,frame.global_basis*safe,"free",index)
				return
	if not is_human(index):
		cpu_policy.used(team(index),"attack depth")
		cpu_policy.used(team(index),"attack effort")
	observe_opponent_shot(1-team(index),point,motion,spin_rate)
	launch(point,motion,"spike",index,spin_rate)

func choose_contact_attack(index: int, contact: Vector3, preferred: Vector3, motion: Vector3, spin_rate: float) -> Dictionary:
	var side := team(index)
	var frame := frames[side]
	var defense := 1-side
	var defenders: Array[Vector3] = []
	var walls: Array[Vector3] = []
	for opponent in range(defense*team_size,(defense+1)*team_size):
		var position := frame.to_local(players[opponent].global_position)
		if blocks.has(opponent) and not blocks[opponent].overpass_swing and blocks[opponent].hands.size() == 2:
			var block = blocks[opponent]
			var left := frame.to_local(block.hands[0])
			var right := frame.to_local(block.hands[1])
			var height := maxf(left.y,right.y)
			if height > Net.NET_TOP-0.03:
				walls.append(Vector3((left.x+right.x)*0.5,height,maxf(Net.NET_Z+0.12,(left.z+right.z)*0.5)))
				continue
		defenders.append(position)
	var speed := motion.slide(Vector3.UP).length()
	return CpuShots.plan(contact,preferred,speed,spin_rate,defenders,walls)

func shot_read_zone(local_x: float) -> int:
	return 0 if absf(local_x) < 1.3 else (1 if local_x > 0.0 else -1)

func observe_opponent_shot(side: int, point: Vector3, motion: Vector3, spin_rate: float) -> void:
	var frame := frames[side]
	var time := Flight.landing_time(point,motion,Flight.spike_gravity(spin_rate))
	var landing := frame.to_local(point+motion*time)
	if absf(landing.x) > 4.53 or landing.z < -5.03 or landing.z > Net.NET_Z: return
	var contact := frame.to_local(point)
	var zone := shot_read_zone(contact.x)
	var local_motion := frame.global_basis.inverse()*motion
	if local_motion.z < -0.01 and contact.z >= Net.NET_Z:
		var cross_time := (Net.NET_Z-contact.z)/local_motion.z
		var height := contact.y+local_motion.y*cross_time-0.5*Flight.spike_gravity(spin_rate)*cross_time*cross_time
		var crossing := contact.x+local_motion.x*cross_time
		if height >= Net.NET_TOP and absf(crossing) < Net.NET_HALF_WIDTH:
			var offset := crossing-contact.x
			var old: Vector2 = block_crossing_reads[side].get(zone,Vector2(offset,0.0))
			block_crossing_reads[side][zone] = Vector2(lerpf(old.x,offset,0.34),minf(10.0,old.y+1.0))
	var reads := opponent_shot_reads[side]
	var count := int(reads.get(zone,Vector2.ZERO).y)
	var previous := float(reads.get(zone,Vector2(landing.x,0.0)).x)
	reads[zone] = Vector2(lerpf(previous,landing.x,0.23),mini(16,count+1))

func learned_cover(side: int, attack_x: float, base_cover: float) -> float:
	var read: Vector2 = opponent_shot_reads[side].get(shot_read_zone(attack_x),Vector2.ZERO)
	var confidence := smoothstep(2.0,7.0,read.y)
	var limit := 1.10+0.11*mini(completed_read_matches,5)
	return base_cover+clampf(read.x-base_cover,-limit,limit)*confidence

func record_uncovered_shot(side: int, point: Vector3) -> void:
	var frame := frames[side]
	var zone := shot_read_zone(frame.to_local(origin).x)
	var landing := frame.to_local(point)
	var recent: Array = repeated_shot_landings[side].get_or_add(zone,[])
	recent.append(Vector2(landing.x,landing.z))
	if recent.size() > 6: recent.pop_front()

func repeat_shot_read(side: int, attack_x: float) -> Vector3:
	var recent: Array = repeated_shot_landings[side].get(shot_read_zone(attack_x),[])
	if recent.size() < 2: return Vector3.ZERO
	var latest: Vector2 = recent.back()
	var total := Vector2.ZERO
	var count := 0
	for landing: Vector2 in recent:
		if landing.distance_to(latest) <= 1.65:
			total += landing
			count += 1
	var center := total/maxf(count,1)
	return Vector3(center.x,smoothstep(1.0,4.0,count),center.y)

func remember_opponent_reads() -> void:
	completed_read_matches += 1
	for side in opponent_shot_reads.size():
		carried_shot_reads[side].clear()
		for zone in opponent_shot_reads[side]:
			var read: Vector2 = opponent_shot_reads[side][zone]
			var samples := mini(8,floori(read.y*0.65))
			if samples > 0:
				carried_shot_reads[side][zone] = Vector2(read.x,samples)

func route_ball_sound() -> void:
	if OS.get_name() != "Windows": return
	var outputs := AudioServer.get_output_device_list()
	for output in outputs:
		var name_ := output.to_lower()
		if name_.begins_with("speakers (") and not name_.contains("streaming") and not name_.contains("virtual"):
			AudioServer.output_device = output
			return
	AudioServer.output_device = "Default"

func make_ball_audio(stream: AudioStream, gain: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = gain
	player.max_polyphony = 3
	add_child(player)
	return player

func set_ball_sound(enabled: bool) -> void:
	StorySession.attack_ball_audio_muted = not enabled
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"),not enabled)
	if enabled:
		route_ball_sound()
		play_touch(true)
	else:
		for player in [touch_audio,set_audio,spike_audio,floor_audio,net_audio]: player.stop()

func play_touch(strong := false) -> void:
	if StorySession.attack_ball_audio_muted: return
	var player := spike_audio if strong else touch_audio
	player.play()

func set_pin_for(index: int, setter_x := INF) -> Vector3:
	if drill_set_pin.is_finite(): return frames[team(index)].to_local(drill_set_pin)
	var side := team(index)
	var frame := frames[side]
	if is_human(index) and aim_point.is_finite():
		var point := frame.to_local(aim_point)
		if point.z <= Net.NET_Z: return Vector3(clampf(point.x,-4.6,4.6),0.065,clampf(point.z,-1.6,3.62))
	var hitter := players[hitter_for_set(index)]
	if is_human(index) or (flight_kind != "pass" and not defensive_ball()):
		return Vector3(clampf(hitter.position.x,-3.75,3.75),0.065,3.20)
	if called_pin_flight == flight_number and (not is_finite(setter_x) or absf(called_pin.x-setter_x) >= 1.0):
		return called_pin
	if not is_finite(setter_x):
		var meet := path_point(arrival(1.92))
		setter_x = frame.to_local(meet).x
	var transition: bool = transition_possession[side] or defensive_ball()
	var preparation := maxf(0.0,arrival(1.92)-elapsed-0.26)
	var reach := (3.25 if transition else 2.65)+preparation*3.6
	var lane_bias := cpu_policy.choose(side,"set lane",[0,-1,1],0)
	var fallback := Vector3(clampf(hitter.position.x,-3.75,3.75),0.065,3.20)
	called_pin = fallback
	var called_zone := posmod(flight_number*3+rallies+team(index)*2,SET_ZONES.size())
	var preferred: float = SET_ZONES[called_zone]
	var opposition := 1-team(index)
	var blocker: int = defender_assignment[opposition]
	var best_cost := INF
	var best_is_wide := false
	for x in SET_ZONES:
		var candidate := Vector3(x,0.065,3.20)
		var staging := candidate-Vector3.BACK*2.02
		var gap := (staging-hitter.position).slide(Vector3.UP).length()
		if gap > reach: continue
		var blocker_gap := 0.0
		if blocker >= 0:
			var blocker_x := frame.to_local(players[blocker].global_position).x
			blocker_gap = absf(x-blocker_x)
		var repeat := 0.0
		if is_finite(last_called_set_x[side]):
			repeat = (1.0-smoothstep(0.35,2.05,absf(x-last_called_set_x[side])))*(1.70 if transition else 0.75)
		var same_lane := (1.0-smoothstep(0.45,1.85,absf(x-hitter.position.x)))*0.88 if transition else 0.0
		var cost := 0.34*maxf(0.0,gap-1.8)+0.39*absf(x-preferred)-0.49*minf(blocker_gap,3.6)+repeat+same_lane
		if lane_bias != 0: cost += 0.24*absf(x-lane_bias*2.50)
		var is_wide := absf(x-setter_x) >= 1.0
		if (is_wide and not best_is_wide) or (is_wide == best_is_wide and cost < best_cost):
			best_cost = cost
			best_is_wide = is_wide
			called_pin = candidate
	called_pin_flight = flight_number
	return called_pin

func defensive_ball() -> bool:
	return flight_kind in ["spike","dump","block","free"] or (touched_tape and not net_hit.is_empty())

func queue_receive(index: int, technique: int) -> void:
	if technique == 0 and not can_play_forearms(index): return
	var bump := platforms[index]
	if is_finite(bump.pressed_at): return
	bump.hand_setting = technique != 0
	bump.quick_hand_receive = technique == 1 and (team(index) != possession_team or touches == 0)
	bump.forearm_setting = team(index) == possession_team and touches == 1
	bump.green_hand_allowance = 0.50 if is_human(index) and bump.forearm_setting else 0.38
	bump.green_forearm_allowance = 0.48 if is_human(index) else 0.30
	bump.green_start = 0.0 if is_human(index) else 0.01
	bump.green_end = 0.78 if is_human(index) else 0.55
	bump.fast_hand_dig = technique == 1 and not is_human(index) and (defensive_ball() or flight_kind == "serve") and cpu_hand_receive_too_fast(arrival(hand_contact_height(1)))
	bump.defensive_hand_dig = technique == 1 and (defensive_ball() or bump.fast_hand_dig)
	bump.quick_low_save = technique == 0 and not is_human(index)
	bump.allow_pancake = flight_kind not in ["spike","dump"] or touched_tape
	bump.pancake_requires_chase = true
	bump.allow_auto_dive = technique == 0 and (not is_human(index) or not defensive_ball())
	bump.queue_bump(elapsed)
	show_key(index,["Q","E","F"][technique])

func pass_support_receiver(index: int) -> int:
	if team_size == 2: return index^1
	var side := team(index)
	var target := Vector3(players[index].position.x*0.5,PLAYER_GROUND_Y,2.0)
	return nearest_on_team(side,frames[side].to_global(target),index)

func cpu_pass_target(index: int) -> Vector3:
	if drill_pass_target.is_finite(): return frames[team(index)].to_local(drill_pass_target)
	var passer := players[index].position
	var teammate := players[pass_support_receiver(index)].position
	var x := lerpf(passer.x,teammate.x,0.82)
	var forward := maxf(1.05,absf(x-passer.x)*tan(deg_to_rad(40.0)))
	if not is_human(index):
		var depth := cpu_policy.choose(team(index),"pass depth",[0,-1,1],0)
		forward += depth*0.38
	return Vector3(x,0.065,clampf(passer.z+forward,-3.4,2.95))

func aim_receive(index: int) -> void:
	var bump := platforms[index]
	var side := team(index)
	var frame := frames[side]
	var destination := cpu_pass_target(index)
	bump.passing_skill_override = passing_skill
	bump.setting_skill_override = setting_skill
	bump.hard_dig = flight_kind in ["spike","dump","block"]
	if is_human(index) and aim_point.is_finite(): destination = frame.to_local(aim_point)
	elif side == possession_team and (touches >= 2 or (cpu_dump and index == cpu_choice)): destination = choose_shot(index)
	bump.set_follow_target = set_pin_for(index) if cpu_is_setting(index) and not cpu_dump else Vector3.INF
	bump.destination = Vector2(clampf(destination.x,-6.5,6.5),clampf(destination.z,-6.0,13.0))
	var variety := float(posmod(flight_number+index*3,7))/6.0
	var difficulty := smoothstep(7.0,25.0,velocity.length())
	var pass_apex := lerpf(3.65,6.35,clampf(variety*0.78+difficulty*0.22,0.0,1.0))
	if not is_human(index):
		pass_apex += cpu_policy.choose(side,"pass height",[0,-1,1],0)*0.36
	bump.height = pass_height if is_human(index) else (3.65 if cpu_dump and index == cpu_choice else pass_apex)

func cpu_set_apex(index: int, point: Vector3, pin: Vector3, pace: float) -> float:
	var hitter := players[hitter_for_set(index)]
	var tight := smoothstep(0.40,1.35,point.z)
	var distance := (pin-hitter.position).slide(Vector3.UP).length()
	var ready := 1.0-smoothstep(2.15,3.80,distance)
	var controlled := 1.0-smoothstep(8.0,15.0,pace)*0.38
	var variety := float(posmod(second_ball_options+index+rallies,4))/3.0
	var quick := lerpf(2.98,3.30,variety)
	var high := lerpf(5.50,7.28,maxf(variety*0.69,1.0-ready))
	var apex := lerpf(high,quick,tight*ready*controlled)
	if transition_possession[team(index)]:
		var peel := smoothstep(1.50,3.10,hitter.position.z)*smoothstep(0.16,0.9,hitter.position.z-(pin.z-1.85))
		var lateral := smoothstep(0.8,3.45,absf(pin.x-hitter.position.x))
		var transition_load := maxf(peel,lateral)
		apex = maxf(apex,lerpf(2.98,6.15,transition_load))
	var adjustment := cpu_policy.choose(team(index),"set height",[0,-1,1],0)
	return maxf(point.y+0.18,apex+0.32*adjustment)

func receive_contact(index: int, world_point: Vector3, world_motion: Vector3, technique: int) -> void:
	if frames[team(index)].to_local(world_point).z > Net.NET_Z+0.07: return
	var transition := defensive_ball()
	if not can_touch(index): return
	var side := team(index)
	if transition: transition_possession[side] = true
	var frame := frames[side]
	var point := frame.to_local(world_point)
	var bump := platforms[index]
	stroke = ["Forearm","Hands","Jump set"][technique]
	if touches == 1 and not is_human(index):
		cpu_policy.used(side,"pass depth")
		cpu_policy.used(side,"pass height")
	if defensive_ball() and not bump.contact_check.is_empty():
		trace.write("dig_contact",match_clock,bump.contact_check)
	var sample_before := maxf(0.0,bump.touch_time-0.003)
	var sample_after := minf(flight_end(),bump.touch_time+0.003)
	var fast_forearm: bool = technique == 0 and not bump.low_save.active and sample_after > sample_before
	fast_forearm = fast_forearm and path_point(sample_before).distance_to(path_point(sample_after)) >= FAST_DIG_ELBOW_SPEED*(sample_after-sample_before)
	begin_recovery(index)
	if fast_forearm:
		recoveries[index]["fast_elbow_bend"] = true
		if bump.knee_bend_depth > 0.001:
			recoveries[index]["hold"] = FAST_DIG_ELBOW_DURATION
	if not StorySession.attack_ball_audio_muted:
		if technique != 0 and not transition: set_audio.play()
		else: play_touch()
	var cpu_dump_attempt := touches == 2 and cpu_dump and index == cpu_choice and not is_human(index)
	var unsafe_dump := cpu_dump_attempt and not dump_can_land_in_court(point,frame.global_basis.inverse()*world_motion)
	if touches == 2 and (unsafe_dump or (not (cpu_dump and index == cpu_choice) and (bump.destination.y < 4.0 or (is_human(index) and technique != 0)))):
		var setter_x := players[index].position.x
		var pin := set_pin_for(index,setter_x)
		last_called_set_x[side] = pin.x
		var incoming := velocity+Vector3.DOWN*Flight.GRAVITY*elapsed
		var driver := attackers[side]
		var minimum := maxf((driver.set_contact_height()+0.22) if is_human(index) else 2.96,point.y+0.18)
		var apex: float = bump.height if is_human(index) else cpu_set_apex(index,point,pin,incoming.length())
		apex = maxf(minimum,apex)
		var error := Bump.Accuracy.sample_set_offset(Bump.Accuracy.spread(0.0,incoming.length(),spin,setting_skill,true))
		var set_width := pin.x-setter_x
		pin += error.slide(Vector3.UP)
		if not is_human(index) and absf(set_width) >= 1.0 and (pin.x-setter_x)*signf(set_width) < 1.0:
			pin.x = setter_x+signf(set_width)
		apex = maxf(maxf(2.74,point.y+0.18),apex+error.y)
		if not is_human(index):
			var span := (pin-point).slide(Vector3.UP).length()
			var time_to_hit := maxf(0.68,span/6.2)
			apex = driver.apex_for_set_time(point.y,apex,time_to_hit)
		if is_finite(drill_set_apex): apex = maxf(point.y+0.18,drill_set_apex)
		var contact_height: float = driver.set_contact_height(apex)
		last_set_apex = apex
		if not is_human(index):
			cpu_policy.used(side,"set lane")
			cpu_policy.used(side,"set height")
		var motion: Vector3 = driver.set_toward_pin(point,pin,apex,contact_height)
		launch(world_point,frame.global_basis*motion,"set",index,1.0,hitter_for_set(index),frame.to_global(pin))
		return
	if drill_pass_target.is_finite():
		world_motion = drill_pass_motion(world_point,world_motion)
	if not is_human(index) and touches == 3:
		world_motion = frame.global_basis*cpu_free_ball_motion(point,frame.global_basis.inverse()*world_motion)
	var crossing := (Net.NET_Z-world_point.z)/world_motion.z if absf(world_motion.z)>0.001 else -1.0
	var over := crossing > 0.0 and crossing < Flight.landing_time(world_point,world_motion)
	if over:
		var crossing_point := world_point+world_motion*crossing+Vector3.DOWN*0.5*Flight.GRAVITY*crossing*crossing
		# A teammate can still play a low pass before it reaches the net.
		over = crossing_point.y >= Net.NET_TOP+0.02
	var outgoing_spin := Vector3.ZERO
	if technique == 0 and sample_after > sample_before:
		var incoming_motion := (path_point(sample_after)-path_point(sample_before))/(sample_after-sample_before)
		outgoing_spin = Flight.forearm_spin(incoming_motion,world_motion,ball_spin,BallPreview.RADIUS)
	launch(world_point,world_motion,("dump" if touches == 2 and technique != 0 else "free") if over else "pass",index,outgoing_spin.length(),-1,Vector3.ZERO,Vector3.INF,outgoing_spin)

func drill_pass_motion(contact: Vector3, motion: Vector3) -> Vector3:
	# Keep the receiver's existing aim error and move the descending arrival to the target height.
	var floor_time := Flight.landing_time(contact,motion)
	var landing := contact+motion*floor_time
	var height := drill_pass_target.y
	var rise := sqrt(maxf(0.0,2.0*Flight.GRAVITY*(height+0.28-contact.y)))
	var vertical := rise if drill_set_pin.is_finite() else maxf(motion.y,rise)
	var discriminant := vertical*vertical+2.0*Flight.GRAVITY*(contact.y-height)
	var arrival_time := maxf(0.08,(vertical+sqrt(maxf(0.0,discriminant)))/Flight.GRAVITY)
	var destination := drill_pass_target if drill_set_pin.is_finite() else landing
	var horizontal := (destination-contact).slide(Vector3.UP)/arrival_time
	return horizontal+Vector3.UP*vertical

func dump_can_land_in_court(point: Vector3, motion: Vector3) -> bool:
	if motion.z <= 0.001: return false
	var landing := Flight.landing_time(point,motion)
	var cross := (Net.NET_Z-point.z)/motion.z
	if cross <= 0.0 or cross >= landing: return false
	var at_net := point+motion*cross+Vector3.DOWN*0.5*Flight.GRAVITY*cross*cross
	var floor_point := point+motion*landing
	return absf(at_net.x) <= Net.NET_HALF_WIDTH and at_net.y >= Net.NET_TOP+0.02 and absf(floor_point.x) <= 4.53 and floor_point.z <= 13.03

func owns_action(index: int, allow_serve_move := false) -> bool:
	if blocks.has(index) or set_jumps[index].active: return true
	var actor := players[index]
	if not drill_set_pin.is_finite() and serve.player == actor and not serve.moved_after_contact and serve.swing_time < serve.recovery_end():
		if not allow_serve_move or not serve.can_run_after_contact(): return true
	var driver := attackers[team(index)]
	return driver.enabled and driver.setter == actor and (driver.jump.active or driver.stage == driver.Stage.HIT)

func begin_recovery(index: int) -> void:
	var actor := players[index]
	var rig: Skeleton3D = actor.skeleton
	var pose: Array[Transform3D] = []
	for bone in rig.get_bone_count(): pose.append(rig.get_bone_pose(bone))
	var recovery := {"started":match_clock,"pose":pose,"animation":receive_animation_labels.get(index,"")}
	var bump := platforms[index]
	if is_finite(bump.touch_time) and not bump.hand_setting and not bump.low_save.active:
		recovery["hold"] = 0.06
		recovery["rise"] = RECOVERY_TIME-0.06
	if is_finite(bump.touch_time) and (bump.knee_bend_depth > 0.001 or bump.fast_back_receive or bump.reach.get("tier",0) == 2) and not bump.low_save.active:
		recovery["hold"] = FAST_RECEIVE_HOLD
		recovery["rise"] = squat_rise_duration if bump.knee_bend_depth > 0.001 else FAST_RECEIVE_RISE
	if bump.forearm_setting and bump.reach.has("custom_clip") and is_finite(bump.touch_time):
		recovery["hold"] = 0.02
		recovery["rise"] = Bump.FOREARM_RECOVERY_TIME
	if bump.hand_setting and not bump.defensive_hand_dig and is_finite(bump.release_time):
		recovery["hold"] = 0.08
		recovery["rise"] = 0.65
		recovery["spine_rise"] = 0.80
		if not bump.release_wrist_goals.is_empty():
			recovery["wrist_goals"] = bump.release_wrist_goals.duplicate()
			recovery["wrist_elapsed"] = bump.release_wrist_elapsed
			recovery["wrist_turn_end"] = bump.hand_release_delay()+Bump.HandPose.FRONT_WRIST_FOLLOW_TIME
	if bump.low_save.active:
		recovery["save"] = bump.low_save
		recovery["save_time"] = elapsed
		recovery["save_release"] = bump.touch_time if is_finite(bump.touch_time) else bump.low_save.contact_time+0.07
		bump.low_save = Bump.LowSave.new()
	recoveries[index] = recovery
	actor.animator.speed_scale = 1.0
	actor.play_action("idle",0.0)

func advance_recoveries(delta: float) -> void:
	for index in recoveries.keys():
		var recovery: Dictionary = recoveries[index]
		var age := match_clock-float(recovery.started)
		if recovery.has("save"):
			var time := float(recovery.save_time)+age
			if not recovery.save.finished(time):
				recovery.save.sample(players[index],time,recovery.save_release)
				animated[index] = true
				continue
			var final_time: float = recovery.save.end_time()
			recovery.save.sample(players[index],final_time,recovery.save_release)
			begin_recovery(index)
			animated[index] = true
			continue
		var hold: float = recovery.get("hold",0.0)
		var rise: float = recovery.get("rise",RECOVERY_TIME)
		var spine_rise: float = recovery.get("spine_rise",rise)
		if age >= hold+maxf(rise,spine_rise):
			recoveries.erase(index)
			continue
		var landing_set: bool = set_jumps[index].active
		if owns_action(index) and not landing_set: continue
		var actor := players[index]
		var rig: Skeleton3D = actor.skeleton
		if not landing_set: actor.animator.advance(delta)
		animated[index] = true
		var weight := 1.0-smoothstep(hold,hold+rise,age)
		var spine_weight := 1.0-smoothstep(hold,hold+spine_rise,age)
		var wrist_goals: Dictionary = recovery.get("wrist_goals",{})
		for bone in rig.get_bone_count():
			if landing_set:
				var name_ := rig.get_bone_name(bone)
				if name_.begins_with("thigh_") or name_.begins_with("calf_") or name_.begins_with("foot_") or name_.begins_with("ball_") or name_ in ["root","pelvis"]: continue
			var bone_weight := spine_weight if spine_rise > rise and rig.get_bone_name(bone).begins_with("spine_") else weight
			var pose: Transform3D = recovery.pose[bone]
			var idle := rig.get_bone_pose(bone)
			rig.set_bone_pose_position(bone,idle.origin.lerp(pose.origin,bone_weight))
			var rotation := pose.basis.orthonormalized().get_rotation_quaternion().normalized()
			if wrist_goals.has(bone):
				var elapsed_at_release: float = recovery.wrist_elapsed
				var turn_end: float = recovery.wrist_turn_end
				var initial := smoothstep(0.0,turn_end,elapsed_at_release)
				var progress := smoothstep(0.0,turn_end,elapsed_at_release+age)
				rotation = rotation.slerp(wrist_goals[bone],(progress-initial)/maxf(0.0001,1.0-initial))
				var wrist_hold := maxf(hold,turn_end-elapsed_at_release)
				bone_weight = 1.0-smoothstep(wrist_hold,hold+rise,age)
			rig.set_bone_pose_rotation(bone,idle.basis.orthonormalized().get_rotation_quaternion().normalized().slerp(rotation,bone_weight))
		if recovery.get("fast_elbow_bend",false) and age > 0.0 and age < FAST_DIG_ELBOW_DURATION:
			apply_fast_dig_elbow_bend(rig,age)
		if recovery.has("kick_foot"):
			var flick := smoothstep(0.0,0.070,age)*(1.0-smoothstep(0.07,0.22,age))
			if flick > 0.001: pose_kick_leg(actor,recovery.kick_foot,(Vector3.UP*0.15+actor.global_basis.z*0.11)*flick)

func apply_fast_dig_elbow_bend(rig: Skeleton3D, age: float) -> void:
	var bend := deg_to_rad(50.0)*smoothstep(0.0,0.095,age)*(1.0-smoothstep(0.12,FAST_DIG_ELBOW_DURATION,age))
	var left := rig.find_bone("lowerarm_l")
	var right := rig.find_bone("lowerarm_r")
	var axis := (rig.get_bone_global_pose(left).origin-rig.get_bone_global_pose(right).origin).normalized()
	if axis.is_zero_approx(): return
	var chest := rig.get_bone_global_pose(rig.find_bone("spine_03")).origin
	var flexion_direction := 0.0
	for elbow_bone in [left,right]:
		var elbow := rig.get_bone_global_pose(elbow_bone).origin
		var shoulder := rig.get_bone_global_pose(rig.get_bone_parent(elbow_bone)).origin
		var wrist := rig.get_bone_global_pose(rig.find_bone("hand_l" if elbow_bone == left else "hand_r")).origin
		var upper := (elbow-shoulder).normalized()
		var forearm := (wrist-elbow).normalized()
		var hinge := upper.cross(forearm)
		if hinge.length_squared() < 0.0001:
			hinge = forearm.cross((chest-wrist).normalized())
		var direction := hinge.normalized().dot(axis)
		# Skip the recoil if a shared hinge would bend either elbow against its flexion plane.
		if absf(direction) < 0.05 or flexion_direction*direction < 0.0: return
		flexion_direction = direction
		bend = minf(bend,maxf(0.0,deg_to_rad(100.0)-upper.angle_to(forearm)))
	# Rotation about the elbow span preserves the wrists' separation along that span.
	for elbow_bone in [left,right]:
		var parent_basis := rig.get_bone_global_pose(rig.get_bone_parent(elbow_bone)).basis.orthonormalized()
		var rotation := Quaternion(parent_basis.inverse()*axis,bend*signf(flexion_direction))
		rig.set_bone_pose_rotation(elbow_bone,(rotation*rig.get_bone_pose_rotation(elbow_bone)).normalized())


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
		if phase == Phase.LIVE and not is_human(index):
			actor.rotation.y = rotate_toward(actor.rotation.y,0.0,delta*8.0)
		actor.animator.speed_scale = 1.0
		actor.play_action("idle")
		actor.animator.advance(delta)
		if not is_human(index): footwork[index].step(Vector3.ZERO,delta,1.0,true)

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

func move_cpu(index: int, target: Vector3, delta: float, speed := 5.3, receive_facing := Vector3.INF, chase := false, turn_to_travel := false, turn_rate := 12.5, paced_run := false) -> void:
	if recoveries.has(index) or owns_action(index,true): return
	var actor := players[index]
	var is_server: bool = not drill_set_pin.is_finite() and serve.player == actor
	if is_server:
		if not serve.can_run_after_contact(): return
		if not serve.moved_after_contact:
			serve_run_started = match_clock
			var rig: Skeleton3D = actor.skeleton
			for bone in rig.get_bone_count():
				var name_ := str(rig.get_bone_name(bone))
				if name_.begins_with("spine_") or name_.begins_with("clavicle_") or name_.begins_with("upperarm_") or name_.begins_with("lowerarm_") or name_.begins_with("hand_"):
					serve_run_rotations[bone] = rig.get_bone_pose_rotation(bone)
		serve.moved_after_contact = true
	var local := frames[team(index)].to_local(target)
	var offset := (local-actor.position).slide(Vector3.UP)
	var heading := offset.normalized()
	var already_running: bool = actor.animator.current_animation == actor.animation_slots["run"]
	var distance := offset.length()
	if is_server and offset.z > 0.75 and offset.z > absf(offset.x):
		chase = true
		turn_to_travel = true
		speed = maxf(speed,6.5)
	var run_distance := 0.18 if paced_run else (0.48 if already_running else 0.85)
	var run_alignment := 0.66 if already_running else 0.76
	var may_run := chase and distance > run_distance
	var yaw := 0.0
	if (may_run and heading.dot(actor.basis.z.normalized()) >= run_alignment) or (turn_to_travel and distance > 0.25):
		yaw = atan2(heading.x,heading.z)
	elif receive_facing.is_finite() and not receive_facing.is_zero_approx():
		yaw = atan2(receive_facing.x,receive_facing.z)
		if not turn_to_travel: yaw = clampf(yaw,-1.03,1.03)
	actor.rotation.y = rotate_toward(actor.rotation.y,yaw,delta*(turn_rate if turn_to_travel else 8.0))
	var sprint := may_run and heading.dot(actor.basis.z.normalized()) >= run_alignment
	var pace := minf(speed,4.35)*CPU_SHUFFLE_SPEED_SCALE
	if sprint:
		pace = clampf(speed,0.65,CPU_SPRINT_SPEED) if paced_run else clampf(speed*1.24,5.85,CPU_SPRINT_SPEED)
	var before := actor.position
	var step_target := before+offset.limit_length(delta*pace)
	var grounded := Court.clamp_setter(step_target,3.43)
	if is_server and before.z < Court.RUNOFF_NEAR_BASELINE:
		grounded.z = clampf(step_target.z,before.z,3.43)
	grounded.y = move_toward(before.y,PLAYER_GROUND_Y,delta*1.25)
	actor.position = grounded
	var movement := actor.basis.inverse()*(actor.position-before).slide(Vector3.UP)
	if actor.mirror_animation: movement.x = -movement.x
	actor.animator.speed_scale = lerpf(1.60,1.92,smoothstep(5.85,8.4,pace)) if sprint else 1.0
	if sprint and paced_run:
		actor.animator.speed_scale = clampf(pace/3.7,0.22,2.05)
	actor.play_action("run" if sprint else "idle",0.10)
	actor.animator.advance(delta)
	var steps := footwork[index]
	if sprint:
		steps.weight = 0.0
	else:
		steps.step(movement.limit_length(delta*2.1)/maxf(delta*2.1,0.001),delta,clampf(pace/2.06,0.65,2.25),true)
	if is_server and not serve_run_rotations.is_empty():
		var blend := smoothstep(0.0,SERVE_RUN_BLEND,match_clock-serve_run_started)
		if blend >= 1.0: serve_run_rotations.clear()
		else:
			var rig: Skeleton3D = actor.skeleton
			for bone in serve_run_rotations:
				var source: Quaternion = serve_run_rotations[bone]
				rig.set_bone_pose_rotation(bone,source.slerp(rig.get_bone_pose_rotation(bone),blend))
	animated[index] = true

func arrival(height: float) -> float:
	var start := elapsed
	if touched_tape and not net_hit.is_empty(): start = maxf(start,float(net_hit.release_time))
	var beginning := start
	var end := flight_end()
	if not touched_tape and not net_hit.is_empty() and net_hit.kind == "under":
		end = minf(end,float(net_hit.time))
	if beginning >= end: return end
	for i in range(1,26):
		var next := lerpf(beginning,end,i/25.0)
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
	var first := side*team_size
	if side == possession_team and touches > 0 and not last_was_block:
		cpu_choice = setter_for_pass(last_player) if touches == 1 else (last_player^1 if team_size == 2 else nearest_on_team(side,point,last_player))
	elif defensive_ball():
		var best_cost := INF
		for index in range(first,first+team_size):
			var at := dig_intercept(index)
			var contact := path_point(at)
			var distance := (contact-players[index].global_position).slide(Vector3.UP).length()
			var cost := distance-maxf(0.0,at-elapsed)*3.5
			if blocks.has(index): cost += 2.0
			if recoveries.has(index) and recoveries[index].has("save"): cost += 2.4
			if index == defender_assignment[side]: cost += 0.30
			if cost < best_cost:
				cpu_choice = index
				best_cost = cost
	elif team_size == 3:
		cpu_choice = nearest_on_team(side,point)
	elif point.distance_squared_to(players[first].global_position) <= point.distance_squared_to(players[first+1].global_position):
		cpu_choice = first
	else: cpu_choice = first+1
	if not spectator and side == 0 and cpu_choice == 0 and side != possession_team and not is_finite(platforms[0].pressed_at):
		if point.slide(Vector3.UP).distance_to(human.global_position.slide(Vector3.UP)) > 1.65:
			cpu_choice = 1 if team_size == 2 else nearest_on_team(0,point,0)
	cpu_technique = 0
	cpu_dump = false
	cpu_fake_dump = false
	if is_human(cpu_choice): return
	var second_ball := side == possession_team and touches == 1 and flight_kind == "pass"
	if second_ball and overhead_available(cpu_choice,2):
		cpu_technique = 2
	elif overhead_available(cpu_choice,1):
		cpu_technique = 1
	if second_ball:
		second_ball_options += 1
		var hand_point := frames[side].to_local(path_point(arrival(2.35 if cpu_technique == 2 else 1.92)))
		var tight := hand_point.z >= 2.65 and hand_point.z <= 3.70
		var can_fake := cpu_technique == 2 and hand_point.z >= 1.9 and hand_point.z <= 3.70
		if cpu_technique != 0 and (tight or can_fake):
			cpu_dump = tight and second_ball_options%3 == 0
			cpu_fake_dump = can_fake and second_ball_options%3 == 2

func cpu_is_setting(index: int) -> bool:
	return team(index) == possession_team and touches == 1 and flight_kind == "pass"

func hand_contact_height(technique: int) -> float:
	if technique == 2:
		var apex := origin.y+maxf(velocity.y,0.0)**2/(2.0*Flight.GRAVITY)
		return clampf(apex-0.15,2.35,maxf(2.35,Bump.HandPose.CONTACT_HEIGHT+attack_vertical*0.0254-0.08))
	return Bump.HandPose.CONTACT_HEIGHT if defensive_ball() or flight_kind == "serve" else 1.92

func hand_receive_reach(index: int) -> float:
	if cpu_is_setting(index): return Bump.HandPose.SET_CONTACT_FORWARD
	if defensive_ball(): return HAND_DIG_REACH
	return Bump.HandPose.CONTACT_FORWARD if flight_kind == "serve" else 0.28

func cpu_hand_receive_too_fast(at: float) -> bool:
	var before := maxf(0.0,at-0.003)
	var after := minf(flight_end(),at+0.003)
	return after > before and path_point(before).distance_to(path_point(after)) > CPU_HAND_RECEIVE_MAX_SPEED*(after-before)

func cpu_prefers_fast_forearms(index: int, hand_at: float) -> bool:
	if not cpu_hand_receive_too_fast(hand_at): return false
	for height in [1.13,0.86,0.60,0.46]:
		var at := arrival(height)
		var point := path_point(at)
		if point.y < height-0.12 or at >= flight_end()-0.025: continue
		if frames[team(index)].to_local(point).z > Net.NET_Z: continue
		var gap := (point-players[index].global_position).slide(Vector3.UP).length()
		var travel := 4.35*CPU_SHUFFLE_SPEED_SCALE*maxf(0.0,at-elapsed-0.10)
		var reach := 1.32 if height >= 0.60 else 1.55
		if gap <= travel+reach: return true
	return false

func cpu_should_backshuffle(index: int, contact: Vector3, cue: float) -> bool:
	if not (defensive_ball() or flight_kind == "serve"): return false
	var frame := frames[team(index)]
	var approach := frame.to_local(contact)-frame.to_local(path_point(maxf(0.0,cue-0.06)))
	var depth := frame.to_local(contact).z-players[index].position.z
	return depth < -0.25 and approach.z < -0.05 and cpu_hand_receive_too_fast(cue)

func overhead_available(index: int, technique: int) -> bool:
	if not is_human(index) and flight_kind == "serve" and not drill_feed_acceleration.is_finite() and serve.get_script() == SERVES[3]: return false
	var first_contact := technique == 1 and (defensive_ball() or flight_kind == "serve")
	var setting := cpu_is_setting(index)
	var height := hand_contact_height(technique)
	var at := arrival(height)
	if first_contact and not is_human(index) and cpu_prefers_fast_forearms(index,at): return false
	var frame := frames[team(index)]
	var point := frame.to_local(path_point(at))
	var actor := players[index]
	var offset := (point-actor.position).slide(Vector3.UP)
	var range_ := (0.76 if technique == 2 else 0.92)+minf(0.88,maxf(0.0,at-elapsed-0.24)*2.4)
	if first_contact or setting:
		var approach := frame.global_basis.inverse()*(path_point(maxf(elapsed,at-0.08))-path_point(at))
		var forward := approach.slide(Vector3.UP).normalized()
		if forward.is_zero_approx(): forward = actor.basis.z
		offset -= forward*hand_receive_reach(index)
		var reserve := 0.32 if technique == 2 else 0.10
		var pace := 4.35*CPU_SHUFFLE_SPEED_SCALE if first_contact and (flight_kind == "serve" or cpu_hand_receive_too_fast(at)) else 4.15
		range_ = (0.48 if first_contact else 0.55)+maxf(0.0,at-elapsed-reserve)*pace
	return point.z <= Net.NET_Z+0.05 and point.y >= height-0.12 and at < flight_end()-0.03 and (first_contact or setting or point.z >= actor.position.z-0.24) and offset.length() <= range_

func dig_intercept(index: int) -> float:
	var actor := players[index]
	var best := arrival(0.96)
	var best_cost := INF
	for height in [0.96,1.13,0.78,0.60,0.46]:
		var at := arrival(height)
		if at >= flight_end()-0.025: continue
		var point := path_point(at)
		if frames[team(index)].to_local(point).z > Net.NET_Z: continue
		var approach := (path_point(maxf(0.0,at-0.06))-point).slide(Vector3.UP).normalized()
		var body_target := point-approach*FOREARM_DIG_REACH
		var offset := (body_target-actor.global_position).slide(Vector3.UP)
		var aligned := offset.normalized().dot(actor.global_basis.z.normalized())
		var pace := lerpf(4.35,7.2,smoothstep(0.50,0.85,aligned))
		var cost := maxf(0.0,offset.length()-pace*maxf(0.0,at-elapsed-0.06))+absf(height-0.86)*0.46
		if cost < best_cost:
			best = at
			best_cost = cost
	return best

func start_second_ball_spike(index: int, require_open_lane := false) -> bool:
	var side := team(index)
	var driver := attackers[side]
	if driver.enabled or not net_hit.is_empty() or recoveries.has(index): return false
	var at := arrival(driver.set_contact_height())
	if at-elapsed < 0.57 or at >= flight_end()-0.07: return false
	var frame := frames[side]
	var contact := frame.to_local(path_point(at))
	if contact.z < 2.18 or contact.z > 3.68: return false
	var attacker := players[index]
	var gap := (contact-attacker.position).slide(Vector3.UP).length()
	if gap < 0.45 or gap > 2.30: return false
	var blocker: int = defender_assignment[1-side]
	var wall := Vector3.INF
	if blocker >= 0:
		wall = frame.to_local(players[blocker].global_position)
		wall.z = Net.NET_Z+0.40
	if require_open_lane:
		if not cpu_spike_has_lane(contact): return false
		if blocker >= 0:
			var actual := frame.to_local(players[blocker].global_position)
			var lane_gap := absf(actual.x-contact.x)
			var closing_time := maxf(0.0,at-elapsed-0.25)
			var net_gap := maxf(0.0,actual.z-(Net.NET_Z+0.70))
			if Vector2(maxf(0.0,lane_gap-0.85),net_gap).length() <= closing_time*5.3: return false
	set_cpu_swing_power(index)
	driver.start_set(attacker,frame.to_local(origin),frame.global_basis.inverse()*velocity,contact,choose_shot(index,contact,wall),elapsed,false)
	if not driver.find_approach_intercept(true).is_finite():
		driver.enabled = false
		return false
	driver.queue_jump(Vector2.ZERO)
	cpu_second_spike = driver.approach_jump_queued
	if cpu_second_spike:
		next_touch_cue = at
		show_key(index,"Space")
	return cpu_second_spike

func should_let_blockout_go() -> bool:
	if not last_was_block or last_player < 0 or team(last_player) == receiving_team: return false
	var landing := path_point(flight_end())
	return absf(landing.x) > 4.72 or landing.z < -5.22 or landing.z > 13.22

func cpu_can_lunge(index: int, contact: Vector3, lead: float) -> bool:
	if contact.y < 0.42 or lead < -0.035: return false
	var actor := players[index]
	var gap := (contact-actor.global_position).slide(Vector3.UP).length()
	var lunge_reach := lerpf(1.02,1.32,smoothstep(0.035,0.22,lead))
	if gap <= lunge_reach: return true
	if lead < 0.10 or gap > 1.55: return false
	var bump := platforms[index]
	var offset: Vector3 = bump.to_local(contact)-bump.ready_contact()
	return Bump.Timing.practice_reach_tier(offset) == 2

func tick_receive(delta: float, previous: float) -> void:
	if spectator or not is_finite(platforms[0].pressed_at):
		if should_let_blockout_go(): return
		if flight_kind == "spike" and not net_hit.is_empty() and team(last_player) != receiving_team:
			var landing := path_point(flight_end())
			if absf(landing.x) > 4.85 or landing.z < -5.35 or landing.z > 13.35: return
	if expected_hitter >= 0 and flight_kind == "set":
		var hitter := expected_hitter
		var driver := attackers[team(hitter)]
		if not is_human(hitter):
			if driver.jump.active: return
			var remaining: float = driver.pin_arrival-(driver.clock-driver.stage_start)
			var forecast: Vector3 = frames[team(hitter)].to_local(path_point(clampf(driver.pin_arrival,elapsed,flight_end())))
			var safe_lane := cpu_spike_has_lane(forecast)
			var approach_window := 0.28 if last_set_apex < 3.65 else 0.54
			if safe_lane and driver.enabled and remaining > approach_window:
				prepare_cpu_approach(hitter,driver,delta)
				return
			if safe_lane and driver.approach_jump_queued: return
			driver.approach_jump_queued = false
			driver.enabled = false
			expected_hitter = -1
			cpu_choice = hitter
			cpu_technique = 1 if overhead_available(hitter,1) else 0
			next_touch_cue = INF
		elif driver.jump.active or not is_finite(platforms[0].pressed_at): return
	if cpu_choice < 0: select_receiver()
	var index := cpu_choice
	if not spectator and receiving_team == 0 and is_finite(platforms[0].pressed_at) and not blocks.has(0): index = 0
	if index < 0 or blocks.has(index): return
	if cpu_second_spike: return
	if not is_human(index) and not is_finite(platforms[index].pressed_at):
		var planned_attack := cpu_dump or overpass_flight == flight_number
		var opportunistic_attack := cpu_is_setting(index) and not cpu_fake_dump and not drill_set_pin.is_finite()
		if (planned_attack or opportunistic_attack) and start_second_ball_spike(index,not planned_attack): return
	var frame := frames[team(index)]
	var bump := platforms[index]
	var technique := requested if is_human(index) else cpu_technique
	var force_forearms := drill_force_forearm_serve_receive and flight_kind == "serve"
	if not force_forearms and not is_human(index) and (defensive_ball() or flight_kind == "serve") and is_finite(bump.pressed_at) and not is_finite(bump.touch_time) and not bump.low_save.active and elapsed-dig_switch_at > 0.16:
		var hands_at := arrival(hand_contact_height(1))
		var hands_lead := hands_at-elapsed
		var alternate := technique
		if technique == 0 and defensive_ball() and hands_lead >= 0.065 and hands_lead <= 0.30 and overhead_available(index,1):
			alternate = 1
		elif technique == 1 and (cpu_prefers_fast_forearms(index,hands_at) or (defensive_ball() and (path_point(elapsed).y < players[index].global_position.y+1.54 or (hands_lead < 0.17 and not overhead_available(index,1) and path_point(elapsed).y < 2.10)))):
			alternate = 0
		if alternate != technique:
			bump.reset()
			bump.begin_dig_transition(elapsed)
			technique = alternate
			cpu_technique = alternate
			next_touch_cue = INF
			dig_switch_at = elapsed
			queue_receive(index,alternate)
	var cpu_setting := not is_human(index) and cpu_is_setting(index)
	var free_ball := not is_human(index) and flight_kind == "set" and expected_hitter < 0
	if not force_forearms and not is_human(index) and not is_finite(bump.pressed_at):
		var preferred := technique
		if cpu_setting and technique < 2 and overhead_available(index,2):
			preferred = 2
		elif technique == 0 and (cpu_setting or free_ball or defensive_ball() or flight_kind == "serve") and overhead_available(index,1):
			preferred = 1
		if preferred != technique:
			technique = preferred
			cpu_technique = preferred
			next_touch_cue = INF
	var recovering := recoveries.has(index)
	if recovering:
		if technique != 0 or not defensive_ball() or recoveries[index].has("save"): return
		if index == last_player and not last_was_block and possession_team == team(index): return
	if is_human(index) and technique < 0: return
	if is_human(index) and not is_finite(bump.pressed_at) and elapsed-request_age < 0.44: queue_receive(0,technique)
	if technique == 0 and not can_play_forearms(index): return
	var height := 1.10 if technique == 0 else hand_contact_height(technique)
	var is_dig := defensive_ball()
	var hand_pass := technique == 1 and flight_kind == "serve"
	var forearm_dig := technique == 0 and is_dig
	var cpu_dig := forearm_dig and not is_human(index)
	if not is_finite(next_touch_cue):
		next_touch_cue = dig_intercept(index) if cpu_dig else arrival(height)
	var cue := next_touch_cue
	var catch_point := path_point(cue)
	if not is_human(index) and frame.to_local(catch_point).z > Net.NET_Z+0.07: return
	var actor := players[index]
	var max_set_jump := attack_vertical*0.0254
	var set_jump_height := clampf((catch_point.y-actor.global_position.y-1.72)*1.12,minf(0.56,max_set_jump),max_set_jump)
	var set_jump_rise := 0.0
	var set_jump_plant_gap := INF
	if technique == 2: set_jump_rise = set_jumps[index].flight_duration(set_jump_height,true)*0.43
	bump.low_save_approach_velocity = Vector3.ZERO
	if not is_human(index) and cpu_should_backshuffle(index,catch_point,cue): backshuffle_receiver = index
	var backshuffle := backshuffle_receiver == index
	var square_receive := not is_human(index) and (flight_kind == "serve" or (is_dig and cpu_hand_receive_too_fast(cue)))
	if not is_human(index):
		if technique != 0 and not is_finite(bump.pressed_at) and not overhead_available(index,technique):
			cpu_technique = 1 if technique == 2 and overhead_available(index,1) else 0
			cpu_dump = cpu_dump and cpu_technique == 1
			cpu_fake_dump = false
			next_touch_cue = INF
			return
		var face := toward_incoming(index,catch_point)
		if face.is_zero_approx(): face = Vector3.BACK
		var to_drop := (frame.to_local(catch_point)-actor.position).slide(Vector3.UP)
		var drop_distance := to_drop.length()
		var drop_heading := to_drop.normalized()
		var alignment := drop_heading.dot(actor.basis.z.normalized())
		if cpu_dig and not square_receive and not backshuffle and drop_distance > 0.80 and alignment < -0.32:
			rear_chaser = index
		var turning_chase := cpu_dig and not square_receive and rear_chaser == index
		var forward_chase := is_dig and not square_receive and drop_distance > 1.20 and alignment > 0.48 and cue-elapsed > 0.095
		var run_to_drop := turning_chase or forward_chase
		var outside_lunge_range := cpu_dig and not cpu_can_lunge(index,catch_point,cue-elapsed)
		var turn_for_save: bool = cpu_dig and not square_receive and not bump.low_save.active and flight_end()-elapsed <= 0.33 and drop_distance > 1.20
		if backshuffle: face = Vector3.BACK
		elif run_to_drop: face = drop_heading if drop_distance > 0.45 else actor.basis.z
		elif turn_for_save: face = face.lerp(drop_heading,0.68).normalized()
		var offset := (FOREARM_DIG_REACH if cpu_dig else 0.52) if technique == 0 else hand_receive_reach(index)
		if not recovering and not set_jumps[index].active and not bump.low_save.active and not bump.reach.get("deep_side",false):
			var spacing := 0.88 if square_receive and cpu_dig and cue < 0.40 else offset
			var target := catch_point-frame.global_basis*face*spacing
			if backshuffle:
				# Leave room to play the ball behind the hips after the backward steps.
				target = catch_point+frame.global_basis.z*0.45
			var lead := cue-elapsed
			var speed := lerpf(1.7,5.3,smoothstep(0.035,0.24,lead))
			if is_dig or hand_pass or cpu_setting or free_ball:
				var distance := (target-actor.global_position).slide(Vector3.UP).length()
				var reserve := 0.26 if cpu_setting and technique == 2 else (0.055 if cpu_dig else 0.12)
				speed = clampf(distance/maxf(0.035,lead-reserve),2.0,7.2)
			elif is_finite(bump.pressed_at):
				speed = minf(speed,2.0)
			if not backshuffle and run_to_drop and drop_distance > 1.55: speed = CPU_SPRINT_SPEED
			var plant := not backshuffle and not outside_lunge_range and is_finite(bump.pose_started_at) and lead < 0.16 and drop_distance < 1.05
			var lateral_run := outside_lunge_range and not square_receive and not run_to_drop and not backshuffle
			if lateral_run: speed = CPU_SPRINT_SPEED
			var before_move := actor.position
			# Leave the final step to the lunge when the receive pose can cover it.
			if square_receive and technique == 0 and lead <= 0.16 and lead >= -0.035:
				var reach_offset: Vector3 = bump.to_local(catch_point)-bump.ready_contact()
				var reach_tier: int = Bump.Timing.practice_reach_tier(reach_offset)
				if bump.reach.get("tier",0) == 2 or (reach_tier == 2 and cue >= 0.40):
					target = actor.global_position
			var set_travel := (target-actor.global_position).slide(Vector3.UP).length()
			var setting_run := cpu_setting and technique != 0 and lead > 0.24 and set_travel > 0.85
			move_cpu(index,target,delta,speed,face,not square_receive and not backshuffle and not plant and (is_dig or cpu_setting or free_ball or flight_kind == "serve"),(run_to_drop or turn_for_save or lateral_run or setting_run) and not plant and not backshuffle,18.0 if lateral_run else 12.5)
			bump.low_save_approach_velocity = (actor.position-before_move)/maxf(delta,0.001)
			set_jump_plant_gap = (target-actor.global_position).slide(Vector3.UP).length()
		var prep := set_jump_rise+0.16 if technique == 2 else (0.40 if cpu_dig else (0.18 if cpu_setting and technique == 0 else 0.27))
		if elapsed >= cue-prep: queue_receive(index,technique)
	if not is_finite(bump.pressed_at): return
	if touched_tape and not net_hit.is_empty() and elapsed < float(net_hit.release_time): return
	if recovering: recoveries.erase(index)
	if technique == 2 and not jump_set_started[index] and cue-elapsed <= set_jump_rise+0.13:
		if not is_human(index) and set_jump_plant_gap > 0.38:
			if cue-elapsed > set_jump_rise+0.045:
				return
			bump.reset()
			cpu_technique = 1 if overhead_available(index,1) else 0
			cpu_fake_dump = false
			cpu_dump = cpu_dump and cpu_technique == 1
			next_touch_cue = INF
			queue_receive(index,cpu_technique)
			return
		jump_set_started[index] = true
		set_jumps[index].front_limit = 3.35
		set_jumps[index].begin_set_jump(actor,clampf(cue-elapsed-set_jump_rise,0.055,0.16),set_jump_height)
	var end := flight_end()
	var path := func(t: float) -> Vector3: return frame.to_local(path_point(t))
	var motion := (path_point(minf(end,elapsed+0.003))-path_point(maxf(0.0,elapsed-0.003)))/0.006
	bump.setter_jumping = set_jumps[index].active
	aim_receive(index)
	if is_human(index):
		bump.show()
		bump.update_aim()
	var floor_lead := end-elapsed
	bump.emergency_low_save = cpu_dig and floor_lead <= 0.25
	var timing_cue := cue if is_human(index) and technique == 0 else INF
	bump.knee_bend_depth = 0.0
	if forearm_dig:
		var low := 1.0-smoothstep(0.48,1.12,catch_point.y)
		bump.ready_knee_bend_depth = lerpf(0.21,0.35,low)
		bump.lunge_bend_depth = lerpf(0.14,0.22,low)
		bump.knee_bend_depth = bump.ready_knee_bend_depth*smoothstep(cue-0.33,cue-0.06,elapsed)
		if cpu_dig:
			bump.allow_auto_dive = not backshuffle and (bump.emergency_low_save or not cpu_can_lunge(index,catch_point,cue-elapsed))
	bump.rushed_cpu_receive = not is_human(index) and technique == 0 and (is_dig or flight_kind == "serve") and cpu_hand_receive_too_fast(cue) and cue-elapsed <= RUSHED_RECEIVE_WINDOW
	if square_receive and technique == 0 and not bump.low_save.active and not bump.deep_squat:
		var reach_offset: Vector3 = bump.to_local(catch_point)-bump.ready_contact()
		if bump.reach.is_empty() and cue-elapsed <= 0.22 and Bump.Timing.practice_reach_tier(reach_offset) == 2:
			bump.plan_reach(reach_offset)
		var lunge_in_range := cpu_can_lunge(index,catch_point,cue-elapsed)
		var committed: Vector3 = bump.reach.get("intercept",Vector3.INF)
		var holds_lunge: bool = bump.reach.get("tier",0) == 2 and committed.is_finite() and committed.distance_to(bump.to_local(catch_point)) <= bump.contact_radius()
		# Decide before the dive windup runs out. A viable grounded receive keeps priority.
		bump.allow_auto_dive = not holds_lunge and (not lunge_in_range or elapsed > cue+0.035)
	if cpu_dig and not backshuffle and not bump.low_save.active and not bump.deep_squat and not bump.reach.has("custom_clip") and not bump.reach.get("deep_side",false):
		var low_at := maxf(elapsed,arrival(0.60))
		var low_point := path_point(low_at)
		var offset := actor.to_local(low_point)
		var low_in_front := offset.z >= 0.10 and low_point.y <= 0.61
		var side_gap := absf(offset.x)
		if low_in_front and side_gap > 0.45 and side_gap <= 1.12 and offset.z <= 0.95 and low_at-elapsed >= 0.14:
			bump.clear_reach()
			bump.plan_reach(bump.to_local(low_point)-bump.ready_contact(),true)
		elif low_in_front and offset.z <= 1.22 and side_gap <= 0.60:
			bump.deep_squat = true
			bump.clear_reach()
	if bump.reach.get("deep_side",false):
		bump.allow_auto_dive = false
		bump.lunge_bend_depth = 0.36
	if bump.reach.has("custom_clip"): bump.allow_auto_dive = false
	if bump.deep_squat:
		bump.allow_auto_dive = false
		bump.knee_bend_depth = maxf(bump.knee_bend_depth,0.62*smoothstep(cue-0.33,cue-0.06,elapsed))
	if not is_human(index) and frame.to_local(path_point(end)).z > Net.NET_Z: bump.allow_auto_dive = false
	var was_diving: bool = bump.low_save.active
	bump.fast_back_receive = backshuffle and technique == 0 and is_dig
	bump.update_attempt(elapsed,previous,end,path,frame.global_basis.inverse()*motion,delta,timing_cue,spin,cue if is_dig else INF,true)
	if bump.low_save.active and not was_diving:
		var save := "Pancake" if bump.low_save.pancake else ("One-arm dive" if not bump.low_save.wide_arm.is_empty() else "Dive")
		show_key(index,"Q")
		trace.write("low_save",match_clock,{"player":index,"type":save,"target":frame.to_global(bump.low_save.aim),"flight":flight_kind})
	if is_finite(bump.pose_started_at) or bump.low_save.active:
		var animation := "Forearm receive"
		if bump.low_save.active:
			animation = "Pancake" if bump.low_save.pancake else ("One-arm dive" if not bump.low_save.wide_arm.is_empty() else "Two-arm dive")
		elif technique != 0:
			animation = "Jump set" if technique == 2 else ("Overhead dig" if is_dig else "Hands receive")
		elif bump.deep_squat:
			animation = "Deep squat"
		elif bump.reach.get("deep_side",false):
			animation = "Deep side lunge"
		elif bump.reach.get("tier",0) == 2:
			animation = "Lunge"
			if bump.reach.get("forward_lunge",false): animation = "Forward lunge"
			elif bump.reach.get("backward",false): animation = "D2 back-leg lift" if bump.reach.has("custom_clip") else "Backward lunge"
			elif bump.reach.get("side_lunge",false): animation = "Side lunge"
		if receive_animation_labels.get(index,"") != animation:
			receive_animation_labels[index] = animation
			trace.write("receive_animation",match_clock,{"player":index,"animation":animation,"flight":flight_kind})
	animated[index] = true
	if cpu_fake_dump and not is_human(index) and technique == 2 and not is_finite(bump.touch_time):
		pose_fake_dump(actor,cue-elapsed)
	if is_finite(bump.touch_time):
		if touched_tape and not net_hit.is_empty() and bump.touch_time < float(net_hit.release_time):
			bump.reset()
			next_touch_cue = INF
			return
		if bump.hand_setting and not is_finite(bump.release_time):
			held_ball = true
			ball.global_position = frame.to_global(bump.platform_center())
			return
		held_ball = false
		var touch: Vector3 = bump.release_point if bump.hand_setting else bump.touch
		if touch.z > Net.NET_Z+0.07:
			touch = bump.touch
		if not is_human(index) and not is_dig and technique != 0 and bump.touch.y < actor.position.y+1.45:
			bump.reset()
			cpu_technique = 0
			cpu_dump = false
			cpu_fake_dump = false
			next_touch_cue = INF
			return
		receive_contact(index,frame.to_global(touch),frame.global_basis*bump.outgoing,technique)
	elif not is_human(index) and not is_dig and previous <= cue and elapsed >= cue and catch_point.y > 0.55:
		var gap := (actor.global_position-catch_point).slide(Vector3.UP).length()
		var reachable_height := technique == 0 or catch_point.y >= actor.global_position.y+1.49
		var reach := 0.66 if technique == 0 else 0.46
		if gap <= reach and cue < end-0.025 and reachable_height:
			if technique == 0: bump.apply_pose(bump.contact_frame,0.82)
			else: Bump.HandPose.apply(actor,catch_point,0.86)
			var spread: Vector2 = bump.accuracy_bounds(0.0,frame.global_basis.inverse()*motion,spin)
			var result: Vector3 = bump.aim_velocity(frame.to_local(catch_point),spread)
			receive_contact(index,catch_point,frame.global_basis*result,technique)

func input_kick() -> void:
	if spectator or phase != Phase.LIVE or receiving_team != 0 or not can_play_forearms(0): return
	kick_pressed_until = match_clock+0.20

func try_foot_save(previous: float) -> void:
	if held_ball or elapsed > flight_end()+0.05: return
	var end := flight_end()
	var first := path_point(previous)
	var last := path_point(minf(elapsed,end))
	var lookahead := path_point(minf(end,elapsed+0.060))
	if minf(last.y,lookahead.y) > 0.42 or maxf(first.y,last.y) < Flight.FLOOR: return
	var side := receiving_team
	for index in range(side*team_size,(side+1)*team_size):
		if is_human(index) and match_clock > kick_pressed_until: continue
		if index == last_player and not last_was_block: continue
		if not can_play_forearms(index) or owns_action(index) or recoveries.has(index): continue
		var bump := platforms[index]
		if bump.low_save.active or is_finite(bump.touch_time): continue
		if is_finite(bump.pose_started_at):
			var reachable: PackedVector3Array = bump.dig_contact_segment(bump.to_local(last),bump.to_local(lookahead))
			if reachable[0].distance_to(reachable[1]) <= Net.RADIUS+0.055: continue
		var actor := players[index]
		if actor.global_position.slide(Vector3.UP).distance_to(last.slide(Vector3.UP)) > 0.95: continue
		var rig: Skeleton3D = actor.skeleton
		var foot_side := ""
		var goal := Vector3.ZERO
		var gap := 0.35
		for suffix in ["l","r"]:
			var toe := rig.to_global(rig.get_bone_global_pose(rig.find_bone("ball_"+suffix)).origin)
			var aim := Geometry3D.get_closest_point_to_segment(toe,last,lookahead)
			var distance := toe.distance_to(aim)
			if distance < gap and aim.y <= 0.42:
				gap = distance
				goal = aim
				foot_side = suffix
		if foot_side.is_empty(): continue
		var foot := "foot_"+foot_side
		var toe_bone := "ball_"+foot_side
		var toe := rig.to_global(rig.get_bone_global_pose(rig.find_bone(toe_bone)).origin)
		var shift := (goal-Vector3.UP*0.055-toe).limit_length(0.30)
		var lift := 1.0-smoothstep(0.16,0.35,gap)
		pose_kick_leg(actor,foot_side,shift*lift)
		animated[index] = true
		var a := rig.to_global(rig.get_bone_global_pose(rig.find_bone(foot)).origin)
		var b := rig.to_global(rig.get_bone_global_pose(rig.find_bone(toe_bone)).origin)
		var pair := Geometry3D.get_closest_points_between_segments(first,last,a,b)
		var contact := pair[0]
		if contact.y > 0.42 or frames[side].to_local(contact).z > Net.NET_Z+0.07 or contact.distance_to(pair[1]) > Net.RADIUS+0.055: continue
		if not can_touch(index): return
		kick_pressed_until = -INF
		show_key(index,"C | Kick")
		begin_recovery(index)
		recoveries[index]["kick_foot"] = foot_side
		var heading := Vector3.BACK.rotated(Vector3.UP,randf_range(-PI,PI))
		var rebound := heading*randf_range(1.8,6.0)+Vector3.UP*randf_range(3.2,6.0)
		trace.write("foot_save",match_clock,{"player":index,"foot":foot_side,"point":contact,"rebound":rebound},true)
		stroke = "Kick save"
		play_touch()
		launch(contact,rebound,"pass",index)
		return

func pose_kick_leg(actor: Node3D, side: String, world_shift: Vector3) -> void:
	var rig: Skeleton3D = actor.skeleton
	var author: RefCounted = actor.get_pose_author()
	var pose: Array[Transform3D] = []
	for bone in rig.get_bone_count(): pose.append(rig.get_bone_pose(bone))
	var foot := "foot_"+side
	var thigh := "thigh_"+side
	var calf := "calf_"+side
	var ankle: Vector3 = author.point(pose,foot)
	var knee := Vector3(0.10 if side == "l" else -0.10,0.12,1.0)
	author.limb(pose,thigh,calf,foot,ankle+rig.global_basis.inverse()*world_shift,knee,1.0,174.0)
	for joint in [thigh,calf,foot]:
		var bone := rig.find_bone(joint)
		rig.set_bone_pose_rotation(bone,pose[bone].basis.get_rotation_quaternion())

func deflect_defender_body(previous: float) -> void:
	if flight_kind not in ["spike","dump","block"] or held_ball: return
	var first := path_point(previous)
	var last := path_point(minf(elapsed,flight_end()))
	var travel := last-first
	if travel.length_squared() < 0.000001: return
	var player := -1
	var contact := Vector3.ZERO
	var surface := Vector3.ZERO
	var first_fraction := INF
	var body_part := ""
	for index in range(receiving_team*team_size,(receiving_team+1)*team_size):
		if index == last_player: continue
		var actor := players[index]
		if actor.global_position.slide(Vector3.UP).distance_to(last.slide(Vector3.UP)) > 1.1+travel.length(): continue
		var rig: Skeleton3D = actor.skeleton
		for segment in BODY_CONTACT_SEGMENTS:
			var a := rig.to_global(rig.get_bone_global_pose(rig.find_bone(segment[0])).origin)
			var b := rig.to_global(rig.get_bone_global_pose(rig.find_bone(segment[1])).origin)
			var pair := Geometry3D.get_closest_points_between_segments(first,last,a,b)
			var radius := Net.RADIUS+float(segment[2])
			if pair[0].distance_squared_to(pair[1]) > radius*radius: continue
			var enter := 0.0
			var inside := clampf((pair[0]-first).dot(travel)/travel.length_squared(),0.0,1.0)
			for refinement in 6:
				var middle := (enter+inside)*0.5
				var sample := first+travel*middle
				var axis_point := Geometry3D.get_closest_point_to_segment(sample,a,b)
				if sample.distance_squared_to(axis_point) <= radius*radius: inside = middle
				else: enter = middle
			if inside >= first_fraction: continue
			var point := first+travel*inside
			if frames[receiving_team].to_local(point).z > Net.NET_Z+0.07: continue
			var normal := (point-Geometry3D.get_closest_point_to_segment(point,a,b)).normalized()
			if travel.dot(normal) > 0.0: continue
			first_fraction = inside
			player = index
			contact = point
			surface = normal
			body_part = segment[0]
	if player < 0 or not can_touch(player): return
	var incoming := travel/maxf(0.001,minf(elapsed,flight_end())-previous)
	if surface.is_zero_approx(): surface = -incoming.normalized()
	var rebound := incoming.slide(surface)*0.48-surface*incoming.dot(surface)*0.46
	trace.write("body_contact",match_clock,{"player":player,"body_part":body_part,"point":contact,"rebound":rebound})
	if is_finite(platforms[player].pose_started_at) and not platforms[player].low_save.active and not owns_action(player):
		begin_recovery(player)
	stroke = "Body deflection"
	transition_possession[team(player)] = true
	play_touch()
	launch(contact,rebound,"pass",player)

func pose_fake_dump(actor: Node3D, lead: float) -> void:
	var weight := (1.0-smoothstep(0.15,0.28,lead))*smoothstep(0.045,0.12,lead)
	if weight <= 0.001: return
	var rig: Skeleton3D = actor.skeleton
	var author: RefCounted = actor.get_pose_author()
	var pose: Array = []
	for bone in rig.get_bone_count(): pose.append(rig.get_bone_pose(bone))
	var shoulder: Vector3 = author.point(pose,"upperarm_r")
	var target := shoulder+Vector3(-0.23,0.35,0.14)/rig.global_basis.y.length()
	author.limb(pose,"upperarm_r","lowerarm_r","hand_r",target,Vector3(-0.85,0.10,0.30),weight)
	for part in ["upperarm_r","lowerarm_r","hand_r"]:
		var bone := rig.find_bone(part)
		rig.set_bone_pose_rotation(bone,pose[bone].basis.orthonormalized().get_rotation_quaternion())

func start_block(index: int, remaining := INF, reads_second := false, overpass_swing := false) -> void:
	if blocks.has(index) or set_jumps[index].active: return
	if recoveries.has(index): return
	var actor := players[index]
	if serve.player == actor and not serve.can_run_after_contact(): return
	if actor.position.z < 2.25 or actor.position.z > 3.45: return
	var block := Block.new()
	block.jump_height = block_vertical*0.0254
	block.landing_recovery = 0.43 if reads_second else 0.13
	block.overpass_swing = overpass_swing
	block.aggressive_press = not is_human(index) and not overpass_swing
	block.begin(actor)
	if is_finite(remaining): block.tempo = clampf((Block.START+Block.AIR*0.5)/maxf(remaining,0.18),1.13,1.80)
	blocks[index] = block
	if not is_human(index): cpu_policy.used(team(index),"block lane")
	show_key(index,"Space")

func soft_block_rebound(rebound: Vector3, power: float) -> Vector3:
	if power > 0.56: return rebound
	var looseness := 1.0-smoothstep(0.0,0.62,power)
	var scatter := lerpf(0.32,1.0,looseness)
	var angle := deg_to_rad(lerpf(34.0,96.0,scatter))
	var horizontal := rebound.slide(Vector3.UP).rotated(Vector3.UP,randf_range(-angle,angle))
	horizontal *= lerpf(1.0,randf_range(0.24,1.85),scatter)
	if randf() < 0.30*looseness:
		horizontal.z *= -randf_range(0.60,1.18)
	var lift := rebound.y+randf_range(-4.0,3.7)*scatter
	return horizontal+Vector3.UP*lift

func block_contact_power(palm_gap: float, along: float, square: float, attack_depth: float) -> float:
	var power := (1.0-smoothstep(0.09,0.24,palm_gap))*(1.0-smoothstep(0.72,1.22,along))*smoothstep(0.18,0.66,square)
	var tight := 1.0-smoothstep(0.30,0.92,attack_depth)
	var palm := (1.0-smoothstep(0.10,0.22,palm_gap))*(1.0-smoothstep(0.78,1.04,along))
	var press := tight*palm*smoothstep(0.16,0.48,square)
	return lerpf(power,1.0,0.58*press)

func tick_blocks(delta: float, previous: float) -> void:
	var incoming_spike := phase == Phase.LIVE and (flight_kind in ["spike","dump"] or overpass_flight == flight_number)
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
				if block.overpass_swing and (overpass_flight != flight_number or hand != 1 or block.age < 0.31 or block.age > 0.79): continue
				var tip: Vector3 = block.previous_hands[hand].lerp(block.hands[hand],fraction)
				var wrist: Vector3 = block.previous_wrists[hand].lerp(block.wrists[hand],fraction)
				var center := Geometry3D.get_closest_point_to_segment(point,wrist,tip)
				var gap := point.distance_to(center)
				var reach := 0.28 if block.overpass_swing else (0.30 if block.aggressive_press else 0.27)
				if gap > reach or center.y < Net.NET_TOP or absf(point.z-Net.NET_Z) > 0.9: continue
				if block.overpass_swing:
					if hit_overpass(index,point): return
					continue
				if not can_touch(index,true): return
				var backward := frames[team(index)].global_basis.z.normalized()
				var axis := (tip-wrist).normalized()
				var incoming := velocity.normalized()
				var square := clampf(-incoming.dot(backward),0.0,1.0)
				var palm := wrist.lerp(tip,0.45)
				var travel := (point-palm).dot(backward)/maxf(square,0.10)
				var impact := point+incoming*clampf(travel,0.0,0.29)
				var palm_gap := impact.distance_to(Geometry3D.get_closest_point_to_segment(impact,wrist,tip))
				var along := (impact-wrist).dot(axis)/maxf(0.01,wrist.distance_to(tip))
				var attack_depth := absf(origin.z-Net.NET_Z)
				var power := block_contact_power(palm_gap,along,square,attack_depth)
				var tight := 1.0-smoothstep(0.30,0.92,attack_depth)
				var speed := velocity.length()
				var firm := smoothstep(0.35,0.77,power)*tight
				var rebound := backward*lerpf(-speed*0.16,speed*0.69,power)+Vector3.UP*lerpf(3.1,-6.0,power)
				rebound += backward*speed*0.24*firm+Vector3.DOWN*2.7*firm
				rebound.x += (point.x-center.x)*10.0
				rebound = soft_block_rebound(rebound,power)
				if power <= 0.56:
					rebound += backward*signf(rebound.dot(backward))*speed*0.10*tight*(1.0-firm)
				var outward := signf(center.x)
				var edge := (center.x-players[index].global_position.x)*outward
				if absf(center.x) > 3.4 and edge > 0.16 and (point.x-center.x)*outward > 0.025 and power < 0.56:
					rebound.x = outward*maxf(rebound.x*outward,speed*0.28)
				trace.write("block_contact",match_clock,{"power":power,"palm_gap":palm_gap,"along":along,"tight":tight,"point":point,"rebound":rebound})
				stroke = "Stuff block" if power > 0.56 else "Block"
				play_touch()
				var over := rebound.dot(backward) > 0.0
				launch(point,rebound,"free" if over else "block",index)
				return

func hit_overpass(index: int, point: Vector3) -> bool:
	var side := team(index)
	var frame := frames[side]
	var contact := frame.to_local(point)
	if contact.z > Net.NET_Z-Net.RADIUS*0.45 or contact.y < Net.NET_TOP+Net.RADIUS: return false
	var defender: int = defender_assignment[1-side]
	var wall := Vector3.INF
	if blocks.has(defender):
		wall = frame.to_local(players[defender].global_position)
		wall.z = Net.NET_Z+0.38
	var shot := choose_shot(index,contact,wall)
	var offset := shot-contact
	var time := maxf(0.10,offset.slide(Vector3.UP).length()/maxf(9.0,26.0*spike_strength))
	var spin_rate := 6.0
	var gravity := Flight.spike_gravity(spin_rate)
	var motion := offset/time+Vector3.UP*0.5*gravity*time
	var tactic := choose_contact_attack(index,contact,shot,motion,spin_rate)
	if not tactic.is_empty():
		shot = tactic.target
		motion = tactic.motion
	else:
		motion = controlled_spike_motion(contact,motion,shot,spin_rate)
	if not Net.first_hit(func(t): return contact+motion*t+Vector3.DOWN*0.5*gravity*t*t,0.0,Flight.landing_time(contact,motion,gravity)).is_empty():
		motion = cpu_free_ball_motion(contact,motion)
		spin_rate = 0.0
	if not can_touch(index): return false
	stroke = "Overpass attack"
	var world_motion := frame.global_basis*motion
	trace.write("overpass_attack",match_clock,{"player":index,"point":point,"target":shot,"blocker":defender},true)
	play_touch(true)
	observe_opponent_shot(1-side,point,world_motion,spin_rate)
	launch(point,world_motion,"spike",index,spin_rate)
	return true

func peel_cpu_off_net(index: int, staging: Vector3, delta: float) -> void:
	if recoveries.has(index):
		var recovery: Dictionary = recoveries[index]
		if recovery.has("save") or match_clock-float(recovery.started) < 0.11: return
		recoveries.erase(index)
	move_cpu(index,frames[team(index)].to_global(staging),delta,7.4,Vector3.INF,true,true,17.0)

func move_cpu_to_approach(hitter: int, staging: Vector3, delta: float, speed: float) -> void:
	var offset := (staging-players[hitter].position).slide(Vector3.UP)
	var running := offset.z > 0.12 and offset.length() > 0.18
	move_cpu(hitter,frames[team(hitter)].to_global(staging),delta,speed,Vector3.INF,running,running,17.0,running)

func prepare_cpu_approach(hitter: int, driver: Node3D, delta: float) -> void:
	if driver.approach_jump_queued: return
	var actor := players[hitter]
	var pin: Vector3 = driver.rally_set_target
	var time_left: float = driver.pin_arrival-(driver.clock-driver.stage_start)
	var gap := (pin-actor.position).slide(Vector3.UP).length()
	var staging := pin-Vector3.BACK*2.02
	var peeling := actor.position.z > pin.z-1.70 and time_left > 0.82
	if peeling:
		peel_cpu_off_net(hitter,staging,delta)
		return
	if recoveries.has(hitter): return
	if gap < 1.86 and time_left > 0.95 and last_set_apex > 4.85:
		move_cpu_to_approach(hitter,staging,delta,2.8)
		return
	if not driver.approach_space_held:
		var intercept: Vector3 = driver.find_approach_intercept(true)
		var run_up_gap := (staging-actor.position).slide(Vector3.UP).length()
		if intercept.is_finite() and ((time_left <= 0.88 and gap <= 2.40 and run_up_gap <= 0.35) or time_left <= 0.68):
			driver.queue_jump(Vector2.ZERO)
			if driver.approach_jump_queued:
				show_key(hitter,"Space")
				return
	var distance := (staging-actor.position).slide(Vector3.UP).length()
	if distance > 0.12:
		var speed := clampf(distance/maxf(0.05,time_left-0.82),0.65,CPU_SPRINT_SPEED)
		move_cpu_to_approach(hitter,staging,delta,speed)

func position_attack(delta: float) -> void:
	if defensive_ball() and flight_kind != "pass":
		var side := receiving_team
		var frame := frames[side]
		var ball_behind_block := frame.to_local(ball.global_position).z < 2.40
		var own_block := last_was_block and last_player >= 0 and team(last_player) == side
		if ball_behind_block or own_block:
			if cpu_choice < 0: select_receiver()
			var blocker: int = last_player if own_block else defender_assignment[side]
			if blocker >= 0 and cpu_choice >= 0 and cpu_choice != blocker and not is_human(blocker) and players[blocker].position.z > 1.20:
				var stage_from := players[blocker].position
				stage_from.z = 0.95
				peel_cpu_off_net(blocker,stage_from,delta)
		return
	if flight_kind != "pass" or possession_team != receiving_team or touches != 1: return
	var setter := setter_for_pass(last_player)
	var hitter := hitter_for_set(setter)
	if is_human(hitter) or blocks.has(hitter) or set_jumps[hitter].active: return
	var receive_at := arrival(1.55)
	var receive_depth := frames[receiving_team].to_local(path_point(receive_at)).z
	var run_up := lerpf(2.72,2.18,smoothstep(1.55,2.85,receive_depth))
	var staging := set_pin_for(setter)-Vector3.BACK*run_up
	var distance := (staging-players[hitter].position).slide(Vector3.UP).length()
	var speed := clampf(distance/maxf(0.24,receive_at-elapsed+0.16),1.5,4.1)
	if players[hitter].position.z-staging.z > 0.45:
		peel_cpu_off_net(hitter,staging,delta)
	else:
		move_cpu_to_approach(hitter,staging,delta,speed)

func position_receive_support(delta: float) -> void:
	if last_player < 0 or team(last_player) == receiving_team: return
	if flight_kind not in ["serve","free","spike","dump","block"]: return
	if cpu_choice < 0 or (not net_hit.is_empty() and not touched_tape): return
	var primary := cpu_choice
	if not spectator and receiving_team == 0 and is_finite(platforms[0].pressed_at) and not blocks.has(0):
		primary = 0
	if team(primary) != receiving_team or blocks.has(primary): return
	var frame := frames[receiving_team]
	var passer := players[primary]
	var support := pass_support_receiver(primary)
	if is_human(support) or animated[support] or is_finite(platforms[support].pressed_at): return
	var receive_at := dig_intercept(primary) if defensive_ball() else arrival(1.10)
	var lead := receive_at-elapsed
	if lead <= 0.08: return
	var contact := frame.to_local(path_point(receive_at))
	if contact.z >= Net.NET_Z: return
	var actor := players[support]
	var primary_gap := (contact-passer.position).slide(Vector3.UP).length()
	var support_gap := (contact-actor.position).slide(Vector3.UP).length()
	if primary_gap > 0.62+lead*3.8 or support_gap < maxf(1.35,primary_gap+0.95): return
	var side := 1.0 if actor.position.x >= contact.x else -1.0
	var target := Vector3(clampf(contact.x+side*1.55,-3.85,3.85),PLAYER_GROUND_Y,clampf(contact.z+1.35,-1.35,2.35))
	if target.z <= actor.position.z+0.10: return
	move_cpu(support,frame.to_global(target),delta,2.7,contact-actor.position)

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

func position_overpass(delta: float) -> bool:
	if last_player < 0 or (flight_kind not in ["pass","set"] and overpass_flight != flight_number): return false
	var side := 1-team(last_player)
	var frame := frames[side]
	var crossing := INF
	if net_hit.is_empty():
		var local_velocity := frame.global_basis.inverse()*velocity
		if local_velocity.z >= -0.05: return false
		crossing = (Net.NET_Z-origin.z)/velocity.z+0.085/absf(velocity.z)
	else:
		var release: Vector3 = frame.to_local(net_hit.release_point)
		if release.z >= Net.NET_Z or release.y < Net.NET_TOP: return false
		crossing = float(net_hit.release_time)
	if crossing-elapsed > 1.0: return false
	var at := INF
	var point := Vector3.ZERO
	for delay in [0.0,0.045,0.09,0.145,0.21,0.28,0.36,0.45,0.55]:
		var sample := crossing+float(delay)
		if sample < elapsed+0.14 or sample >= flight_end(): continue
		var trial := frame.to_local(path_point(sample))
		if absf(trial.x) >= Net.NET_HALF_WIDTH-Net.RADIUS or trial.z < Net.NET_Z-1.28 or trial.z > Net.NET_Z-0.045: continue
		if trial.y < Net.NET_TOP+Net.RADIUS or trial.y > 2.55+block_vertical*0.0254: continue
		at = sample
		point = trial
		break
	if not is_finite(at): return false
	var target := Vector3(clampf(point.x,-4.30,4.30),PLAYER_GROUND_Y,clampf(point.z-0.32,2.45,3.55))
	var world_target := frame.to_global(target)
	if overpass_plan_flight != flight_number:
		overpass_plan_flight = flight_number
		overpass_player = (0 if player_blocks else 1) if side == 0 and not spectator else nearest_on_team(side,world_target)
	var hitter := overpass_player
	var eta := at-elapsed
	defender_assignment[side] = hitter
	if not is_human(hitter):
		move_cpu(hitter,world_target,delta,9.2,Vector3.BACK,true,false)
		var approach_gap := (players[hitter].position-target).slide(Vector3.UP).length()
		if eta <= 0.46 and approach_gap <= 0.72 and cpu_spike_has_lane(point):
			start_block(hitter,eta,false,true)
	var opposing := 1-side
	var opposing_frame := frames[opposing]
	var opposing_target := opposing_frame.to_local(world_target)
	opposing_target.z = 3.42
	var wall := opposing_frame.to_global(opposing_target)
	var blocker := (0 if player_blocks else 1) if opposing == 0 and not spectator else nearest_on_team(opposing,wall)
	defender_assignment[opposing] = blocker
	if not is_human(blocker):
		move_cpu(blocker,wall,delta,6.8,Vector3.INF,true)
		if blocks.has(hitter) and blocks[hitter].overpass_swing and eta >= 0.10 and eta <= 0.31 and absf(players[blocker].position.x-opposing_target.x) <= 0.65:
			start_block(blocker,eta+0.075)
	return true

func position_defense(delta: float) -> void:
	if position_overpass(delta): return
	if flight_kind not in ["serve","pass","set","free"]: return
	var hitter_side := receiving_team
	var defense_side := 1-hitter_side
	var frame := frames[defense_side]
	var driver := attackers[hitter_side]
	var tracking_set := flight_kind == "set" and expected_hitter >= 0
	var threat := frames[hitter_side].to_global(driver.rally_set_target) if tracking_set else path_point(arrival(2.0))
	var second_ball := flight_kind == "pass" and possession_team == hitter_side and touches == 1
	var second_ball_eta := INF
	if second_ball:
		var setter := setter_for_pass(last_player)
		var attack_frame := frames[hitter_side]
		var setter_approaching: bool = driver.enabled and driver.setter == players[setter] and (driver.approach_jump_queued or driver.jump.active)
		var jump_setting: bool = set_jumps[setter].active
		var contact_time := arrival(hand_contact_height(2)) if jump_setting else arrival(driver.set_contact_height())
		var contact := path_point(contact_time)
		var contact_depth := attack_frame.to_local(contact).z
		if setter_approaching:
			threat = attack_frame.to_global(driver.rally_set_target)
			second_ball_eta = contact_time-elapsed
			if is_finite(driver.approach_expected_hit_at):
				second_ball_eta = driver.approach_expected_hit_at-driver.clock
		elif jump_setting and contact_depth >= 2.55 and contact_depth <= Net.NET_Z:
			threat = contact
			second_ball_eta = contact_time-elapsed
		else:
			var hitter_x := players[hitter_for_set(setter)].position.x
			if not is_human(setter):
				hitter_x = move_toward(hitter_x,set_pin_for(setter).x,0.65)
			threat = attack_frame.to_global(Vector3(hitter_x,0.04,3.20))
	var x := frame.to_local(threat).x
	var first := defense_side*team_size
	var near: int = defender_assignment[defense_side]
	if defense_side == 0 and not spectator:
		near = 0 if player_blocks else 1
	elif near < 0:
		near = first if absf(players[first].position.x-x) < absf(players[first+1].position.x-x) else first+1
		if team_size == 3:
			near = nearest_on_team(defense_side,frame.to_global(Vector3(x,0.04,3.42)))
	defender_assignment[defense_side] = near
	var depth := -2.15
	var cover := -x*0.48
	var deep := near^1
	if team_size == 3:
		deep = deep_defenders[defense_side]
		if deep < 0 or deep == near:
			deep = nearest_on_team(defense_side,frame.to_global(Vector3(cover,0.04,depth)),near)
			deep_defenders[defense_side] = deep
			support_lanes[defense_side] = 3.6 if cover < 0.0 else -3.6
	var remaining := INF
	if tracking_set:
		var attack := frame.to_local(threat)
		var repeated := repeat_shot_read(defense_side,attack.x)
		var line_goal := Vector3(attack.x,0.0,depth)
		var cross_goal := Vector3(clampf(-attack.x*0.80,-3.7,3.7),0.0,depth)
		var sideline := signf(attack.x) if absf(attack.x) > 0.20 else (1.0 if players[near].position.x >= 0.0 else -1.0)
		var line_x := clampf(lane_at_depth(attack,line_goal,3.42)+sideline*0.25,-4.15,4.15)
		var cross_x := lerpf(lane_at_depth(attack,cross_goal,3.42),attack.x,0.44)
		if block_lane_flight[defense_side] != flight_number:
			var line_cost := absf(players[near].position.x-line_x)+0.35*absf(players[deep].position.x-cross_goal.x)
			var cross_cost := absf(players[near].position.x-cross_x)+0.35*absf(players[deep].position.x-line_goal.x)
			var prefer_line: bool = (block_calls[defense_side]+defense_side)%3 == 0
			if not is_human(near):
				var lane := cpu_policy.choose(defense_side,"block lane",[0,-1,1],0)
				if lane != 0: prefer_line = lane > 0
				if repeated.y >= 0.50:
					prefer_line = absf(repeated.x-line_goal.x) < absf(repeated.x-cross_goal.x)
			var preferred_cost := line_cost if prefer_line else cross_cost
			var alternate_cost := cross_cost if prefer_line else line_cost
			block_line[defense_side] = prefer_line if preferred_cost <= alternate_cost+1.8 else not prefer_line
			block_calls[defense_side] += 1
			block_lane_flight[defense_side] = flight_number
		var take_line: bool = block_line[defense_side]
		if is_human(near):
			take_line = absf(players[near].position.x-line_x) <= absf(players[near].position.x-cross_x)
		x = line_x if take_line else cross_x
		if not is_human(near):
			var read: Vector2 = block_crossing_reads[defense_side].get(shot_read_zone(attack.x),Vector2.ZERO)
			var learned_x := attack.x+read.x
			x += clampf(learned_x-x,-0.80,0.80)*smoothstep(1.0,5.0,read.y)
		cover = cross_goal.x if take_line else line_goal.x
		if not is_human(deep):
			cover = learned_cover(defense_side,attack.x,cover)
			if repeated.y > 0.0:
				var intercept := attack.lerp(Vector3(repeated.x,0.0,repeated.z),0.80)
				cover = lerpf(cover,intercept.x,repeated.y*0.82)
				depth = lerpf(depth,clampf(intercept.z,-3.85,1.10),repeated.y*0.82)
		var hit_at: float = driver.approach_expected_hit_at
		update_air_attack_read(expected_hitter,near,driver)
		if is_finite(driver.swing_drive_started):
			hit_at = driver.swing_drive_started+driver.swing_drive_duration*0.95
			var shot: Vector3 = frame.to_local(frames[hitter_side].to_global(driver.swing_aim))
			var crossing := lane_at_depth(attack,shot,3.42)
			if not is_human(near):
				x += clampf(crossing-x,-0.60,0.60)*0.60
		if attack_aim_flight == flight_number or is_finite(driver.swing_drive_started):
			var read := frame.to_local(frames[hitter_side].to_global(driver.swing_aim))
			var front_limit := 0.25 if is_finite(driver.swing_drive_started) else -1.30
			var read_depth := clampf(lerpf(attack.z,read.z,0.72),-3.25,front_limit)
			var read_x := lane_at_depth(attack,read,read_depth)
			cover += clampf(read_x-cover,-2.30,2.30)
			depth = lerpf(depth,read_depth,0.72)
		if is_finite(hit_at): remaining = hit_at-driver.clock+0.045
		var wall := Vector3(x,0.04,3.42)
		if is_human(near) and players[near].position.z > 2.7: wall = players[near].position
		var shadow := lane_at_depth(attack,wall,depth)
		if absf(cover-shadow) < 0.88:
			if repeated.y >= 0.50:
				var preferred_side := -1.0 if repeated.x < shadow else 1.0
				cover = shadow+preferred_side*0.90
				if absf(cover) > 4.05: cover = shadow-preferred_side*0.90
			else:
				cover = dig_cover_x(frame,threat,frame.to_global(wall),depth,players[deep].position.x)
	pocket_x[defense_side] = cover
	if not is_human(near) and not blocks.has(near):
		var target := frame.to_global(Vector3(clampf(x,-4.15,4.15),0.04,3.42))
		move_cpu(near,target,delta,8.6 if tracking_set else 7.6,Vector3.INF,true)
		var attack_ready := remaining >= -0.04 and remaining <= 0.41
		var dump_ready := second_ball_eta >= -0.06 and second_ball_eta <= 0.30
		if absf(players[near].position.x-clampf(x,-4.15,4.15)) < 0.62 and (attack_ready or dump_ready):
			var timing := remaining if attack_ready else second_ball_eta+0.035
			start_block(near,timing,dump_ready)
	if not is_human(deep) and not blocks.has(deep) and not set_jumps[deep].active:
		move_cpu(deep,frame.to_global(Vector3(clampf(cover,-4.05,4.05),0.04,depth)),delta)
	if team_size == 3:
		var support := nearest_on_team(defense_side,frame.to_global(Vector3.ZERO),near,deep)
		if not is_human(support) and not blocks.has(support) and not set_jumps[support].active:
			var opposite := lerpf(cover,support_lanes[defense_side],0.78)
			move_cpu(support,frame.to_global(Vector3(opposite,0.04,depth+1.05)),delta)

func update_air_attack_read(hitter: int, blocker: int, driver: Node3D) -> void:
	if is_human(hitter) or not driver.jump.active: return
	if is_finite(driver.swing_drive_started):
		var drive_age: float = driver.clock-driver.swing_drive_started
		if drive_age > minf(0.045,driver.swing_drive_duration*0.28): return
	if driver.jump.elapsed <= driver.jump.load_duration()+0.018: return
	var first_read := attack_aim_flight != flight_number
	if not first_read and match_clock-attack_aim_read_at < 0.070: return
	var frame := frames[team(hitter)]
	var wall := frame.to_local(players[blocker].global_position)
	if blocks.has(blocker) and blocks[blocker].hands.size() == 2:
		var hands: Array = blocks[blocker].hands
		wall.x = frame.to_local((hands[0]+hands[1])*0.5).x
	if wall.z > Net.NET_Z+1.60:
		wall = Vector3.INF
	else:
		wall.z = clampf(wall.z-0.36,Net.NET_Z+0.10,Net.NET_Z+0.55)
	var contact: Vector3 = driver.approach_intercept if driver.approach_intercept.is_finite() else driver.rally_set_target
	if contact.y < Net.NET_TOP: contact.y = driver.set_contact_height()
	var previous: Vector3 = Vector3.INF if first_read else driver.swing_aim
	driver.swing_aim = choose_shot(hitter,contact,wall,previous)
	attack_aim_flight = flight_number
	attack_aim_read_at = match_clock

func lane_at_depth(from: Vector3, to: Vector3, depth: float) -> float:
	var span := to.z-from.z
	if absf(span) < 0.02: return to.x
	return lerpf(from.x,to.x,(depth-from.z)/span)

func update_action_labels() -> void:
	for index in players.size():
		key_labels[index].global_position = players[index].global_position+Vector3.UP*(2.43 if is_human(index) else 2.18)
		key_labels[index].visible = (not spectator or drill_pass_target.is_finite()) and players[index].visible and match_clock < key_until[index]
		animation_labels[index].global_position = key_labels[index].global_position+Vector3.UP*0.32
		var animation: String = recoveries.get(index,{}).get("animation",receive_animation_labels.get(index,""))
		animation_labels[index].text = animation
		animation_labels[index].visible = (not spectator or drill_pass_target.is_finite()) and players[index].visible and not animation.is_empty()

func update_player_guide() -> void:
	player_label.global_position = human.global_position+Vector3.UP*2.17
	player_label.visible = not spectator
	update_action_labels()
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
		var contact_at: float = driver.descending_time(origin,velocity,driver.set_contact_height())
		start = flight_point(clampf(contact_at,0.0,duration))
		target = driver.swing_aim
		var travel := target-start
		var air_time := maxf(0.1,travel.slide(Vector3.UP).length()/24.0)
		launch = travel/air_time+Vector3.UP*0.5*Flight.GRAVITY*air_time
	elif receiving_team == 0 and possession_team == 0 and touches == 1 and human_can_set():
		target = set_pin_for(0)
		launch = attackers[0].set_toward_pin(start,target,maxf(maxf(3.60,start.y+0.18),pass_height),attackers[0].set_contact_height())
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

func hand_over_overpass(side: int) -> void:
	var driver := attackers[team(last_player)]
	if driver.enabled and driver.stage == driver.Stage.SET: driver.stage = driver.Stage.MISS
	expected_hitter = -1
	receiving_team = side
	flight_kind = "free"
	stroke = "Overpass"
	overpass_flight = flight_number
	reset_receives()

func begin_ball_bounce() -> void:
	bounce_origin = path_point(flight_end())
	bounce_origin.y = Flight.FLOOR
	var before_impact := path_point(maxf(0.0,flight_end()-0.015))
	var impact_velocity := (bounce_origin-before_impact)/0.015
	play_floor_impact(absf(impact_velocity.y))
	bounce_velocity = impact_velocity.slide(Vector3.UP)*0.37
	bounce_velocity.y = maxf(absf(impact_velocity.y)*0.64,2.10)*sqrt(1.25)
	bounce_end = Flight.landing_time(bounce_origin,bounce_velocity)

func play_floor_impact(speed: float, rebound := false) -> void:
	if StorySession.attack_ball_audio_muted: return
	var strength := smoothstep(2.0,11.0,speed)
	floor_audio.volume_db = lerpf(-10.0,1.5,strength)-(6.0 if rebound else 0.0)
	floor_audio.pitch_scale = lerpf(1.04,0.96,strength)
	floor_audio.play()

func check_floor(previous: float) -> void:
	if held_ball: return
	if not crossed_net and net_hit.is_empty():
		var before := path_point(previous)
		var after := path_point(minf(elapsed,flight_end()))
		if (before.z-Net.NET_Z)*(after.z-Net.NET_Z) < 0.0:
			crossed_net = true
			var crossing := before.lerp(after,inverse_lerp(before.z,after.z,Net.NET_Z))
			if absf(crossing.x) > Net.NET_HALF_WIDTH:
				award(1-team(last_player),"Outside the antenna")
				return
			if crossing.y < Net.NET_TOP:
				award(1-team(last_player),"Under the net")
				return
			if flight_kind in ["pass","set"]:
				hand_over_overpass(1-team(last_player))
				trace.write("overpass",match_clock,{"crossing":crossing,"receiver":receiving_team})
	if elapsed < flight_end(): return
	begin_ball_bounce()
	var point := bounce_origin
	var in_bounds := absf(point.x) <= 4.53 and point.z >= -5.03 and point.z <= 13.03
	if in_bounds:
		var court_side := 0 if point.z < Net.NET_Z else 1
		var reason := "Into the net" if not net_hit.is_empty() and not net_hit.rollover else "Ball down"
		if reason == "Ball down" and flight_kind == "spike" and last_player >= 0 and court_side != team(last_player):
			record_uncovered_shot(court_side,point)
		award(1-court_side,reason)
	else:
		award(1-team(last_player),"Out")

func toggle_replay(prefer_current := false) -> void:
	replay.toggle(self,prefer_current or phase in [Phase.DEAD,Phase.FINISHED])

func pose_serve_receive_wait() -> void:
	var weight := smoothstep(0.0,0.24,ready_age)
	if serve_pending:
		var release: float = serve.toss_release_time() if serve.has_method("toss_release_time") else 0.0
		var finish: float = minf(release+0.25,serve.contact_time())
		weight *= 1.0-smoothstep(minf(release,finish-0.01),finish,serve.swing_time)
	for index in players.size():
		if team(index) == service_team: continue
		var actor := players[index]
		actor.animator.seek(0.0,true)
		if weight <= 0.001: continue
		var bump := platforms[index]
		bump.knee_bend_depth = (0.055 if index%team_size == 2 else 0.14)*weight
		bump.apply_knee_bend()
		bump.knee_bend_depth = 0.0
		var rig: Skeleton3D = actor.skeleton
		var author: RefCounted = actor.get_pose_author()
		var pose: Array[Transform3D] = []
		for bone in rig.get_bone_count(): pose.append(rig.get_bone_pose(bone))
		var scale_: float = rig.global_basis.y.length()
		for side in ["l","r"]:
			var thigh: Vector3 = author.point(pose,"thigh_"+side)
			var knee: Vector3 = author.point(pose,"calf_"+side)
			var outward := 1.0 if side == "l" else -1.0
			var target := thigh.lerp(knee,0.82)+Vector3(outward*0.04,0.035,0.075)/scale_
			author.limb(pose,"upperarm_"+side,"lowerarm_"+side,"hand_"+side,target,
				Vector3(outward*0.6,-0.4,-0.2),weight*0.85)
			for name_ in ["upperarm_","lowerarm_","hand_"]:
				var bone := rig.find_bone(name_+side)
				rig.set_bone_pose_rotation(bone,pose[bone].basis.get_rotation_quaternion())

func tick_match(delta: float, controls: RefCounted) -> void:
	if replay.active:
		replay.step(self,delta)
		return
	delta *= live_speed
	var previous_rallies := rallies
	step_match(delta,controls)
	if (phase != Phase.FINISHED or dead_age <= 2.0) and match_clock+0.0005 >= next_replay_sample:
		replay.record(self)
		next_replay_sample = match_clock+1.0/60.0
	if not cpu_policy.demo_recording: return
	var point_finished := rallies > previous_rallies
	if phase == Phase.LIVE:
		review.observe(self,delta)
	elif phase == Phase.READY and serve_pending:
		review.observe_motion(self,delta)
	for motion in review.take_motion(match_clock,point_finished):
		report_review_evidence(motion)
	if point_finished:
		var evidence := review.finding(last_point)
		if not evidence.is_empty(): report_review_evidence(evidence)
		var bad_set := review.unplayed_set(self)
		if not bad_set.is_empty(): report_review_evidence(bad_set)

func report_review_evidence(evidence: Dictionary) -> void:
	var point := rallies+1 if phase in [Phase.READY,Phase.LIVE] else rallies
	evidence["point"] = point
	var path := review.save_finding(self,evidence)
	trace.write("automatic_review_marker",match_clock,{"point":point,"evidence":evidence,"replay":path},true)
	review_flagged.emit(str(evidence.type))

func step_match(delta: float, controls: RefCounted) -> void:
	match_clock += delta
	if trace.file != null and match_clock >= trace.next_sample: trace.sample(match_clock,trace_snapshot())
	animated.fill(false)
	update_player_guide()
	if phase in [Phase.DEAD,Phase.FINISHED]:
		dead_age += delta
		settle_point(delta)
		if is_finite(dead_flight_from) and bounce_end <= 0.0:
			var flight_time := minf(dead_flight_from+dead_age,flight_end())
			ball.global_position = path_point(flight_time)
			if flight_time >= flight_end():
				bounce_start = dead_age
				begin_ball_bounce()
		if bounce_end > 0.0:
			var time := minf(dead_age-bounce_start,bounce_end)
			ball.global_position = bounce_origin+bounce_velocity*time+Vector3.DOWN*0.5*Flight.GRAVITY*time*time
			if time >= bounce_end and dead_age-delta < bounce_start+bounce_end:
				play_floor_impact(absf(bounce_velocity.y-Flight.GRAVITY*bounce_end),true)
		if phase == Phase.DEAD and (not is_finite(dead_flight_from) or bounce_end > 0.0) and dead_age >= maxf(0.85,bounce_start+bounce_end+0.15):
			var settling := false
			for index in players.size(): settling = settling or owns_action(index)
			if not settling or dead_age >= 1.55: begin_point()
		elif phase == Phase.FINISHED and auto_rematch and spectator and dead_age >= maxf(3.0,bounce_start+bounce_end+0.35):
			reset_match()
		return
	if phase == Phase.READY:
		ready_age += delta
		if not is_human(server_index()) and ready_age >= 0.65: start_serve()
		pose_serve_receive_wait()
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
		var serve_spin := Vector3.INF
		if serve.has_method("reception_spin_vector"):
			serve_spin = serve.global_basis*serve.reception_spin_vector()
		launch(serve.to_global(serve.origin),serve.global_basis*serve.velocity,"serve",server_index(),serve.reception_spin_rps(),-1,Vector3.ZERO,Vector3.INF,serve_spin)
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
		if not StorySession.attack_ball_audio_muted: net_audio.play()
		var release: Vector3 = net_hit.release_point
		var side_after_tape := 0 if release.z < Net.NET_Z else 1
		if side_after_tape == receiving_team:
			if spectator or not is_finite(platforms[0].pressed_at): reset_receives()
			else: next_touch_cue = INF
		else:
			if flight_kind in ["pass","set"] and side_after_tape != team(last_player):
				hand_over_overpass(side_after_tape)
			else:
				receiving_team = side_after_tape
				reset_receives()
	advance_ball_spin(delta)
	var player_attacking: bool = attackers[0].enabled and attackers[0].setter == human and attackers[0].jump.active
	var serving_human: bool = serve.player == human and not serve.can_run_after_contact()
	advance_set_jumps(delta)
	advance_recoveries(delta)
	var diving: bool = platforms[0].low_save.active and not platforms[0].low_save.finished(elapsed)
	if not spectator and not blocks.has(0) and not player_attacking and not serving_human and not set_jumps[0].active and not diving and not recoveries.has(0):
		controls.read_pace_input()
		var motion: Vector2 = controls.movement_input()
		if serve.player == human:
			if motion.length() > 0.05: serve.moved_after_contact = true
			if serve.moved_after_contact:
				human.position.y = move_toward(human.position.y,PLAYER_GROUND_Y,delta*1.25)
		var bump := platforms[0]
		var mobility: float = bump.movement_scale(elapsed,next_touch_cue,ball.global_position)
		if is_finite(bump.pressed_at) and (is_finite(bump.pose_started_at) or next_touch_cue-elapsed <= 0.18):
			controls.sprint_requested = false
			mobility = minf(mobility,0.45)
		animated[0] = true
		controls.move_player(motion,delta,false,ball.global_position,mobility,0.15,true,3.42,0.0,0.0,true)
	advance_attackers(delta)
	if flight_number != current_flight: return
	position_attack(delta)
	position_defense(delta)
	tick_blocks(delta,previous)
	if flight_number != current_flight or phase != Phase.LIVE: return
	held_ball = false
	tick_receive(delta,previous)
	if flight_number != current_flight or phase != Phase.LIVE: return
	position_receive_support(delta)
	try_foot_save(previous)
	if flight_number != current_flight or phase != Phase.LIVE: return
	deflect_defender_body(previous)
	if flight_number != current_flight or phase != Phase.LIVE: return
	advance_idle_players(delta)
	check_floor(previous)
	if phase == Phase.LIVE:
		if spectator:
			info.text = "%s | %s court" % [stroke,"Blue" if receiving_team == 0 else "Orange"]
			return
		var cue := "Opponent's ball"
		if receiving_team == 0:
			cue = "Hold Space to attack" if expected_hitter == 0 else ("Set to your teammate" if possession_team == 0 and touches == 1 and human_can_set() else "Receive or cover")
		elif flight_kind == "set": cue = "Move up to block | Space" if player_blocks else "Teammate blocking | Cover the court"
		info.text = "%s | %s" % [stroke,cue]

func trace_snapshot() -> Dictionary:
	var actors: Array = []
	for index in players.size():
		actors.append({"position":Trace.json_value(players[index].global_position),"yaw":players[index].rotation.y,
			"key":key_labels[index].text if match_clock < key_until[index] else "",
			"animation":animation_labels[index].text,
			"contact":Trace.json_value(platforms[index].contact_check)})
	return {"phase":phase,"score":score,"flight":flight_kind,"ball":ball.global_position,"velocity":velocity,
		"receiving_team":receiving_team,"last_touch":last_player,"touches":touches,"set_apex":last_set_apex,"set_zone":SET_ZONES.find(called_pin.x)+1,
		"blocker":defender_assignment,"takes_line":block_line,"dig_pocket":pocket_x,"players":actors}

func mark_trace() -> bool:
	if trace.file == null: return false
	var snapshot: Dictionary = replay.frames[replay.index].trace.duplicate(true) if replay.active else trace_snapshot()
	snapshot["last_point"] = last_point
	snapshot["point"] = rallies if phase != Phase.LIVE else rallies+1
	var samples := replay.frames if replay.active else replay.current
	if replay.active:
		snapshot["replay_time"] = replay.clock
		snapshot["recorded_at"] = replay.frames[replay.index].time
	elif phase == Phase.READY and not replay.previous.is_empty() and not last_point.is_empty():
		samples = replay.previous
		snapshot["recorded_at"] = last_point.time
	var path := review.save_finding(self,{"type":"Player debug marker","time":snapshot.get("recorded_at",match_clock)},samples,Trace.MARKER_REPLAYS)
	if not path.is_empty(): snapshot["replay"] = path
	trace.write("player_marker",match_clock,snapshot,true)
	return true

func _exit_tree() -> void:
	trace.close(match_clock)
