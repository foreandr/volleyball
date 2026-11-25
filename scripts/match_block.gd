extends RefCounted

const HandPose = preload("res://scripts/hand_setting_pose.gd")
const START := 0.16
const AIR := 0.74
const ARM_RADII := [.085,.095,.12]
const HEIGHT := 1.16
var actor: Node3D
var age := 0.0
var tempo := 1.0
var jump_height := HEIGHT
var landing_recovery := 0.13
var overpass_swing := false
var aggressive_press := false
var lean_input := 0.
var reach_input := Vector2.ZERO
var lean := 0.
var reach := Vector2.ZERO
var court_aim := Vector3.INF
var elbows: Array[Vector3] = []
var shoulders: Array[Vector3] = []
var min_hand_x := -INF
var max_hand_x := INF
var base: Vector3
var previous_hands: Array[Vector3] = []
var hands: Array[Vector3] = []
var wrists: Array[Vector3] = []
var previous_wrists: Array[Vector3] = []

func begin(player: Node3D) -> void:
	actor = player
	base = player.position
	actor.play_action("idle",0.0)
	actor.animator.seek(0.0,true)

func step(delta: float, world_ball: Vector3) -> bool:
	age += delta*tempo
	var phase := clampf((age-START)/AIR,0.0,1.0)
	var lift := 4.0*jump_height*phase*(1.0-phase)
	var load := sin(PI*clampf(age/START,0.0,1.0))
	var since_landing := age-START-AIR
	var absorb := smoothstep(0.0,0.055,since_landing)*(1.0-smoothstep(0.055,0.145,since_landing))
	var squat := 0.20*load*load+0.14*absorb
	actor.position = base+Vector3.UP*(lift-squat)
	actor.animator.seek(0.0,true)
	var rig: Skeleton3D = actor.skeleton
	var author: RefCounted = actor.get_pose_author()
	var pose: Array = []
	for bone in rig.get_bone_count(): pose.append(rig.get_bone_pose(bone))
	var lower_start := 0.71 if overpass_swing else 0.79
	var lower_end := 0.97 if overpass_swing else 1.02
	var weight := smoothstep(0.04,0.30,age)*(1.0-smoothstep(lower_start,lower_end,age))
	var aim := rig.to_local(world_ball)
	var scale_: float = rig.global_basis.y.length()
	if squat > 0.00001:
		var drop := rig.global_basis.inverse()*(Vector3.UP*squat)
		for side in ["l","r"]:
			var thigh: String = "thigh_"+side
			var knee: String = "calf_"+side
			var foot: String = "foot_"+side
			var ankle: Transform3D = author.world_pose(pose,rig.find_bone(foot))
			var bend: Vector3 = author.point(pose,knee)-author.point(pose,thigh)
			author.limb(pose,thigh,knee,foot,ankle.origin+drop,bend)
			author.set_world_basis(pose,foot,ankle.basis)
	if court_aim.is_finite() and phase>0. and phase<1.:
		var pike := smoothstep(.19,.50,phase)*(1.-smoothstep(.52,.85,phase))*smoothstep(.30,.80,lift)
		var forward := actor.global_basis.z.normalized()
		actor.position-=forward*.19*pike
		author.rotate_world(pose,"spine_01",Vector3.RIGHT,.24*pike)
		author.rotate_world(pose,"spine_02",Vector3.RIGHT,.13*pike)
		for side in ["l","r"]:
			var thigh: String="thigh_"+side
			var calf: String="calf_"+side
			var foot: String="foot_"+side
			var hip: Vector3=author.point(pose,thigh)
			var leg_length := rig.to_global(hip).distance_to(rig.to_global(author.point(pose,calf)))+rig.to_global(author.point(pose,calf)).distance_to(rig.to_global(author.point(pose,foot)))
			var clearance := maxf(0.,rig.to_global(hip).z-preload("res://scripts/net_collision.gd").NET_Z-.19)
			var angle := minf(deg_to_rad(47.),asin(clampf(clearance/maxf(.01,leg_length),0.,1.)))
			var direction := Vector3(.10 if side=="l" else -.10,-cos(angle),sin(angle)).normalized()
			var leg: Vector3=(author.point(pose,calf)-hip).normalized()
			author.aim_joint(pose,thigh,calf,hip+leg.slerp(direction,pike))
			var knee: Vector3=author.point(pose,calf)
			var shin: Vector3=(author.point(pose,foot)-knee).normalized()
			author.aim_joint(pose,calf,foot,knee+shin.slerp(direction,pike*.96))
	var air_weight := smoothstep(0.,.12,phase)*(1.-smoothstep(.82,1.,phase))
	lean=lerpf(lean,lean_input,1.-exp(-14.*delta))
	reach=reach.lerp(reach_input,1.-exp(-16.*delta))
	if absf(lean)*air_weight>.0001:
		var axis_local := (rig.global_basis.inverse()*Vector3.BACK).normalized()
		author.rotate_world(pose,"spine_01",axis_local,-lean*.20*air_weight)
		author.rotate_world(pose,"spine_02",axis_local,-lean*.15*air_weight)
	previous_hands = hands.duplicate()
	previous_wrists = wrists.duplicate()
	hands.clear()
	elbows.clear()
	shoulders.clear()
	wrists.clear()
	for side in ["l","r"]:
		var arm: String = "upperarm_"+side
		var shoulder: Vector3 = author.point(pose,arm)
		var outward := 1.0 if side == "l" else -1.0
		var press := smoothstep(0.32,0.70,lift) if aggressive_press else smoothstep(0.45,0.95,lift)
		var below_tape := 1.0-smoothstep(2.50,2.80,rig.to_global(shoulder).y+0.62)
		var depth := lerpf(lerpf(0.20,0.55,press),0.17,below_tape)
		var lateral_limit := 0.24 if aggressive_press else 0.18
		var target := shoulder+Vector3(clampf(aim.x-shoulder.x,-lateral_limit,lateral_limit)-outward*0.06,0.62,depth)/scale_
		var spread := (reach.x if side=="l" else reach.y)*air_weight
		var opposite := (reach.y if side=="l" else reach.x)*air_weight
		var balance := opposite*(1.-spread)
		var spine: Vector3=author.point(pose,"spine_03")
		var side_sign := signf(shoulder.x-spine.x)
		var diagonal := Vector3(side_sign*.78,.25,.52)
		var counterweight := Vector3(side_sign*.48,-.47,.12)
		target=target.lerp(shoulder+counterweight/scale_,balance)
		target=target.lerp(shoulder+diagonal/scale_,spread)
		if is_finite(min_hand_x) or is_finite(max_hand_x):
			var world_target := rig.to_global(target)
			var forward := actor.global_basis.z.normalized()
			if court_aim.is_finite(): world_target.x+=clampf(court_aim.x-world_target.x,-1.,1.)*.09*press
			world_target+=forward*.18*press*(1.-below_tape)
			world_target.x=clampf(move_toward(world_target.x,world_ball.x,.12*press*(1.-maxf(spread,balance))),min_hand_x,max_hand_x)
			target=rig.to_local(world_target)
		var pole := Vector3(outward*0.38,-0.55,0.30)
		if overpass_swing and side == "r":
			var draw := smoothstep(0.11,0.30,age)*(1.0-smoothstep(0.30,0.47,age))
			var strike := smoothstep(0.30,0.51,age)
			var follow := smoothstep(0.53,0.74,age)
			var contact := aim+Vector3(0.0,-0.055,-0.07)/scale_
			target = (target+Vector3(-0.13,-0.23,-0.40)*draw/scale_).lerp(contact,strike)
			target = target.lerp(shoulder+Vector3(-0.16,-0.35,0.30)/scale_,follow)
			pole = pole.lerp(Vector3(-0.75,-0.27,-0.42),draw)
		elif overpass_swing:
			target = target.lerp(shoulder+Vector3(0.12,0.04,0.30)/scale_,smoothstep(0.30,0.56,age))
		var extension := 174.
		if court_aim.is_finite():
			# Probe with a bent elbow. Only a wrist clear of the tape can press straight.
			var bent := pose.duplicate()
			author.limb(bent,arm,"lowerarm_"+side,"hand_"+side,target,pole,weight,132.)
			var wrist_world := rig.to_global(author.point(bent,"hand_"+side))
			var across_net := preload("res://scripts/net_collision.gd").NET_Z-wrist_world.z
			var above_tape := wrist_world.y-preload("res://scripts/net_collision.gd").NET_TOP
			extension=lerpf(132.,174.,smoothstep(0.,.12,across_net)*smoothstep(0.,.14,above_tape))
		author.limb(pose,arm,"lowerarm_"+side,"hand_"+side,target,pole,weight,extension)
		for digit in ["thumb","index","middle","ring","pinky"]:
			for segment in ["01","02","03"]:
				var bone := rig.find_bone("%s_%s_%s" % [digit,segment,side])
				pose[bone].basis = pose[bone].basis.slerp(rig.get_bone_rest(bone).basis,weight)
		var hand_name: String = "hand_"+side
		var wrist: Transform3D = author.world_pose(pose,rig.find_bone(hand_name))
		var finger_direction: Vector3 = author.point(pose,"middle_01_"+side)-wrist.origin
		var across: Vector3 = author.point(pose,"index_01_"+side)-author.point(pose,"pinky_01_"+side)
		var palm_normal := Vector3(clampf(aim.x-wrist.origin.x,-0.18,0.18),-0.45,1.0).normalized()
		if court_aim.is_finite():
			var incoming := world_ball.direction_to(rig.to_global(wrist.origin))
			var outgoing := rig.to_global(wrist.origin).direction_to(court_aim)
			var normal := (outgoing-incoming).normalized()
			if normal.length_squared()>.5: palm_normal=(rig.global_basis.inverse()*normal).normalized()
		var up := Vector3.UP.slide(palm_normal).normalized()
		var edge := up.cross(palm_normal)*-outward
		var palm := HandPose.hand_basis(up,edge)*HandPose.hand_basis(finger_direction,across).inverse()*wrist.basis
		author.set_world_basis(pose,hand_name,wrist.basis.orthonormalized().slerp(palm.orthonormalized(),weight))
		var hand: Vector3 = author.point(pose,"hand_"+side)
		var tip: Vector3 = author.point(pose,"middle_03_"+side)
		shoulders.append(rig.to_global(shoulder))
		elbows.append(rig.to_global(author.point(pose,"lowerarm_"+side)))
		hands.append(rig.to_global(tip))
		wrists.append(rig.to_global(hand))
	if previous_hands.is_empty():
		previous_hands = hands.duplicate()
		previous_wrists = wrists.duplicate()
	for bone in rig.get_bone_count():
		rig.set_bone_pose_rotation(bone,pose[bone].basis.orthonormalized().get_rotation_quaternion())
	if age < START+AIR+0.02+landing_recovery: return true
	actor.position = base
	actor.animator.seek(0.0,true)
	return false
