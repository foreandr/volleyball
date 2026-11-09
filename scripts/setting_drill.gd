extends Node3D

const Player = preload("res://scripts/volleyball_player.gd")
const Flight = preload("res://scripts/pass_flight.gd")
const Contact = preload("res://scripts/forearm_contact.gd")
const Dive = preload("res://scripts/forward_reception_dive.gd")
const KneeSlide = preload("res://scripts/side_knee_slide.gd")
const BumpSetting = preload("res://scripts/bump_setting.gd")
const Net = preload("res://scripts/net_collision.gd")
const BallPreview = preload("res://scripts/animation_ball_preview.gd")
const RECEIVER_START := Vector3(-1.8,0.04,-2.85)
# Distance and local offset of the serve from the ready platform.
const RECEPTIONS := [
	[1,Vector3(0.42,0,0)],
	[2,Vector3(-0.85,0,0)],
	[1,Vector3(0,0,0.42)],
	[3,Vector3(1.42,0,0)],
	[2,Vector3(0.59,0,0.59)],
	[3,Vector3(0,0,1.42)],
	[1,Vector3(-0.42,0,0)],
	[2,Vector3(0.85,0,0)],
	[3,Vector3(-1.42,0,0)],
]
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
var ready_pose: Array[Transform3D]
var clasp: Array[Transform3D]
var slide_pose: Array[Transform3D]
var slide_start: Vector3
var receiver_yaw: float
var receive_offset: Vector3
var receive_tier: int
var receive_side: String
var dive_heading: Vector3
var dive_aim: Vector3
var serve_velocity: Vector3
var pass_velocity: Vector3
var arrival: float
var landing: float
var clock := 0.0
var rep := 0
var receiving := false
var judged := false
var bump: MeshInstance3D
var bump_enabled := false
var ready_range: MeshInstance3D
var range_style := StandardMaterial3D.new()
var arm_swing_weight := 0.0

func configure(player: Node3D, readout: Label, meter: Control, use_bump: bool) -> void:
	setter = player
	status = readout
	receiver = Player.new()
	receiver.name = "CPUReceiver"
	receiver.player_number = 2
	receiver.team_color = Color("35b59b")
	receiver.position = RECEIVER_START
	var facing: Vector3 = SOURCE-receiver.position
	receiver_yaw = atan2(facing.x,facing.z)
	receiver.rotation.y = receiver_yaw
	add_child(receiver)
	receiver.get_node("DirectionArrows").hide()
	receiver.play_action("forearm")
	var clip: Animation = receiver.animator.get_animation("custom_forearm/clip")
	contact_frame = float(clip.get_meta("contact_time"))
	receive_duration = clip.length
	receiver.animator.seek(0.0,true)
	ready_pose = snapshot()
	receiver.animator.seek(contact_frame,true)
	clasp = snapshot()
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
	bump = BumpSetting.new()
	add_child(bump)
	bump.configure(setter,clip,meter)
	bump_enabled = use_bump
	bump.visible = use_bump
	ready_range = MeshInstance3D.new()
	var outline := TorusMesh.new()
	outline.inner_radius = 1.965
	outline.outer_radius = 2.0
	ready_range.mesh = outline
	range_style.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ready_range.material_override = range_style
	ready_range.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ready_range)
	reset_feed()

func set_bump_mode(enabled: bool) -> void:
	if bump_enabled == enabled: return
	bump_enabled = enabled
	bump.visible = enabled
	reset_feed()

func queue_bump() -> void:
	if bump_enabled and clock >= 0.45+SERVE_TIME:
		bump.queue_bump(clock-0.45-SERVE_TIME)

func apply_setter_arms(phase: float, moving: bool, delta: float) -> void:
	var distance := (ball.position-setter.position).slide(Vector3.UP).length()
	ready_range.position = Vector3(ball.position.x,0.058,ball.position.z)
	range_style.albedo_color = Color("6beeb3") if distance <= 2.0 else Color("657f9b")
	var weight := smoothstep(1.85,2.15,distance) if moving else 0.0
	arm_swing_weight = move_toward(arm_swing_weight,weight,delta*7.0)
	if arm_swing_weight <= 0.0: return
	var rig: Skeleton3D = setter.skeleton
	for side in ["l","r"]:
		var sign_ := 1.0 if side == "l" else -1.0
		var shoulder := rig.find_bone("upperarm_"+side)
		var elbow := rig.find_bone("lowerarm_"+side)
		var upper: Quaternion = rig.get_bone_pose_rotation(shoulder)
		var lower: Quaternion = rig.get_bone_pose_rotation(elbow)
		var swing := (0.14+sin(TAU*phase)*0.43*sign_)*arm_swing_weight
		var axis: Vector3 = rig.get_bone_global_pose(shoulder).basis.inverse()*Vector3.RIGHT
		rig.set_bone_pose_rotation(shoulder,upper*Quaternion(axis.normalized(),swing))
		axis = rig.get_bone_global_pose(elbow).basis.inverse()*Vector3.RIGHT
		rig.set_bone_pose_rotation(elbow,lower*Quaternion(axis.normalized(),-0.18*arm_swing_weight))


func reset_feed() -> void:
	clock = 0.0
	receiving = false
	judged = false
	bump.reset()
	var reception: Array = RECEPTIONS[rep % RECEPTIONS.size()]
	receive_tier = reception[0]
	receive_offset = reception[1]
	receive_side = "l" if receive_offset.x >= 0.0 else "r"
	var facing := Basis(Vector3.UP,receiver_yaw)
	dive_heading = facing*receive_offset.normalized()
	dive_aim = RECEIVER_START+facing*receive_offset+Vector3.UP*0.42
	receiver.play_action("forearm")
	receiver.animator.pause()
	pose_receive(0.0)
	contact = platform_contact()
	if is_knee_slide():
		slide_pose = snapshot()
		slide_start = receiver.position
	serve_velocity = (contact-SOURCE)/SERVE_TIME+Vector3.UP*Flight.GRAVITY*SERVE_TIME*0.5
	receiver.position = RECEIVER_START
	receiver.rotation.y = receiver_yaw
	var target: Vector3 = TARGETS[rep % TARGETS.size()]
	var rise := sqrt(2.0*Flight.GRAVITY*(PASS_APEX-contact.y))
	arrival = rise/Flight.GRAVITY+sqrt(2.0*(PASS_APEX-SET_HEIGHT)/Flight.GRAVITY)
	pass_velocity = (target-contact).slide(Vector3.UP)/arrival+Vector3.UP*rise
	landing = Flight.landing_time(contact,pass_velocity)
	var stand := target
	if bump_enabled:
		var bump_height: float = bump.ready_contact().y
		var bump_arrival := rise/Flight.GRAVITY+sqrt(2.0*(PASS_APEX-bump_height)/Flight.GRAVITY)
		stand = flight_point(contact,pass_velocity,bump_arrival)+pass_velocity.slide(Vector3.UP).normalized()*0.62
	region.position = Vector3(stand.x,0.065,stand.z)
	region_style.albedo_color = Color("49d6ff")
	region.visible = bump_enabled
	ball.position = SOURCE
	receiver.play_action("idle")
	status.text = "Serve incoming"

func step(delta: float) -> void:
	var previous := clock-0.45-SERVE_TIME
	clock += delta
	if bump_enabled: bump.update_aim()
	var elapsed := clock-0.45
	if elapsed < 0.0: return
	var after_pass := elapsed-SERVE_TIME
	var start := -Dive.WINDUP if is_forward_dive() else -contact_frame
	var finish := Dive.DURATION-Dive.WINDUP if is_forward_dive() else receive_duration-contact_frame
	if is_knee_slide(): finish = KneeSlide.DURATION
	if after_pass >= start and after_pass < finish:
		if not receiving:
			receiving = true
			receiver.play_action("forearm")
			receiver.animator.pause()
		pose_receive(after_pass)
		if not is_forward_dive() and after_pass > 0.0: recover_receiver_arms(after_pass)
	elif receiving:
		receiving = false
		receiver.position = RECEIVER_START
		receiver.rotation.y = receiver_yaw
		receiver.play_action("idle")
	if after_pass < 0.0:
		ball.position = flight_point(SOURCE,serve_velocity,elapsed)
		return
	if not region.visible or status.text == "Serve incoming":
		region.show()
		status.text = "Get your platform under the ball" if bump_enabled else "Move under the pass"
	ball.position = flight_point(contact,pass_velocity,minf(after_pass,landing))
	if bump_enabled:
		step_bump(after_pass,maxf(0.0,previous),delta)
		return
	if not judged and after_pass >= arrival:
		judged = true
		var under := (setter.position-region.position).slide(Vector3.UP).length() <= REGION_RADIUS
		region_style.albedo_color = Color("66e891") if under else Color("ff9966")
		status.text = "Under the ball" if under else "Outside the target"
	if after_pass >= landing+0.8:
		rep += 1
		reset_feed()

func step_bump(time: float, previous: float, delta: float) -> void:
	var path := func(t): return flight_point(contact,pass_velocity,minf(t,landing))
	var incoming := pass_velocity+Vector3.DOWN*Flight.GRAVITY*time
	bump.update_attempt(time,previous,landing,path,incoming,delta)
	var reset_at := landing
	if is_finite(bump.touch_time):
		var after_touch: float = time-bump.touch_time
		reset_at = bump.touch_time+bump.floor_time
		if not bump.net_hit.is_empty() and after_touch >= bump.net_hit.time:
			ball.position = Net.after_hit(bump.net_hit,after_touch)
		else:
			ball.position = flight_point(bump.touch,bump.outgoing,minf(after_touch,bump.floor_time))
		status.text = "Bump set"
	if time >= reset_at+0.85:
		rep += 1
		reset_feed()

func recover_receiver_arms(time: float) -> void:
	var weight := smoothstep(0.075,0.27,time)
	var rig: Skeleton3D = receiver.skeleton
	for side in ["l","r"]:
		for part in ["clavicle_","upperarm_","lowerarm_","hand_"]:
			var bone := rig.find_bone(part+side)
			if bone >= 0:
				var current := rig.get_bone_pose_rotation(bone)
				rig.set_bone_pose_rotation(bone,current.slerp(ready_pose[bone].basis.get_rotation_quaternion(),weight))

func is_forward_dive() -> bool:
	return receive_tier == 3 and receive_offset.z > 0.0

func is_knee_slide() -> bool:
	return receive_tier == 3 and not is_forward_dive()

func pose_receive(time: float) -> void:
	receiver.rotation.y = receiver_yaw
	if is_forward_dive():
		receiver.pose_reception_dive(ready_pose,clasp,RECEIVER_START,dive_heading,time+Dive.WINDUP,dive_aim,Dive.WINDUP)
		return
	if is_knee_slide() and time > 0.0:
		receiver.pose_reception_knee_slide(slide_pose,ready_pose,slide_start,receive_side,time,{"velocity":pass_velocity,"point":contact,"spread":0.0})
		return
	receiver.animator.seek(clampf(contact_frame+time,0.0,receive_duration),true)
	var tier := mini(receive_tier,2)
	var windup := 0.19 if tier == 2 else 0.15
	var progress := clampf(1.0+time/windup,0.0,1.0)
	var weight := smoothstep(0.0,1.0,progress)*(1.0-smoothstep(0.04,receive_duration-contact_frame,time))
	var side_lunge := tier == 2 and absf(receive_offset.x)>0.1
	var forward_lunge := absf(receive_offset.x)<0.1
	var lead := "r" if forward_lunge and tier == 1 else receive_side
	var stride := 0.68 if side_lunge else 0.48
	if is_knee_slide(): stride += 0.43
	var step := receive_offset.normalized()*stride
	var travel := step*weight
	receiver.position = RECEIVER_START+receiver.basis*travel
	receiver.pose_reception_reach(step,travel,weight,progress,ready_pose,{
		"tier":tier,"back":false,"rear_diagonal":false,"short_straight_back":false,
		"forward_lunge":forward_lunge,"lead":lead,"side_lunge":side_lunge,"height":0.0,
	},is_knee_slide(),0,Vector3.INF)

func snapshot() -> Array[Transform3D]:
	var pose: Array[Transform3D] = []
	for bone in receiver.skeleton.get_bone_count():
		pose.append(receiver.skeleton.get_bone_pose(bone))
	return pose

func platform_contact() -> Vector3:
	var rig: Skeleton3D = receiver.skeleton
	var elbows := []
	var wrists := []
	for side in ["l","r"]:
		elbows.append(rig.to_global(rig.get_bone_global_pose(rig.find_bone("lowerarm_"+side)).origin))
		wrists.append(rig.to_global(rig.get_bone_global_pose(rig.find_bone("hand_"+side)).origin))
	return Contact.surface(elbows,wrists,0.055).ball

func flight_point(origin: Vector3, velocity: Vector3, time: float) -> Vector3:
	return origin+velocity*time-Vector3.UP*0.5*Flight.GRAVITY*time*time
