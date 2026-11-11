extends "res://scripts/attack_drill.gd"

const BLOCK_START := Vector3(0.0,0.04,3.25)
const BLOCK_LOAD := 0.16
const BLOCK_AIR := 0.86
const BLOCK_HEIGHT := 1.12
const SHOT_LANES := [3.35,0.0,-3.35]

var next_shot_lane := 0
var blocker: Node3D
var blocker_start: Transform3D
var blocker_animation_mode: int
var block_elapsed := -1.0
var block_base := BLOCK_START
var block_tracking := 0.0
var block_lift := 0.0
var vertical_inches := 0.0
var active_block_height := BLOCK_HEIGHT
var hand_normals: Array[Vector3] = [Vector3.BACK,Vector3.BACK]
var block_hands: Array[Dictionary] = [{},{}]
var block_contact_at := INF
var block_contact: Vector3
var block_velocity: Vector3

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
	configure(hitter,readout,true,build)
	receiver.hide()

func stop_block() -> void:
	blocker.transform = blocker_start
	blocker.animator.callback_mode_process = blocker_animation_mode
	blocker.get_node("DirectionArrows").show()

func reset_feed() -> void:
	super.reset_feed()
	stage = Stage.SET
	block_contact_at = INF
	approach_space_held = true
	setter.position = Vector3(0.0,0.04,1.67)
	setter.rotation.y = 0.0
	rally_set_target = Vector3(0.0,0.065,3.34)
	pass_origin = Vector3(-0.65,2.12,2.35)
	pass_motion = set_toward_pin(pass_origin,rally_set_target,4.75,3.38)
	pin_arrival = descending_time(pass_origin,pass_motion,3.38)
	flight_end = Flight.landing_time(pass_origin,pass_motion)
	ball.position = pass_origin
	bump.hide()
	region.hide()
	aim_swing(Vector3(SHOT_LANES[next_shot_lane],Flight.FLOOR,10.5))
	next_shot_lane = (next_shot_lane+1)%SHOT_LANES.size()
	swing_target.hide()
	approach_set_touched_at = clock
	status.text = "Time your jump"

func set_vertical_inches(value: float) -> void:
	vertical_inches = clampf(value,-20.0,20.0)

func queue_block() -> void:
	if block_elapsed >= 0.0: return
	block_base = blocker.position
	block_tracking = 0.0
	active_block_height = BLOCK_HEIGHT+vertical_inches*0.0254
	hand_normals = [Vector3.BACK,Vector3.BACK]
	block_hands = [{},{}]
	blocker.animator.speed_scale = 1.0
	blocker.play_action("idle",0.0)
	blocker.animator.advance(0.0)
	block_elapsed = 0.0

func tick_block(delta: float) -> void:
	step_blocker(delta)
	if stage == Stage.SET: queued_approach_input(delta)
	step_jump(delta)
	step(delta)

func step_blocker(delta: float) -> void:
	if block_elapsed < 0.0: return
	block_elapsed += delta
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
	blocker.position.z -= 0.26*maxf(raise,low_clearance)*(1.0-smoothstep(0.66,0.97,block_lift))
	var shot: Vector3 = ball.global_position
	var crunch := 0.0
	if stage == Stage.HIT and pass_motion.z > 0.1:
		var crossing := maxf(0.0,(Net.NET_Z-pass_origin.z)/pass_motion.z)
		var age := clock-stage_start-crossing
		crunch = smoothstep(-0.13,-0.015,age)*(1.0-smoothstep(0.04,0.19,age))*raise
		if not is_finite(block_contact_at): shot = to_global(flight_point(pass_origin,pass_motion,crossing))
	# Stay upright until the block has enough height to press over the tape.
	var clearance := smoothstep(0.58,BLOCK_HEIGHT,block_lift)
	var extra_height := smoothstep(BLOCK_HEIGHT,BLOCK_HEIGHT+0.508,block_lift)
	var body_press := clearance*(1.0+0.70*extra_height)
	blocker.position.z += 0.12*extra_height*press
	author.rotate_world(pose,"spine_01",Vector3.RIGHT,(0.12*press+0.085*crunch)*body_press)
	author.rotate_world(pose,"spine_02",Vector3.RIGHT,(0.10*press+0.10*crunch)*body_press)
	var track := clampf(shot.x-blocker.position.x,-0.23,0.23)
	block_tracking = lerpf(block_tracking,track,1.0-exp(-delta*17.0))
	for hand_index in 2:
		var side := "l" if hand_index == 0 else "r"
		var sign_ := 1.0 if side == "l" else -1.0
		var shoulder: Vector3 = author.point(pose,"upperarm_"+side)
		var wrist := shoulder+Vector3(-sign_*0.105+block_tracking*press*2.0,0.64,0.20+0.34*press)/scale_
		author.limb(pose,"upperarm_"+side,"lowerarm_"+side,"hand_"+side,wrist,Vector3(sign_*0.31,-0.52,0.34),raise,176.0)
		var base: Transform3D = author.world_pose(pose,rig.find_bone("hand_"+side))
		var fingers: Vector3 = author.point(pose,"middle_01_"+side)-base.origin
		var across: Vector3 = author.point(pose,"index_01_"+side)-author.point(pose,"pinky_01_"+side)
		var ball_direction := (rig.to_local(ball.global_position)-base.origin).normalized()
		if ball_direction.z > 0.04 and not is_finite(block_contact_at):
			var desired := Vector3(clampf(ball_direction.x,-0.16,0.16),clampf(ball_direction.y,-0.14,0.09),1.0).normalized()
			hand_normals[hand_index] = hand_normals[hand_index].slerp(desired,1.0-exp(-delta*28.0))
		var toward_ball := hand_normals[hand_index]
		var finger_direction := Vector3.UP.slide(toward_ball).normalized()
		var index_edge := finger_direction.cross(toward_ball).normalized()*-sign_
		var palm := HandPose.hand_basis(finger_direction,index_edge)*HandPose.hand_basis(fingers,across).inverse()*base.basis
		author.set_world_basis(pose,"hand_"+side,base.basis.slerp(palm,raise))
		spread_block_fingers(pose,rig,author,side,raise)
	var retreat := block_net_retreat(pose,rig,author)
	blocker.position.z -= retreat
	for hand_index in 2:
		update_block_hand(pose,rig,author,"l" if hand_index == 0 else "r",hand_index,delta)
	for bone in rig.get_bone_count(): rig.set_bone_pose_rotation(bone,pose[bone].basis.get_rotation_quaternion())
	if pose_time >= BLOCK_LOAD+BLOCK_AIR+0.20:
		block_elapsed = -1.0
		block_lift = 0.0
		blocker.position = block_base
		blocker.animator.seek(0.0,true)

func block_net_retreat(pose: Array, rig: Skeleton3D, author: RefCounted) -> float:
	var furthest := Net.NET_Z-0.035
	var tape := Net.NET_TOP+0.035
	for side in ["l","r"]:
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
	var wrist: Vector3 = author.point(pose,"hand_"+side)
	var middle: Vector3 = author.point(pose,"middle_01_"+side)
	var fingertip: Vector3 = author.point(pose,"middle_03_"+side)
	var across: Vector3 = author.point(pose,"pinky_01_"+side)-author.point(pose,"index_01_"+side)
	var local_normal := (middle-wrist).cross(across).normalized()*(-1.0 if side == "l" else 1.0)
	var normal := (global_basis.inverse()*rig.global_basis*local_normal).normalized()
	var center := to_local(rig.to_global(wrist.lerp(middle,0.76)))
	var previous: Vector3 = block_hands[index].get("center",center)
	block_hands[index] = {
		"wrist":to_local(rig.to_global(wrist)),
		"tip":to_local(rig.to_global(fingertip)),
		"center":center,
		"normal":normal,
		"velocity":((center-previous)/maxf(delta,0.001)).limit_length(5.0)
	}

func rebound_from_hand(incoming: Vector3, hit: Vector3, hand: Dictionary) -> Vector3:
	var normal: Vector3 = hand.normal
	var motion: Vector3 = hand.velocity
	var relative := incoming-motion
	if normal.dot(relative) > 0.0: normal = -normal
	var center: Vector3 = hand.center
	var edge := (hit-center).slide(normal).limit_length(0.23)
	normal = (normal+edge*2.0).normalized()
	var normal_speed := minf(relative.dot(normal),0.0)
	return relative.slide(normal)*0.69-normal*normal_speed*0.42+motion*0.52

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

func play_spike(time: float, delta: float) -> void:
	if is_finite(block_contact_at):
		var elapsed := time-block_contact_at
		var end := Flight.landing_time(block_contact,block_velocity)
		ball.position = flight_point(block_contact,block_velocity,minf(elapsed,end))
		if time < SWING_FOLLOW_TIME:
			var follow := 1.0-pow(1.0-clampf(time/0.19,0.0,1.0),2.0)
			pose_bow_draw(delta,1.0-smoothstep(0.19,SWING_FOLLOW_TIME,time),swing_contact,swing_contact_extension,follow)
		if elapsed >= end and elapsed-delta < end: play_floor_sound()
		if elapsed >= end+0.40 and not jump.active: reset_feed()
		return
	if block_lift > 0.10 and time <= flight_end:
		var before := flight_point(pass_origin,pass_motion,maxf(0.0,time-delta))
		var after := flight_point(pass_origin,pass_motion,time)
		var best_gap := BallPreview.RADIUS+0.19
		var hit_hand: Dictionary = {}
		for hand in block_hands:
			if hand.is_empty(): continue
			var closest := Geometry3D.get_closest_points_between_segments(before,after,hand.wrist,hand.tip)
			var gap := closest[0].distance_to(closest[1])
			if closest[0].y >= Net.NET_TOP and gap <= best_gap:
				best_gap = gap
				block_contact = closest[0]
				hit_hand = hand
		if not hit_hand.is_empty():
			block_contact_at = time
			var incoming := pass_motion+Vector3.DOWN*Flight.GRAVITY*time
			block_velocity = rebound_from_hand(incoming,block_contact,hit_hand)
			ball.position = block_contact
			status.text = "Block!"
			if not ball_audio_muted: spike_audio.play()
			return
	super.play_spike(time,delta)
