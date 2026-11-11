extends Node3D

const BallPreview = preload("res://scripts/animation_ball_preview.gd")
const Flight = preload("res://scripts/pass_flight.gd")
const START := Vector3(0.0,0.04,-5.65)
const TARGET := Vector3(0.0,Flight.FLOOR,10.5)
const CONTACT_TIME := 0.55

var player: Node3D
var ball: MeshInstance3D
var original_transform: Transform3D
var original_animation_mode: int
var elapsed := -1.0
var origin: Vector3
var velocity: Vector3
var landing_time := 0.0

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
	reset()

func stop() -> void:
	player.transform = original_transform
	player.animator.callback_mode_process = original_animation_mode
	queue_free()

func reset() -> void:
	elapsed = -1.0
	player.play_action("idle",0.0)
	player.animator.seek(0.0,true)
	pose(0.0)

func serve() -> void:
	if elapsed >= 0.0: return
	elapsed = 0.0

func step(delta: float) -> void:
	if elapsed < 0.0: return
	var previous := elapsed
	elapsed += delta
	pose(elapsed)
	if previous < CONTACT_TIME and elapsed >= CONTACT_TIME:
		origin = ball.position
		var duration := 1.95
		velocity = (TARGET-origin)/duration+Vector3.UP*Flight.GRAVITY*duration*0.5
		landing_time = duration
	var flight_time := elapsed-CONTACT_TIME
	if flight_time >= 0.0:
		var time := minf(flight_time,landing_time)
		ball.position = origin+velocity*time+Vector3.DOWN*0.5*Flight.GRAVITY*time*time
	if flight_time >= landing_time+0.55: reset()

func pose(time: float) -> void:
	player.animator.seek(0.0,true)
	var rig: Skeleton3D = player.skeleton
	var author: RefCounted = player.get_pose_author()
	var bones: Array = []
	for bone in rig.get_bone_count(): bones.append(rig.get_bone_pose(bone))
	var scale_: float = rig.global_basis.get_scale().y
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
	for bone in rig.get_bone_count():
		rig.set_bone_pose_rotation(bone,bones[bone].basis.get_rotation_quaternion())
	if time <= CONTACT_TIME:
		ball.position = to_local(rig.to_global(left_hand))+Vector3(0.0,0.09,0.08)
