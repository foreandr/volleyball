extends "res://scripts/attack_drill.gd"

const BLOCK_START := Vector3(0.0,0.04,3.25)
const BLOCK_LOAD := 0.16
const BLOCK_AIR := 0.86
const BLOCK_HEIGHT := 1.12
const BLOCK_AIM_HALF_WIDTH := 18.0
const BLOCK_AIM_FAR := 29.0
const SETUP_PATH := "user://blocking_setup.cfg"
const SHOT_LANES := [3.35,0.0,-3.35]

var next_shot_lane := 0
var player_attacks := true
var cpu_block_queued := false
var block_tempo := 1.0
var feed_lane := 0
var next_pin := 1.0
var current_pin := 0.0
var repeat_setup_feed := false
var attacker_offset := Vector2.ZERO
var blocker_offset := Vector2.ZERO
var set_offset := Vector2.ZERO
var ball_source_offset := Vector2.ZERO
var set_apex := 4.75
var player_shot_aim := Vector3(0.0,0.065,10.5)
var blocker: Node3D
var blocker_start: Transform3D
var blocker_animation_mode: int
var block_elapsed := -1.0
var block_base := BLOCK_START
var block_tracking := 0.0
var arm_tracking := 1.0
var high_hands_held := false
var last_block_surface := ""
var block_lift := 0.0
var vertical_inches := 0.0
const PALM_ANGLE_DEGREES := 30.0
var last_block_gap := INF
var last_block_hand := ""
var kong_pressed_at: Array[float] = [INF,INF]
var kong_tracking: Array[Vector2] = [Vector2(0.83,0.43),Vector2(0.83,0.43)]
var active_block_height := BLOCK_HEIGHT
var hand_normals: Array[Vector3] = [Vector3.BACK,Vector3.BACK]
var block_hands: Array[Dictionary] = [{},{}]
var chest_top := Vector3.ZERO
var chest_bottom := Vector3.ZERO
var previous_chest_top := Vector3.ZERO
var previous_chest_bottom := Vector3.ZERO
var block_contact_at := INF
var block_contact: Vector3
var block_velocity: Vector3

func attack_pose_smoothing_time() -> float:
	return 0.026

func uses_front_right_lift() -> bool:
	return true

func load_setup() -> void:
	var config := ConfigFile.new()
	if config.load(SETUP_PATH) != OK: return
	player_attacks = config.get_value("court","player_attacks",true)
	feed_lane = config.get_value("court","feed_lane",0)
	attacker_offset = config.get_value("court","attacker_offset",Vector2.ZERO)
	blocker_offset = config.get_value("court","blocker_offset",Vector2.ZERO)
	set_offset = config.get_value("court","set_offset",Vector2.ZERO)
	ball_source_offset = config.get_value("court","ball_source_offset",Vector2.ZERO)
	set_apex = config.get_value("court","set_apex",4.75)
	vertical_inches = config.get_value("court","vertical_inches",0.0)
	arm_tracking = config.get_value("court","arm_tracking",1.0)
	player_shot_aim = config.get_value("court","shot_aim",player_shot_aim)

func save_setup() -> void:
	var config := ConfigFile.new()
	var setup := {
		"player_attacks":player_attacks,"feed_lane":feed_lane,
		"attacker_offset":attacker_offset,"blocker_offset":blocker_offset,
		"set_offset":set_offset,"ball_source_offset":ball_source_offset,
		"set_apex":set_apex,"vertical_inches":vertical_inches,
		"arm_tracking":arm_tracking,"shot_aim":player_shot_aim
	}
	for key in setup: config.set_value("court",key,setup[key])
	config.save(SETUP_PATH)

func configure_block(actor: Node3D, readout: Label, build: String) -> void:
	blocker = actor
	blocker_start = actor.transform
	blocker_animation_mode = actor.animator.callback_mode_process
	blocker.position = BLOCK_START
	blocker.rotation.y = 0.0
	blocker.animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	blocker.play_action("idle",0.0)
	blocker.animator.advance(0.0)
	blocker.get_node("DirectionArrows").hide()
	var hitter := Player.new()
	hitter.team_color = Color("d9874e")
	hitter.name = "OpponentAttacker"
	add_child(hitter)
	hitter.animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	hitter.get_node("DirectionArrows").hide()
	swing_practice = false
	load_setup()
	configure(hitter,readout,true,build)
	receiver.hide()

func stop_block() -> void:
	blocker.transform = blocker_start
	blocker.animator.callback_mode_process = blocker_animation_mode
	blocker.get_node("DirectionArrows").show()

func set_player_attacks(value: bool) -> void:
	player_attacks = value
	restart_block_feed()

func apply_position_setup() -> void:
	repeat_setup_feed = true
	restart_block_feed()
	blocker.position.x = to_global(setup_marker("blocker")).x
	save_setup()

func setup_marker(marker: String) -> Vector3:
	match marker:
		"attacker":
			return Vector3(clampf(current_pin*0.78-attacker_offset.x,-5.5,5.5),0.04,1.67-attacker_offset.y)
		"blocker":
			var lane := rally_set_target.x if player_attacks else 0.0
			return Vector3(clampf(lane-blocker_offset.x,-5.5,5.5),0.04,2.0*Net.NET_Z-BLOCK_START.z+blocker_offset.y)
		"ball":
			return Vector3((0.0 if player_attacks else -0.65)+ball_source_offset.x,2.12,2.35+ball_source_offset.y)
		_:
			return Vector3(clampf(current_pin-set_offset.x,-4.4,4.4),0.065,3.34-set_offset.y)

func move_setup_marker(marker: String, point: Vector3) -> void:
	match marker:
		"attacker":
			attacker_offset = Vector2(current_pin*0.78-point.x,1.67-point.z)
		"blocker":
			var lane := rally_set_target.x if player_attacks else 0.0
			blocker_offset = Vector2(lane-point.x,point.z-(2.0*Net.NET_Z-BLOCK_START.z))
		"set":
			set_offset = Vector2(current_pin-point.x,3.34-point.z)
		"ball":
			ball_source_offset = Vector2(point.x-(0.0 if player_attacks else -0.65),point.z-2.35)
	apply_position_setup()

func restart_block_feed() -> void:
	release_approach_jump()
	block_elapsed = -1.0
	block_lift = 0.0
	block_hands = [{},{}]
	blocker.position.y = BLOCK_START.y
	blocker.animator.seek(0.0,true)
	reset_feed()

func set_feed_lane(value: int) -> void:
	feed_lane = value
	if player_attacks: set_player_attacks(true)

func aim_player_spike(ray_origin: Vector3, ray_direction: Vector3) -> void:
	if not player_attacks or stage != Stage.SET: return
	var origin := to_local(ray_origin)
	var direction := global_basis.inverse()*ray_direction
	var far_time := maxf(0.0,(BLOCK_AIM_FAR-origin.z)/maxf(direction.z,0.01))
	var floor_time := (origin.y-Flight.FLOOR)/maxf(-direction.y,0.0001)
	var point := origin+direction*minf(floor_time,far_time)
	if point.z < SHOT_AIM_NEAR: return
	player_shot_aim = Vector3(clampf(point.x,-BLOCK_AIM_HALF_WIDTH,BLOCK_AIM_HALF_WIDTH),Flight.FLOOR,clampf(point.z,SHOT_AIM_NEAR,BLOCK_AIM_FAR))
	show_player_spike_aim()

func show_player_spike_aim() -> void:
	swing_aim = player_shot_aim
	swing_target.position = Vector3(swing_aim.x,0.065,swing_aim.z)
	swing_target.show()

func reset_feed() -> void:
	var space_held := approach_space_held
	super.reset_feed()
	stage = Stage.SET
	block_contact_at = INF
	last_block_gap = INF
	last_block_hand = ""
	last_block_surface = ""
	approach_space_held = space_held if player_attacks else true
	cpu_block_queued = false
	var pin_x := 0.0
	if player_attacks and repeat_setup_feed:
		pin_x = current_pin
	elif player_attacks:
		match feed_lane:
			0:
				pin_x = next_pin*PIN.x
				next_pin = -next_pin
			1: pin_x = PIN.x
			2: pin_x = -PIN.x
	current_pin = pin_x
	repeat_setup_feed = false
	setter.position = setup_marker("attacker")
	setter.rotation.y = 0.0
	rally_set_target = setup_marker("set")
	if block_elapsed < 0.0:
		blocker.position.z = BLOCK_START.z-blocker_offset.y
		if not player_attacks: blocker.position.x = blocker_offset.x
	pass_origin = setup_marker("ball")
	pass_motion = set_toward_pin(pass_origin,rally_set_target,set_apex,3.38)
	pin_arrival = descending_time(pass_origin,pass_motion,3.38)
	flight_end = Flight.landing_time(pass_origin,pass_motion)
	ball.position = pass_origin
	bump.hide()
	region.position = rally_set_target
	region.visible = player_attacks
	if player_attacks:
		show_player_spike_aim()
	else:
		aim_swing(Vector3(SHOT_LANES[next_shot_lane],Flight.FLOOR,10.5))
		next_shot_lane = (next_shot_lane+1)%SHOT_LANES.size()
		swing_target.hide()
	approach_set_touched_at = clock
	status.text = PromptControls.hint("Begin your approach","Hold Space to approach") if player_attacks else "Time your jump"

func set_vertical_inches(value: float) -> void:
	vertical_inches = clampf(value,-20.0,30.0)

func queue_block() -> void:
	if block_elapsed >= 0.0: return
	block_base = blocker.position
	block_tracking = 0.0
	kong_pressed_at = [INF,INF]
	kong_tracking = [Vector2(0.83,0.43),Vector2(0.83,0.43)]
	active_block_height = (BLOCK_HEIGHT+vertical_inches*0.0254)*preload("res://scripts/setter_jump.gd").COURT_VERTICAL_SCALE
	hand_normals = [Vector3.BACK,Vector3.BACK]
	block_hands = [{},{}]
	blocker.animator.speed_scale = 1.0
	blocker.play_action("idle",0.0)
	blocker.animator.advance(0.0)
	block_tempo = 1.0
	block_elapsed = 0.0

func queue_kong(hand_index: int) -> void:
	if block_elapsed < 0.0 or block_elapsed >= BLOCK_LOAD+BLOCK_AIR*sqrt(active_block_height/BLOCK_HEIGHT): return
	if not is_finite(kong_pressed_at[hand_index]):
		kong_pressed_at[hand_index] = block_elapsed

func tick_block(delta: float) -> void:
	if player_attacks and stage == Stage.SET and block_elapsed < 0.0:
		var target := to_global(setup_marker("blocker"))
		blocker.position.x = move_toward(blocker.position.x,target.x,delta*8.0)
	if player_attacks and not cpu_block_queued and block_elapsed < 0.0 and stage == Stage.SET and jump.active:
		var takeoff_at := clock+maxf(0.0,jump.load_duration()-jump.elapsed) if not is_finite(swing_started) else swing_started
		var contact_at := maxf(approach_expected_hit_at+0.04,takeoff_at+0.43)
		if is_finite(swing_drive_started):
			contact_at = maxf(clock,swing_drive_started+swing_drive_duration*0.92)
		var remaining := contact_at+0.055-clock
		var rise_time := BLOCK_LOAD+0.49*BLOCK_AIR*sqrt(((BLOCK_HEIGHT+vertical_inches*0.0254)*preload("res://scripts/setter_jump.gd").COURT_VERTICAL_SCALE)/BLOCK_HEIGHT)
		if remaining <= rise_time/1.15:
			cpu_block_queued = true
			queue_block()
			block_tempo = clampf(rise_time/maxf(remaining,0.18),1.15,1.8)
	step_blocker(delta)
	update_chest_contact()
	if stage == Stage.SET: queued_approach_input(delta)
	step_jump(delta)
	step(delta)

func step_blocker(delta: float) -> void:
	if block_elapsed < 0.0: return
	block_elapsed += delta*block_tempo
	var air_scale := sqrt(active_block_height/BLOCK_HEIGHT)
	var pose_time := minf(block_elapsed,BLOCK_LOAD)+maxf(0.0,block_elapsed-BLOCK_LOAD)/air_scale
	var airborne := clampf((pose_time-BLOCK_LOAD)/BLOCK_AIR,0.0,1.0)
	block_lift = 4.0*active_block_height*airborne*(1.0-airborne)
	var load := smoothstep(0.0,BLOCK_LOAD*0.70,pose_time)*(1.0-smoothstep(BLOCK_LOAD*0.70,BLOCK_LOAD,pose_time))
	var settle := smoothstep(BLOCK_LOAD+BLOCK_AIR-0.045,BLOCK_LOAD+BLOCK_AIR+0.045,pose_time)
	settle *= 1.0-smoothstep(BLOCK_LOAD+BLOCK_AIR+0.045,BLOCK_LOAD+BLOCK_AIR+0.20,pose_time)
	blocker.position = block_base+Vector3.UP*(block_lift-0.13*load-0.08*settle)
	blocker.animator.seek(0.0,true)
	var rig: Skeleton3D = blocker.skeleton
	var author: RefCounted = blocker.get_pose_author()
	var pose: Array = []
	for bone in rig.get_bone_count(): pose.append(rig.get_bone_pose(bone))
	var scale_: float = rig.global_basis.get_scale().y
	var raise := smoothstep(0.06,BLOCK_LOAD+0.14,pose_time)*(1.0-smoothstep(BLOCK_LOAD+0.63,BLOCK_LOAD+BLOCK_AIR+0.13,pose_time))
	var press := smoothstep(BLOCK_LOAD+0.025,BLOCK_LOAD+0.24,pose_time)*(1.0-smoothstep(BLOCK_LOAD+0.58,BLOCK_LOAD+0.76,pose_time))
	var low_clearance := 0.40*smoothstep(0.0,0.09,pose_time)*(1.0-smoothstep(BLOCK_LOAD+BLOCK_AIR+0.09,BLOCK_LOAD+BLOCK_AIR+0.20,pose_time))
	if not player_attacks:
		blocker.position.z -= 0.26*maxf(raise,low_clearance)*(1.0-smoothstep(0.66,0.97,block_lift))
	var shot: Vector3 = ball.global_position
	var crunch := 0.0
	if stage == Stage.HIT and pass_motion.z > 0.1:
		var crossing := maxf(0.0,(Net.NET_Z-pass_origin.z)/pass_motion.z)
		var age := clock-stage_start-crossing
		crunch = smoothstep(-0.13,-0.015,age)*(1.0-smoothstep(0.04,0.19,age))*raise
		if not is_finite(block_contact_at): shot = to_global(spike_flight_point(crossing))
	# Stay upright until the block has enough height to press over the tape.
	var clearance := smoothstep(0.58,BLOCK_HEIGHT,block_lift)
	var extra_height := smoothstep(BLOCK_HEIGHT,BLOCK_HEIGHT+0.508,block_lift)
	var body_press := clearance*(1.0+0.70*extra_height)
	var high_fold := extra_height*crunch*smoothstep(0.0,0.65,blocker.position.y+1.90-shot.y)
	if not player_attacks: blocker.position.z += 0.12*extra_height*press
	author.rotate_world(pose,"spine_01",Vector3.RIGHT,(0.12*press+0.085*crunch)*body_press+0.24*high_fold)
	author.rotate_world(pose,"spine_02",Vector3.RIGHT,(0.10*press+0.10*crunch)*body_press+0.22*high_fold)
	var track := clampf(shot.x-blocker.position.x,-0.23,0.23)
	block_tracking = lerpf(block_tracking,track,1.0-exp(-delta*17.0))
	for hand_index in 2:
		var side := "l" if hand_index == 0 else "r"
		var sign_ := 1.0 if side == "l" else -1.0
		var shoulder: Vector3 = author.point(pose,"upperarm_"+side)
		var kong := 0.0
		if is_finite(kong_pressed_at[hand_index]):
			kong = smoothstep(0.0,0.115,block_elapsed-kong_pressed_at[hand_index])
			kong *= 1.0-smoothstep(BLOCK_LOAD+0.61,BLOCK_LOAD+BLOCK_AIR+0.12,pose_time)
		var wrist_offset := Vector3(-sign_*0.105+block_tracking*press*arm_tracking*2.0,0.64-0.25*high_fold,0.20+0.34*press)
		if kong > 0.0 and stage == Stage.HIT and not is_finite(block_contact_at):
			var shoulder_world := rig.to_global(shoulder)
			var local_depth := Net.NET_Z-0.12*press
			var time_to_hand := maxf(0.0,(local_depth-pass_origin.z)/maxf(pass_motion.z,0.1))
			var intercept := to_global(spike_flight_point(time_to_hand))
			var reach := clampf((intercept.x-shoulder_world.x)*sign_+0.04,0.16,0.86)
			var height := clampf(intercept.y-shoulder_world.y-0.07,0.35,0.66)
			kong_tracking[hand_index] = kong_tracking[hand_index].lerp(Vector2(reach,height),1.0-exp(-delta*33.0))
		var tracked := Vector2(0.83,0.43).lerp(kong_tracking[hand_index],arm_tracking)
		wrist_offset = wrist_offset.lerp(Vector3(sign_*tracked.x,tracked.y,0.29+0.27*press),kong)
		if player_attacks:
			wrist_offset.y += 0.035*press
			var clearance_height := rig.to_global(shoulder).y+wrist_offset.y
			var safe_depth := Net.NET_Z-0.16-blocker.position.z
			var pressed_depth := maxf(wrist_offset.z,Net.NET_Z+0.035-blocker.position.z)
			var above_tape := smoothstep(Net.NET_TOP+0.18,Net.NET_TOP+0.40,clearance_height)
			wrist_offset.z = lerpf(minf(wrist_offset.z,safe_depth),pressed_depth,above_tape*press)
		var wrist := shoulder+wrist_offset/scale_
		author.limb(pose,"upperarm_"+side,"lowerarm_"+side,"hand_"+side,wrist,Vector3(sign_*lerpf(0.31,0.78,kong),-0.52,0.34),raise,176.0)
		var base: Transform3D = author.world_pose(pose,rig.find_bone("hand_"+side))
		var fingers: Vector3 = author.point(pose,"middle_01_"+side)-base.origin
		var across: Vector3 = author.point(pose,"index_01_"+side)-author.point(pose,"pinky_01_"+side)
		var ball_direction := (rig.to_local(ball.global_position)-base.origin).normalized()
		if ball_direction.z > 0.04 and not is_finite(block_contact_at):
			var desired := Vector3(clampf(ball_direction.x,-0.16,0.16),clampf(ball_direction.y,-0.14,0.09),1.0).normalized()
			hand_normals[hand_index] = hand_normals[hand_index].slerp(desired,1.0-exp(-delta*28.0))
		var toward_ball := hand_normals[hand_index].rotated(Vector3.RIGHT,deg_to_rad(PALM_ANGLE_DEGREES))
		var finger_direction := Vector3.UP.slide(toward_ball).normalized()
		var index_edge := finger_direction.cross(toward_ball).normalized()*-sign_
		var palm := HandPose.hand_basis(finger_direction,index_edge)*HandPose.hand_basis(fingers,across).inverse()*base.basis
		author.set_world_basis(pose,"hand_"+side,base.basis.slerp(palm,raise))
		spread_block_fingers(pose,rig,author,side,raise)
	if player_attacks:
		for side in ["l","r"]:
			for attempt in 4:
				var excess := arm_net_excess(pose,rig,author,side)
				if excess < 0.002: break
				author.rotate_world(pose,"upperarm_"+side,Vector3.RIGHT,-minf(0.18,excess*3.0))
	else:
		blocker.position.z -= block_net_retreat(pose,rig,author)
	for hand_index in 2:
		update_block_hand(pose,rig,author,"l" if hand_index == 0 else "r",hand_index,delta)
	for bone in rig.get_bone_count(): rig.set_bone_pose_rotation(bone,pose[bone].basis.get_rotation_quaternion())
	if pose_time >= BLOCK_LOAD+BLOCK_AIR+0.20:
		block_elapsed = -1.0
		block_lift = 0.0
		blocker.position = block_base
		blocker.animator.seek(0.0,true)

func update_chest_contact() -> void:
	var rig: Skeleton3D = blocker.skeleton
	var spine := rig.to_global(rig.get_bone_global_pose(rig.find_bone("spine_01")).origin)
	var neck := rig.to_global(rig.get_bone_global_pose(rig.find_bone("neck_01")).origin)
	previous_chest_bottom = chest_bottom
	previous_chest_top = chest_top
	chest_bottom = to_local(spine.lerp(neck,0.18)+Vector3.BACK*0.035)
	chest_top = to_local(spine.lerp(neck,0.78)+Vector3.BACK*0.035)
	if previous_chest_bottom.is_zero_approx():
		previous_chest_bottom = chest_bottom
		previous_chest_top = chest_top

func block_net_retreat(pose: Array, rig: Skeleton3D, author: RefCounted) -> float:
	return maxf(arm_net_excess(pose,rig,author,"l"),arm_net_excess(pose,rig,author,"r"))

func arm_net_excess(pose: Array, rig: Skeleton3D, author: RefCounted, side: String) -> float:
	var furthest := Net.NET_Z-0.035
	var tape := Net.NET_TOP+0.035
	var previous: Vector3 = rig.to_global(author.point(pose,"upperarm_"+side))
	for joint in ["lowerarm_","hand_","middle_03_"]:
		var point: Vector3 = rig.to_global(author.point(pose,joint+side))
		if previous.y <= tape: furthest = maxf(furthest,previous.z)
		if point.y <= tape: furthest = maxf(furthest,point.z)
		if (previous.y < tape) != (point.y < tape):
			furthest = maxf(furthest,previous.lerp(point,inverse_lerp(previous.y,point.y,tape)).z)
		previous = point
	return furthest-(Net.NET_Z-0.035)

func update_block_hand(pose: Array, rig: Skeleton3D, author: RefCounted, side: String, index: int, delta: float) -> void:
	var shoulder := to_local(rig.to_global(author.point(pose,"upperarm_"+side)))
	var elbow := to_local(rig.to_global(author.point(pose,"lowerarm_"+side)))
	var wrist: Vector3 = author.point(pose,"hand_"+side)
	var middle: Vector3 = author.point(pose,"middle_01_"+side)
	var fingertip: Vector3 = author.point(pose,"middle_03_"+side)
	var across: Vector3 = author.point(pose,"pinky_01_"+side)-author.point(pose,"index_01_"+side)
	var local_normal := (middle-wrist).cross(across).normalized()*(-1.0 if side == "l" else 1.0)
	var normal := (global_basis.inverse()*rig.global_basis*local_normal).normalized()
	var center := to_local(rig.to_global(wrist.lerp(middle,0.76)))
	var previous: Vector3 = block_hands[index].get("center",center)
	var wrist_point := to_local(rig.to_global(wrist))
	var tip := to_local(rig.to_global(fingertip))
	block_hands[index] = {
		"wrist":wrist_point,
		"elbow":elbow,
		"shoulder":shoulder,
		"previous_shoulder":block_hands[index].get("shoulder",shoulder),
		"previous_elbow":block_hands[index].get("elbow",elbow),
		"tip":tip,
		"previous_wrist":block_hands[index].get("wrist",wrist_point),
		"previous_tip":block_hands[index].get("tip",tip),
		"center":center,
		"side":side,
		"normal":normal,
		"velocity":((center-previous)/maxf(delta,0.001)).limit_length(5.0)
	}

func rebound_from_hand(incoming: Vector3, hit: Vector3, hand: Dictionary) -> Vector3:
	var normal: Vector3 = hand.normal
	var motion: Vector3 = hand.velocity
	var relative := incoming-motion
	if normal.dot(relative) > 0.0: normal = -normal
	var center: Vector3 = hand.center
	var incidence := clampf(-incoming.normalized().dot(normal),0.0,1.0)
	var surface: String = hand.get("surface","chest")
	var top_edge := float(hand.get("top_edge",0.0))
	var side_edge := float(hand.get("side_edge",0.0))
	var edge := (hit-center).slide(normal).limit_length(0.23)
	if surface == "palm" and incidence >= 0.33 and absf(side_edge) < 0.65:
		# A square, pressed palm sends the spike straight back and down.
		var press_normal := normal.lerp(Vector3(0.0,-0.42,-0.91),0.62).normalized()
		var speed := maxf(0.0,-relative.dot(press_normal))
		var stuff := relative.slide(press_normal)*0.18+press_normal*speed*0.69+motion*0.18
		stuff.z = minf(stuff.z,-maxf(3.0,incoming.z*0.40))
		return stuff
	normal = (normal+edge*1.45).normalized()
	var normal_speed := minf(relative.dot(normal),0.0)
	var give := float(hand.get("give",0.0))
	var rebound := relative.slide(normal)*lerpf(0.69,0.42,give)-normal*normal_speed*lerpf(0.42,0.26,give)
	var edge_speed := relative.length()
	var carry := relative*0.78
	carry.x += side_edge*minf(7.0,edge_speed*0.35)
	carry.y = lerpf(carry.y,minf(5.0,edge_speed*0.26),top_edge)
	var wipe := maxf(smoothstep(0.16,0.90,top_edge),absf(side_edge))
	rebound = rebound.lerp(carry,wipe*0.82)+motion*lerpf(0.52,0.30,give)
	if surface == "fingers":
		rebound.y = maxf(rebound.y,lerpf(0.8,2.2,top_edge))
		rebound -= rebound.slide(Vector3.UP)*(0.55*top_edge)
	return rebound

func spread_block_fingers(pose: Array, rig: Skeleton3D, author: RefCounted, side: String, weight: float) -> void:
	var digits: Array[String] = ["index","middle","ring","pinky"]
	var fan: Array[float] = [0.34,0.08,-0.15,-0.43]
	var wrist: Vector3 = author.point(pose,"hand_"+side)
	var index_base: Vector3 = author.point(pose,"index_01_"+side)
	var pinky_base: Vector3 = author.point(pose,"pinky_01_"+side)
	var forward := (index_base.lerp(pinky_base,0.5)-wrist).normalized()
	var across := (index_base-pinky_base).slide(forward).normalized()
	for index in digits.size():
		var first := digits[index]+"_01_"+side
		var second := digits[index]+"_02_"+side
		var third := digits[index]+"_03_"+side
		var direction := (forward+across*fan[index]).normalized()
		var root: Vector3 = author.point(pose,first)
		var next: Vector3 = author.point(pose,second)
		author.aim_joint(pose,first,second,next.lerp(root+direction*root.distance_to(next),weight))
		var joint: Vector3 = author.point(pose,second)
		var tip: Vector3 = author.point(pose,third)
		author.aim_joint(pose,second,third,tip.lerp(joint+direction*joint.distance_to(tip),weight))
		var bone := rig.find_bone(third)
		pose[bone].basis = pose[bone].basis.slerp(rig.get_bone_rest(bone).basis,weight)
	var thumb := "thumb_01_"+side
	var thumb_joint := "thumb_02_"+side
	var root: Vector3 = author.point(pose,thumb)
	var next: Vector3 = author.point(pose,thumb_joint)
	var direction := (forward*0.52+across*0.85).normalized()
	author.aim_joint(pose,thumb,thumb_joint,next.lerp(root+direction*root.distance_to(next),weight))

func hit_spike(charge: float, point: Vector3, palm_gap := 0.0) -> void:
	super.hit_spike(charge,point,palm_gap)
	if not player_attacks or not high_hands_held or pass_motion.z <= 0.0: return
	var top := Vector3.ZERO
	for hand in block_hands:
		if not hand.is_empty() and hand.tip.y > top.y: top = hand.tip
	var depth := top.z if top.z > point.z+0.18 else Net.NET_Z+0.12
	var time_to_hands := (depth-point.z)/pass_motion.z
	var height := maxf(Net.NET_TOP+0.30,top.y+0.07)
	var gravity := Flight.spike_gravity(spike_topspin_rps)
	pass_motion.y = (height-point.y)/time_to_hands+gravity*time_to_hands*0.5
	flight_end = Flight.landing_time(pass_origin,pass_motion,gravity)
	swing_net_hit = Net.first_hit(spike_flight_point,0.0,flight_end)

func projected_landing() -> Vector3:
	if is_visible_in_tree() and stage==Stage.HIT and is_finite(block_contact_at) and ball.position.y>.15:
		return to_global(flight_point(block_contact,block_velocity,Flight.landing_time(block_contact,block_velocity)))
	return super.projected_landing()

func play_spike(time: float, delta: float) -> void:
	if is_finite(block_contact_at):
		var elapsed := time-block_contact_at
		var end := Flight.landing_time(block_contact,block_velocity)
		ball.position = flight_point(block_contact,block_velocity,minf(elapsed,end))
		if time < SWING_FOLLOW_TIME:
			var follow := 1.0-pow(1.0-clampf(time/0.19,0.0,1.0),2.0)
			pose_bow_draw(delta,1.0-smoothstep(0.19,SWING_FOLLOW_TIME,time),swing_contact,swing_contact_extension,follow)
		if elapsed >= end and elapsed-delta < end: play_floor_sound((block_velocity+Vector3.DOWN*Flight.GRAVITY*end).length())
		if elapsed >= end+0.40 and not jump.active: reset_feed()
		return
	if time <= flight_end and (swing_net_hit.is_empty() or time-delta < swing_net_hit.time):
		var before := spike_flight_point(maxf(0.0,time-delta))
		var sweep_end := time if swing_net_hit.is_empty() else minf(time,float(swing_net_hit.time))
		var after := spike_flight_point(sweep_end)
		var hit_hand: Dictionary = {}
		for sample in 9:
			var best_gap := INF
			var progress := sample/8.0
			var point := before.lerp(after,progress)
			for hand in block_hands:
				if block_lift <= 0.10 or hand.is_empty(): continue
				var wrist: Vector3 = hand.previous_wrist.lerp(hand.wrist,progress)
				var tip: Vector3 = hand.previous_tip.lerp(hand.tip,progress)
				var elbow: Vector3 = hand.previous_elbow.lerp(hand.elbow,progress)
				var shoulder: Vector3 = hand.previous_shoulder.lerp(hand.shoulder,progress)
				var joints := [tip,wrist,elbow,shoulder]
				for segment in 3:
					var is_hand := segment == 0
					var start: Vector3 = joints[segment+1]
					var finish: Vector3 = joints[segment]
					var surface := Geometry3D.get_closest_point_to_segment(point,start,finish)
					var gap := point.distance_to(surface)
					last_block_gap = minf(last_block_gap,gap)
					var reach := BallPreview.RADIUS+(0.096 if is_hand else 0.075)
					if gap > reach or gap/reach >= best_gap: continue
					if surface.y < Net.NET_TOP and surface.z <= Net.NET_Z: continue
					best_gap = gap/reach
					block_contact = point
					hit_hand = hand.duplicate()
					hit_hand.surface = "forearm"
					if is_hand:
						var axis := (tip-wrist).normalized()
						# Measure the strike on the palm plane, ahead of the ball's center at first touch.
						var normal: Vector3 = hand.normal
						var direction := (after-before).normalized()
						var incidence := direction.dot(normal)
						var contact_center := point
						if absf(incidence) > 0.15:
							var travel := (wrist-point).dot(normal)/incidence
							contact_center += direction*clampf(travel,0.0,0.30)
						var along := (contact_center-wrist).dot(axis)/maxf(wrist.distance_to(tip),0.001)
						hit_hand.surface = "fingers" if along >= 0.83 else "palm"
						hit_hand.give = smoothstep(0.80,1.04,along)
						hit_hand.top_edge = smoothstep(0.76,1.12,along)
						var lateral := (contact_center-wrist-axis*(contact_center-wrist).dot(axis)).x
						hit_hand.side_edge = signf(lateral)*smoothstep(0.065,0.20,absf(lateral))
						# Two palms close the seam even when the first contact is on an inside edge.
						var other: Dictionary = block_hands[1 if hand.side == "l" else 0]
						if not other.is_empty() and hit_hand.surface == "palm":
							var other_center: Vector3 = other.center
							var center: Vector3 = hand.center
							if (contact_center.x-center.x)*(contact_center.x-other_center.x) <= 0.0 and absf(contact_center.y-other_center.y) < 0.18:
								hit_hand.side_edge *= 0.35
					else:
						hit_hand.give = 0.68
						hit_hand.center = surface
						hit_hand.normal = (point-surface).normalized()
			if not hit_hand.is_empty(): break
			var torso := Geometry3D.get_closest_point_to_segment(point,previous_chest_bottom.lerp(chest_bottom,progress),previous_chest_top.lerp(chest_top,progress))
			if not chest_bottom.is_zero_approx() and point.distance_to(torso) <= BallPreview.RADIUS+0.18:
				block_contact = point
				hit_hand = {"side":"chest","center":torso,"normal":(point-torso).normalized(),
					"velocity":((chest_bottom-previous_chest_bottom)/maxf(delta,0.001)).limit_length(5.0)}
				break
		if not hit_hand.is_empty():
			block_contact_at = time
			last_block_hand = hit_hand.side
			last_block_surface = hit_hand.get("surface","chest")
			var incoming := pass_motion+Vector3.DOWN*Flight.spike_gravity(spike_topspin_rps)*time
			block_velocity = rebound_from_hand(incoming,block_contact,hit_hand)
			ball.position = block_contact
			if last_block_hand == "chest":
				status.text = "Chest deflection"
			elif last_block_surface == "palm" and block_velocity.z < -5.0:
				status.text = "Stuff block!"
			elif last_block_surface == "fingers" and block_velocity.z > 0.0:
				status.text = "High hands!"
			elif block_velocity.z > 0.0:
				status.text = "Off the block"
			else:
				status.text = "Soft block"
			if not ball_audio_muted: spike_audio.play()
			return
	super.play_spike(time,delta)

func trace_snapshot(time: float) -> Dictionary:
	var snapshot := super.trace_snapshot(time)
	snapshot["block"] = {
		"jump_elapsed":block_elapsed,"lift":block_lift,"kong":kong_pressed_at,
		"hands":block_hands,"closest_gap":last_block_gap,
		"contact_at":block_contact_at,"contact_hand":last_block_hand,"surface":last_block_surface,"outgoing":block_velocity
	}
	return snapshot
