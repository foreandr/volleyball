extends RefCounted

const BALL_RADIUS := preload("res://scripts/gym_physics.gd").BALL_RADIUS
const PALM := 0
const FINGERTIP := 1
const WRIST := 2
const PAD_RADII := [.023,.012,.026]

# Samples live in the attack driver's court space, including on a mirrored rig.
static func sample(rig:Skeleton3D, court:Node3D) -> Dictionary:
	var wrist:=rig.get_bone_global_pose(rig.find_bone("hand_r")).origin
	var knuckle:=rig.get_bone_global_pose(rig.find_bone("middle_01_r")).origin
	var index:=rig.get_bone_global_pose(rig.find_bone("index_01_r")).origin
	var pinky:=rig.get_bone_global_pose(rig.find_bone("pinky_01_r")).origin
	var tip:=rig.get_bone_global_pose(rig.find_bone("middle_03_r")).origin
	var normal:=(knuckle-wrist).cross(pinky-index).normalized()
	var transform:=court.global_transform.affine_inverse()*rig.global_transform
	return {"points":[transform*(wrist.lerp(knuckle,.64)+normal*.014), transform*tip, transform*wrist],
		"normal":(transform.basis*normal).normalized(),
		"shoulder":transform*rig.get_bone_global_pose(rig.find_bone("upperarm_r")).origin}

static func crossing(a:Vector3,b:Vector3,radius:float) -> float:
	var travel:=b-a
	var c:=a.length_squared()-radius*radius
	if c<=0.: return 0.
	var length_sq:=travel.length_squared()
	var along:=a.dot(travel)
	if length_sq<.0000001 or along>=0.: return INF
	var disc:=along*along-length_sq*c
	if disc<0.: return INF
	var t:=(-along-sqrt(disc))/length_sq
	return t if t<=1. else INF

static func sweep(before:Dictionary,after:Dictionary,ball_before:Vector3,ball_after:Vector3,delta:float) -> Dictionary:
	var first:=INF
	var part:=-1
	for i in PAD_RADII.size():
		var t:=crossing(ball_before-Vector3(before.points[i]),ball_after-Vector3(after.points[i]),BALL_RADIUS+float(PAD_RADII[i]))
		if t<first:
			first=t
			part=i
	if part<0: return {}
	var a:Vector3=before.points[part]
	var b:Vector3=after.points[part]
	var ball:=ball_before.lerp(ball_after,first)
	var outward:=a.lerp(b,first).direction_to(ball)
	var normal:=Vector3(before.normal).lerp(after.normal,first).normalized()
	var shoulder:=Vector3(before.shoulder).lerp(after.shoulder,first)
	return {"reach":ball-shoulder,"fraction":first,"part":part,"outward":outward,"normal":normal,
		"hand_velocity":(b-a)/delta,"incoming":(ball_after-ball_before)/delta}

static func transfer(contact:Dictionary,aim:Vector3) -> float:
	if contact.part!=PALM: return 0.
	var normal:Vector3=contact.normal
	var velocity:Vector3=contact.hand_velocity
	var facing:=smoothstep(.12,.72,normal.dot(contact.outward))
	var direction:=smoothstep(.05,.65,normal.dot(aim.normalized()))
	var drive:=smoothstep(.35,3.8,velocity.dot(aim.normalized()))
	var in_front:=smoothstep(-.12,.10,Vector3(contact.reach).dot(aim.slide(Vector3.UP).normalized()))
	return facing*direction*drive*in_front

static func outgoing(contact:Dictionary,intended:Vector3) -> Vector3:
	var normal:Vector3=contact.outward
	var arriving:Vector3=contact.incoming
	var hand:Vector3=contact.hand_velocity
	var closing:=maxf(0.,(hand-arriving).dot(normal))
	var glance:=arriving+normal*closing*1.17
	var soft_cap:=minf(intended.length(),clampf(arriving.length()*.65+hand.length()*.35,2.5,9.))
	return glance.limit_length(soft_cap).lerp(intended,transfer(contact,intended))
