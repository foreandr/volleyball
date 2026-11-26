extends Node3D

const HandPose = preload("res://scripts/hand_setting_pose.gd")
const BallPreview = preload("res://scripts/animation_ball_preview.gd")
const Net = preload("res://scripts/net_collision.gd")
const Flight = preload("res://scripts/pass_flight.gd")
const START := Vector3(0.0,0.04,-6.20)
const TARGET := Vector3(0.0,Flight.FLOOR,10.5)
const CONTACT_TIME := 0.55
const STEP_DISTANCE := 0.98
const SERVE_CONTACT_LEAD := 0.16
const PREVIEW_DOTS := 42

var player: Node3D
var serve_start := START
var serve_yaw := 0.0
var running := false
var external_rally := false
var moved_after_contact := false
var forward := Vector3.BACK
var ball: MeshInstance3D
var aim_ring: MeshInstance3D
var path_preview: MultiMeshInstance3D
var net_hit: Dictionary = {}
var original_transform: Transform3D
var original_animation_mode: int
var elapsed := -1.0
var swing_time := 0.0
var contact_clock := INF
var origin: Vector3
var velocity: Vector3
var landing_time := 0.0
var planned_duration := 0.0
var target := TARGET
var launch_target := TARGET
var test_speed_mps := 0.0
var apex := 5.6
var foot_starts: Dictionary = {}

func aim(point: Vector3) -> void:
	target = Vector3(point.x,Flight.FLOOR,maxf(point.z,4.4))
	aim_ring.position = Vector3(target.x,0.062,target.z)
	update_path_preview()

func change_arc(amount: float) -> void:
	apex = clampf(apex+amount,3.5,9.0)
	update_path_preview()

func configure(actor: Node3D, start := START, yaw := 0.0) -> void:
	player = actor
	original_transform = player.transform
	original_animation_mode = player.animator.callback_mode_process
	serve_start = start
	serve_yaw = yaw
	player.position = serve_start
	player.rotation.y = yaw
	forward = player.basis.z.normalized()
	player.animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	ball = MeshInstance3D.new()
	ball.mesh = BallPreview.make_ball()
	var style := StandardMaterial3D.new()
	style.vertex_color_use_as_albedo = true
	style.roughness = 0.7
	ball.material_override = style
	add_child(ball)
	aim_ring = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.30
	ring.outer_radius = 0.34
	aim_ring.mesh = ring
	var marker_style := StandardMaterial3D.new()
	marker_style.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_style.albedo_color = Color("ffd278")
	aim_ring.material_override = marker_style
	add_child(aim_ring)
	path_preview = MultiMeshInstance3D.new()
	var dots := MultiMesh.new()
	dots.transform_format = MultiMesh.TRANSFORM_3D
	var dot := SphereMesh.new()
	dot.radius = 0.037
	dot.height = 0.074
	dot.radial_segments = 8
	dot.rings = 4
	var dot_style := StandardMaterial3D.new()
	dot_style.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot_style.albedo_color = Color("64cfff")
	dot.material = dot_style
	dots.mesh = dot
	dots.instance_count = PREVIEW_DOTS*preview_lane_count()
	path_preview.multimesh = dots
	path_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(path_preview)
	reset()
	aim(TARGET)

func stop() -> void:
	player.transform = original_transform
	player.animator.callback_mode_process = original_animation_mode
	queue_free()

func reset() -> void:
	elapsed = -1.0
	contact_clock = INF
	external_rally = false
	moved_after_contact = false
	running = false
	ball.show()
	net_hit.clear()
	player.animator.speed_scale = 1.0
	player.play_action("idle",0.0)
	player.position = serve_start
	player.rotation.y = serve_yaw
	player.animator.seek(0.0,true)
	var rig: Skeleton3D = player.skeleton
	for side in ["l","r"]:
		foot_starts[side] = rig.to_global(rig.get_bone_global_pose(rig.find_bone("foot_"+side)).origin)
	prepare_serve_reset()
	pose(contact_time())
	preview_origin = ball.position
	pose(0.0)
	update_path_preview()

func prepare_serve_reset() -> void:
	pass

var preview_origin: Vector3

func preview_lane_count() -> int:
	return 1

func preview_lane_offset(_lane: int, _progress: float, _launch: Vector3) -> Vector3:
	return Vector3.ZERO

func update_path_preview() -> void:
	var launch := aimed_velocity(preview_origin)
	var duration := Flight.landing_time(preview_origin,launch)
	for lane in preview_lane_count():
		for i in PREVIEW_DOTS:
			var progress := (i+1)/float(PREVIEW_DOTS)
			var time := duration*progress
			var point := preview_origin+launch*time+Vector3.DOWN*0.5*Flight.GRAVITY*time*time+preview_lane_offset(lane,progress,launch)
			path_preview.multimesh.set_instance_transform(lane*PREVIEW_DOTS+i,Transform3D(Basis.IDENTITY,point))

func aimed_velocity(start: Vector3, pace := 1.0) -> Vector3:
	var duration := flight_duration(start)
	if test_speed_mps>0.:
		var displacement := Vector3(target.x-start.x,Flight.FLOOR-start.y,target.z-start.z)
		var speed_term := test_speed_mps*test_speed_mps-Flight.GRAVITY*displacement.y
		var discriminant := speed_term*speed_term-Flight.GRAVITY*Flight.GRAVITY*displacement.length_squared()
		# Lower-angle ballistic solution, limited by the height needed to clear the tape.
		if discriminant>=0. and speed_term>0.:
			var fast_time := sqrt(2.*displacement.length_squared()/(speed_term+sqrt(discriminant)))
			duration=maxf(fast_time,minimum_aim_duration(start))
		else:
			duration=sqrt(2.*displacement.length()/Flight.GRAVITY)
	duration=maxf(.05,duration/pace)
	var velocity_to_target := Vector3(target.x-start.x,Flight.FLOOR-start.y,target.z-start.z)/duration+Vector3.UP*.5*Flight.GRAVITY*duration
	return velocity_to_target.limit_length(test_speed_mps) if test_speed_mps>0. else velocity_to_target

func minimum_aim_duration(_start: Vector3) -> float:
	return 0.0

func flight_duration(start: Vector3) -> float:
	return (sqrt(2.0*Flight.GRAVITY*(apex-start.y))+sqrt(2.0*Flight.GRAVITY*(apex-Flight.FLOOR)))/Flight.GRAVITY

func launch_velocity(start: Vector3, duration: float) -> Vector3:
	return (target-start).slide(Vector3.UP)/duration+Vector3.UP*sqrt(2.0*Flight.GRAVITY*(apex-start.y))

func run_to(point: Vector3, yaw: float, delta: float, animation_speed := 1.0) -> void:
	if elapsed < 0.0:
		preview_origin += point-serve_start
		serve_start = point
	else: moved_after_contact = true
	player.position = point
	player.rotation.y = rotate_toward(player.rotation.y,yaw,delta*16.0)
	player.animator.speed_scale = animation_speed
	player.play_action("run")
	player.animator.advance(delta)
	running = true
	if elapsed < 0.0:
		var rig: Skeleton3D = player.skeleton
		var palm := rig.get_bone_global_pose(rig.find_bone("middle_01_l")).origin
		ball.position = to_local(rig.to_global(palm))+Vector3.UP*(BallPreview.RADIUS+0.012)
		update_path_preview()

func settle_run() -> void:
	if not running: return
	running = false
	player.animator.speed_scale = 1.0
	if elapsed < 0.0: reset()
	else: player.play_action("idle")

func serve() -> void:
	if elapsed >= 0.0: return
	settle_run()
	elapsed = 0.0
	swing_time = 0.0
	contact_clock = INF

func contact_time() -> float:
	return CONTACT_TIME

func front_start_limit() -> float:
	return -5.20

func can_run_after_contact() -> bool:
	return is_finite(contact_clock)

func recovery_end() -> float:
	return 1.23

func step(delta: float) -> void:
	if elapsed < 0.0: return
	var contact := contact_time()
	var previous := swing_time
	var launch_speed := launch_velocity(preview_origin,flight_duration(preview_origin)).length()
	var swing_rate := serve_swing_rate(launch_speed)
	elapsed += delta
	swing_time += delta*swing_rate if not is_finite(contact_clock) else delta
	var striking := previous < contact and swing_time >= contact
	if not moved_after_contact and swing_time <= recovery_end(): pose(contact if striking else swing_time)
	elif not running and not external_rally: player.animator.advance(delta)
	if not is_finite(contact_clock): spin_toss_ball(previous,minf(swing_time,contact),swing_rate)
	if striking:
		contact_clock = elapsed-(swing_time-contact)/swing_rate
		origin = ball.position
		landing_time = flight_duration(origin)
		planned_duration = landing_time
		launch_target = target
		velocity = launch_velocity(origin,landing_time)
		begin_serve_curve()
		net_hit = Net.first_hit(flight_point,0.0,landing_time)
		if not net_hit.is_empty(): landing_time = net_hit.end_time
	var flight_time := elapsed-contact_clock
	if flight_time >= 0.0:
		advance_serve_curve(minf(flight_time,planned_duration))
		spin_serve_ball(delta)
		var time := minf(flight_time,landing_time)
		ball.position = Net.after_hit(net_hit,time) if not net_hit.is_empty() and time >= net_hit.time else flight_point(time)
	if flight_time >= landing_time+0.55 and not external_rally: reset()

func serve_swing_rate(launch_speed: float) -> float:
	return clampf(launch_speed/12.0,0.65,1.45)

func spin_toss_ball(_previous: float, _time: float, _rate: float) -> void:
	pass

func reception_spin_rps() -> float:
	return 0.0

func spin_serve_ball(_delta: float) -> void:
	pass

func begin_serve_curve() -> void:
	pass

func advance_serve_curve(_time: float) -> void:
	pass

func serve_curve_offset(_time: float, _duration: float) -> Vector3:
	return Vector3.ZERO

func flight_point(time: float) -> Vector3:
	return origin+velocity*time+Vector3.DOWN*0.5*Flight.GRAVITY*time*time+serve_curve_offset(time,planned_duration)

func prepare_serve_pose(time: float) -> Array:
	var step := smoothstep(0.14,0.50,time)
	var transfer := smoothstep(0.20,CONTACT_TIME,time)
	player.position = serve_start+forward*(STEP_DISTANCE*0.55-SERVE_CONTACT_LEAD*0.45)*transfer
	player.position.y -= 0.12*transfer*(1.0-smoothstep(CONTACT_TIME,1.05,time))
	player.animator.seek(0.0,true)
	var rig: Skeleton3D = player.skeleton
	var author: RefCounted = player.get_pose_author()
	var bones: Array = []
	for bone in rig.get_bone_count(): bones.append(rig.get_bone_pose(bone))
	for side in ["l","r"]:
		var foot: Vector3 = foot_starts[side]
		if side == "l": foot += forward*STEP_DISTANCE*step+Vector3.UP*0.15*sin(PI*step)
		author.limb(bones,"thigh_"+side,"calf_"+side,"foot_"+side,rig.to_local(foot),Vector3(0.1 if side == "l" else -0.1,0.2,1.0))
	return bones

func pose(time: float) -> void:
	var transfer := smoothstep(0.20,CONTACT_TIME,time)
	var bones := prepare_serve_pose(time)
	var rig: Skeleton3D = player.skeleton
	var author: RefCounted = player.get_pose_author()
	var scale_: float = rig.global_basis.y.length()
	var back := smoothstep(0.0,0.32,time)*(1.0-smoothstep(0.32,CONTACT_TIME,time))
	var follow := smoothstep(CONTACT_TIME,0.78,time)*(1.0-smoothstep(0.78,1.22,time))
	var right_shoulder: Vector3 = author.point(bones,"upperarm_r")
	var left_shoulder: Vector3 = author.point(bones,"upperarm_l")
	var right_wrist := right_shoulder+Vector3(-0.055-0.08*back,-0.59+0.28*back+0.34*follow,0.015-0.66*back+0.51*follow)/scale_
	var left_wrist := Vector3(right_shoulder.x,left_shoulder.y,left_shoulder.z)+Vector3(-0.015,-0.27-0.12*transfer,0.29+(0.13+SERVE_CONTACT_LEAD*0.45)*transfer)/scale_
	var hold := 1.0-smoothstep(CONTACT_TIME,0.85,time)
	var left_ready: Vector3 = author.point(bones,"hand_l")
	author.limb(bones,"upperarm_l","lowerarm_l","hand_l",left_ready.lerp(left_wrist,hold),Vector3(0.22,-1.0,-0.25))
	var left_basis: Transform3D = author.world_pose(bones,rig.find_bone("hand_l"))
	var fingers: Vector3 = author.point(bones,"middle_01_l")-left_basis.origin
	var palm_width: Vector3 = author.point(bones,"index_01_l")-author.point(bones,"pinky_01_l")
	var palm_up := HandPose.hand_basis(Vector3(0.0,0.10,1.0),Vector3.LEFT)*HandPose.hand_basis(fingers,palm_width).inverse()*left_basis.basis
	author.set_world_basis(bones,"hand_l",left_basis.basis.slerp(palm_up,hold))
	for digit in ["thumb","index","middle","ring","pinky"]:
		for joint in ["01","02","03"]:
			var left_digit := rig.find_bone("%s_%s_l" % [digit,joint])
			var right_digit := rig.find_bone("%s_%s_r" % [digit,joint])
			bones[left_digit].basis = bones[left_digit].basis.slerp(rig.get_bone_rest(left_digit).basis,hold)
			bones[right_digit].basis = rig.get_bone_rest(right_digit).basis
	var knuckles: Vector3 = author.point(bones,"middle_01_l")
	var ball_center := left_basis.origin.lerp(knuckles,0.72)+Vector3.UP*(BallPreview.RADIUS+0.012)/scale_
	var strike := smoothstep(0.32,CONTACT_TIME,time)*(1.0-smoothstep(CONTACT_TIME,0.78,time))
	right_wrist = right_wrist.lerp(ball_center+Vector3(-0.02,-0.11,-0.05)/scale_,strike)
	var right_elbow: Vector3 = author.point(bones,"lowerarm_r")
	var right_hand: Vector3 = author.point(bones,"hand_r")
	var arm_length := right_shoulder.distance_to(right_elbow)+right_elbow.distance_to(right_hand)
	var swing_direction := (right_wrist-right_shoulder).normalized()
	right_wrist = right_shoulder+swing_direction*arm_length
	author.limb(bones,"upperarm_r","lowerarm_r","hand_r",right_wrist,Vector3(-0.35,0.15,-1.0),1.0,173.0)
	var across: Vector3 = (author.point(bones,"index_01_r")-author.point(bones,"pinky_01_r")).normalized()
	var fist := smoothstep(0.0,0.13,time)*(1.0-smoothstep(0.85,1.20,time))
	for digit in ["index","middle","ring","pinky"]:
		for joint in ["01","02","03"]:
			author.rotate_world(bones,"%s_%s_r" % [digit,joint],across,fist*(-1.25 if joint != "03" else -0.85))
	author.rotate_world(bones,"thumb_01_r",across,-0.45*fist)
	for bone in rig.get_bone_count():
		rig.set_bone_pose_rotation(bone,bones[bone].basis.get_rotation_quaternion())
	if time <= CONTACT_TIME:
		ball.position = to_local(rig.to_global(ball_center))
