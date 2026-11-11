extends "res://scripts/attack_drill.gd"

const BLOCK_START := Vector3(0.0,0.04,3.25)
const BLOCK_LOAD := 0.16
const BLOCK_AIR := 0.86

var blocker: Node3D
var blocker_start: Transform3D
var blocker_animation_mode: int
var block_elapsed := -1.0
var block_base := BLOCK_START
var block_tracking := 0.0
var block_lift := 0.0
var block_palm_left: Vector3
var block_palm_right: Vector3
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
	aim_swing(Vector3(0.0,Flight.FLOOR,10.5))
	swing_target.hide()
	approach_set_touched_at = clock
	status.text = "Time your jump"

func queue_block() -> void:
	if block_elapsed >= 0.0: return
	block_base = blocker.position
	block_tracking = 0.0
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
	var airborne := clampf((block_elapsed-BLOCK_LOAD)/BLOCK_AIR,0.0,1.0)
	block_lift = 4.0*1.12*airborne*(1.0-airborne)
	var load := smoothstep(0.0,BLOCK_LOAD*0.70,block_elapsed)*(1.0-smoothstep(BLOCK_LOAD*0.70,BLOCK_LOAD,block_elapsed))
	var settle := smoothstep(BLOCK_LOAD+BLOCK_AIR-0.045,BLOCK_LOAD+BLOCK_AIR+0.045,block_elapsed)
	settle *= 1.0-smoothstep(BLOCK_LOAD+BLOCK_AIR+0.045,BLOCK_LOAD+BLOCK_AIR+0.20,block_elapsed)
	blocker.position = block_base+Vector3.UP*(block_lift-0.13*load-0.08*settle)
	blocker.animator.seek(0.0,true)
	var rig: Skeleton3D = blocker.skeleton
	var author: RefCounted = blocker.get_pose_author()
	var pose: Array = []
	for bone in rig.get_bone_count(): pose.append(rig.get_bone_pose(bone))
	var scale_: float = rig.global_basis.get_scale().y
	var raise := smoothstep(0.06,BLOCK_LOAD+0.14,block_elapsed)*(1.0-smoothstep(BLOCK_LOAD+0.63,BLOCK_LOAD+BLOCK_AIR+0.13,block_elapsed))
	var press := smoothstep(BLOCK_LOAD+0.025,BLOCK_LOAD+0.24,block_elapsed)*(1.0-smoothstep(BLOCK_LOAD+0.58,BLOCK_LOAD+0.76,block_elapsed))
	var shot: Vector3 = ball.global_position
	var crunch := 0.0
	if stage == Stage.HIT and pass_motion.z > 0.1:
		var crossing := maxf(0.0,(Net.NET_Z-pass_origin.z)/pass_motion.z)
		var age := clock-stage_start-crossing
		crunch = smoothstep(-0.13,-0.015,age)*(1.0-smoothstep(0.04,0.19,age))*raise
		if not is_finite(block_contact_at): shot = to_global(flight_point(pass_origin,pass_motion,crossing))
	author.rotate_world(pose,"spine_01",Vector3.RIGHT,0.12*press+0.085*crunch)
	author.rotate_world(pose,"spine_02",Vector3.RIGHT,0.10*press+0.10*crunch)
	var track := clampf(shot.x-blocker.position.x,-0.23,0.23)
	block_tracking = lerpf(block_tracking,track,1.0-exp(-delta*17.0))
	for side in ["l","r"]:
		var sign_ := 1.0 if side == "l" else -1.0
		var shoulder: Vector3 = author.point(pose,"upperarm_"+side)
		var wrist := shoulder+Vector3(sign_*(0.06-0.12*press)+block_tracking*press,0.53+0.04*press,0.23+0.34*press)/scale_
		author.limb(pose,"upperarm_"+side,"lowerarm_"+side,"hand_"+side,wrist,Vector3(sign_*0.65,-0.52,0.34),raise,169.0)
		var base: Transform3D = author.world_pose(pose,rig.find_bone("hand_"+side))
		var fingers: Vector3 = author.point(pose,"middle_01_"+side)-base.origin
		var across: Vector3 = author.point(pose,"index_01_"+side)-author.point(pose,"pinky_01_"+side)
		var toward_ball := Vector3(block_tracking*1.4-sign_*0.12*press,-0.48*press,1.0).normalized()
		var finger_direction := Vector3.UP.slide(toward_ball).normalized()
		var index_edge := finger_direction.cross(toward_ball).normalized()
		var palm := HandPose.hand_basis(finger_direction,index_edge)*HandPose.hand_basis(fingers,across).inverse()*base.basis
		author.set_world_basis(pose,"hand_"+side,base.basis.slerp(palm,raise))
		spread_block_fingers(pose,rig,author,side,toward_ball,raise)
	for bone in rig.get_bone_count(): rig.set_bone_pose_rotation(bone,pose[bone].basis.get_rotation_quaternion())
	block_palm_left = to_local(rig.to_global(author.point(pose,"middle_01_l")))
	block_palm_right = to_local(rig.to_global(author.point(pose,"middle_01_r")))
	if block_elapsed >= BLOCK_LOAD+BLOCK_AIR+0.20:
		block_elapsed = -1.0
		block_lift = 0.0
		blocker.position = block_base
		blocker.animator.seek(0.0,true)

func spread_block_fingers(pose: Array, rig: Skeleton3D, author: RefCounted, side: String, palm_normal: Vector3, weight: float) -> void:
	var fingers := ["index","middle","ring","pinky"]
	var spread_angles := [-16.0,-4.0,8.0,21.0]
	var mirror := 1.0 if side == "l" else -1.0
	for digit in fingers+["thumb"]:
		for joint in ["01","02","03"]:
			var index := rig.find_bone("%s_%s_%s" % [digit,joint,side])
			if index >= 0: pose[index].basis = pose[index].basis.slerp(rig.get_bone_rest(index).basis,weight)
	for index in fingers.size():
		author.rotate_world(pose,fingers[index]+"_01_"+side,palm_normal,deg_to_rad(spread_angles[index]*mirror)*weight)
	author.rotate_world(pose,"thumb_01_"+side,palm_normal,deg_to_rad(-17.0*mirror)*weight)

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
		var closest := Geometry3D.get_closest_points_between_segments(before,after,block_palm_left,block_palm_right)
		if closest[0].y >= Net.NET_TOP and closest[0].distance_to(closest[1]) <= BallPreview.RADIUS+0.14:
			block_contact = closest[0]
			block_contact_at = time
			block_velocity = Vector3(pass_motion.x*0.28,1.85,-maxf(2.4,pass_motion.z*0.37))
			ball.position = block_contact
			status.text = "Block!"
			if not ball_audio_muted: spike_audio.play()
			return
	super.play_spike(time,delta)
