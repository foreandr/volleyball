extends Node3D

const BallPreview = preload("res://scripts/animation_ball_preview.gd")
const Net = preload("res://scripts/net_collision.gd")
const Flight = preload("res://scripts/pass_flight.gd")
const START := Vector3(0.0,0.04,-5.95)
const TARGET := Vector3(0.0,Flight.FLOOR,10.5)
const CONTACT_TIME := 0.55
const STEP_DISTANCE := 0.70
const PREVIEW_DOTS := 42

var player: Node3D
var ball: MeshInstance3D
var aim_ring: MeshInstance3D
var path_preview: MultiMeshInstance3D
var net_hit: Dictionary = {}
var original_transform: Transform3D
var original_animation_mode: int
var elapsed := -1.0
var origin: Vector3
var velocity: Vector3
var landing_time := 0.0
var target := TARGET
var apex := 5.6
var foot_starts: Dictionary = {}

func aim(point: Vector3) -> void:
	target = Vector3(clampf(point.x,-4.35,4.35),Flight.FLOOR,clampf(point.z,4.4,12.85))
	aim_ring.position = Vector3(target.x,0.062,target.z)
	update_path_preview()

func change_arc(amount: float) -> void:
	apex = clampf(apex+amount,3.5,9.0)
	update_path_preview()

func configure(actor: Node3D) -> void:
	player = actor
	original_transform = player.transform
	original_animation_mode = player.animator.callback_mode_process
	player.position = START
	player.rotation.y = 0.0
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
	dots.instance_count = PREVIEW_DOTS
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
	net_hit.clear()
	player.play_action("idle",0.0)
	player.position = START
	player.animator.seek(0.0,true)
	var rig: Skeleton3D = player.skeleton
	for side in ["l","r"]:
		foot_starts[side] = rig.to_global(rig.get_bone_global_pose(rig.find_bone("foot_"+side)).origin)
	pose(CONTACT_TIME)
	preview_origin = ball.position
	pose(0.0)
	update_path_preview()

var preview_origin: Vector3

func update_path_preview() -> void:
	var duration := flight_duration(preview_origin)
	var launch := launch_velocity(preview_origin,duration)
	for i in PREVIEW_DOTS:
		var time := duration*(i+1)/float(PREVIEW_DOTS)
		var point := preview_origin+launch*time+Vector3.DOWN*0.5*Flight.GRAVITY*time*time
		path_preview.multimesh.set_instance_transform(i,Transform3D(Basis.IDENTITY,point))

func flight_duration(start: Vector3) -> float:
	return (sqrt(2.0*Flight.GRAVITY*(apex-start.y))+sqrt(2.0*Flight.GRAVITY*(apex-Flight.FLOOR)))/Flight.GRAVITY

func launch_velocity(start: Vector3, duration: float) -> Vector3:
	return (target-start).slide(Vector3.UP)/duration+Vector3.UP*sqrt(2.0*Flight.GRAVITY*(apex-start.y))

func serve() -> void:
	if elapsed >= 0.0: return
	elapsed = 0.0

func step(delta: float) -> void:
	if elapsed < 0.0: return
	var previous := elapsed
	elapsed += delta
	pose(CONTACT_TIME if previous < CONTACT_TIME and elapsed >= CONTACT_TIME else elapsed)
	if previous < CONTACT_TIME and elapsed >= CONTACT_TIME:
		origin = ball.position
		landing_time = flight_duration(origin)
		velocity = launch_velocity(origin,landing_time)
		net_hit = Net.first_hit(flight_point,0.0,landing_time)
		if not net_hit.is_empty(): landing_time = net_hit.end_time
	var flight_time := elapsed-CONTACT_TIME
	if flight_time >= 0.0:
		var time := minf(flight_time,landing_time)
		ball.position = Net.after_hit(net_hit,time) if not net_hit.is_empty() and time >= net_hit.time else flight_point(time)
	if flight_time >= landing_time+0.55: reset()

func flight_point(time: float) -> Vector3:
	return origin+velocity*time+Vector3.DOWN*0.5*Flight.GRAVITY*time*time

func pose(time: float) -> void:
	var step := smoothstep(0.14,0.50,time)
	var transfer := smoothstep(0.20,CONTACT_TIME,time)
	player.position = START+Vector3.BACK*STEP_DISTANCE*0.55*transfer
	player.position.y -= 0.12*transfer*(1.0-smoothstep(0.55,1.05,time))
	player.animator.seek(0.0,true)
	var rig: Skeleton3D = player.skeleton
	var author: RefCounted = player.get_pose_author()
	var bones: Array = []
	for bone in rig.get_bone_count(): bones.append(rig.get_bone_pose(bone))
	var scale_: float = rig.global_basis.get_scale().y
	for side in ["l","r"]:
		var foot: Vector3 = foot_starts[side]
		if side == "l": foot += Vector3.BACK*STEP_DISTANCE*step+Vector3.UP*0.11*sin(PI*step)
		author.limb(bones,"thigh_"+side,"calf_"+side,"foot_"+side,rig.to_local(foot),Vector3(0.1 if side == "l" else -0.1,0.2,1.0))
	var back := smoothstep(0.0,0.32,time)*(1.0-smoothstep(0.32,CONTACT_TIME,time))
	var follow := smoothstep(CONTACT_TIME,0.78,time)*(1.0-smoothstep(0.78,1.22,time))
	var right_shoulder: Vector3 = author.point(bones,"upperarm_r")
	var left_shoulder: Vector3 = author.point(bones,"upperarm_l")
	var right_wrist := right_shoulder+Vector3(0.06+0.17*back,-0.49+0.30*follow,0.33-0.68*back+0.16*follow)/scale_
	var left_wrist := left_shoulder+Vector3(-0.19,-0.44,0.37)/scale_
	var hold := 1.0-smoothstep(CONTACT_TIME,0.85,time)
	var left_ready: Vector3 = author.point(bones,"hand_l")
	author.limb(bones,"upperarm_l","lowerarm_l","hand_l",left_ready.lerp(left_wrist,hold),Vector3(0.3,-0.4,0.6))
	var left_hand: Vector3 = author.point(bones,"hand_l")
	var strike := smoothstep(0.32,CONTACT_TIME,time)*(1.0-smoothstep(CONTACT_TIME,0.78,time))
	right_wrist = right_wrist.lerp(left_hand+Vector3(0.04,0.04,0.03)/scale_,strike)
	author.limb(bones,"upperarm_r","lowerarm_r","hand_r",right_wrist,Vector3(-0.3,-0.4,0.6))
	var across: Vector3 = (author.point(bones,"index_01_r")-author.point(bones,"pinky_01_r")).normalized()
	for digit in ["index","middle","ring","pinky"]:
		for joint in ["01","02","03"]:
			author.rotate_world(bones,"%s_%s_r" % [digit,joint],across,-1.25 if joint != "03" else -0.85)
	author.rotate_world(bones,"thumb_01_r",across,-0.45)
	for bone in rig.get_bone_count():
		rig.set_bone_pose_rotation(bone,bones[bone].basis.get_rotation_quaternion())
	if time <= CONTACT_TIME:
		ball.position = to_local(rig.to_global(left_hand))+Vector3(0.0,0.09,0.08)
