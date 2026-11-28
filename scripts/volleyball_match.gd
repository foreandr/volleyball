extends Node3D

const PromptControls = preload("res://scripts/xbox_controls.gd")

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
const GroundMovement = preload("res://scripts/player_ground_controls.gd")
const Net = preload("res://scripts/net_collision.gd")
const BallPreview = preload("res://scripts/animation_ball_preview.gd")
const Court = preload("res://scripts/preview_court.gd")
const GymPaths = preload("res://scripts/tryout_paths.gd")
var gym_contacts := preload("res://scripts/gym_physics.gd").new()
var court_velocities := {}
var movement_times := {}
const Footwork = preload("res://scripts/directional_footwork.gd")
const CONTACT_SOUND = preload("res://assets/audio/pass_contact.wav")
const SPIKE_SOUND = preload("res://assets/audio/hand_gym_01.wav")
const ZONE_FOUR := Vector3(3.75,.065,3.20)
const SET_ZONES := [-3.75,-2.50,-1.25,0.0,1.25,2.50,3.75]
const SERVES := [
	preload("res://scripts/underhand_serve.gd"),
	preload("res://scripts/standing_float_serve.gd"),
	preload("res://scripts/jump_float_serve.gd"),
	preload("res://scripts/spin_serve.gd"),
]
const TOPSPIN_SERVE := 3
const SERVICE_START := [-6.40,-6.40,-7.4,-8.15]
const CpuShots = preload("res://scripts/cpu_attack_shots.gd")
const CpuPolicy = preload("res://scripts/cpu_policy.gd")
const WIN_SCORE := 15
const CPU_COURT_FRONT_LIMIT := 3.43
const RECOVERY_TIME := 0.32
const ForearmDrive = preload("res://scripts/reception_pass_drive.gd")
const FAST_DIG_ELBOW_DURATION := preload("res://scripts/reception_pass_drive.gd").FAST_DIG_ELBOW_DURATION
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
var first_ball_source := ""
var previous_attacker := -1
var attack_decision := ""
var set_decision := ""
var actual_tempo := -1
var human: Node3D
var saved_transform: Transform3D
var saved_callback: int
var saved_arrows: bool
var displayed_stamina := -1
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
var show_pass_trajectory:=true
var displayed_flight:=-1
var flight_guide:=MeshInstance3D.new()
var cpu_reception:=preload("res://scripts/match_manual_reception.gd").new()
var manual: Node3D
var replay_meter:Dictionary={}
var indicators: Control
var serve: Node3D
var ball_sound_enabled := true
var touch_audio: AudioStreamPlayer
var spike_audio: AudioStreamPlayer
var net_audio: AudioStreamPlayer
var floor_audio: AudioStreamPlayer
var serve_style := 0
var cpu_serve_override := -1
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
var net_ripple := {}
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
var court_boundary:=preload("res://scripts/court_boundary_flash.gd").new()
var spike_strength := 1.0
var serve_pending := false
var crossed_net := false
var next_touch_cue := INF
var touched_tape := false
var stroke := ""
var receive_prepared := false
var roster_active := false
var team_size := 2 # Home count retained for legacy replay files.
var away_size := 2
var side_names := ["Blue", "Orange"]
var exhibition := false
var win_score := WIN_SCORE
var auto_rematch := false
var review := Review.new()
var rally_setter := -1
var last_set_to: Dictionary[int,int] = {}
var rally_hitter := -1
var deep_defenders := [-1,-1]
var support_lanes := [0.0,0.0]

var held_input := preload("res://scripts/held_input_hud.gd").new()

func configure(actor: Node3D, board: Label, status: Label, build := "", players_per_team := 2, learn_from_demo := false, mirror_blue_right := true, away_count := 0) -> void:
	if cpu_reception.get_parent()==null: add_child(cpu_reception)
	if held_input.get_parent()==null: add_child(held_input)
	team_size = clampi(players_per_team,2,6)
	away_size = clampi(away_count,2,6) if away_count > 0 else team_size
	roster_active = (exhibition or not spectator) and StorySession.offline_roster.size() == team_size + away_size
	key_until.resize(team_size + away_size)
	jump_set_started.resize(team_size + away_size)
	animated.resize(team_size + away_size)
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
		for slot in count_for(side):
			var avatar := actor if side == 0 and slot == 0 else Player.new()
			if avatar != actor:
				avatar.name = ("Teammate" if slot == 1 else "Teammate2") if side == 0 else "Opponent%d" % (slot+1)
				avatar.team_color = Color("287fda") if side == 0 else Color("d9874e")
				if side == 0 and slot == 1 and mirror_blue_right and not roster_active:
					avatar.handedness = "Left"
					avatar.mirror_animation = true
				frame.add_child(avatar)
			var setup_side := 1-side if exhibition and StorySession.offline_controller == 1 else side
			if roster_active:
				var roster_index := (0 if setup_side == 0 else StorySession.offline_size)+slot if exhibition else first_on(side)+slot
				avatar.apply_profile(StorySession.offline_roster[roster_index])
				avatar.team_color = StorySession.kit_colors[setup_side]
				if avatar.kit_material: avatar.kit_material.albedo_color = avatar.team_color
			if not avatar.shirt_fabric:
				preload("res://scripts/practice_kit.gd").apply(avatar,false,setup_side*6+slot if exhibition else first_on(side)+slot,false)
			avatar.shirt_fabric.set_shader_parameter("fabric",avatar.team_color)
			if not avatar.skeleton.find_child("PracticeJointLimits",false,false):
				var turn_steps := preload("res://scripts/ground_turn_steps.gd").new()
				turn_steps.actor=avatar
				avatar.skeleton.add_child(turn_steps)
				var limits := preload("res://scripts/practice_joint_limits.gd").new()
				limits.name="PracticeJointLimits"
				avatar.skeleton.add_child(limits)
			avatar.animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			avatar.get_node("DirectionArrows").hide()
			players.append(avatar)
			footwork.append(Footwork.new(avatar))
			avatar.play_action("forearm")
			var bump := Bump.new()
			bump.receive_front_limit = CPU_COURT_FRONT_LIMIT
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
		driver.configure_for_match(players[first_on(side)],hidden_status)
		driver.struck.connect(on_spike)
		driver.lift_lean_back_degrees = attack_lift_lean
		attackers.append(driver)
	ball = MeshInstance3D.new()
	ball.mesh = BallPreview.make_ball(StorySession.match_preference("ball_brand","Mikasa"))
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	ball.material_override = material
	add_child(ball)
	add_child(court_boundary)
	preload("res://scripts/ball_landing_marker.gd").attach(ball,func(): return path_point(flight_end()) if phase==Phase.LIVE and not replay.active else Vector3.INF)
	for avatar in players:
		avatar.limit_live_turns(replay)
		avatar.watch_ball(ball)
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
	flight_guide.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flight_guide)
	flight_guide.hide()
	show_pass_trajectory=StorySession.game_options.get_value("match","pass_trajectory",true)
	touch_audio = make_ball_audio(CONTACT_SOUND,3.0)
	spike_audio = make_ball_audio(SPIKE_SOUND,2.0)
	floor_audio = make_ball_audio(preload("res://assets/audio/floor_impacts.tres"),1.5)
	net_audio = Net.contact_sound()
	add_child(net_audio)
	if exhibition and not spectator:
		manual=preload("res://scripts/match_court_controls.gd").new()
		add_child(manual)
		manual.configure(self)
	if six_on_six(): build_six_lineups()
	if learn_from_demo or six_on_six(): reset_match()
	else: begin_point()

	indicators = preload("res://scripts/tryout_player_ring.gd").new()
	update_indicator_participants()
	if manual: indicators.match_meter=func(): return replay_meter if replay.active else manual.timing()
	add_child(indicators)

func update_indicator_participants() -> void:
	if not indicators: return
	if exhibition: indicators.participants=[] if spectator else [human]
	else: indicators.participants=players

func stop() -> void:
	if replay.active: toggle_replay()
	human.transform = saved_transform
	human.animator.callback_mode_process = saved_callback
	human.get_node("DirectionArrows").visible = saved_arrows
	queue_free()

func team(index: int) -> int:
	return 0 if index < team_size else 1

func count_for(side: int) -> int:
	return team_size if side == 0 else away_size

func first_on(side: int) -> int:
	return 0 if side == 0 else team_size

func slots_for(side: int) -> Array:
	return range(first_on(side),first_on(side)+count_for(side))

func partner_of(index: int) -> int:
	var first := first_on(team(index))
	return first + (1 if index == first else 0)

func nearest_on_team(side: int, target: Vector3, exclude := -1, also_exclude := -1) -> int:
	var best := -1
	var best_cost := INF
	for index in slots_for(side):
		if index == exclude or index == also_exclude: continue
		var cost := players[index].global_position.distance_squared_to(target)
		if blocks.has(index) or recoveries.has(index): cost += 2.0
		if cost < best_cost:
			best = index
			best_cost = cost
	return best

func setter_for_pass(passer: int) -> int:
	if six_on_six(): return choose_setter(team(passer),passer)
	if count_for(team(passer)) == 2: return partner_of(passer)
	if rally_setter >= 0 and team(rally_setter) == team(passer) and rally_setter != passer:
		return rally_setter
	return choose_setter(team(passer),passer)

func choose_setter(side:int,passer:int) -> int:
	if six_on_six() and lineup_roles.size()==2:
		for slot in count_for(side):
			var i:=first_on(side)+slot
			if lineup_role(passer)==0:
				if active_identities.get(i,-1)==6: return i
			elif lineup_role(i)==0: return i
	return nearest_on_team(side,path_point(arrival(1.92)),passer)

# Team-local +X is the left pin. A back-row outside starts the pipe behind the attack line.
func back_row_setter(index:int) -> bool:
	return six_on_six() and lineup_role(index)==0 and setter_zones[team(index)] in [1,6,5]

func excluded_from_attack(index:int) -> bool:
	return back_row_setter(index) or (six_on_six() and active_identities.get(index,-1)==6)

func attack_lane_for(index:int) -> Vector3:
	var role:=lineup_role(index)
	var rotation:=setter_zones[team(index)]
	var front:=Formation.zone(role,rotation) in [2,3,4]
	match Formation.attack_route(role,rotation):
		"left": return ZONE_FOUR
		"right":
			if front: return Vector3(-3.75,.065,3.20)
		"pipe": return Vector3(pipe_gap[team(index)],.065,.85)
		"middle": return Vector3(1.30 if middle_31[team(index)] else 0.,.065,3.30)
	return Vector3.INF

func front_middle(side:int) -> int:
	var roles:=lineup_roles[side]
	var middle:=2 if Formation.zone(2,setter_zones[side]) in [2,3,4] else 5
	return first_on(side)+roles.find(middle)

func middle_showing_quick(side:int) -> bool:
	var i:=front_middle(side)
	return players[i].position.y>PLAYER_GROUND_Y+.075 and (quick_flight[side]==flight_number or is_human(i))

static func space_middle_from_setter(lane:Vector3,meet:Vector3,runner_x:float) -> Vector3:
	if meet.z>=2.55 or absf(lane.x-meet.x)>=1.50: return lane
	var left:=meet.x+1.50
	var right:=meet.x-1.50
	var prefer_left:=left<=2.40 and (right< -2.40 or absf(runner_x-left)<absf(runner_x-right))
	lane.x=left if prefer_left else right
	return lane

func prepare_middle_quick(side:int,delta:float) -> void:
	if not setter_can_run_middle[side] or quick_flight[side]==flight_number: return
	var i:=front_middle(side)
	if yielding.has(i) or interrupted_hitters.has(i) or is_human(i) or i==rally_setter or owns_action(i) or recoveries.has(i): return
	var actor:=players[i]
	var lane:=attack_lane_for(i)
	var cue:=next_touch_cue if is_finite(next_touch_cue) else arrival(hand_contact_height(2))
	var remaining:=cue-elapsed
	var meet:=frames[side].to_local(path_point(cue))
	lane=space_middle_from_setter(lane,meet,actor.position.x)
	var plant:=lane-Vector3.BACK*1.65
	var gap:=(plant-actor.position).slide(Vector3.UP).length()
	if remaining>.55 or gap>1.45:
		move_cpu_to_approach(i,plant,delta,6.4)
		return
	if remaining<-.05: return
	var jump:=set_jumps[i]
	jump.front_limit=3.45
	jump.attack_arm_lift=true
	var height:=jump_inches(i,attack_vertical,"Attack jump")*.0254
	var heading:=(lane-actor.position).slide(Vector3.UP).normalized()
	var steps:=3 if remaining>.34 else 2
	var lead:=.19 if steps==3 else 0.
	jump.begin(actor,Vector2(-heading.x,heading.z),lane,clampf(remaining-lead-.13,.08,.21),height,steps,false,.80,false,.38)
	jump.release()
	quick_actor[side]=i
	quick_lanes[side]=lane
	quick_flight[side]=flight_number

func choose_at_set_contact(setter:int,point:Vector3) -> void:
	var side:=team(setter)
	if active_identities.get(setter,-1)==6:
		rally_hitter=libero_outlet(setter)
		return
	read_pipe(side)
	if rally_hitter>=0 and (team(rally_hitter)!=side or rally_hitter==setter or interrupted_hitters.has(rally_hitter) or excluded_from_attack(rally_hitter)):
		rally_hitter=-1
	if side==0 and called_this_pass and rally_hitter==0 and not interrupted_hitters.has(0): return
	var in_system:bool=setter_can_run_middle[side] and point.z>=Net.NET_Z-3.
	var back_outside:=1 if Formation.zone(1,setter_zones[side]) in [1,5,6] else 4
	var pipe:=first_on(side)+lineup_roles[side].find(back_outside)
	var middle:=front_middle(side)
	var quick_ready:=in_system and middle_showing_quick(side) and middle!=setter and not interrupted_hitters.has(middle)
	var pipe_ready:=quick_ready and pipe_open[side] and pipe!=setter and pipe_runner_ready(pipe)
	if quick_ready and (rally_hitter==middle or (rally_hitter==pipe and not pipe_ready)):
		rally_hitter=middle
	elif pipe_ready and (rally_hitter<0 or rally_hitter==pipe or randf()<.25):
		rally_hitter=pipe
	elif rally_hitter==pipe or (rally_hitter==middle and not quick_ready) or rally_hitter<0:
		setter_can_run_middle[side]=in_system
		rally_hitter=-1
		rally_hitter=hitter_for_set(setter,quick_ready)

func pipe_runner_ready(index:int) -> bool:
	if interrupted_hitters.has(index) or yielding.has(index) or recoveries.has(index): return false
	var lane:=attack_lane_for(index)
	var runner:=players[index].position
	var runway:=lane.z-runner.z
	# A tempo-one pipe gives the outside time to plant and rise, not to cross into a new seam.
	return absf(runner.x-lane.x)<=.75 and runway>=.35 and runway<=2.1 and runner.z<=Net.NET_Z-3.

func read_pipe(side:int) -> void:
	var middle_x:=0.
	var pins:Array[float]=[]
	for i in slots_for(1-side):
		var role:=lineup_role(i)
		if Formation.zone(role,setter_zones[1-side]) not in [2,3,4]: continue
		var x:=frames[side].to_local(players[i].global_position).x
		if role in [2,5]: middle_x=x
		else: pins.append(x)
	var best:=-1.
	for pin in pins:
		var gap:=clampf((middle_x+pin)*.5,-1.8,1.8)
		var clearance:=absf(gap-middle_x)
		for outer in pins: clearance=minf(clearance,absf(gap-outer))
		if clearance>best:
			best=clearance
			pipe_gap[side]=gap
	pipe_open[side]=best>=1.05

func libero_outlet(setter:int) -> int:
	var side:=team(setter)
	var best:=-1
	var best_score:=-INF
	for i in slots_for(side):
		var role:=lineup_role(i)
		var lane:=Formation.attack_route(role,setter_zones[side])
		if lane not in ["left","right"] or not attack_lane_for(i).is_finite(): continue
		var score:float=-float(last_set_to.get(i,-1))
		if interrupted_hitters.has(i): score-=100000.
		if i==rally_hitter and not interrupted_hitters.has(i): return i
		if score>best_score:
			best=i
			best_score=score
	return best

func hitter_for_set(setter: int, allow_quick: bool = true) -> int:
	if active_identities.get(setter,-1)==6: return libero_outlet(setter)
	if count_for(team(setter)) == 2: return partner_of(setter)
	if manual and is_human(setter) and manual.lane>=0: return manual_target_hitter(setter)
	if rally_hitter >= 0 and not interrupted_hitters.has(rally_hitter) and team(rally_hitter) == team(setter) and rally_hitter != setter and not excluded_from_attack(rally_hitter):
		return rally_hitter
	var side := team(setter)
	if six_on_six():
		var hitters:Array[int]=[]
		for i in slots_for(side):
			if interrupted_hitters.has(i) or i==setter or not attack_lane_for(i).is_finite(): continue
			var role:=lineup_role(i)
			if role in [2,5] and (not allow_quick or not setter_can_run_middle[side]): continue
			if role in [1,4] and Formation.zone(role,setter_zones[side]) in [1,5,6]:
				if allow_quick and setter_can_run_middle[side] and middle_showing_quick(side) and pipe_open[side] and pipe_runner_ready(i): return i
				continue
			hitters.append(i)
		if not hitters.is_empty():
			var chosen:=hitters[posmod(flight_number+rallies,hitters.size())]
			for candidate in hitters:
				if last_set_to.get(candidate,-1)<last_set_to.get(chosen,-1): chosen=candidate
			return chosen
		for i in slots_for(side):
			if i!=setter and not interrupted_hitters.has(i) and not excluded_from_attack(i): return i
	return nearest_on_team(side,frames[side].to_global(Vector3(0.0,0.04,1.45)),setter)

func manual_target_hitter(setter:int) -> int:
	var target:Vector3=manual.aim_set()
	if six_on_six():
		var closest:=-1
		var best:=INF
		for i in slots_for(0):
			var lane:=attack_lane_for(i)
			if interrupted_hitters.has(i) or i==setter or not lane.is_finite(): continue
			var gap:=lane.distance_squared_to(target)
			if gap<best:
				best=gap
				closest=i
		if closest>=0: return closest
	return nearest_on_team(0,frames[0].to_global(target),setter)

func human_can_set() -> bool:
	return last_player > 0 and team(last_player) == 0 and (team_size == 2 or rally_setter == 0)

func is_human(index: int) -> bool:
	return index == 0 and not spectator

func set_spectator(value: bool) -> void:
	if spectator == value: return
	spectator = value
	update_indicator_participants()
	carried_shot_reads = [{},{}]
	repeated_shot_landings = [{},{}]
	completed_read_matches = 0
	reset_match()

func show_key(index: int, caption: String) -> void:
	if exhibition: return
	key_labels[index].text = caption
	key_until[index] = match_clock+0.64

func server_index() -> int:
	return first_on(service_team)+server_slot[service_team]

const Formation=preload("res://scripts/six_rotations.gd")
var middle_31:Array[bool]=[false,false]
var pipe_gap:Array[float]=[0.,0.]
var quick_actor:Array[int]=[-1,-1]
var quick_lanes:Array[Vector3]=[Vector3.ZERO,Vector3.ZERO]
var quick_read_flight:Array[int]=[-1,-1]
var scored_31:Array[int]=[0,0]
var attacking_31_side:=-1
var quick_swing: Array=[preload("res://scripts/camp_spike_pose.gd").new(),preload("res://scripts/camp_spike_pose.gd").new()]
var quick_flight:Array[int]=[-1,-1]
var pipe_open:Array[bool]=[false,false]
var setter_can_run_middle:Array[bool]=[true,true]
var setter_zones: Array[int]=[1,1]
var lineup_roles: Array[PackedInt32Array]=[]
var human_receive_bounds:=Rect2()
var receive_marks: Array[PackedVector2Array]=[]
var defense_marks: Array[PackedVector2Array]=[]

# Keep the six animation controllers in place across substitutions. The on-court
# identities and their stamina follow the athletes as the two middles rotate.
var middle_profiles:Array[Dictionary]=[]
var middle_stamina:Array[Dictionary]=[]
var active_identities:Dictionary={}
var lineup_template:Array[PackedInt32Array]=[]
var human_libero:=false

func build_six_lineups() -> void:
	for side in 2:
		var first:=first_on(side)
		var roles:=Formation.lineup(players.slice(first,first+6))
		lineup_template.append(roles)
		lineup_roles.append(roles.duplicate())
		var profiles:Dictionary={}
		var energies:Dictionary={}
		var roster_side:=1-side if exhibition and StorySession.offline_controller==1 else side
		for j in 6:
			var role:=roles[j]
			if role not in [2,5]: continue
			var actor:=players[first+j]
			var profile:Dictionary=StorySession.offline_roster[roster_side*6+j].duplicate(true) if roster_active else actor.attributes.duplicate(true)
			var identity:=6 if profile.get("position","")=="Libero" else role
			if first+j==0 and identity==6 and not spectator: human_libero=true
			profiles[identity]=profile
			energies[identity]=actor.stamina
			active_identities[first+j]=identity
		for identity in [2,5,6]:
			if profiles.has(identity): continue
			var reserve:=preload("res://scripts/player_profile.gd").generate()
			reserve.position="Libero" if identity==6 else Formation.ROLES[identity]
			reserve.jersey_number=90+identity
			profiles[identity]=reserve
			energies[identity]=preload("res://scripts/player_stamina.gd").new()
		middle_profiles.append(profiles)
		middle_stamina.append(energies)

func apply_receive_substitutions() -> void:
	for side in 2:
		var roles:=lineup_template[side].duplicate()
		var back_role:=2 if Formation.back_row_libero(2,setter_zones[side]) else 5
		var controlled_libero:=side==0 and human_libero
		if controlled_libero and roles[0]!=back_role:
			var other:=roles.find(back_role)
			roles[other]=roles[0]
			roles[0]=back_role
		lineup_roles[side]=roles
		for j in 6:
			var role:=roles[j]
			if role not in [2,5]: continue
			var id:=first_on(side)+j
			var identity:=6 if role==back_role else role
			var actor:=players[id]
			if active_identities[id]!=identity:
				active_identities[id]=identity
				actor.stamina=middle_stamina[side][identity]
				actor.apply_profile(middle_profiles[side][identity])
			var color:Color=actor.team_color
			if identity==6: color=Color("#f9f1cb") if color.get_luminance()<.52 else Color("#172c48")
			actor.shirt_fabric.set_shader_parameter("fabric",color)
		server_slot[side]=rotation_server(side)

func six_on_six() -> bool:
	return team_size==6 and away_size==6

func lineup_role(index:int) -> int:
	var side:=team(index)
	return lineup_roles[side][index-first_on(side)]

func rotation_server(side:int) -> int:
	for i in 6:
		if Formation.zone(lineup_roles[side][i],setter_zones[side])==1: return i
	return 0

func formation_home(index:int,defense:bool) -> Vector3:
	var marks:=defense_marks if defense else receive_marks
	return Formation.on_court(marks[team(index)][lineup_role(index)])

func formation_slot(index:int) -> int:
	if exhibition and StorySession.career_scrimmage and roster_active:
		var role:String=StorySession.offline_roster[index].get("position","")
		var slot:=["Setter","P2","M2","Opposite","P1","M1"].find(role)
		if role=="Libero": return 2
		if slot>=0: return slot
	return index-first_on(team(index))

func starting_lane(index: int) -> float:
	if six_on_six():
		var court_zone:=Formation.zone(lineup_role(index),setter_zones[team(index)])
		return float([-1,-1,0,1,1,0][court_zone-1])
	var lane: float = [-1.0,1.0,0.0,-1.0,1.0,0.0][formation_slot(index)]
	return -lane if team(index) == 0 else lane

func reset_match() -> void:
	scored_31.assign([0,0])
	last_set_to.clear()
	career_involvement=0
	career_errors=0
	career_contributed=false
	court_velocities.clear()
	movement_times.clear()
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
	if six_on_six():
		setter_zones.assign([1,1])
		for side in 2:
			server_slot[side]=rotation_server(side)
	rallies = 0
	begin_point()

func set_player_blocks(value: bool) -> void:
	player_blocks = value

var serve_coverage := [preload("res://scripts/coverage_read.gd").new(),preload("res://scripts/coverage_read.gd").new()]

func begin_point() -> void:
	attacking_31_side=-1
	if manual: manual.reception.stop_pose()
	receive_prepared = false
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
	if six_on_six():
		apply_receive_substitutions()
		receive_marks.clear()
		defense_marks.clear()
		for side in 2:
			quick_actor[side]=-1
			quick_read_flight[side]=-1
			quick_flight[side]=-1
			middle_31[side]=randf()<.5
			pipe_gap[side]=0.
			pipe_open[side]=false
			setter_can_run_middle[side]=true
			receive_marks.append(Formation.layout(StorySession.game_options,setter_zones[side],false))
			var defense:=Formation.layout(StorySession.game_options,setter_zones[side],true)
			# In setter one the two pin hitters stay reversed through the rally.
			# Assign the existing blocking spots in the same order as their attack lanes.
			if setter_zones[side]==1 and defense[1].x<defense[3].x:
				var outside_spot:=defense[1]
				defense[1]=defense[3]
				defense[3]=outside_spot
			defense_marks.append(defense)
		var rotation:=int(setter_zones[0])
		human_receive_bounds=Formation.receive_bounds(receive_marks[0],lineup_role(0),Formation.receive_edges(rotation))
	for index in players.size():
		var actor := players[index]
		var slot := formation_slot(index)
		var front_row:=slot>=3 or (count_for(team(index))==3 and slot==2)
		actor.position=Vector3(2.1*starting_lane(index),.04,.70) if front_row else Vector3(GroundMovement.BACK_ROW_SPACING*starting_lane(index),.04,GroundMovement.BACK_ROW_DEPTH)
		if six_on_six(): actor.position=formation_home(index,team(index)==service_team)
		elif team(index)!=service_team and not is_human(index):
			actor.position=serve_coverage[team(index)].position_for(actor.position)
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
	first_ball_source = ""
	previous_attacker = -1
	attack_decision = ""
	set_decision = ""
	actual_tempo = -1
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
	var style := serve_style
	if not is_human(server):
		style = cpu_serve_override if cpu_serve_override >= 0 else cpu_policy.choose_serve(team(server))
	prepare_serve(style)
	if manual: manual.new_point()
	update_score()
	trace.begin_feed({"mode":"offline_match" if exhibition else "demo_match","score":score,"server":server_index(),"spectator":spectator,"team_size":team_size,"away_size":away_size})

func prepare_serve(style: int, station := Vector3.INF) -> void:
	serve_run_rotations.clear()
	if is_instance_valid(serve):
		serve.hide()
		serve.queue_free()
	var index := server_index()
	var side := team(index)
	serve = SERVES[style].new()
	frames[side].add_child(serve)
	var x := 1.6*starting_lane(index)
	serve.configure(players[index],station if station.is_finite() else Vector3(x,0.04,SERVICE_START[style]))
	serve.ball.mesh = ball.mesh
	if style == TOPSPIN_SERVE:
		var pace:=1.12
		if not is_human(index) and last_point.get("flight","")=="serve" and int(last_point.get("winner",side))!=side:
			pace*=lerpf(.84,1.,float(players[index].attributes.get("Confidence",65))/100.)
		serve.set_serve_speed(pace)
	if serve.has_method("set_jump_height"): serve.set_jump_height(jump_inches(index,serve_vertical,"Serve jump")*0.0254)
	var aim := Vector3(0.0,Flight.FLOOR,10.7)
	if not is_human(index):
		var placement := cpu_policy.choose(side,"serve lane",[0,-1,1],0)
		aim.x = randf_range(-3.35,3.35)
		if placement != 0: aim.x = clampf(aim.x*0.35+placement*2.45,-3.35,3.35)
		aim.z = randf_range(9.2,12.4)
	serve.test_speed_mps=preload("res://scripts/swing_speed.gd").kmh(players[index])*pow(preload("res://scripts/serving_camp.gd").TOSS_POWER_STEP,3-style)/3.6
	serve.aim(aim)
	serve.aim_ring.visible = is_human(index)
	serve.path_preview.visible = is_human(index)
	serve_pending = false
	info.text = "Your serve" if is_human(index) else str(side_names[side])+" serving"

func jump_inches(index:int,fallback:float,skill:="") -> float:
	if not exhibition or not roster_active: return fallback
	var stats:Dictionary=players[index].attributes
	var factor:=lerpf(.88,1.,clampf((float(stats.get(skill,100))-40.)/60.,0.,1.25))
	return (float(stats.vertical_in)+.25*int(stats.get("perk_tiers",{}).get("vertical_in",0)))*factor

func size_attack_jump(driver:Node3D,hitter:int) -> void:
	# AttackDrill reserves eight inches in max_height and subtracts them at takeoff.
	driver.jump.max_height=jump_inches(hitter,attack_vertical,"Attack jump")*.0254+.2032
	driver.standing_contact=clampf(float(players[hitter].attributes.reach_in)*.0254-.14,1.75,2.75)

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
	if manual and phase==Phase.READY and is_human(server_index()):
		if point.z>Net.NET_Z: manual.service.target=Vector3(clampf(point.x,-6.,6.),Flight.FLOOR,clampf(point.z,Net.NET_Z+.2,Net.NET_Z+10.5))
		return
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

var called_this_pass := false

func call_for_set() -> void:
	if spectator or phase!=Phase.LIVE or flight_kind!="pass" or possession_team!=0 or touches!=1 or team_size<3 or rally_setter<=0 or called_this_pass: return
	if excluded_from_attack(0) or interrupted_hitters.has(0) or cpu_second_spike: return
	if six_on_six() and not attack_lane_for(0).is_finite(): return
	if active_identities.get(rally_setter,-1)==6 and Formation.attack_route(lineup_role(0),setter_zones[0]) not in ["left","right"]: return
	called_this_pass=true
	cpu_dump=false
	cpu_fake_dump=false
	rally_hitter=0
	if manual:
		manual.call_notice="Called for set"
		manual.call_until=match_clock+1.

func input_space(pressed: bool) -> void:
	if spectator: return
	space_held = pressed
	if phase == Phase.FINISHED: return
	if phase == Phase.READY and server_index() == 0 and pressed:
		start_serve()
		return
	if pressed: call_for_set()
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
	if not exhibition: show_key(server_index(),"Space")
	serve.serve()

func update_score() -> void:
	score_label.text = "%s   %d   -   %d   %s" % [str(side_names[0]).to_upper(),score[0],score[1],str(side_names[1]).to_upper()]
	if not players.is_empty():
		displayed_stamina=roundi(players[0].stamina.value)
		if not exhibition: score_label.text+="   |   Stamina %d/%d" % [displayed_stamina,roundi(players[0].stamina.capacity())]

var career_involvement:=0
var career_errors:=0
var career_contributed:=false

func award(side: int, reason: String) -> void:
	if phase != Phase.LIVE: return
	if attacking_31_side==side: scored_31[side]+=1
	cpu_reception.stop_pose()
	if manual and side!=0 and manual.reception.eligible(self) and is_finite(manual.reception.closest_receive_gap):
		ContactTiming.missed_reception(manual.reception.miss_offset,manual.reception.closest_receive_gap,"Dig" if defensive_ball() else "Reception")
	if career_contributed: career_involvement+=1
	if side!=0 and last_player==0: career_errors+=1
	career_contributed=false
	score[side] += 1
	cpu_policy.finish_point(side)
	if side != service_team:
		service_team = side
		if six_on_six():
			setter_zones[side]=posmod(setter_zones[side]-2,6)+1
			server_slot[side]=rotation_server(side)
		elif rallies > 0: server_slot[side] = (int(server_slot[side])+1)%count_for(side)
	rallies += 1
	dead_age = 0.0
	if manual: attackers[0].swing_target.hide()
	if bounce_end <= 0.0 and elapsed < flight_end(): dead_flight_from = elapsed
	last_point = {"reason":reason,"ball":Trace.json_value(ball.global_position),"flight":flight_kind,
		"net":net_hit.get("kind",""),"winner":side,"time":match_clock}
	trace.write("point",match_clock,last_point,true)
	if flight_kind=="spike" and reason in ["Into the net","Under the net"]:
		var jersey:Variant=players[last_player].get_meta("school_jersey_number",last_player)
		var details:Dictionary=last_point.duplicate(true)
		details["jersey"]=jersey
		details["decision"]=attack_decision
		details["recorded_at"]=Time.get_datetime_string_from_system()
		var clip_path:=GameRecording.save_net_attack_alert(details)
		details["clip"]=ProjectSettings.globalize_path(clip_path) if not clip_path.is_empty() else ""
		GameRecording.show_net_attack_alert(jersey,reason)
		trace.write("net_attack_alert",match_clock,details,true)
		push_warning("Net attack alert · #%s · %s"%[jersey,reason])
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
		var winner := str(side_names[side])+" wins"
		if exhibition and StorySession.career_scrimmage and not spectator:
			var grade:=clampf(.60+.40*float(career_involvement)/maxi(1,rallies)-.50*float(career_errors)/maxi(1,rallies),0.,1.)
			var earned:=CareerSession.match_reward(side==0,rallies,match_clock,grade)
			winner+="   |   Teammate %d/100   +%d VP"%[roundi(grade*100.),earned]
		info.text = winner if exhibition else winner+("\nRematch starting soon" if auto_rematch and spectator else "\nUse Reset Match to play again")
	else:
		phase = Phase.DEAD
		var winner := str(side_names[side])+" point"
		info.text = winner+"  |  "+reason

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

func launch(point: Vector3, motion: Vector3, kind: String, from: int, spin_rate := 0.0, hitter := -1, set_pin := Vector3.ZERO, feed_acceleration := Vector3.INF, angular_spin := Vector3.INF, pace_includes_stamina := false) -> void:
	if kind=="spike": previous_attacker=from
	elif not last_was_block: previous_attacker=-1
	if six_on_six() and kind=="spike" and from>=0:
		var side:=team(from)
		attacking_31_side=side if flight_kind=="set" and expected_hitter==from and from==front_middle(side) and middle_31[side] else -1
	elif not (last_was_block and kind in ["free","block"]):
		attacking_31_side=-1
	cpu_reception.stop_pose()
	# A deflection changes the ball's flight immediately, even during a player's slide.
	for index in players.size():
		var save: RefCounted = platforms[index].low_save
		if save.active and not save.finished(elapsed): begin_recovery(index)
	if from==0 and kind!="serve": career_contributed=true
	if from>=0 and from<players.size():
		var athlete := players[from]
		if kind in ["serve","spike","dump","block"] and not pace_includes_stamina:
			motion*=athlete.stamina.effectiveness()
		if kind in ["serve","spike"]:
			var base := preload("res://scripts/swing_speed.gd").kmh(athlete)
			var endurance:float=athlete.stamina.effectiveness()
			var shot_scale := motion.length()*3.6/maxf(.001,base*endurance)
			var details:=preload("res://scripts/swing_speed.gd").ratings(athlete)+"\nShot power ×%.2f  ·  Stamina ×%.2f"%[shot_scale,endurance]
			if kind=="serve" and manual and is_human(from) and manual.service.launched:
				var shot=manual.service.curve()
				details=preload("res://scripts/serving_camp.gd").serve_speed_line(athlete,3-serve_style,manual.service.spin,shot)
				ContactTiming.launch_speed(shot.velocity,details)
			else:
				ContactTiming.launch_speed(motion,details)
		athlete.stamina.spend(5. if kind in ["serve","spike","block"] else 2.)
	if manual: manual.flight_changed(kind)
	if six_on_six() and kind=="serve":
		var setting_side:=1-team(from)
		var setter_index:=first_on(setting_side)+lineup_roles[setting_side].find(0)
		players[setter_index].shirt_fabric.set_shader_parameter("signal_lift",0.)
	interrupted_hitters.clear()
	flight_number += 1
	if six_on_six() and kind=="set" and hitter>=0: last_set_to[hitter]=flight_number
	line_read_error=randf_range(-1.,1.)
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
		var curve=manual.service.curve() if manual and is_human(from) and manual.service.launched else serve
		net_hit = curve.net_hit.duplicate()
		if not net_hit.is_empty():
			net_hit.release_point = serve.to_global(net_hit.release_point)
			net_hit.point = serve.to_global(net_hit.point)
			net_hit.velocity = serve.global_basis*net_hit.velocity
			if team(from) == 1: net_hit.side = -float(net_hit.side)
		duration = curve.planned_duration
	if kind in ["spike","free","dump"]: receiving_team = 1-team(from)
	if last_was_block and kind in ["block","free"]:
		receiving_team = 0 if path_point(flight_end()).z < Net.NET_Z else 1
	if count_for(receiving_team) >= 3 and kind == "pass" and touches == 1 and possession_team == receiving_team:
		called_this_pass=false
		rally_setter = choose_setter(receiving_team,from)
		if six_on_six():
			read_pipe(receiving_team)
			var meet:=frames[receiving_team].to_local(path_point(arrival(1.92)))
			setter_can_run_middle[receiving_team]=meet.z>=Net.NET_Z-3. and active_identities.get(rally_setter,-1)!=6
		rally_hitter = -1
		rally_hitter = hitter_for_set(rally_setter)
	if not manual and not spectator and kind == "pass" and human_can_set() and receiving_team == 0 and match_clock-last_input_at <= 0.35:
		requested = last_input_technique
		request_age = 0.0
		queue_receive(0,requested)
	if manual: manual.claim_held_target()
	if hitter >= 0:
		var side := team(hitter)
		var frame := frames[side]
		var shot := frame.to_local(drill_spike_target) if drill_spike_target.is_finite() else choose_shot(hitter)
		if drill_spike_target.is_finite():
			attackers[side].spike_strength = drill_spike_pace
		else: set_cpu_swing_power(hitter)
		if exhibition and roster_active: size_attack_jump(attackers[side],hitter)
		attackers[side].timed_human=manual!=null and is_human(hitter)
		attackers[side].cpu_middle_attack=six_on_six() and not is_human(hitter) and hitter==front_middle(side)
		var plan:Dictionary={}
		attackers[side].off_net_shovel=false
		if six_on_six() and not is_human(hitter) and not drill_spike_target.is_finite():
			var at:=frame.to_local(set_pin)
			if at.y<1.: at.y=attackers[side].set_contact_height(last_set_apex)
			shot=choose_shot(hitter,at)
			plan=choose_contact_attack(hitter,at,shot,Vector3.BACK*preload("res://scripts/swing_speed.gd").kmh(players[hitter])/3.6,8.)
			shot=plan.get("target",shot)
			if attackers[side].cpu_middle_attack and frame.to_local(origin).z<2.55 and absf(at.x-frame.to_local(origin).x)<1.45:
				shot=Vector3(clampf(at.x,-3.,3.),Flight.FLOOR,8.6)
				plan={"type":"Roll shot"}
				attackers[side].off_net_shovel=true
		attackers[side].start_set(players[hitter],frame.to_local(origin),frame.global_basis.inverse()*velocity,frame.to_local(set_pin),shot,0.0,is_human(hitter) and (manual.attack_lane>=0 if manual else space_held))
		if not plan.is_empty():
			attackers[side].shot_plan=plan.type
			attackers[side].rally_shot="roll" if plan.type=="Roll shot" else "spike"
		if six_on_six() and hitter==front_middle(side) and quick_flight[side]==flight_number-1 and set_jumps[hitter].active:
			var driver:=attackers[side]
			var unused=driver.jump
			quick_actor[side]=-1
			driver.jump=set_jumps[hitter]
			driver.inherited_quick_jump=true
			# The middle already loaded the swing during the pass, before the setter released it.
			driver.approach_pressed_at=driver.stage_start
			driver.approach_space_held=true
			set_jumps[hitter]=unused
			driver.takeoff_yaw=players[hitter].rotation.y
			driver.approach_intercept=frame.to_local(set_pin)
			if driver.approach_intercept.y<=1.: driver.approach_intercept.y=driver.set_contact_height(last_set_apex)
			driver.approach_expected_hit_at=driver.stage_start+driver.pin_arrival

	ball.global_position = point
	ball.show()
	update_flight_guide()

func advance_ball_spin(delta: float) -> void:
	if not ball_spin.is_zero_approx():
		ball.global_rotate(ball_spin.normalized(),TAU*ball_spin.length()*delta)

func flight_gravity() -> float:
	if drill_feed_acceleration.is_finite(): return -drill_feed_acceleration.y
	return Flight.spike_gravity(spin) if flight_kind == "spike" else Flight.GRAVITY

func flight_point(time: float) -> Vector3:
	if flight_kind == "serve" and not drill_feed_acceleration.is_finite() and is_instance_valid(serve):
		if manual and last_player==0 and manual.service.launched: return manual.service.curve().flight_point(time)
		return serve.to_global(serve.flight_point(time))
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
	if not is_human(index) and cpu_is_setting(index):
		var release:=contact if contact.is_finite() else frame.to_local(path_point(arrival(1.92)))
		return open_dump_target(index,release)
	var defending := 1-side
	var blocker: int = defender_assignment[defending]
	var defender := partner_of(blocker) if count_for(defending) == 2 and blocker >= 0 else first_on(defending)
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
			if count_for(defending) >= 3:
				for index_ in slots_for(defending):
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
	if phase != Phase.LIVE or (not block and cannot_cover_own_attack(index)): return false
	var side := team(index)
	if block:
		possession_team=side
		touches=0
		last_was_block=true
		return true
	if side != possession_team:
		possession_team = side
		touches = 0
	elif index == last_player and not last_was_block:
		award(1-side,"Double contact")
		return false
	if touches == 0:
		first_ball_source="block" if last_was_block else flight_kind
		transition_possession[side]=first_ball_source not in ["serve","free"]
	if touches == 3:
		award(1-side,"Four contacts")
		return false
	touches += 1
	last_was_block = block
	return true

func cannot_cover_own_attack(index:int) -> bool:
	return last_was_block and index>=0 and index==previous_attacker

func set_cpu_swing_power(hitter: int) -> void:
	var side := team(hitter)
	var effort := cpu_policy.choose(side,"attack effort",[0,1,2],0) if not is_human(hitter) else 0
	var power := preload("res://scripts/swing_speed.gd").kmh(players[hitter])/(3.6*27.)
	attackers[side].spike_strength = spike_strength*(1.0-0.075*effort)*power

func on_spike(actor: Node3D, point: Vector3, motion: Vector3, spin_rate: float) -> void:
	var index := players.find(actor)
	if index < 0 or not can_touch(index): return
	if manual and is_human(index) and attackers[0].rally_shot in ["tip","roll"]:
		var tip:bool=attackers[0].rally_shot=="tip"
		var target:Vector3=manual.aim
		var flight:=preload("res://scripts/attacking_camp.gd").soft_shot_duration(point,target,tip)
		spin_rate=0. if tip else 2./.52
		motion=(target-point)/flight+Vector3.UP*.5*Flight.spike_gravity(spin_rate)*flight
	if drill_spike_target.is_finite():
		play_touch(motion.length()>=preload("res://scripts/gym_physics.gd").HARD_SPIKE_SPEED)
		observe_opponent_shot(1-team(index),point,motion,spin_rate,index)
		stroke = "Spike"
		launch(point,motion,"spike",index,spin_rate)
		return
	stroke = "Second-ball spike" if cpu_second_spike and overpass_flight != flight_number else "Spike"
	if manual and is_human(index) and attackers[0].rally_shot!="spike": stroke=attackers[0].rally_shot.capitalize()
	if not is_human(index):
		var frame := frames[team(index)]
		var start := frame.to_local(point)
		var local_motion := frame.global_basis.inverse()*motion*float(actor.stamina.effectiveness())
		var shot: Vector3 = attackers[team(index)].swing_aim
		var drive:=attackers[team(index)]
		var clean:bool=drive.strike_sample.is_empty() or drive.release_transfer>=.78
		var tactic := choose_contact_attack(index,start,shot,local_motion,spin_rate,true) if clean else {}
		if not tactic.is_empty():
			local_motion = tactic.motion
			drive.shot_plan=tactic.type
			spin_rate=tactic.get("spin",spin_rate)
			if tactic.type=="Roll shot": stroke="Roll shot"
			trace.write("cpu_attack_choice",match_clock,{"type":tactic.type,"contact":start,"target":tactic.target,"motion":local_motion})
		if clean:
			local_motion=CpuShots.lift_over_tape(start,local_motion,Flight.spike_gravity(spin_rate))
		var part: int=drive.strike_sample.get("part",0)
		var surface:String=["Palm","Fingertip","Wrist"][part]
		var gap_text:="moving away from net"
		if local_motion.z>.01:
			var t:float=(Net.NET_Z-start.z)/local_motion.z
			var margin:float=start.y+local_motion.y*t-.5*Flight.spike_gravity(spin_rate)*t*t-Net.NET_TOP-Net.RADIUS
			var land:=Flight.landing_time(start,local_motion,Flight.spike_gravity(spin_rate))
			gap_text="falls %.2f m short of net"%(Net.NET_Z-start.z-local_motion.z*land) if t>land else "net clearance %+.2f m"%margin
		var reason:="palm drive %d%%"%roundi(drive.release_transfer*100.) if part==0 else "off-center contact"
		attack_decision="#%s · %s · %s · %.0f km/h\n%s · %s"%[actor.get_meta("school_jersey_number",index),drive.shot_plan,surface,local_motion.length()*3.6,reason,gap_text]
		trace.write("attack_release",match_clock,{"hitter":index,"shot":drive.shot_plan,"surface":surface,"transfer":drive.release_transfer,"incoming":drive.strike_sample.get("incoming",Vector3.ZERO),"hand":drive.strike_sample.get("hand_velocity",Vector3.ZERO),"aim":shot,"motion":local_motion,"net":gap_text})
		motion = frame.global_basis*local_motion
	if not is_human(index):
		cpu_policy.used(team(index),"attack depth")
		cpu_policy.used(team(index),"attack effort")
	play_touch(motion.length()>=preload("res://scripts/gym_physics.gd").HARD_SPIKE_SPEED)
	observe_opponent_shot(1-team(index),point,motion,spin_rate,index)
	launch(point,motion,"spike",index,spin_rate,-1,Vector3.ZERO,Vector3.INF,Vector3.INF,not is_human(index))

func choose_contact_attack(index: int, contact: Vector3, preferred: Vector3, motion: Vector3, spin_rate: float, committed:=false) -> Dictionary:
	var side := team(index)
	var frame := frames[side]
	var defense := 1-side
	var defenders: Array[Vector3] = []
	var walls: Array[Vector3] = []
	for opponent in slots_for(defense):
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
	var speed := motion.length()
	return CpuShots.plan(contact,preferred,speed,spin_rate,defenders,walls,motion if committed else Vector3.ZERO)

func shot_read_zone(local_x: float) -> int:
	return 0 if absf(local_x) < 1.3 else (1 if local_x > 0.0 else -1)

func observe_opponent_shot(side: int, point: Vector3, motion: Vector3, spin_rate: float, attacker_index: int) -> void:
	var frame := frames[side]
	for i in slots_for(side): players[i].block_read(players[attacker_index]).record_velocity(frame.global_basis.inverse()*motion)
	var time := Flight.landing_time(point,motion,Flight.spike_gravity(spin_rate))
	var landing := frame.to_local(point+motion*time)
	if absf(landing.x) > 4.53 or landing.z < -5.03 or landing.z > Net.NET_Z: return
	var contact := frame.to_local(point)
	var zone := shot_read_zone(contact.x)
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

func make_ball_audio(stream: AudioStream, gain: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = gain
	player.max_polyphony = 3
	add_child(player)
	return player

func set_ball_sound(enabled: bool) -> void:
	ball_sound_enabled = enabled
	if not enabled:
		for player in [touch_audio,spike_audio,floor_audio,net_audio]: player.stop()

func play_touch(strong := false) -> void:
	if not ball_sound_enabled: return
	if strong: StorySession.play_hand_contact(SPIKE_SOUND,2.)
	else: touch_audio.play()

func set_pin_for(index: int, setter_x := INF) -> Vector3:
	if active_identities.get(index,-1)==6: return attack_lane_for(libero_outlet(index))
	if manual and is_human(index) and manual.lane>=0: return manual.aim_set()
	if drill_set_pin.is_finite(): return frames[team(index)].to_local(drill_set_pin)
	var side := team(index)
	var frame := frames[side]
	if is_human(index) and aim_point.is_finite():
		var point := frame.to_local(aim_point)
		if point.z <= Net.NET_Z: return Vector3(clampf(point.x,-4.6,4.6),0.065,clampf(point.z,-1.6,3.62))
	var selected_hitter:=hitter_for_set(index)
	var hitter := players[selected_hitter]
	if six_on_six() and not is_human(index):
		var lane:=attack_lane_for(selected_hitter)
		if lane.is_finite(): return lane
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
	if count_for(team(index)) == 2: return partner_of(index)
	var side := team(index)
	var target := Vector3(players[index].position.x*0.5,PLAYER_GROUND_Y,2.0)
	return nearest_on_team(side,frames[side].to_global(target),index)

func cpu_pass_target(index: int) -> Vector3:
	if drill_pass_target.is_finite(): return frames[team(index)].to_local(drill_pass_target)
	return players[setter_for_pass(index)].position


func aim_receive(index: int) -> void:
	var bump := platforms[index]
	var side := team(index)
	var frame := frames[side]
	var destination := cpu_pass_target(index)
	bump.passing_skill_override = passing_skill
	bump.setting_skill_override = setting_skill
	bump.hard_dig = flight_kind in ["spike","dump","block"]
	if roster_active:
		var skills: Dictionary = players[index].attributes
		var technique := "Hand" if bump.hand_setting else "Forearm"
		bump.passing_skill_override = skills[technique + (" defense" if bump.hard_dig else " reception")]
		bump.setting_skill_override = skills[technique + " setting"]
	var first_in_sixes:=six_on_six() and (possession_team!=side or touches==0 or last_was_block)
	if first_in_sixes: destination=cpu_pass_target(index)
	elif manual and is_human(index) and manual.lane>=0: destination=manual.aim_set()
	elif is_human(index) and aim_point.is_finite(): destination = frame.to_local(aim_point)
	elif side == possession_team and (touches >= 2 or (cpu_dump and index == cpu_choice)): destination = choose_shot(index)
	bump.set_follow_target = set_pin_for(index) if cpu_is_setting(index) and not cpu_dump else Vector3.INF
	bump.destination = Vector2(clampf(destination.x,-6.5,6.5),clampf(destination.z,-6.0,13.0))
	bump.height = pass_height if is_human(index) else (3.65 if cpu_dump and index == cpu_choice else Bump.Accuracy.IDEAL_APEX)
	bump.receive_target_y=players[setter_for_pass(index)].height_cm*.0118 if not is_human(index) and not cpu_is_setting(index) and destination==cpu_pass_target(index) else Flight.FLOOR


func six_set_tempo(hitter:int,point:Vector3) -> int:
	if manual and is_human(hitter): return manual.requested_tempo
	var role:=lineup_role(hitter)
	if role in [2,5]: return 0 if randf()<.90 else 1
	if role in [1,4] and Formation.zone(role,setter_zones[team(hitter)]) in [1,5,6]: return 1
	if point.z<0. or absf(point.x)>4.4: return 3
	return randi_range(1,2)

# Fast pin sets need a designated setter, a controlled first ball and a hitter with a runway.
func pin_tempo(setter:int,hitter:int,point:Vector3,requested_tempo:int) -> int:
	var route:=Formation.attack_route(lineup_role(hitter),setter_zones[team(hitter)])
	if route not in ["left","right"]: return requested_tempo
	var lane:=attack_lane_for(hitter)
	var actor:=players[hitter]
	var runway:=lane.z-actor.position.z
	var approach:=(lane-actor.position).slide(Vector3.UP)
	var reason:=""
	if lineup_role(setter)!=0 or active_identities.get(setter,-1)==6: reason="emergency setter"
	elif first_ball_source not in ["serve","free"]: reason="transition"
	elif point.z<Net.NET_Z-3.: reason="pass off the net"
	elif runway<.85 or approach.length()>3.9 or actor.position.y>PLAYER_GROUND_Y+.12 or actor.basis.z.dot(approach.normalized())<.30: reason="hitter needs approach time"
	set_decision=reason if not reason.is_empty() else "hitter ready"
	return maxi(requested_tempo,2) if not reason.is_empty() else requested_tempo

func manual_pin_apex(setter:int,point:Vector3,requested_apex:float) -> float:
	if first_ball_source in ["serve","free"] and lineup_role(setter)==0 and active_identities.get(setter,-1)!=6: return requested_apex
	return maxf(requested_apex,maxf(point.y,attackers[team(setter)].set_contact_height())+1.12)

func set_height_error(error:float) -> float:
	return error

func cpu_set_apex(index: int, point: Vector3, pin: Vector3, pace: float, tempo:=-1) -> float:
	var target:=hitter_for_set(index)
	var hitter:=players[target]
	if six_on_six():
		if tempo<0: tempo=six_set_tempo(target,point)
		var rise:float=[.18,.47,1.12,2.65][tempo]
		return maxf(point.y,attackers[team(index)].set_contact_height())+rise
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
	if flight_kind=="serve": serve_coverage[team(index)].covered()
	if frames[team(index)].to_local(world_point).z > Net.NET_Z+0.07: return
	if not can_touch(index): return
	var side := team(index)
	if is_human(index) and velocity.length() > 18.0:
		var pads := Input.get_connected_joypads()
		if not pads.is_empty():
			var strength := clampf((velocity.length()-14.0)/20.0,0.1,1.0)
			Input.start_joy_vibration(pads[0],strength*0.5,strength,0.13)
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
	var bend := 0.
	if technique==0 and not bump.low_save.active and sample_after>sample_before:
		bend=ForearmDrive.forearm_bend_degrees(path_point(sample_before).distance_to(path_point(sample_after))/(sample_after-sample_before))
	begin_recovery(index)
	if bend>0.:
		recoveries[index]["elbow_bend"] = bend
		if bump.knee_bend_depth > 0.001:
			recoveries[index]["hold"] = FAST_DIG_ELBOW_DURATION
	var cpu_dump_attempt := touches == 2 and cpu_dump and index == cpu_choice and not is_human(index)
	var unsafe_dump := cpu_dump_attempt and not dump_can_land_in_court(point,frame.global_basis.inverse()*world_motion)
	var called_set:=side==0 and called_this_pass and rally_hitter==0 and index==rally_setter and flight_kind=="pass"
	var libero_set:bool = not is_human(index) and six_on_six() and active_identities.get(index,-1)==6 and index==rally_setter
	if touches == 2 and (libero_set or called_set or unsafe_dump or (not (cpu_dump and index == cpu_choice) and (bump.destination.y < 4.0 or (is_human(index) and technique != 0)))):
		var setter_x := players[index].position.x
		if six_on_six() and not is_human(index):
			choose_at_set_contact(index,point)
		var pin := set_pin_for(index,setter_x)
		last_called_set_x[side] = pin.x
		var incoming := velocity+Vector3.DOWN*Flight.GRAVITY*elapsed
		var driver := attackers[side]
		var hitter:=hitter_for_set(index)
		if six_on_six() and absf(pin.x)<2.5 and hitter==front_middle(side) and not is_human(hitter) and not middle_showing_quick(side):
			pin=space_middle_from_setter(pin,point,players[hitter].position.x)
		if exhibition and roster_active: size_attack_jump(driver,hitter)
		var minimum := maxf((driver.set_contact_height()+0.22) if is_human(index) else 2.96,point.y+0.18)
		var tempo:=six_set_tempo(hitter,point) if six_on_six() and not is_human(index) else -1
		if tempo>=0:
			set_decision="middle approach" if hitter==front_middle(side) else "pipe approach"
			tempo=pin_tempo(index,hitter,point,tempo)
			actual_tempo=tempo
			set_decision="%s · tempo %d · %s"%[Formation.attack_route(lineup_role(hitter),setter_zones[side]).capitalize(),tempo,set_decision]
			attack_decision=""
		var apex: float = bump.height if is_human(index) else cpu_set_apex(index,point,pin,incoming.length(),tempo)
		if six_on_six() and is_human(index) and absf(pin.x)>2.5:
			apex=manual_pin_apex(index,point,apex)
		apex = maxf(minimum,apex)
		var timing_error:=0.
		if manual and is_human(index) and is_finite(manual.set_release):
			timing_error=clampf(absf(manual.feedback.get("offset",0.))/.21,0.,1.)
		var error := Bump.Accuracy.sample_set_offset(Bump.Accuracy.spread(timing_error,incoming.length(),spin,bump.setting_skill_override*players[index].stamina.effectiveness(),true))
		var set_width := pin.x-setter_x
		pin += error.slide(Vector3.UP)
		if not is_human(index) and absf(set_width) >= 1.0 and (pin.x-setter_x)*signf(set_width) < 1.0:
			pin.x = setter_x+signf(set_width)
		apex = maxf(maxf(2.74,point.y+0.18),apex+set_height_error(error.y))
		if not is_human(index) and not six_on_six():
			var span := (pin-point).slide(Vector3.UP).length()
			var time_to_hit := maxf(0.68,span/6.2)
			apex = driver.apex_for_set_time(point.y,apex,time_to_hit)
		if tempo>=2 and six_on_six() and absf(pin.x)>2.5:
			var runway:float=(players[hitter].position-pin).slide(Vector3.UP).length()
			var outlet_delay:=.10 if active_identities.get(index,-1)==6 else 0.
			var approach_time:=.77 if pin.x>0. else .64
			var minimum_flight:=clampf(approach_time+outlet_delay+runway/6.8,(1.02 if pin.x>0. else .91)+outlet_delay,1.68)
			if pin.x>2.5 and players[hitter].position.x>4.45:
				var long_outlet:=smoothstep(4.1,5.2,pin.x-point.x)
				pin=Vector3(minf(pin.x+.34*long_outlet,maxf(4.05,pin.x)),pin.y,pin.z-.56*long_outlet)
				minimum_flight=maxf(minimum_flight,zone_four_flight_time(pin.x-point.x))
			apex=driver.apex_for_set_time(point.y,apex,minimum_flight)
		if is_finite(drill_set_apex): apex = maxf(point.y+0.18,drill_set_apex)
		var contact_height: float = driver.set_contact_height(apex)
		last_set_apex = apex
		if not is_human(index):
			cpu_policy.used(side,"set lane")
			cpu_policy.used(side,"set height")
		var airborne: bool=players[index].position.y>PLAYER_GROUND_Y+.12
		var carry: Vector3=set_jumps[index].horizontal_velocity() if airborne and set_jumps[index].active else Vector3.ZERO
		var duration := (sqrt(2.*Flight.GRAVITY*maxf(0.,apex-point.y))+sqrt(2.*Flight.GRAVITY*maxf(0.,apex-contact_height)))/Flight.GRAVITY
		pin=players[index].reachable_set(point,pin,airborne,carry,duration)
		var motion: Vector3 = driver.set_toward_pin(point,pin,apex,contact_height)
		var airborne_quick:=six_on_six() and not is_human(index) and not is_human(hitter) and hitter==front_middle(side) and middle_showing_quick(side)
		if airborne_quick:
			var runner:=players[hitter]
			var jump:=set_jumps[hitter]
			var air_age:float=jump.elapsed-jump.load_duration()
			# Keep the contact on the middle's shoulder, slightly later in the arc.
			# Spending more time in flight reduces the set's lateral speed.
			var hit_phase:=.59 if tempo==0 else .66
			var max_flight:=.40 if tempo==0 else .46
			duration=clampf(jump.air_time*hit_phase-air_age,.13,max_flight)
			var phase_at_hit:=clampf((air_age+duration)/jump.air_time,0.,1.)
			var rig:Skeleton3D=runner.skeleton
			var shoulder:=frame.to_local(rig.to_global(rig.get_bone_global_pose(rig.find_bone("upperarm_r")).origin))
			var root_y:float=jump.start.y+4.*jump.height*jump.COURT_VERTICAL_SCALE*phase_at_hit*(1.-phase_at_hit)
			pin=shoulder+jump.horizontal_velocity().slide(Vector3.UP)*duration+Vector3.BACK*.35
			pin.y+=root_y-runner.position.y+runner.height_cm*.0031
			motion=(pin-point)/duration+Vector3.UP*(.5*Flight.GRAVITY*duration)
			apex=point.y+maxf(0.,motion.y)**2/(2.*Flight.GRAVITY)
			last_set_apex=apex
		if six_on_six() and not is_human(index):
			trace.write("cpu_set_release",match_clock,{"setter":index,"hitter":hitter,"role":lineup_role(hitter),"tempo":tempo,"airborne_quick":airborne_quick,"route":attack_lane_for(hitter),"runner":players[hitter].position,"target":pin,"apex":apex,"arrival_seconds":duration})
		launch(world_point,frame.global_basis*motion,"set",index,1.0,hitter,frame.to_global(pin))
		if airborne_quick:
			driver.pin_arrival=duration
			driver.approach_expected_hit_at=driver.stage_start+duration
		return
	if six_on_six() and not is_human(index) and touches==1 and flight_kind in ["spike","dump"] and not drill_pass_target.is_finite():
		var incoming_speed:=((path_point(sample_after)-path_point(sample_before))/(sample_after-sample_before)).length() if sample_after>sample_before else (velocity+Vector3.DOWN*flight_gravity()*elapsed).length()
		var skill:float=players[index].effective_rating("Forearm defense" if technique==0 else "Hand defense")
		var spread:=Bump.Accuracy.dig_spread(incoming_speed,skill)
		var offset:=Bump.Accuracy.sample_offset(spread)
		var pot:=Vector2(0.,Net.NET_Z-3.)
		var aim:=pot+Vector2(offset.x,offset.z)
		var apex:=maxf(point.y+.18,4.6+offset.y)
		var motion:=Flight.target_velocity(point,{"position":aim,"fit":"height","height":apex,"end_y":minf(2.15,apex-.15)},0.)
		world_motion=frame.global_basis*motion
		trace.write("dig_outlet",match_clock,{"player":index,"speed_kmh":incoming_speed*3.6,"pot":pot,"target":aim,"apex":apex,"spread":spread})
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
	var outgoing_spin := Flight.reception_backspin(world_motion,ball_spin.length(),technique!=0) if touches==1 or technique==0 else Vector3.ZERO
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

func open_dump_target(setter:int,contact:Vector3) -> Vector3:
	var side:=team(setter)
	var coverage:=PackedVector2Array()
	for defender in slots_for(1-side):
		var at:=frames[side].to_local(players[defender].global_position)
		coverage.append(Vector2(at.x,at.z))
	var release:=Vector2(contact.x,contact.z)
	var best:=Vector3(0.,Flight.FLOOR,Net.NET_Z+4.5)
	var best_score:=-INF
	for x:float in [-3.8,-2.,0.,2.,3.8]:
		for depth:float in [1.35,3.,4.7,6.5,8.15]:
			var landing:=Vector2(x,Net.NET_Z+depth)
			var nearest:=INF
			var wall_risk:=0.
			var crossing:=lerpf(contact.x,x,clampf((Net.NET_Z-contact.z)/maxf(.1,landing.y-contact.z),0.,1.))
			for defender in coverage:
				nearest=minf(nearest,defender.distance_squared_to(landing))
				if defender.y<=Net.NET_Z+1.1:
					wall_risk=maxf(wall_risk,1.-smoothstep(.35,1.35,absf(defender.x-crossing)))
			# Prefer the widest gap, with a shorter delivery when cover is comparable.
			var score:=sqrt(nearest)-.12*release.distance_to(landing)-1.1*wall_risk
			var motion:=Flight.target_velocity(contact,{"position":landing,"fit":"height","height":3.65},45.)
			if not dump_can_land_in_court(contact,motion): score-=20.
			if score>best_score:
				best_score=score
				best=Vector3(x,Flight.FLOOR,landing.y)
	return best

func dump_can_land_in_court(point: Vector3, motion: Vector3) -> bool:
	if motion.z <= 0.001: return false
	var landing := Flight.landing_time(point,motion)
	var cross := (Net.NET_Z-point.z)/motion.z
	if cross <= 0.0 or cross >= landing: return false
	var at_net := point+motion*cross+Vector3.DOWN*0.5*Flight.GRAVITY*cross*cross
	var floor_point := point+motion*landing
	return absf(at_net.x) <= Net.NET_HALF_WIDTH and at_net.y >= Net.NET_TOP+0.02 and absf(floor_point.x) <= 4.53 and floor_point.z <= 13.03

func owns_action(index: int, allow_serve_move := false) -> bool:
	if manual and is_human(index) and not manual.reception.motion.is_empty(): return true
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
		if recovery.get("elbow_bend",0.)>0. and age > 0.0 and age < FAST_DIG_ELBOW_DURATION:
			ForearmDrive.recoil_platform(rig,age,recovery.elbow_bend)
		if recovery.has("set_push") and age<Bump.HandPose.CPU_FOLLOW_TIME:
			var push:Dictionary=recovery.set_push
			Bump.HandPose.standing_set(actor,push.point,push.direction,push.direction.normalized(),age,1.)
		if recovery.has("kick_foot"):
			var flick := smoothstep(0.0,0.070,age)*(1.0-smoothstep(0.07,0.22,age))
			if flick > 0.001: pose_kick_leg(actor,recovery.kick_foot,(Vector3.UP*0.15+actor.global_basis.z*0.11)*flick)

func advance_set_jumps(delta: float) -> void:
	for index in players.size():
		var jump := set_jumps[index]
		if jump.active:
			if jump_set_started[index] and cpu_is_setting(index) and six_on_six() and not is_human(index) and active_identities.get(index,-1)==6:
				var leaves_floor:bool=jump.elapsed<=jump.load_duration() and jump.elapsed+delta>jump.load_duration()
				if leaves_floor and not libero_feet_behind_line(index):
					jump.active=false
					players[index].position.y=jump.start.y
					cancel_cpu_jump_set(index)
					continue
			jump.step(players[index],delta,Vector2.ZERO)
			var side:=team(index)
			if quick_actor[side]==index:
				if not jump.active: quick_actor[side]=-1
				else:
					var runner:=players[index]
					if jump.elapsed<=jump.load_duration():
						var heading:=clampf(atan2(jump.heading.x,maxf(.35,jump.heading.z)),-.60,.60)
						runner.rotation.y=rotate_toward(runner.rotation.y,heading,delta*GymPaths.TURN_RATE)
					var age:float=jump.elapsed-jump.load_duration()
					if age>0.:
						var frame:=frames[side]
						var goal:=frame.to_global(quick_lanes[side]+Vector3.UP*2.9)
						var swing_at:float=jump.air_time*.48
						var t:=age-swing_at+.11
						var rig:Skeleton3D=players[index].skeleton
						var strike_offset:=rig.to_local(goal)-rig.get_bone_global_pose(rig.find_bone("upperarm_r")).origin
						quick_swing[side].apply(players[index],jump,"spike" if t>=.11 else "set",t,.11,goal,frame.to_global(SETTER_BASE),goal,goal,frame.to_global(Vector3(0.,.14,10.)),strike_offset,jump.height,1.,24.,1.,0,-1.)
			animated[index] = true

# In team-local space +Z is straight across the net on either court.
func guarding_net(index: int, target_depth: float) -> bool:
	if target_depth < 2.25 or phase != Phase.LIVE: return false
	var side := team(index)
	if six_on_six():
		if Formation.zone(lineup_role(index),setter_zones[side]) not in [2,3,4]: return false
	elif defender_assignment[side] != index: return false
	if flight_kind in ["spike","dump"]: return side == receiving_team and index != cpu_choice
	return side != receiving_team and flight_kind in ["serve","pass","set","block","free"]

func advance_idle_players(delta: float) -> void:
	for index in players.size():
		if animated[index] or owns_action(index): continue
		var actor := players[index]
		if phase == Phase.LIVE and not is_human(index):
			var sight:=frames[team(index)].to_local(ball.global_position)-actor.position
			var yaw:=atan2(sight.x,sight.z) if six_on_six() and not guarding_net(index,actor.position.z) else 0.
			if six_on_six() and index==front_middle(team(index)) and actor.position.z>1.6 and not guarding_net(index,actor.position.z):
				yaw=atan2(sight.x,maxf(1.25,sight.z))
			actor.rotation.y = rotate_toward(actor.rotation.y,yaw,delta*GymPaths.TURN_RATE)
		actor.animator.speed_scale = 1.0
		actor.play_action("idle")
		actor.animator.advance(delta)
		if not is_human(index): footwork[index].step(Vector3.ZERO,delta,1.0,true)

func advance_attackers(delta: float) -> void:
	for driver in attackers:
		if not driver.enabled: continue
		var index := players.find(driver.setter)
		driver.tick_attack(delta)
		if not driver.enabled and index >= 0:
			begin_recovery(index)
			animated[index] = true

func player_game_point_attack() -> bool:
	return phase==Phase.LIVE and not spectator and not replay.active and score[0]+1>=win_score and score[0]>=score[1]+1 and flight_kind in ["spike","dump"] and last_player>=0 and team(last_player)==0

func settle_point(delta: float) -> void:
	if not serve.moved_after_contact and serve.swing_time < serve.recovery_end(): serve.step(delta)
	advance_set_jumps(delta)
	advance_attackers(delta)
	tick_blocks(delta,elapsed)
	advance_recoveries(delta)
	advance_idle_players(delta)

func block_lane_limits(index:int, target_depth:float) -> Vector2:
	var limits:=Vector2(-INF,INF)
	var side:=team(index)
	if target_depth<2.7 or players[index].position.z<2.6 or side==receiving_team or flight_kind not in ["set","pass"] or not six_on_six(): return limits
	var role:=lineup_role(index)
	if Formation.zone(role,setter_zones[side]) not in [2,3,4]: return limits
	var home_x:=formation_home(index,true).x
	for i in slots_for(side):
		if i==index: continue
		var neighbor_role:=lineup_role(i)
		if Formation.zone(neighbor_role,setter_zones[side]) not in [2,3,4]: continue
		var depth_gap:=absf(players[index].position.z-players[i].position.z)
		if depth_gap>=.62: continue
		var spacing:=sqrt(.62*.62-depth_gap*depth_gap)
		var neighbor_home:=formation_home(i,true).x
		if neighbor_home<home_x: limits.x=maxf(limits.x,players[i].position.x+spacing)
		elif neighbor_home>home_x: limits.y=minf(limits.y,players[i].position.x-spacing)
	if limits.x>limits.y:
		var center:=(limits.x+limits.y)*.5
		return Vector2(center,center)
	return limits

func move_cpu(index: int, target: Vector3, delta: float, speed := 5.3, receive_facing := Vector3.INF, chase := false, turn_to_travel := false, turn_rate := 12.5, paced_run := false, run_cadence := 0.0, shuffle_pace := 0., outside_direction := 0., shoulder_x := 0.) -> void:
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
	var block_stance := guarding_net(index,local.z)
	if block_stance:
		receive_facing = Vector3.BACK
		chase = false
		turn_to_travel = false
		paced_run = false
	var limits:=block_lane_limits(index,local.z)
	if outside_direction>0.: limits.x=maxf(limits.x,shoulder_x)
	elif outside_direction<0.: limits.y=minf(limits.y,shoulder_x)
	if limits.x<=limits.y: local.x=clampf(local.x,limits.x,limits.y)
	var offset := (local-actor.position).slide(Vector3.UP)
	var heading := offset.normalized()
	var already_running: bool = actor.animator.current_animation == actor.animation_slots["run"]
	var distance := offset.length()
	if not block_stance and shuffle_pace<=0. and is_server and offset.z > 0.75 and offset.z > absf(offset.x):
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
	actor.rotation.y = rotate_toward(actor.rotation.y,yaw,delta*minf(turn_rate,GymPaths.TURN_RATE))
	var sprint: bool = may_run and actor.stamina.can_sprint() and heading.dot(actor.basis.z.normalized()) >= run_alignment
	var previous_body_pose := {}
	if paced_run:
		var rig: Skeleton3D = actor.skeleton
		for joint in ["pelvis","spine_01","spine_02","spine_03","neck_01","head","thigh_l","thigh_r","calf_l","calf_r","foot_l","foot_r","ball_l","ball_r"]:
			var bone := rig.find_bone(joint)
			if bone >= 0: previous_body_pose[bone] = rig.get_bone_pose(bone)
	var pace := shuffle_pace if shuffle_pace>0. else minf(speed,4.35)*CPU_SHUFFLE_SPEED_SCALE
	if sprint:
		pace = clampf(speed,0.65,CPU_SPRINT_SPEED) if paced_run else clampf(speed*1.24,5.85,CPU_SPRINT_SPEED)
	if roster_active and exhibition:
		pace*=lerpf(.78,1.18,float(actor.attributes.Speed)/100.)
	var block_scale:=1.
	if six_on_six() and not sprint and local.z>=2.9 and actor.position.z>=2.25 and flight_kind in ["pass","set"] and team(index)!=receiving_team and Formation.zone(lineup_role(index),setter_zones[team(index)]) in [2,3,4]:
		block_scale=lerpf(1.,GroundMovement.block_shuffle_scale(actor),absf(heading.x))
		pace*=block_scale
	if sprint: actor.stamina.spend(delta*actor.stamina.SPRINT_DRAIN,"Sprint")
	var before := actor.position
	var velocity: Vector3 = court_velocities.get(index,Vector3.ZERO)
	if match_clock-float(movement_times.get(index,match_clock))>delta*2.: velocity=Vector3.ZERO
	var acceleration:=GymPaths.WALK_ACCELERATION*block_scale
	# A planted shuffle brakes toward the new lane before accelerating back across.
	if shuffle_pace>0. and velocity.dot(heading)<0.:
		acceleration*=2.
	if roster_active and exhibition: acceleration*=lerpf(.82,1.15,float(actor.attributes.Athleticism)/100.)
	velocity=velocity.move_toward(heading*minf(pace,sqrt(2.*acceleration*distance)),acceleration*delta)
	if delta>0.:
		# Brake at the shoulder even if the incoming shuffle still carries lateral speed.
		var left_speed:=minf(0.,limits.x-actor.position.x)/delta
		var right_speed:=maxf(0.,limits.y-actor.position.x)/delta
		velocity.x=clampf(velocity.x,left_speed,right_speed)
	var passer:=priority_passer(index)
	if passer>=0 and delta>0.:
		var away:Vector3=(actor.position-players[passer].position).slide(Vector3.UP)
		var gap:=away.length()
		if gap>.001 and gap<1.15:
			var normal:=away/gap
			var passer_velocity:Vector3=court_velocities.get(passer,Vector3.ZERO)
			if match_clock-float(movement_times.get(passer,-INF))>2.*delta: passer_velocity=Vector3.ZERO
			var closing:float=(passer_velocity-velocity).dot(normal)
			var allowed:=maxf(0.,gap-.62)/delta
			if closing>allowed: velocity+=normal*(closing-allowed)
	movement_times[index]=match_clock
	court_velocities[index]=velocity
	var world_step := frames[team(index)].global_basis*(velocity*delta).limit_length(distance)
	var safe := gym_contacts.travel(self,actor.global_position,world_step,actor.height_cm*.01)
	var step_target := frames[team(index)].to_local(safe)
	var grounded := Court.clamp_setter(step_target,CPU_COURT_FRONT_LIMIT)
	if is_server and before.z < Court.RUNOFF_NEAR_BASELINE:
		grounded.z = clampf(step_target.z,before.z,CPU_COURT_FRONT_LIMIT)
	if step_target.z>grounded.z+.00001 and velocity.z>0.:
		court_velocities[index].z=0.
	grounded.y = move_toward(before.y,PLAYER_GROUND_Y,delta*1.25)
	actor.position = grounded
	var movement := actor.basis.inverse()*(actor.position-before).slide(Vector3.UP)
	if actor.mirror_animation: movement.x = -movement.x
	actor.animator.speed_scale = lerpf(1.60,1.92,smoothstep(5.85,8.4,pace)) if sprint else 1.0
	if sprint and paced_run:
		actor.animator.speed_scale = run_cadence if run_cadence > 0.0 else clampf(pace/3.7,0.22,2.05)
	var reverse: bool=not block_stance and shuffle_pace<=0. and actor.backpedaling((actor.position-before)/maxf(delta,.001))
	if reverse: actor.play_travel_gait((actor.position-before)/maxf(delta,.001))
	else: actor.play_action("run" if sprint else "idle",0.10)
	actor.animator.advance(delta)
	var steps := footwork[index]
	if sprint or reverse:
		steps.weight = 0.0
	else:
		steps.step(movement.limit_length(delta*2.1)/maxf(delta*2.1,0.001),delta,clampf(pace/2.06,0.65,2.25),true,block_stance)
	if not previous_body_pose.is_empty():
		var rig: Skeleton3D = actor.skeleton
		var weight := 1.0-exp(-delta/0.066)
		for bone in previous_body_pose:
			var pose: Transform3D = previous_body_pose[bone].interpolate_with(rig.get_bone_pose(bone),weight)
			rig.set_bone_pose_rotation(bone,pose.basis.get_rotation_quaternion())
			rig.set_bone_pose_position(bone,pose.origin)
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
	var first := first_on(side)
	if side == possession_team and touches > 0 and not last_was_block:
		cpu_choice = setter_for_pass(last_player) if touches == 1 else (partner_of(last_player) if count_for(side) == 2 else nearest_on_team(side,point,last_player))
	elif defensive_ball():
		var best_cost := INF
		for index in slots_for(side):
			if cannot_cover_own_attack(index): continue
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
	elif count_for(side) >= 3:
		cpu_choice = nearest_on_team(side,point)
	elif point.distance_squared_to(players[first].global_position) <= point.distance_squared_to(players[first+1].global_position):
		cpu_choice = first
	else: cpu_choice = first+1
	if not spectator and side == 0 and cpu_choice == 0 and side != possession_team and not is_finite(platforms[0].pressed_at):
		if point.slide(Vector3.UP).distance_to(human.global_position.slide(Vector3.UP)) > 1.65:
			var fallback:=nearest_on_team(0,point,0,previous_attacker if last_was_block else -1)
			if fallback>=0: cpu_choice=fallback
	cpu_technique = 0
	cpu_dump = false
	cpu_fake_dump = false
	if is_human(cpu_choice): return
	var second_ball := side == possession_team and touches == 1 and flight_kind == "pass"
	if second_ball and overhead_available(cpu_choice,2):
		cpu_technique = 2
	elif overhead_available(cpu_choice,1):
		cpu_technique = 1
	if second_ball and not (side==0 and called_this_pass) and not excluded_from_attack(cpu_choice):
		second_ball_options += 1
		var hand_point := frames[side].to_local(path_point(arrival(2.35 if cpu_technique == 2 else 1.92)))
		var tight := hand_point.z >= 2.65 and hand_point.z <= 3.70
		var can_fake := cpu_technique == 2 and hand_point.z >= 1.9 and hand_point.z <= 3.70
		if cpu_technique != 0 and (tight or can_fake):
			cpu_dump = tight and second_ball_options%3 == 0
			cpu_fake_dump = can_fake and second_ball_options%3 == 2

static func setter_gait(distance:float) -> int:
	if distance>2.5: return 2
	if distance>.9: return 1
	return 0

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

# Keep the whole takeoff footprint behind the attack line. The ball itself can be in front.
const LIBERO_PLANT_Z := Net.NET_Z - 3.0 - 0.48

func libero_plant(stance:Vector3) -> Vector3:
	return Vector3(stance.x,PLAYER_GROUND_Y,minf(stance.z,LIBERO_PLANT_Z))

func libero_launch_speed(index:int,offset:Vector3) -> float:
	var approach:Vector3=court_velocities.get(index,Vector3.ZERO)
	return clampf(1.5 + approach.dot(offset.normalized()),1.5,4.35)

func libero_feet_behind_line(index:int) -> bool:
	var rig:Skeleton3D=players[index].skeleton
	for name_ in ["foot_l","foot_r","ball_l","ball_r"]:
		var foot:=rig.to_global(rig.get_bone_global_pose(rig.find_bone(name_)).origin)
		if frames[team(index)].to_local(foot).z+.07>=Net.NET_Z-3.: return false
	return true

func cancel_cpu_jump_set(index:int) -> void:
	platforms[index].reset()
	jump_set_started[index]=false
	cpu_technique=1 if overhead_available(index,1) else 0
	cpu_fake_dump=false
	cpu_dump=cpu_dump and cpu_technique==1
	next_touch_cue=INF
	queue_receive(index,cpu_technique)

func overhead_available(index: int, technique: int) -> bool:
	if not is_human(index) and flight_kind == "serve" and not drill_feed_acceleration.is_finite() and serve.get_script() == SERVES[TOPSPIN_SERVE]: return false
	var first_contact := technique == 1 and (defensive_ball() or flight_kind == "serve")
	var setting := cpu_is_setting(index)
	var height := hand_contact_height(technique)
	var at := arrival(height)
	if first_contact and not is_human(index) and cpu_prefers_fast_forearms(index,at): return false
	var frame := frames[team(index)]
	var point := frame.to_local(path_point(at))
	var actor := players[index]
	if setting and six_on_six() and active_identities.get(index,-1)==6:
		if technique!=2 or actor.position.z>=Net.NET_Z-3.: return false
		var stance:=point-toward_incoming(index,path_point(at))*hand_receive_reach(index)
		var plant:=libero_plant(stance)
		var runway:=(plant-actor.position).slide(Vector3.UP).length()
		var drift:=(stance-plant).slide(Vector3.UP)
		var max_height:=jump_inches(index,attack_vertical)*.0254
		var lift:=clampf((point.y-PLAYER_GROUND_Y-1.72)*1.12,minf(.56,max_height),max_height)
		var rise:float=set_jumps[index].flight_duration(lift,true)*.43
		var speed:=minf(4.35,libero_launch_speed(index,drift)+sqrt(2.*GymPaths.WALK_ACCELERATION*runway))
		if point.y>PLAYER_GROUND_Y+Bump.HandPose.CONTACT_HEIGHT+lift*set_jumps[index].COURT_VERTICAL_SCALE+.12: return false
		if runway>.23+maxf(0.,at-elapsed-rise-.045)*4.35 or drift.length()>speed*rise+.14: return false
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
	if excluded_from_attack(index): return false
	if team(index)==0 and called_this_pass and cpu_is_setting(index): return false
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
	driver.cpu_middle_attack=false
	driver.off_net_shovel=false
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

var line_read_error := 0.

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
	if expected_hitter >= 0 and flight_kind == "set":
		var hitter := expected_hitter
		var driver := attackers[team(hitter)]
		if not is_human(hitter):
			if driver.jump.active: return
			var remaining: float = driver.pin_arrival-(driver.clock-driver.stage_start)
			var forecast: Vector3 = frames[team(hitter)].to_local(path_point(clampf(driver.pin_arrival,elapsed,flight_end())))
			var pin_outlet:=six_on_six() and absf(driver.rally_set_target.x)>2.5 and forecast.y>Net.NET_TOP+.02 and forecast.z<Net.NET_Z-.15
			var safe_lane := pin_outlet or cpu_spike_has_lane(forecast)
			var approach_window := 0.28 if last_set_apex < 3.65 else 0.54
			if safe_lane and driver.enabled and remaining > approach_window:
				prepare_cpu_approach(hitter,driver,delta)
				return
			if six_on_six() and safe_lane and driver.enabled and not driver.approach_jump_queued and remaining>0. and not recoveries.has(hitter):
				# Check every reachable approach before switching to a save.
				driver.try_queue_approach(false)
				if driver.approach_jump_queued:
					driver.approach_space_held=true
					show_key(hitter,"Space")
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
	var assigned_second:=six_on_six() and flight_kind=="pass" and touches==1 and receiving_team==possession_team
	if not assigned_second and not spectator and receiving_team == 0 and is_finite(platforms[0].pressed_at) and not blocks.has(0): index = 0
	if index < 0 or blocks.has(index) or cannot_cover_own_attack(index): return
	if not is_human(index) and last_player>=0 and team(last_player)!=team(index):
		if Flight.reads_out(path_point(flight_end()),line_read_error,players[index].effective_rating("Forearm reception")):
			players[index].pose_leave_ball(elapsed)
			return
	if cpu_second_spike: return
	if not is_human(index) and not is_finite(platforms[index].pressed_at):
		var planned_attack := cpu_dump or overpass_flight == flight_number
		var opportunistic_attack := cpu_is_setting(index) and not cpu_fake_dump and not drill_set_pin.is_finite()
		if (planned_attack or opportunistic_attack) and start_second_ball_spike(index,not planned_attack): return
	var frame := frames[team(index)]
	var bump := platforms[index]
	var technique := requested if is_human(index) else cpu_technique
	if not is_human(index) and flight_kind in ["spike","dump"]:
		var lead:=dig_intercept(index)-elapsed
		if lead>0. and lead<=.35:
			key_labels[index].text="LT"
			key_until[index]=match_clock+.12
	if not is_human(index) and defensive_ball() and not recoveries.has(index) and not set_jumps[index].active and not bump.low_save.active:
		if cpu_reception.cpu_dig(self,index,previous): return
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
	if manual and is_human(index) and (manual.reception.eligible(self) or manual.context()=="set"): return
	if is_human(index) and technique < 0: return
	if is_human(index) and not is_finite(bump.pressed_at) and elapsed-request_age < 0.44: queue_receive(0,technique)
	if technique == 0 and not can_play_forearms(index): return
	var height := 1.10 if technique == 0 else hand_contact_height(technique)
	var is_dig := defensive_ball()
	if is_dig and not is_human(index) and elapsed<players[index].reaction_seconds(): return
	var hand_pass := technique == 1 and flight_kind == "serve"
	var forearm_dig := technique == 0 and is_dig
	var cpu_dig := forearm_dig and not is_human(index)
	if not is_finite(next_touch_cue):
		next_touch_cue = dig_intercept(index) if cpu_dig else arrival(height)
	var cue := next_touch_cue
	var catch_point := path_point(cue)
	if not is_human(index) and frame.to_local(catch_point).z > Net.NET_Z+0.07: return
	var actor := players[index]
	var max_set_jump := jump_inches(index,attack_vertical)*0.0254
	var set_jump_height := clampf((catch_point.y-actor.global_position.y-1.72)*1.12,minf(0.56,max_set_jump),max_set_jump)
	var set_jump_rise := 0.0
	var libero_jump:bool=cpu_setting and six_on_six() and active_identities.get(index,-1)==6 and technique==2
	var libero_stance:=Vector3.ZERO
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
		var before_set_yaw := actor.rotation.y
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
		if cpu_setting: face=Bump.HandPose.zone_four_facing(actor.position,ZONE_FOUR)
		var offset := (FOREARM_DIG_REACH if cpu_dig else 0.52) if technique == 0 else hand_receive_reach(index)
		if not recovering and not set_jumps[index].active and not bump.low_save.active and not bump.reach.get("deep_side",false):
			var spacing := 0.88 if square_receive and cpu_dig and cue < 0.40 else offset
			var target := catch_point-frame.global_basis*face*spacing
			if libero_jump:
				libero_stance=frame.to_local(target)
				target=frame.to_global(libero_plant(libero_stance))
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
			if cpu_setting:
				var gait:=setter_gait(set_travel)
				var pace:=GroundMovement.speed(true,gait!=0)
				move_cpu(index,target,delta,pace,face,false,false,Bump.HandPose.CPU_SQUARE_RATE,false,0.,pace)
			else:
				move_cpu(index,target,delta,speed,face,not square_receive and not backshuffle and not plant and (is_dig or free_ball or flight_kind == "serve"),(run_to_drop or turn_for_save or lateral_run) and not plant and not backshuffle,18.0 if lateral_run else 12.5)
			bump.low_save_approach_velocity = (actor.position-before_move)/maxf(delta,0.001)
			set_jump_plant_gap = (target-actor.global_position).slide(Vector3.UP).length()
		if cpu_setting:
			# Footwork, jump anticipation and arm targets share one bounded LT turn.
			actor.rotation.y=rotate_toward(before_set_yaw,atan2(face.x,face.z),delta*Bump.HandPose.CPU_SQUARE_RATE)
		var prep := set_jump_rise+0.16 if technique == 2 else (0.40 if cpu_dig else (0.18 if cpu_setting and technique == 0 else 0.27))
		if elapsed >= cue-prep: queue_receive(index,technique)
	if not is_finite(bump.pressed_at): return
	if touched_tape and not net_hit.is_empty() and elapsed < float(net_hit.release_time): return
	if recovering: recoveries.erase(index)
	if technique == 2 and not jump_set_started[index] and cue-elapsed <= set_jump_rise+0.13:
		var carry:=Vector3.ZERO
		var legal_takeoff:=true
		if libero_jump:
			var travel:=(libero_stance-actor.position).slide(Vector3.UP)
			carry=(travel/maxf(.01,set_jump_rise)).limit_length(libero_launch_speed(index,travel))
			legal_takeoff=libero_feet_behind_line(index) and travel.distance_to(carry*set_jump_rise)<=.14
		if not is_human(index) and (set_jump_plant_gap > 0.38 or not legal_takeoff):
			if cue-elapsed > set_jump_rise+0.045:
				return
			cancel_cpu_jump_set(index)
			return
		jump_set_started[index] = true
		set_jumps[index].front_limit = 3.35
		set_jumps[index].begin_set_jump(actor,clampf(cue-elapsed-set_jump_rise,0.055,0.16),set_jump_height)
		if libero_jump: set_jumps[index].carry_velocity=carry
	if libero_jump and (not set_jumps[index].active or set_jumps[index].elapsed<=set_jumps[index].load_duration()): return
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
	if cpu_setting and technique==0 and catch_point.y>.55 and (actor.global_position-catch_point).slide(Vector3.UP).length()<1.12:
		# A reachable second ball uses the focused platform. A dive takes over the root yaw.
		bump.allow_auto_dive=false
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
	for index in slots_for(side):
		if is_human(index) and match_clock > kick_pressed_until: continue
		if cannot_cover_own_attack(index) or (index == last_player and not last_was_block): continue
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
	for index in slots_for(receiving_team):
		if index == last_player or cannot_cover_own_attack(index): continue
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

func start_block(index: int, remaining := INF, reads_second := false, overpass_swing := false, partner_push := false) -> void:
	if six_on_six() and Formation.zone(lineup_role(index),setter_zones[team(index)]) in [1,5,6]: return
	if manual and team(index)==0 and not is_human(index) and manual.block_call==manual.BlockCall.OFF and not overpass_swing: return
	if manual and index==0 and manual.reception.landing_actor!=null: return
	if blocks.has(index) or set_jumps[index].active: return
	if recoveries.has(index): return
	var actor := players[index]
	if manual and is_human(index):
		if manual.service.plant.active: return
	elif serve.player == actor and not serve.can_run_after_contact(): return
	if (not manual or not is_human(index)) and (actor.position.z < 2.25 or actor.position.z > Net.NET_Z-.10): return
	var block := Block.new()
	block.jump_height = jump_inches(index,block_vertical,"Block jump")*0.0254
	var base_vertical := jump_inches(index,block_vertical)*0.0254
	if manual and is_human(index):
		block.jump_height *= actor.stamina.effectiveness()
		base_vertical *= actor.stamina.effectiveness()
	if not overpass_swing: block.net_heading = 0.0
	block.landing_recovery = 0.43 if reads_second else 0.13
	block.overpass_swing = overpass_swing
	block.aggressive_press = not is_human(index) and not overpass_swing
	if six_on_six() and not overpass_swing:
		block.seal_angle=-clampf(actor.position.x/3.6,-1.,1.)*deg_to_rad(24.)
	block.begin(actor,maxf(0.,manual.block_buffer) if manual and is_human(index) else (1. if partner_push else 0.),base_vertical)
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
	var first_touch:Dictionary={}
	var touched_by:=-1
	for index in blocks.keys():
		var block = blocks[index]
		if manual and is_human(index):
			block.read_air_lane(ball.global_position,players.slice(0,team_size))
			block.lean_input=-manual.axis(JOY_AXIS_LEFT_X)
			block.reach_input=Vector2(manual.axis(PromptControls.trigger(true)),manual.axis(PromptControls.trigger(false)))
		elif not is_human(index):
			block.read_air_lane(ball.global_position,players.slice(first_on(team(index)),first_on(team(index))+count_for(team(index))))
		if not block.step(delta,ball.global_position):
			blocks.erase(index)
			continue
		animated[index] = true
		if not incoming_spike or team(index) != receiving_team: continue
		var before := path_point(previous)
		var after := ball.global_position
		if exhibition and not block.overpass_swing:
			var hit:Dictionary=block.first_block_touch(before,after,Net.RADIUS)
			if not hit.is_empty() and (first_touch.is_empty() or hit.fraction<first_touch.fraction):
				first_touch=hit
				touched_by=index
			continue
		for sample in 7:
			var fraction := sample/6.0
			var point := before.lerp(after,fraction)
			for hand in block.hands.size():
				if block.overpass_swing and (overpass_flight != flight_number or hand != 1 or block.age < 0.31 or block.age > 0.79): continue
				var tip: Vector3 = block.previous_hands[hand].lerp(block.hands[hand],fraction)
				var wrist: Vector3 = block.previous_wrists[hand].lerp(block.wrists[hand],fraction)
				var center := Geometry3D.get_closest_point_to_segment(point,wrist,tip)
				var gap := point.distance_to(center)
				var reach := 0.28 if block.overpass_swing else (Block.ARM_RADII[2]+(0.18 if block.aggressive_press else 0.15))
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
				if power > 0.56:
					rebound = rebound.normalized()*speed*Block.STUFF_SPEED_RETENTION
				trace.write("block_contact",match_clock,{"power":power,"palm_gap":palm_gap,"along":along,"tight":tight,"point":point,"rebound":rebound})
				stroke = "Stuff block" if power > 0.56 else "Block"
				play_touch()
				var over := rebound.dot(backward) > 0.0
				launch(point,rebound,"free" if over else "block",index)
				return

		if not block.overpass_swing:
			var body: Dictionary=block.body_hit(before,after,Net.RADIUS)
			if not body.is_empty() and can_touch(index,true):
				var rebound := velocity*.22
				rebound.y=maxf(3.2,absf(rebound.y))
				stroke="Block touch / "+str(body.part)
				trace.write("block_contact",match_clock,{"blocker":index,"part":body.part,"point":body.point,"rebound":rebound})
				play_touch()
				launch(body.point,rebound,"block",index)
				return
	if touched_by>=0 and can_touch(touched_by,true):
		var incoming:Vector3=(ball.global_position-path_point(previous))/maxf(.0001,elapsed-previous)
		var result:Dictionary=blocks[touched_by].block_rebound(first_touch,incoming,1. if team(touched_by)==1 else -1.)
		var rebound:Vector3=result.velocity
		stroke=("Stuff block / " if result.stuff else "Block touch / ")+str(first_touch.part)
		trace.write("block_contact",match_clock,{"blocker":touched_by,"part":first_touch.part,"point":first_touch.point,"rebound":rebound})
		play_touch()
		launch(first_touch.point,rebound,"free" if rebound.dot(frames[team(touched_by)].global_basis.z)>0. else "block",touched_by)

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
	var speed := maxf(9.,26.*spike_strength)
	var spin_rate := 6.0
	var acceleration := Vector3.DOWN*Flight.spike_gravity(spin_rate)
	var time := Flight.strike_time(offset,acceleration,speed)
	var motion := Flight.strike_velocity(offset,acceleration,time,speed)
	var tactic := choose_contact_attack(index,contact,shot,motion,spin_rate)
	if not tactic.is_empty():
		shot = tactic.target
		motion = tactic.motion
	if not can_touch(index): return false
	stroke = "Overpass attack"
	var world_motion := frame.global_basis*motion
	trace.write("overpass_attack",match_clock,{"player":index,"point":point,"target":shot,"blocker":defender},true)
	play_touch(world_motion.length()>=preload("res://scripts/gym_physics.gd").HARD_SPIKE_SPEED)
	observe_opponent_shot(1-side,point,world_motion,spin_rate,index)
	launch(point,world_motion,"spike",index,spin_rate)
	return true

func priority_passer(index:int) -> int:
	if flight_kind not in ["serve","pass"] or not six_on_six() or is_human(index) or receiving_team!=team(index): return -1
	var passer:=cpu_choice if flight_kind=="serve" else last_player
	if passer<0 or index==passer or index==rally_setter or team(index)!=team(passer): return -1
	return passer

func route_around_passer(index:int, target:Vector3) -> Vector3:
	var priority:=priority_passer(index)
	if priority<0: return target
	var here:=players[index].position.slide(Vector3.UP)
	var passer:=players[priority].position.slide(Vector3.UP)
	if here.distance_squared_to(passer)>2.4*2.4: return target
	var destination:=target.slide(Vector3.UP)
	var toward:=here.direction_to(destination)
	var ahead:=(passer-here).dot(toward)
	if ahead<=0.: return target
	if here.distance_squared_to(destination)<.0001: return target
	if Geometry3D.get_closest_point_to_segment(passer,here,destination).distance_to(passer)>=.72: return target
	var exit_direction:=passer.direction_to(destination)
	if passer.distance_to(destination)<.72:
		var stop:=passer+passer.direction_to(here)*.76
		return Vector3(stop.x,target.y,stop.z)
	if (here-passer).dot(exit_direction)>=.70: return target
	var lateral:=Vector3.UP.cross(exit_direction)
	if (here-passer).dot(lateral)<0.: lateral=-lateral
	var advance:=clampf((here-passer).dot(exit_direction)+.35,0.,passer.distance_to(destination))
	var center:=passer+exit_direction*advance
	var bypass:=center+lateral*1.05
	if absf(bypass.x)>4.5 or bypass.z>CPU_COURT_FRONT_LIMIT: bypass=center-lateral*1.05
	return Vector3(bypass.x,target.y,bypass.z)

func peel_cpu_off_net(index: int, staging: Vector3, delta: float) -> void:
	if recoveries.has(index):
		var recovery: Dictionary = recoveries[index]
		if recovery.has("save") or match_clock-float(recovery.started) < 0.11: return
		recoveries.erase(index)
	var frame := frames[team(index)] as Node3D
	var sight := GroundMovement.forward_sight(frame.to_local(ball.global_position)-players[index].position)
	move_cpu(index,frame.to_global(route_around_passer(index,staging)),delta,4.1,sight,false,false,3.5)

func move_cpu_to_approach(hitter: int, staging: Vector3, delta: float, speed: float) -> void:
	staging=route_around_passer(hitter,staging)
	var offset := (staging-players[hitter].position).slide(Vector3.UP)
	var running := offset.z > 0.12 and offset.length() > 0.18
	move_cpu(hitter,frames[team(hitter)].to_global(staging),delta,speed,Vector3.INF,running,running,17.0,true)

static func zone_four_flight_time(span:float) -> float:
	return clampf(span/3.45,0.,1.70)

func pin_staging(index:int,lane:Vector3) -> Vector3:
	var stage:=GroundMovement.attack_staging(lane)
	if six_on_six() and absf(lane.x)>2.5 and Formation.zone(lineup_role(index),setter_zones[team(index)]) in [2,3,4]:
		stage.x=signf(lane.x)*5.22
		stage.z=minf(stage.z,lane.z-2.25)
	return stage

func prepare_cpu_approach(hitter: int, driver: Node3D, delta: float) -> void:
	if driver.approach_jump_queued: return
	var actor := players[hitter]
	var pin: Vector3 = driver.rally_set_target
	var time_left: float = driver.pin_arrival-(driver.clock-driver.stage_start)
	var gap := (pin-actor.position).slide(Vector3.UP).length()
	var staging := GroundMovement.attack_staging(pin)
	if six_on_six() and pin.x>2.5:
		# Start the run from the sideline, then plant on the line to the ball.
		# Moving back to the generic inner staging spot wastes the outside runway.
		var plant:Vector3=driver.spike_body_target(pin)
		staging.x=plant.x+.42
		staging.z=plant.z-1.48
	if six_on_six() and pin.x>2.5 and last_set_apex>=4.95 and actor.position.x>4.45 and gap>1.55:
		# An outside hitter with a runway can start in as soon as the set is read.
		# Continuing to stage outside spends the first half of the set moving away.
		var plant:Vector3=driver.spike_body_target(pin)
		var inward:Vector3=(plant-actor.position).slide(Vector3.UP).normalized()
		var runway:float=(plant-actor.position).slide(Vector3.UP).length()
		if time_left<=.98 and runway<=2.55:
			var stride:Vector3=court_velocities.get(hitter,Vector3.ZERO)
			if stride.dot(inward)>1.4: driver.queue_run_plant(stride)
			if not driver.approach_jump_queued: driver.try_queue_approach(false)
			if driver.approach_jump_queued:
				driver.approach_space_held=true
				show_key(hitter,"Space")
				return
		move_cpu_to_approach(hitter,plant-inward*.65,delta,6.2)
		return
	if follow_run_into_plant(hitter,driver,staging,time_left,delta): return
	var peeling := actor.position.z > pin.z-1.70 and time_left > 0.82
	if peeling:
		peel_cpu_off_net(hitter,staging,delta)
		return
	if recoveries.has(hitter): return
	if gap < 1.86 and time_left > 0.95 and last_set_apex > 4.85:
		move_cpu_to_approach(hitter,staging,delta,2.8)
		return
	if not driver.approach_space_held:
		var run_up_gap := (staging-actor.position).slide(Vector3.UP).length()
		var commit_time:=.80 if six_on_six() and pin.x>2.5 else .68
		if (time_left <= 0.88 and gap <= 2.40 and run_up_gap <= 0.35) or time_left <= commit_time:
			# Use the same shortest feasible approach as the player input path.
			driver.try_queue_approach(false)
			if driver.approach_jump_queued:
				driver.approach_space_held=true
				show_key(hitter,"Space")
				return
	var distance := (staging-actor.position).slide(Vector3.UP).length()
	if distance > 0.12:
		var speed := clampf(distance/maxf(0.05,time_left-0.82),0.65,CPU_SPRINT_SPEED)
		move_cpu_to_approach(hitter,staging,delta,speed)

func follow_run_into_plant(hitter: int, driver: Node3D, staging: Vector3, time_left: float, delta: float) -> bool:
	var actor := players[hitter]
	var animator: AnimationPlayer = actor.animator
	var run: String = actor.animation_slots["run"]
	if recoveries.has(hitter) or animator.current_animation != run or time_left < 0.54 or time_left > 1.2: return false
	# Hand off on an earlier running plant to leave room for both takeoff steps.
	var entry_target := staging+Vector3.BACK*0.43
	var offset := (entry_target-actor.position).slide(Vector3.UP)
	if offset.z < -0.35 or offset.length() > 2.2: return false
	var before := animator.current_animation_position
	var length := animator.current_animation_length
	var until_left: float = driver.run_left_plant_distance()
	var window := clampf(time_left-0.89,0.09,0.36)
	var cadence := move_toward(animator.speed_scale,clampf(until_left/window,1.4,1.85),delta*6.0)
	var speed := clampf(offset.length()/maxf(window,until_left/maxf(cadence,0.1)),1.45,4.6)
	var before_position := actor.position
	var run_target := entry_target+Vector3.BACK*0.75
	move_cpu(hitter,frames[team(hitter)].to_global(run_target),delta,speed,Vector3.INF,true,true,17.0,true,cadence)
	if animator.current_animation != run: return true
	if driver.record_run_footfalls(before,animator.current_animation_position,length) and time_left <= 1.03:
		driver.queue_run_plant((actor.position-before_position)/delta)
		if driver.approach_jump_queued: show_key(hitter,"Space")
	return true

var interrupted_hitters:Dictionary={}
var yielding:Dictionary={}

func clear_setter_lane(side:int,delta:float) -> void:
	var setter:=rally_setter
	if setter<0 or team(setter)!=side: return
	var start:=players[setter].position.slide(Vector3.UP)
	var end:=frames[side].to_local(path_point(arrival(hand_contact_height(1)))).slide(Vector3.UP)
	var length:=start.distance_to(end)
	var forward:=start.direction_to(end) if length>=.18 else Vector3.BACK
	var lateral:=Vector3.UP.cross(forward)
	for i in slots_for(side):
		if i==setter or owns_action(i) or recoveries.has(i): continue
		var here:=players[i].position.slide(Vector3.UP)
		var along:=(here-start).dot(forward)
		if along<-.12 or along>minf(2.6,length+.35): continue
		var offset:=(here-start).dot(lateral)
		var lane:=attack_lane_for(i)
		var about_to_cross:=false
		if lane.is_finite() and absf(offset)<=1.35:
			var heading:=(lane-here).slide(Vector3.UP).limit_length(.65)
			about_to_cross=absf(offset+heading.dot(lateral))<.80
		if absf(offset)>.85 and not about_to_cross: continue
		var shoulder:=start.distance_to(here)<.68
		if is_human(i) and not shoulder: continue
		var sign_:float=signf(offset) if absf(offset)>.04 else (1. if i%2==0 else -1.)
		var clearance:=1.45 if about_to_cross else .98
		var target:=here+lateral*(sign_*clearance-offset)
		if absf(target.x)>4.35 or target.z>3.55:
			target=here+lateral*(-sign_*clearance-offset)
		if shoulder:
			interrupted_hitters[i]=true
			if rally_hitter==i: rally_hitter=-1
		yielding[i]=true
		move_cpu(i,frames[side].to_global(target),delta,5.,players[i].basis.z,false,false,9.,false,0.,4.4)

const SETTER_BASE := Vector3(-1.4,PLAYER_GROUND_Y,2.8)

func open_cover_spot(index:int, base:Vector3) -> Vector3:
	var teammates:=slots_for(team(index))
	var here:=players[index].position.slide(Vector3.UP)
	var closest:=INF
	var best:=here
	# Prefer the normal base, then the nearest free spot around it.
	for slot in 9:
		var spot:=base
		if slot>0:
			spot+=Vector3.RIGHT.rotated(Vector3.UP,(slot-1)*TAU/8.)*.95
			spot.z=minf(spot.z,CPU_COURT_FRONT_LIMIT)
		var distance:=here.distance_squared_to(spot.slide(Vector3.UP))
		if distance>=closest: continue
		var occupied:=false
		for i in teammates:
			if i!=index and (players[i].position-spot).slide(Vector3.UP).length_squared()<.68*.68:
				occupied=true
				break
		if occupied: continue
		if slot==0: return spot
		closest=distance
		best=spot
	return Vector3(best.x,PLAYER_GROUND_Y,best.z)

func release_setter_for_cover(side:int,first_contact:int,delta:float) -> void:
	var setter:=first_on(side)+lineup_roles[side].find(0)
	if setter==first_contact or is_human(setter) or owns_action(setter): return
	if recoveries.has(setter):
		var recovery:Dictionary=recoveries[setter]
		if recovery.has("save") or match_clock-float(recovery.started)<.18: return
		recoveries.erase(setter)
	var goal:=frames[side].to_global(open_cover_spot(setter,SETTER_BASE))
	var run:bool=(goal-players[setter].global_position).slide(Vector3.UP).length()>1.
	move_cpu(setter,goal,delta,GroundMovement.speed(not run,run),toward_incoming(setter,goal),run,run)

func cover_pin_attack(hitter:int,delta:float) -> void:
	var side:=team(hitter)
	var target:Vector3=attackers[side].rally_set_target
	if absf(target.x)<2.5 or Formation.zone(lineup_role(hitter),setter_zones[side]) not in [2,3,4]: return
	var back_middle:=2 if Formation.back_row_libero(2,setter_zones[side]) else 5
	var cover:=first_on(side)+lineup_roles[side].find(back_middle)
	if is_human(cover) or cover==last_player or owns_action(cover): return
	var home:=formation_home(cover,true)
	# Cover a deflection behind and inside the hitter while leaving the approach clear.
	var pocket:=Vector3(target.x-signf(target.x)*1.6,PLAYER_GROUND_Y,target.z-2.5)
	var support:=home.move_toward(pocket,2.6)
	var goal:=frames[side].to_global(open_cover_spot(cover,support))
	move_cpu(cover,goal,delta,4.1,toward_incoming(cover,players[cover].global_position))

func position_attack(delta: float) -> void:
	yielding.clear()
	if six_on_six() and flight_kind=="set" and expected_hitter>=0:
		cover_pin_attack(expected_hitter,delta)
		for i in slots_for(receiving_team):
			if i==expected_hitter or is_human(i) or owns_action(i) or animated[i]: continue
			var lane:=attack_lane_for(i)
			if lane.is_finite() and absf(lane.x)>2.5 and Formation.zone(lineup_role(i),setter_zones[receiving_team]) in [2,3,4]:
				peel_cpu_off_net(i,pin_staging(i,lane),delta)
	if six_on_six() and flight_kind=="pass": clear_setter_lane(receiving_team,delta)
	if six_on_six() and flight_kind in ["set","spike"] and last_player>=0:
		release_setter_for_cover(team(last_player),expected_hitter if flight_kind=="set" else last_player,delta)
	if six_on_six() and flight_kind in ["serve","pass"]:
		if cpu_choice<0: select_receiver()
		var side:=receiving_team
		var quick:=flight_kind=="pass" and setter_can_run_middle[side] and rally_setter>=0 and rally_setter!=front_middle(side)
		if quick: prepare_middle_quick(side,delta)
		var designated:=hitter_for_set(rally_setter) if flight_kind=="pass" and rally_setter>=0 else -1
		for i in slots_for(side):
			if yielding.has(i) or is_human(i) or i==cpu_choice or i==designated or owns_action(i) or (quick and i==front_middle(side)): continue
			var lane:=attack_lane_for(i)
			var role:=lineup_role(i)
			var target:=formation_home(i,true)
			if lane.is_finite():
				target=pin_staging(i,lane)
				if role in [2,5]: target.z=1.55
			elif role==0: target=open_cover_spot(i,SETTER_BASE)
			peel_cpu_off_net(i,target,delta)

	if defensive_ball() and flight_kind != "pass":
		var side := receiving_team
		var frame := frames[side]
		var ball_behind_block := frame.to_local(ball.global_position).z < 2.40
		var own_block := last_was_block and last_player >= 0 and team(last_player) == side
		if six_on_six() and last_was_block:
			if cpu_choice<0: select_receiver()
			release_setter_for_cover(side,cpu_choice,delta)
		if ball_behind_block or own_block:
			if cpu_choice < 0: select_receiver()
			var blocker: int = last_player if own_block else defender_assignment[side]
			if blocker >= 0 and cpu_choice >= 0 and cpu_choice != blocker and not is_human(blocker) and not (six_on_six() and last_was_block and lineup_role(blocker)==0) and players[blocker].position.z > 1.20:
				var stage_from := players[blocker].position
				stage_from.z = 0.95
				peel_cpu_off_net(blocker,stage_from,delta)
		return
	if flight_kind != "pass" or possession_team != receiving_team or touches != 1: return
	var setter := setter_for_pass(last_player)
	var hitter := hitter_for_set(setter)
	if six_on_six() and setter_can_run_middle[receiving_team] and hitter==front_middle(receiving_team): return
	if yielding.has(hitter) or is_human(hitter) or blocks.has(hitter) or set_jumps[hitter].active: return
	var receive_at := arrival(1.55)
	var staging := pin_staging(hitter,set_pin_for(setter))
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

func overpass_front_player(side:int,point:Vector3) -> int:
	if not six_on_six():
		return (0 if player_blocks else 1) if side==0 and not spectator else nearest_on_team(side,point)
	var closest:=-1
	var distance:=INF
	for i in slots_for(side):
		if Formation.zone(lineup_role(i),setter_zones[side]) not in [2,3,4]: continue
		var gap:=players[i].global_position.slide(Vector3.UP).distance_squared_to(point.slide(Vector3.UP))
		if gap<distance:
			distance=gap
			closest=i
	return closest

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
	# A set can project across the tape *after* its hitter has already played it.
	# Keep the block assigned to the attack until a genuine overpass is available.
	if flight_kind=="set" and expected_hitter>=0:
		var driver:=attackers[team(expected_hitter)]
		var contact_eta:float=driver.pin_arrival-(driver.clock-driver.stage_start)
		if is_finite(driver.approach_expected_hit_at): contact_eta=driver.approach_expected_hit_at-driver.clock
		if driver.enabled and contact_eta>=-.04 and elapsed+contact_eta<=crossing+.04: return false
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
		overpass_player=overpass_front_player(side,world_target)
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
	var blocker:=overpass_front_player(opposing,wall)
	defender_assignment[opposing] = blocker
	if not is_human(blocker) and not (manual and opposing==0 and manual.block_call==manual.BlockCall.OFF):
		move_cpu(blocker,wall,delta,6.8,Vector3.INF,true)
		if blocks.has(hitter) and blocks[hitter].overpass_swing and eta >= 0.10 and eta <= 0.31 and absf(players[blocker].position.x-opposing_target.x) <= 0.65:
			start_block(blocker,eta+0.075)
	return true

# A set to either antenna gives the pin ownership of the outside shoulder.
# Use the team's saved lanes so the same read works on both sides of the net.
func defend_pin_set(side:int,attack_x:float,driver:Node3D,delta:float) -> void:
	var outward:=signf(attack_x)
	var pin:=-1
	var middle:=-1
	var line:=-1
	for i in slots_for(side):
		var front:=Formation.zone(lineup_role(i),setter_zones[side]) in [2,3,4]
		if front and lineup_role(i) in [2,5]: middle=i
		elif front:
			if pin<0 or outward*formation_home(i,true).x>outward*formation_home(pin,true).x: pin=i
		elif line<0 or outward*formation_home(i,true).x>outward*formation_home(line,true).x: line=i
	if pin<0 or middle<0 or line<0: return
	defender_assignment[side]=pin
	var pin_x:=clampf(attack_x,-4.15,4.15)
	var frame:=frames[side]
	var eta:float=driver.pin_arrival-(driver.clock-driver.stage_start)
	if is_finite(driver.approach_expected_hit_at): eta=driver.approach_expected_hit_at-driver.clock+.045
	if is_finite(driver.swing_drive_started): eta=driver.swing_drive_started+driver.swing_drive_duration*.95-driver.clock+.045
	var trap:bool=(manual and side==0 and manual.block_call in [manual.BlockCall.LEFT,manual.BlockCall.RIGHT]) or repeat_shot_read(side,attack_x).y>=.65
	for i in slots_for(side):
		if is_human(i) or blocks.has(i) or set_jumps[i].active: continue
		var target:=formation_home(i,true)
		var sight:=toward_incoming(i,players[i].global_position)
		if i==pin or i==middle:
			target=Vector3(pin_x,.04,3.42)
			if i==middle:
				var inside:=minf(outward*pin_x,outward*players[pin].position.x)-.68
				target.x=clampf(outward*inside,-4.15,4.15)
			move_cpu(i,frame.to_global(target),delta,7.6,sight,false,false,9.,false,0.,4.7)
			# Keep closing early. At the last plant a square block can still cover part of the lane.
			var block_width:=.68 if eta<=.24 else .38
			if i==pin and eta>=-.04 and eta<=.37 and (absf(players[i].position.x-target.x)<block_width or eta<=.26):
				start_block(i,eta+.025)
				if blocks.has(i):
					blocks[i].square_block=not trap
					blocks[i].net_heading=0.
		else:
			if i==line:
				target.x=clampf(target.x+.48*outward,-4.25,4.25)
				target.z=maxf(-4.94,target.z-2.95)
			elif Formation.zone(lineup_role(i),setter_zones[side]) in [2,3,4]:
				# The far pin covers short balls while the double block closes.
				target.z=minf(target.z,2.10)
			var facing:=GroundMovement.forward_sight(sight) if i==line else sight
			move_cpu(i,frame.to_global(target),delta,4.8,facing)

	if blocks.has(middle) or is_human(middle): return
	var leader:RefCounted=blocks.get(pin)
	var seam:=outward*(players[pin].position.x-players[middle].position.x)
	if not leader or seam<.32 or seam>1.08 or leader.age>Block.START*.65:
		# Plant from the ground even after missing the double-block rendezvous.
		if eta<-.03 or eta>.29: return
		start_block(middle,eta+.035)
		if blocks.has(middle):
			var late:RefCounted=blocks[middle]
			late.square_block=true
			var gap:=absf(players[middle].position.x-pin_x)
			if gap>.72 and gap<=1.65: late.late_quick_x=frame.to_global(Vector3(pin_x,0.,3.42)).x
		return
	var pushing:bool=leader.drive_elapsed<leader.drive_duration
	start_block(middle,INF,false,false,pushing)
	if not blocks.has(middle): return
	var follower:RefCounted=blocks[middle]
	follower.square_block=not trap
	follower.net_heading=0.
	follower.tempo=leader.tempo
	follower.age=leader.age
	if pushing:
		follower.drive_duration=leader.drive_duration
		follower.drive_elapsed=leader.drive_elapsed

func defend_pipe(side:int,x:float,driver:Node3D,delta:float) -> void:
	var middle:=front_middle(side)
	defender_assignment[side]=middle
	var eta:float=driver.pin_arrival-(driver.clock-driver.stage_start)
	if is_finite(driver.approach_expected_hit_at): eta=driver.approach_expected_hit_at-driver.clock+.045
	if is_finite(driver.swing_drive_started): eta=driver.swing_drive_started+driver.swing_drive_duration*.95-driver.clock+.045
	for i in slots_for(side):
		if is_human(i) or owns_action(i): continue
		var home:=formation_home(i,true)
		var front:=Formation.zone(lineup_role(i),setter_zones[side]) in [2,3,4]
		if front:
			var flank:=signf(home.x-formation_home(middle,true).x)
			home=Vector3(x+(0. if i==middle else .70*flank),.04,3.42)
			if i!=middle:
				if flank>0.: home.x=maxf(home.x,players[middle].position.x+.64)
				else: home.x=minf(home.x,players[middle].position.x-.64)
		move_cpu(i,frames[side].to_global(home),delta,7.6,toward_incoming(i,players[i].global_position),false,false,9.,false,0.,4.8)
		if front and eta>=-.04 and eta<=.41 and absf(players[i].position.x-home.x)<.48:
			start_block(i,eta)
			if blocks.has(i): blocks[i].square_block=true

func position_defense(delta: float) -> void:
	if position_overpass(delta): return
	if flight_kind not in ["serve","pass","set","free"]: return
	var hitter_side := receiving_team
	var defense_side := 1-hitter_side
	var frame := frames[defense_side]
	var ordered:bool=manual!=null and defense_side==0 and manual.block_call!=manual.BlockCall.AUTO
	if six_on_six():
		var read_attack:=flight_kind=="set" or (flight_kind=="pass" and possession_team==hitter_side and touches==1)
		for i in range(first_on(defense_side),first_on(defense_side)+6):
			if is_human(i) or blocks.has(i) or set_jumps[i].active: continue
			if read_attack and not (ordered and manual.block_call==manual.BlockCall.OFF): continue
			move_cpu(i,frame.to_global(formation_home(i,true)),delta,5.3,toward_incoming(i,players[i].global_position))
		if not read_attack or (ordered and manual.block_call==manual.BlockCall.OFF): return
	if ordered and manual.block_call==manual.BlockCall.OFF:
		defender_assignment[0]=-1
		for i in range(1,team_size):
			if blocks.has(i): continue
			var lane:=starting_lane(i)
			var depth:float=-1.9 if i<3 else .55
			move_cpu(i,frame.to_global(Vector3(lane*2.85,.04,depth)),delta,4.1,toward_incoming(i,ball.global_position))
		return
	var driver := attackers[hitter_side]
	var tracking_set := flight_kind == "set" and expected_hitter >= 0
	var middle_set:=six_on_six() and tracking_set and expected_hitter==front_middle(hitter_side)
	var threat := frames[hitter_side].to_global(driver.rally_set_target) if tracking_set else path_point(arrival(2.0))
	if six_on_six() and tracking_set and lineup_role(expected_hitter) in [1,4] and Formation.zone(lineup_role(expected_hitter),setter_zones[hitter_side]) in [1,5,6]:
		defend_pipe(defense_side,frame.to_local(threat).x,driver,delta)
		return
	if six_on_six() and tracking_set and not middle_set and absf(frame.to_local(threat).x)>=2.5:
		defend_pin_set(defense_side,frame.to_local(threat).x,driver,delta)
		return
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
		elif six_on_six():
			# Before release the wall can see the pass, the setter and a quick approach.
			# It cannot see the setter's chosen pin.
			threat=frame.to_global(formation_home(front_middle(defense_side),true))
		else:
			var hitter_x := players[hitter_for_set(setter)].position.x
			if not is_human(setter):
				hitter_x = move_toward(hitter_x,set_pin_for(setter).x,0.65)
			threat = attack_frame.to_global(Vector3(hitter_x,0.04,3.20))
	# A real approach cues the middle's feet before release, even if the setter
	# eventually goes to a pin. Keep the jump decision tied to the actual set.
	var shadow_middle:=-1
	var shadow_x:=0.
	var release_pin:=-1
	var wide_base:=0.
	if second_ball and six_on_six() and not ordered:
		var runner:=front_middle(hitter_side)
		var defender:=front_middle(defense_side)
		var approach:=set_jumps[runner]
		if not is_human(defender) and approach.active and quick_actor[hitter_side]==runner and approach.elapsed>=players[defender].reaction_seconds():
			shadow_middle=defender
			var shown:=frame.to_local(players[runner].global_position).x
			var base_x:=formation_home(defender,true).x
			var shade:=minf(1.25,.20+.50*scored_31[hitter_side]) if absf(shown-base_x)>.60 else .55
			shadow_x=move_toward(base_x,shown,shade)
			if absf(shown-base_x)>.60:
				for i in slots_for(defense_side):
					if Formation.zone(lineup_role(i),setter_zones[defense_side]) not in [2,3,4]: continue
					var home_x:=formation_home(i,true).x
					if (home_x-base_x)*(shown-base_x)<0.:
						release_pin=i
						wide_base=move_toward(home_x,signf(home_x-base_x)*3.55,.95)
						break
			quick_read_flight[defense_side]=flight_number
	var x := frame.to_local(threat).x
	var first := first_on(defense_side)
	var near: int = defender_assignment[defense_side]
	if defense_side == 0 and not spectator:
		near = 0 if player_blocks else 1
		if ordered and manual.block_call==manual.BlockCall.COMMIT: near=manual.middle_for_call()
		elif ordered and team_size>=3:
			var wall:=frame.to_global(Vector3(x,.04,3.42))
			near=nearest_on_team(0,wall,0)
	elif near < 0:
		near = first if absf(players[first].position.x-x) < absf(players[first+1].position.x-x) else first+1
		if count_for(defense_side) >= 3:
			near = nearest_on_team(defense_side,frame.to_global(Vector3(x,0.04,3.42)))
	if six_on_six() and second_ball and not ordered:
		# Read from the assigned front-row lane until the setter actually releases.
		var nearest_lane:=INF
		for candidate in slots_for(defense_side):
			if Formation.zone(lineup_role(candidate),setter_zones[defense_side]) not in [2,3,4]: continue
			var lane_gap:=absf(formation_home(candidate,true).x-x)
			if lane_gap<nearest_lane:
				near=candidate
				nearest_lane=lane_gap
	if middle_set:
		near=front_middle(defense_side)
	if six_on_six() and Formation.zone(lineup_role(near),setter_zones[defense_side]) not in [2,3,4]:
		var best:=INF
		for i in range(first,first+6):
			if Formation.zone(lineup_role(i),setter_zones[defense_side]) not in [2,3,4]: continue
			var gap:=players[i].position.distance_to(Vector3(x,.04,3.42))
			if gap<best:
				best=gap
				near=i
	defender_assignment[defense_side] = near
	var depth := -2.15
	var cover := -x*0.48
	var deep := partner_of(near)
	if count_for(defense_side) >= 3:
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
		var shoulder_call:bool=ordered and manual.block_call in [manual.BlockCall.LEFT,manual.BlockCall.RIGHT]
		if shoulder_call: block_line[defense_side]=manual.called_line(attack.x)
		var take_line: bool = block_line[defense_side]
		if is_human(near):
			take_line = absf(players[near].position.x-line_x) <= absf(players[near].position.x-cross_x)
		x = line_x if take_line else cross_x
		if shoulder_call and absf(attack.x)<.55: x=attack.x+(.32 if manual.block_call==manual.BlockCall.LEFT else -.32)
		if not is_human(near) and not shoulder_call:
			var pattern: RefCounted=players[near].block_read(players[expected_hitter])
			if not pattern.history.is_empty():
				x+=clampf(attack.x+pattern.shade(attack.z-Net.NET_Z,driver.approach_expected_hit_at-driver.clock)-x,-1.55,1.55)*lerpf(.70,1.,pattern.confidence)
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
			if not is_human(near) and not shoulder_call:
				x += clampf(crossing-x,-0.60,0.60)*0.60
		if attack_aim_flight == flight_number or is_finite(driver.swing_drive_started):
			var read := frame.to_local(frames[hitter_side].to_global(driver.swing_aim))
			var front_limit := 0.25 if is_finite(driver.swing_drive_started) else -1.30
			var read_depth := clampf(lerpf(attack.z,read.z,0.72),-3.25,front_limit)
			var read_x := lane_at_depth(attack,read,read_depth)
			cover += clampf(read_x-cover,-2.30,2.30)
			depth = lerpf(depth,read_depth,0.72)
		if is_finite(hit_at): remaining = hit_at-driver.clock+0.045
		elif six_on_six(): remaining=driver.pin_arrival-(driver.clock-driver.stage_start)
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
	var commit:bool=ordered and manual.block_call==manual.BlockCall.COMMIT
	if commit and second_ball:
		var setter:=setter_for_pass(last_player)
		var middle:=hitter_for_set(setter)
		var lane:=set_pin_for(setter)
		var pass_meet:=frames[hitter_side].to_local(path_point(arrival(hand_contact_height(1))))
		if absf(lane.x)<1.8 and pass_meet.z>1.0 and (players[middle].position-lane).slide(Vector3.UP).length()<3.6:
			x=frame.to_local(frames[hitter_side].to_global(lane)).x
			var eta:=arrival(hand_contact_height(1))-elapsed
			if eta>=-.05 and eta<=.29 and absf(players[near].position.x-x)<.9 and manual.committed_flight!=flight_number:
				start_block(near,maxf(.18,eta+.19))
				if blocks.has(near): manual.committed_flight=flight_number
	pocket_x[defense_side] = cover
	var read_quick:=middle_set and (quick_read_flight[defense_side]==flight_number-1 or remaining<=.30)
	if not is_human(near) and not blocks.has(near) and (not tracking_set or read_quick or elapsed>=players[near].reaction_seconds()):
		if near==shadow_middle: x=shadow_x
		if near==release_pin and not cpu_second_spike: x=wide_base
		if middle_set: x=frame.to_local(threat).x
		var target := frame.to_global(Vector3(clampf(x,-4.15,4.15),0.04,3.42))
		move_cpu(near,target,delta,8.6 if tracking_set else 7.6,Vector3.INF,true)
		var attack_ready := remaining >= -0.04 and remaining <= (.57 if commit and absf(frame.to_local(threat).x)<1.8 else .41)
		var dump_ready := (shadow_middle<0 or cpu_second_spike) and near!=shadow_middle and second_ball_eta >= -0.06 and second_ball_eta <= 0.30
		var lane_gap:=absf(players[near].position.x-clampf(x,-4.15,4.15))
		var late_quick:=middle_set and remaining<=.30
		if (lane_gap<.62 or late_quick) and (attack_ready or dump_ready):
			var timing := remaining if attack_ready else second_ball_eta+0.035
			start_block(near,timing,dump_ready)
			if middle_set and blocks.has(near):
				blocks[near].square_block=true
				if late_quick and lane_gap>.70: blocks[near].late_quick_x=target.x
	if six_on_six():
		var middle:=front_middle(defense_side)
		var quick_lane:=shadow_x if shadow_middle==middle else INF
		if middle_set:
			quick_lane=frame.to_local(threat).x
		for i in range(first,first+6):
			if i==near or is_human(i) or blocks.has(i) or set_jumps[i].active: continue
			var home:=formation_home(i,true)
			if i==release_pin: home.x=wide_base
			if i==shadow_middle: home.x=shadow_x
			if i==deep and tracking_set:
				home=home.move_toward(Vector3(cover,.04,depth),.9)
			var flank:=0.
			var shoulder_x:=0.
			if is_finite(quick_lane) and i!=middle and Formation.zone(lineup_role(i),setter_zones[defense_side]) in [2,3,4]:
				# Stay on the outside shoulder as the middle tracks and lands from a quick.
				flank=signf(formation_home(i,true).x-formation_home(middle,true).x)
				if is_zero_approx(flank): flank=signf(players[i].position.x-quick_lane)
				shoulder_x=flank*(maxf(flank*quick_lane,flank*players[middle].position.x)+.68)
				if not is_zero_approx(flank): home.x=clampf(flank*maxf(flank*home.x,flank*shoulder_x),-4.15,4.15)
			var close_quick:=flank!=0. and tracking_set and flank*(quick_lane-formation_home(middle,true).x)>.50
			if close_quick:
				home.x=shoulder_x
				home.z=3.42
			elif middle_set and flank!=0.:
				home.z=minf(home.z,2.10)
			move_cpu(i,frame.to_global(home),delta,5.3,toward_incoming(i,players[i].global_position),false,false,12.5,false,0.,4.7 if flank!=0. else 0.,flank,shoulder_x)
			var seam_gap:=absf(players[i].position.x-(quick_lane+flank*.68))
			if close_quick and remaining>=-.03 and remaining<=.39 and (seam_gap<.57 or remaining<=.29):
				start_block(i,remaining)
				if blocks.has(i):
					blocks[i].square_block=true
					if seam_gap>=.57 and absf(players[i].global_position.x-threat.x)>.75: blocks[i].late_quick_x=threat.x
		return
	if not is_human(deep) and not blocks.has(deep) and not set_jumps[deep].active:
		move_cpu(deep,frame.to_global(Vector3(clampf(cover,-4.05,4.05),0.04,depth)),delta)
	if count_for(defense_side) >= 3:
		var support := nearest_on_team(defense_side,frame.to_global(Vector3.ZERO),near,deep)
		if not is_human(support) and not blocks.has(support) and not set_jumps[support].active:
			var opposite := lerpf(cover,support_lanes[defense_side],0.78)
			move_cpu(support,frame.to_global(Vector3(opposite,0.04,depth+1.05)),delta)

func update_air_attack_read(hitter: int, blocker: int, driver: Node3D) -> void:
	if is_human(hitter) or not driver.jump.active or driver.off_net_shovel: return
	if is_finite(driver.swing_drive_started):
		var drive_age: float = driver.clock-driver.swing_drive_started
		if drive_age > minf(0.045,driver.swing_drive_duration*0.28): return
	if driver.jump.elapsed <= driver.jump.load_duration()+0.018: return
	var first_read := attack_aim_flight != flight_number
	if not first_read: return
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
	var preferred:=choose_shot(hitter,contact,wall,driver.swing_aim)
	var pace:=preload("res://scripts/swing_speed.gd").kmh(players[hitter])/3.6
	var plan:=choose_contact_attack(hitter,contact,preferred,Vector3.BACK*pace,8.)
	driver.swing_aim=plan.get("target",preferred)
	driver.rally_shot="roll" if plan.get("type","")=="Roll shot" else "spike"
	driver.shot_plan=plan.get("type","Drive")
	attack_aim_flight = flight_number
	attack_aim_read_at = match_clock

func lane_at_depth(from: Vector3, to: Vector3, depth: float) -> float:
	var span := to.z-from.z
	if absf(span) < 0.02: return to.x
	return lerpf(from.x,to.x,(depth-from.z)/span)

func update_action_labels() -> void:
	for index in players.size():
		key_labels[index].global_position = players[index].global_position+Vector3.UP*(2.43 if is_human(index) else 2.18)
		var cpu_focus:=key_labels[index].text=="LT" and not is_human(index)
		key_labels[index].visible = (cpu_focus or (not exhibition and (not spectator or drill_pass_target.is_finite()))) and players[index].visible and match_clock < key_until[index]
		animation_labels[index].global_position = key_labels[index].global_position+Vector3.UP*0.32
		var animation: String = recoveries.get(index,{}).get("animation",receive_animation_labels.get(index,""))
		animation_labels[index].text = animation
		animation_labels[index].visible = (not exhibition) and (not spectator or drill_pass_target.is_finite()) and players[index].visible and not animation.is_empty()

func update_flight_guide() -> void:
	flight_guide.visible=manual!=null and phase==Phase.LIVE and not replay.active and (flight_kind=="serve" or (flight_kind=="set" and expected_hitter==0) or (flight_kind=="pass" and show_pass_trajectory))
	if not flight_guide.visible or displayed_flight==flight_number: return
	var mesh:=ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP,trajectory_style)
	for i in 65: mesh.surface_add_vertex(path_point(flight_end()*i/64.))
	mesh.surface_end()
	flight_guide.mesh=mesh
	displayed_flight=flight_number

func update_player_guide() -> void:
	update_flight_guide()
	player_label.global_position = human.global_position+Vector3.UP*2.17
	player_label.visible = not spectator and not exhibition
	update_action_labels()
	trajectory_node.hide()
	aim_ring.hide()
	if not spectator and phase==Phase.LIVE:
		aim_receive(0)
		if manual and manual.show_arc and manual.context()=="set" and manual.lane>=0: manual.draw_set_arc()

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
	if flight_kind=="spike" and velocity.length()>=preload("res://scripts/gym_physics.gd").HARD_SPIKE_SPEED:
		play_floor_impact(impact_velocity.length())
	bounce_velocity = impact_velocity.slide(Vector3.UP)*0.37
	bounce_velocity.y = maxf(absf(impact_velocity.y)*0.64,2.10)*sqrt(1.25)
	bounce_end = Flight.landing_time(bounce_origin,bounce_velocity)

func play_floor_impact(speed: float, rebound := false) -> void:
	if rebound or speed<preload("res://scripts/gym_physics.gd").HARD_SPIKE_SPEED or not ball_sound_enabled: return
	var strength := smoothstep(2.0,11.0,speed)
	floor_audio.volume_db = lerpf(-10.0,1.5,strength)-(6.0 if rebound else 0.0)
	floor_audio.pitch_scale = 1.0
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
	court_boundary.flash(point,in_bounds)
	if in_bounds:
		var court_side := 0 if point.z < Net.NET_Z else 1
		var reason := "Into the net" if not net_hit.is_empty() and not net_hit.rollover else "Ball down"
		if reason=="Ball down" and flight_kind=="serve" and court_side!=service_team:
			serve_coverage[court_side].beaten(frames[court_side].to_local(point))
		if reason == "Ball down" and flight_kind == "spike" and last_player >= 0 and court_side != team(last_player):
			record_uncovered_shot(court_side,point)
		award(1-court_side,reason)
	else:
		award(1-team(last_player),"Out")

func toggle_replay(prefer_current := false) -> void:
	replay.toggle(self,prefer_current or phase in [Phase.DEAD,Phase.FINISHED])

func pose_serve_receive_wait(delta: float, moving_human := false) -> void:
	var weight := smoothstep(0.0,0.24,ready_age)
	if serve_pending:
		var release: float = serve.toss_release_time() if serve.has_method("toss_release_time") else 0.0
		var finish: float = minf(release+0.25,serve.contact_time())
		weight *= 1.0-smoothstep(minf(release,finish-0.01),finish,serve.swing_time)
	for index in players.size():
		if team(index) == service_team or (moving_human and is_human(index)): continue
		var actor := players[index]
		if weight>=.999: actor.animator.seek(0.0,true)
		else: actor.animator.advance(delta)
		if six_on_six() and lineup_role(index)==0:
			if weight>.001: actor.pose_set_call(1 if middle_31[team(index)] else 0,middle_31[team(index)],weight)
			else: actor.shirt_fabric.set_shader_parameter("signal_lift",0.)
			continue
		if weight <= 0.001: continue
		var bump := platforms[index]
		bump.knee_bend_depth = (0.055 if (index-first_on(team(index))) == 2 else 0.14)*weight
		bump.apply_knee_bend()
		bump.knee_bend_depth = 0.0
		actor.pose_hands_on_knees(weight)

func tick_match(delta: float, controls: RefCounted) -> void:
	if replay.active:
		replay.step(self,delta)
		return
	delta *= live_speed
	var previous_rallies := rallies
	var previous_flight:=flight_number
	step_match(delta,controls)
	var strike_frame:=flight_number!=previous_flight and flight_kind=="spike"
	if (phase != Phase.FINISHED or dead_age <= 2.0) and (strike_frame or match_clock+0.0005 >= next_replay_sample):
		if exhibition and phase==Phase.READY and not serve_pending and replay.current.size()>=90: replay.current.pop_front()
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

func manual_ready_movement(delta:float,controls:RefCounted,can_toss:bool) -> void:
	if is_human(server_index()):
		if not serve_pending: manual.service.ready_step(self,controls,delta,can_toss)
		else: manual.service.step(self,delta)
		pose_serve_receive_wait(delta)
		return
	controls.read_pace_input()
	var stick:Vector2=controls.movement_input()
	controls.move_player(stick,delta,false,players[server_index()].global_position,1.,.15,true,3.42)
	if six_on_six() and service_team!=0:
		var point:=Formation.from_court(human.position)
		var legal:=Formation.on_court(point.clamp(human_receive_bounds.position,human_receive_bounds.end))
		human.position.x=legal.x
		human.position.z=legal.z
	pose_serve_receive_wait(delta,stick.length()>.01)

func step_match(delta: float, controls: RefCounted) -> void:
	match_clock += delta
	cpu_reception.land(delta)
	if manual: manual.reception.land(delta)
	if not net_ripple.is_empty():
		var mesh := get_parent().get_node_or_null("VolleyballCourt/DynamicNet")
		if mesh: mesh.sample(net_ripple,match_clock)
		if match_clock>float(net_ripple.release_time)+1.1: net_ripple.clear()
	for athlete in players: athlete.stamina.recover(delta)
	if not players.is_empty() and roundi(players[0].stamina.value)!=displayed_stamina: update_score()
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
		if manual:
			manual_ready_movement(delta,controls,true)
			if is_human(server_index()): return
		else: pose_serve_receive_wait(delta)
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
	if manual and manual.service.launched: manual.service.follow(self,delta)
	else: serve.step(delta)
	var previous := elapsed
	var current_flight := flight_number
	elapsed += delta
	ball.global_position = path_point(minf(elapsed,flight_end()))
	if not touched_tape and not net_hit.is_empty() and elapsed >= float(net_hit.time):
		touched_tape = true
		if net_hit.kind == "under":
			award(1-team(last_player),"Under the net")
			return
		net_ripple=net_hit.duplicate()
		var ripple_offset := match_clock-elapsed
		net_ripple.time+=ripple_offset
		net_ripple.release_time+=ripple_offset
		if ball_sound_enabled: net_audio.play()
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
	var serving_human: bool = (manual.service.plant.active if manual and manual.service.launched and manual.service.airborne else (serve.player == human and not serve.can_run_after_contact()))
	advance_set_jumps(delta)
	advance_recoveries(delta)
	if manual and recoveries.has(0) and controls.movement_input().length()>.12 and not platforms[0].low_save.active:
		recoveries.erase(0)
	var human_before:=human.position
	var diving: bool = platforms[0].low_save.active and not platforms[0].low_save.finished(elapsed)
	if (not manual or manual.reception.motion.is_empty()) and not spectator and not blocks.has(0) and not player_attacking and not serving_human and not set_jumps[0].active and not diving and not recoveries.has(0):
		controls.read_pace_input()
		var motion: Vector2 = controls.movement_input()
		if manual and manual.load_block.charging:
			motion.x*=Block.lateral_scale(manual.load_block.seconds)
		if serve.player == human:
			if motion.length() > 0.05: serve.moved_after_contact = true
			if serve.moved_after_contact:
				human.position.y = move_toward(human.position.y,PLAYER_GROUND_Y,delta*1.25)
		var bump := platforms[0]
		var mobility: float = bump.movement_scale(elapsed,next_touch_cue,ball.global_position)
		if is_finite(bump.pressed_at) and (is_finite(bump.pose_started_at) or next_touch_cue-elapsed <= 0.18):
			controls.sprint_requested = false
			mobility = minf(mobility,0.45)
		if receive_prepared:
			mobility *= 0.30
		if roster_active:
			mobility *= lerpf(0.78,1.18,human.effective_rating("Speed") / 100.0)
		animated[0] = true
		var block_shuffle:=1.
		var focus_target: Vector3 = ball.global_position
		if manual and controls.focus_requested and manual.context()=="block" and (not six_on_six() or Formation.zone(lineup_role(0),setter_zones[0]) in [2,3,4]):
			block_shuffle=GroundMovement.block_shuffle_scale(human)
			focus_target = human.global_position + frames[0].global_basis.z
		controls.move_player(motion,delta,false,focus_target,mobility,0.15,true,3.42,0.0,0.0,true,false,block_shuffle)
	if manual:
		if manual.load_block.charging:
			var travel:Vector3=(human.position-human_before)/maxf(.0001,delta)
			manual.load_block.update(human,delta,1.-.82*smoothstep(.85,2.35,travel.length()),true)
			manual.load_block.ring.hide()
			footwork[0].block_step(travel,0.,0.,true,true,delta)
		manual.jump_if_ready()
		manual.attack_step(delta)
		attackers[0].manual_release_valid=manual.attack_release_valid()
	advance_attackers(delta)
	if flight_number != current_flight: return
	position_attack(delta)
	position_defense(delta)
	tick_blocks(delta,previous)
	if flight_number != current_flight or phase != Phase.LIVE: return
	held_ball = false
	if manual:
		if manual.reception.step(self,previous,delta,controls): return
		if manual.manual_set(previous): return
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
			info.text = "%s | %s court" % [stroke,side_names[receiving_team]]
			return
		var cue := "Opponent's ball"
		if receiving_team == 0:
			cue = PromptControls.hint("Time the attack","Hold J / I / L to attack" if manual else "Hold Space to attack") if expected_hitter == 0 else ("Set to your teammate" if possession_team == 0 and touches == 1 and human_can_set() else "Receive or cover")
		elif flight_kind == "set": cue = PromptControls.hint("Move up to block","Move up to block | Space") if player_blocks or (manual and manual.context()=="block") else "Teammate blocking | Cover the court"
		info.text = "%s | %s" % [stroke,cue]

func trace_snapshot() -> Dictionary:
	var actors: Array = []
	for index in players.size():
		actors.append({"position":Trace.json_value(players[index].global_position),"yaw":players[index].rotation.y,
			"key":key_labels[index].text if match_clock < key_until[index] else "",
			"animation":animation_labels[index].text,
			"contact":Trace.json_value(platforms[index].contact_check)})
	return {"phase":phase,"score":score,"flight":flight_kind,"ball":ball.global_position,"velocity":velocity,
		"set_decision":set_decision,"attack_decision":attack_decision,
		"receiving_team":receiving_team,"last_touch":last_player,"touches":touches,"set_apex":last_set_apex,"set_zone":SET_ZONES.find(called_pin.x)+1,
		"blocker":defender_assignment,"takes_line":block_line,"dig_pocket":pocket_x,"players":actors}

func save_reviewed_rep(title: String, rep: int, camera: Camera3D, camera_focus: Vector3) -> String:
	if not replay.active: return ""
	var evidence := {"type":"Saved replay","drill":title,"rep":rep,"frame":replay.index,
		"time":replay.frames[replay.index].time,"clock":replay.clock,"speed":replay.speed,
		"camera":camera.global_transform,"camera_focus":camera_focus,"fov":camera.fov,"ball_offset":replay.ball_offset,
		"actor_offsets":replay.actor_offsets}
	return review.write_replay(self,evidence,replay.frames,replay.saved_directory(title))

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
