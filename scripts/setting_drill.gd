extends Node3D

const Player = preload("res://scripts/volleyball_player.gd")
const Flight = preload("res://scripts/pass_flight.gd")
const Contact = preload("res://scripts/forearm_contact.gd")
const BallPreview = preload("res://scripts/animation_ball_preview.gd")
const SOURCE := Vector3(0.6,2.8,12.3)
const SERVE_TIME := 1.55
const PASS_APEX := 4.0
const SET_HEIGHT := 2.0
const REGION_RADIUS := 0.65
const TARGETS := [Vector3(0.8,SET_HEIGHT,1.15),Vector3(-1.45,SET_HEIGHT,0.3),Vector3(1.85,SET_HEIGHT,0.1),Vector3(-0.3,SET_HEIGHT,1.8)]

var receiver: Node3D
var setter: Node3D
var status: Label
var ball: MeshInstance3D
var region: MeshInstance3D
var region_style := StandardMaterial3D.new()
var contact: Vector3
var contact_frame: float
var receive_duration: float
var serve_velocity: Vector3
var pass_velocity: Vector3
var arrival: float
var landing: float
var clock := 0.0
var rep := 0
var receiving := false
var judged := false

func configure(player: Node3D, readout: Label) -> void:
	setter = player
	status = readout
	receiver = Player.new()
	receiver.name = "CPUReceiver"
	receiver.player_number = 2
	receiver.team_color = Color("35b59b")
	receiver.position = Vector3(-1.8,0.04,-2.85)
	var facing: Vector3 = SOURCE-receiver.position
	receiver.rotation.y = atan2(facing.x,facing.z)
	add_child(receiver)
	receiver.get_node("DirectionArrows").hide()
	receiver.play_action("forearm")
	var clip: Animation = receiver.animator.get_animation("custom_forearm/clip")
	contact_frame = float(clip.get_meta("contact_time"))
	receive_duration = clip.length
	receiver.animator.seek(contact_frame,true)
	var rig: Skeleton3D = receiver.skeleton
	var elbows := []
	var wrists := []
	for side in ["l","r"]:
		elbows.append(rig.to_global(rig.get_bone_global_pose(rig.find_bone("lowerarm_"+side)).origin))
		wrists.append(rig.to_global(rig.get_bone_global_pose(rig.find_bone("hand_"+side)).origin))
	contact = Contact.surface(elbows,wrists,0.055).ball
	serve_velocity = (contact-SOURCE)/SERVE_TIME+Vector3.UP*Flight.GRAVITY*SERVE_TIME*0.5
	ball = MeshInstance3D.new()
	ball.mesh = BallPreview.make_ball()
	var ball_style := StandardMaterial3D.new()
	ball_style.vertex_color_use_as_albedo = true
	ball_style.roughness = 0.7
	ball_style.cull_mode = BaseMaterial3D.CULL_DISABLED
	ball.material_override = ball_style
	add_child(ball)
	region = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = REGION_RADIUS-0.045
	ring.outer_radius = REGION_RADIUS
	region.mesh = ring
	region_style.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	region.material_override = region_style
	region.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(region)
	reset_feed()

func reset_feed() -> void:
	clock = 0.0
	receiving = false
	judged = false
	var target: Vector3 = TARGETS[rep % TARGETS.size()]
	var rise := sqrt(2.0*Flight.GRAVITY*(PASS_APEX-contact.y))
	arrival = rise/Flight.GRAVITY+sqrt(2.0*(PASS_APEX-SET_HEIGHT)/Flight.GRAVITY)
	pass_velocity = (target-contact).slide(Vector3.UP)/arrival+Vector3.UP*rise
	landing = Flight.landing_time(contact,pass_velocity)
	region.position = Vector3(target.x,0.065,target.z)
	region_style.albedo_color = Color("49d6ff")
	region.hide()
	ball.position = SOURCE
	receiver.play_action("idle")
	status.text = "Serve incoming"

func step(delta: float) -> void:
	clock += delta
	var elapsed := clock-0.45
	if elapsed < 0.0: return
	var after_pass := elapsed-SERVE_TIME
	var frame := contact_frame+after_pass
	if frame >= 0.0 and frame < receive_duration:
		if not receiving:
			receiving = true
			receiver.play_action("forearm")
			receiver.animator.pause()
		receiver.animator.seek(frame,true)
	elif receiving:
		receiving = false
		receiver.play_action("idle")
	if after_pass < 0.0:
		ball.position = flight_point(SOURCE,serve_velocity,elapsed)
		return
	if not region.visible:
		region.show()
		status.text = "Move under the pass"
	ball.position = flight_point(contact,pass_velocity,minf(after_pass,landing))
	if not judged and after_pass >= arrival:
		judged = true
		var under := (setter.position-region.position).slide(Vector3.UP).length() <= REGION_RADIUS
		region_style.albedo_color = Color("66e891") if under else Color("ff9966")
		status.text = "Under the ball" if under else "Outside the target"
	if after_pass >= landing+0.8:
		rep += 1
		reset_feed()

func flight_point(origin: Vector3, velocity: Vector3, time: float) -> Vector3:
	return origin+velocity*time-Vector3.UP*0.5*Flight.GRAVITY*time*time
