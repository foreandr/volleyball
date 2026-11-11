extends "res://scripts/underhand_serve.gd"

const SpikeArm = preload("res://scripts/spike_arm_swing.gd")

const FLOAT_CONTACT := 0.79
const TOSS_RELEASE := 0.34

var toss_origin: Vector3
var drift_segments: Array[Dictionary] = []
const DRIFT_RADIUS := 0.34

func configure(actor: Node3D, start := START, yaw := 0.0) -> void:
	apex = 3.85
	super.configure(actor,start,yaw)
	var marker := aim_ring.material_override as StandardMaterial3D
	marker.albedo_color = Color("64cfff")

func contact_time() -> float:
	return FLOAT_CONTACT

func toss_release_time() -> float:
	return TOSS_RELEASE

func reset() -> void:
	super.reset()
	pose(toss_release_time())
	toss_origin = ball.position
	pose(0.0)

func front_start_limit() -> float:
	return -6.55

func float_body_scale() -> float:
	return 0.73

func preview_lane_count() -> int:
	return 3

func preview_lane_offset(lane: int, progress: float, launch: Vector3) -> Vector3:
	if lane == 0: return Vector3.ZERO
	var side := Vector3.UP.cross(launch.slide(Vector3.UP).normalized())
	return side*DRIFT_RADIUS*progress*(1.0 if lane == 1 else -1.0)

func begin_serve_curve() -> void:
	drift_segments.clear()
	add_drift_segment(0.0,Vector2.ZERO)

func add_drift_segment(start: float, previous: Vector2) -> void:
	var sample := Vector2.from_angle(randf_range(0.0,TAU))*sqrt(randf())
	var next := previous.lerp(sample,0.65)
	drift_segments.append({"start":start,"end":start+randf_range(0.28,0.54),"from":previous,"to":next})

func advance_serve_curve(time: float) -> void:
	while not drift_segments.is_empty() and time >= float(drift_segments.back().end):
		var previous: Dictionary = drift_segments.back()
		add_drift_segment(previous.end,previous.to)

func serve_curve_offset(time: float, duration: float) -> Vector3:
	if drift_segments.is_empty() or time <= 0.0: return Vector3.ZERO
	var segment: Dictionary = drift_segments.back()
	for candidate in drift_segments:
		if time <= float(candidate.end):
			segment = candidate
			break
	var blend := smoothstep(float(segment.start),float(segment.end),time)
	var start_offset: Vector2 = segment.from
	var offset := start_offset.lerp(segment.to,blend)
	var progress := clampf(time/maxf(duration,0.001),0.0,1.0)
	var side := Vector3.UP.cross(velocity.slide(Vector3.UP).normalized())
	var vertical := offset.y*(1.0-smoothstep(0.78,1.0,progress))
	return (side*offset.x+Vector3.UP*vertical)*DRIFT_RADIUS*progress

func float_approach(time: float, plant_time: float, land_time: float, jump_height: float, stride_scale: float) -> Array:
	var phase := time/plant_time
	var left_lead := smoothstep(0.09,0.38,phase)
	var right_step := smoothstep(0.40,0.72,phase)
	var left_plant := smoothstep(0.72,0.96,phase)
	var flight := clampf((time-plant_time)/(land_time-plant_time),0.0,1.0) if jump_height > 0.0 else 0.0
	var load := smoothstep(0.65,0.90,phase)*(1.0-smoothstep(0.90,1.04,phase))
	var lift := 4.0*jump_height*flight*(1.0-flight)
	var jumping := jump_height > 0.0
	var drift := (0.78 if jumping else 0.58)*flight
	var recovery := smoothstep(contact_time()-0.02,contact_time()+0.31,time)
	var ground_travel := (0.30*left_lead+0.41*right_step+0.43*left_plant)*stride_scale
	if jumping:
		var run := clampf((phase-0.05)/0.95,0.0,1.0)
		ground_travel = 1.14*stride_scale*pow(run,1.53)
	player.position = serve_start+forward*(ground_travel+drift+(0.20*recovery if not jumping else 0.0))+Vector3.UP*(lift-(0.23 if jumping else 0.13)*load)
	player.animator.seek(0.0,true)
	var rig: Skeleton3D = player.skeleton
	var author: RefCounted = player.get_pose_author()
	var bones: Array = []
	for bone in rig.get_bone_count(): bones.append(rig.get_bone_pose(bone))
	var coil := smoothstep(0.25,contact_time()-0.23,time)
	var unwind := smoothstep(contact_time()-0.22,contact_time(),time)
	var settle := smoothstep(contact_time(),contact_time()+0.36,time)
	var hip_turn := (-0.40*coil*(1.0-unwind)+0.44*unwind*(1.0-settle))*float_body_scale()
	author.rotate_world(bones,"pelvis",Vector3.UP,hip_turn)
	if jumping: author.rotate_world(bones,"spine_02",Vector3.RIGHT,0.32*load)
	for side in ["l","r"]:
		var left: bool = side == "l"
		var foot: Vector3 = foot_starts[side]
		var advance := (0.49*left_lead+0.93*left_plant if left else 1.12*right_step)*stride_scale
		var step_height := 0.13*(sin(PI*left_lead)+sin(PI*left_plant)) if left else 0.15*sin(PI*right_step)
		if not left:
			var kick := sin(PI*flight)*(1.0-smoothstep(0.02,0.24,time-contact_time())) if jumping else sin(PI*recovery)*0.45
			advance += (0.38*recovery if jump_height == 0.0 else 0.0)-0.33*kick
			step_height += 0.25*kick
		var tuck := 0.09*sin(PI*flight)*(1.0-smoothstep(0.02,0.22,time-contact_time()))
		foot += forward*(advance+drift)+Vector3.UP*(lift+step_height+tuck)
		author.limb(bones,"thigh_"+side,"calf_"+side,"foot_"+side,rig.to_local(foot),Vector3(0.12 if left else -0.12,0.2,1.0))
	return bones

func float_step_pose(time: float) -> Array:
	return float_approach(time,0.70,1.20,0.0,0.78)

func pose(time: float) -> void:
	var contact := contact_time()
	var toss_release := toss_release_time()
	var bones := float_step_pose(time)
	var rig: Skeleton3D = player.skeleton
	var author: RefCounted = player.get_pose_author()
	var scale_: float = rig.global_basis.get_scale().y
	var windup := smoothstep(0.09,contact-0.21,time)
	var drive := smoothstep(contact-0.22,contact,time)
	var follow := smoothstep(contact,contact+0.40,time)
	author.rotate_world(bones,"spine_03",Vector3.UP,(-0.48*windup*(1.0-drive)+0.39*drive*(1.0-0.60*follow))*float_body_scale())
	author.rotate_world(bones,"spine_02",Vector3.RIGHT,-0.17*windup*(1.0-drive)+0.22*follow)
	var left_shoulder: Vector3 = author.point(bones,"upperarm_l")
	var right_shoulder: Vector3 = author.point(bones,"upperarm_r")
	var toss_lift := smoothstep(0.07,toss_release,time)
	var left_drop := smoothstep(toss_release,0.72,time)
	var left_wrist := left_shoulder+Vector3(-0.14-0.12*toss_lift,-0.37+0.48*toss_lift,0.41)/scale_
	var left_ready: Vector3 = author.point(bones,"hand_l")
	author.limb(bones,"upperarm_l","lowerarm_l","hand_l",left_wrist.lerp(left_ready,left_drop),Vector3(0.30,-0.9,-0.15))
	orient_palm(bones,rig,author,"l",Vector3.BACK,Vector3.LEFT,1.0-left_drop)
	var low_right := right_shoulder+Vector3(-0.08,-0.53,0.03)/scale_
	var drawn_right := right_shoulder+Vector3(-0.24,0.34,-0.47)/scale_
	var contact_right := right_shoulder+Vector3(-0.045,0.53,0.28)/scale_
	var follow_right := right_shoulder+Vector3(0.36,-0.42,0.30)/scale_
	var right_wrist := low_right.lerp(drawn_right,windup).lerp(contact_right,drive).lerp(follow_right,follow)
	author.limb(bones,"upperarm_r","lowerarm_r","hand_r",right_wrist,Vector3(-0.62,0.12,-0.91).lerp(Vector3(-0.35,-0.3,0.6),drive),1.0,176.0)
	prepare_toss_hands(bones,rig,author,time)
	shape_float_strike(bones,rig,author,time)
	finish_float_wrist(bones,rig,author,time)
	for bone in rig.get_bone_count(): rig.set_bone_pose_rotation(bone,bones[bone].basis.get_rotation_quaternion())
	if time <= toss_release:
		var palm: Vector3 = toss_palm(bones,rig,author,time)
		ball.position = to_local(rig.to_global(palm))+Vector3.UP*(BallPreview.RADIUS+0.012)
	elif is_equal_approx(time,contact):
		var palm: Vector3 = author.point(bones,"hand_r").lerp(author.point(bones,"middle_01_r"),0.76)
		ball.position = to_local(rig.to_global(palm))+forward*(BallPreview.RADIUS+0.012)
	elif time < contact:
		var portion := (time-toss_release)/(contact-toss_release)
		ball.position = toss_origin.lerp(preview_origin,portion)+Vector3.UP*toss_curve_height()*4.0*portion*(1.0-portion)

func finish_float_wrist(pose: Array, rig: Skeleton3D, author: RefCounted, time: float) -> void:
	var contact := contact_time()
	var weight := smoothstep(toss_release_time(),toss_release_time()+0.22,time)
	SpikeArm.align_wrist_to_forearm(pose,author,0.88*weight)
	var hand := rig.find_bone("hand_r")
	var neutral := rig.get_bone_rest(hand).basis.get_rotation_quaternion()
	var wrist_rotation: Quaternion = pose[hand].basis.get_rotation_quaternion()
	pose[hand].basis = Basis(wrist_rotation.slerp(neutral,0.78*weight))
	var finish := smoothstep(contact,contact+0.18,time)*(1.0-smoothstep(contact+0.26,recovery_end(),time))
	if finish <= 0.0: return
	var wrist: Vector3 = author.point(pose,"hand_r")
	var elbow: Vector3 = author.point(pose,"lowerarm_r")
	author.rotate_world(pose,"hand_r",(wrist-elbow).normalized(),deg_to_rad(12.0)*finish)

func shape_float_strike(_pose: Array, _rig: Skeleton3D, _author: RefCounted, _time: float) -> void:
	pass

func toss_curve_height() -> float:
	return 0.25

func prepare_toss_hands(_pose: Array, _rig: Skeleton3D, _author: RefCounted, _time: float) -> void:
	pass

func toss_palm(pose: Array, _rig: Skeleton3D, author: RefCounted, _time: float) -> Vector3:
	return author.point(pose,"hand_l").lerp(author.point(pose,"middle_01_l"),0.72)

func orient_palm(pose: Array, rig: Skeleton3D, author: RefCounted, side: String, direction: Vector3, across: Vector3, weight: float) -> void:
	var hand := "hand_"+side
	var base: Transform3D = author.world_pose(pose,rig.find_bone(hand))
	var fingers: Vector3 = author.point(pose,"middle_01_"+side)-base.origin
	var width: Vector3 = author.point(pose,"index_01_"+side)-author.point(pose,"pinky_01_"+side)
	var basis := HandPose.hand_basis(direction,across)*HandPose.hand_basis(fingers,width).inverse()*base.basis
	author.set_world_basis(pose,hand,base.basis.slerp(basis,weight))
	for digit in ["thumb","index","middle","ring","pinky"]:
		for joint in ["01","02","03"]:
			var bone := rig.find_bone("%s_%s_%s" % [digit,joint,side])
			if bone >= 0: pose[bone].basis = pose[bone].basis.slerp(rig.get_bone_rest(bone).basis,weight)
