extends RefCounted

const HandPose = preload("res://scripts/hand_setting_pose.gd")
const START := 0.13
const AIR := 0.74
const HEIGHT := 1.16
var actor: Node3D
var age := 0.0
var tempo := 1.0
var jump_height := HEIGHT
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
	actor.position = base+Vector3.UP*(lift-0.12*sin(PI*clampf(age/START,0.0,1.0)))
	actor.animator.seek(0.0,true)
	var rig: Skeleton3D = actor.skeleton
	var author: RefCounted = actor.get_pose_author()
	var pose: Array = []
	for bone in rig.get_bone_count(): pose.append(rig.get_bone_pose(bone))
	var weight := smoothstep(0.04,0.30,age)*(1.0-smoothstep(0.71,0.97,age))
	var aim := rig.to_local(world_ball)
	var scale_: float = rig.global_basis.get_scale().y
	previous_hands = hands.duplicate()
	previous_wrists = wrists.duplicate()
	hands.clear()
	wrists.clear()
	for side in ["l","r"]:
		var arm: String = "upperarm_"+side
		var shoulder: Vector3 = author.point(pose,arm)
		var outward := 1.0 if side == "l" else -1.0
		var press := smoothstep(0.45,0.95,lift)
		var below_tape := 1.0-smoothstep(2.50,2.80,rig.to_global(shoulder).y+0.62)
		var depth := lerpf(lerpf(0.20,0.55,press),0.17,below_tape)
		var target := shoulder+Vector3(clampf(aim.x-shoulder.x,-0.18,0.18)-outward*0.06,0.62,depth)/scale_
		author.limb(pose,arm,"lowerarm_"+side,"hand_"+side,target,Vector3(outward*0.38,-0.55,0.30),weight,174.0)
		for digit in ["thumb","index","middle","ring","pinky"]:
			for segment in ["01","02","03"]:
				var bone := rig.find_bone("%s_%s_%s" % [digit,segment,side])
				pose[bone].basis = pose[bone].basis.slerp(rig.get_bone_rest(bone).basis,weight)
		var hand_name: String = "hand_"+side
		var wrist: Transform3D = author.world_pose(pose,rig.find_bone(hand_name))
		var finger_direction: Vector3 = author.point(pose,"middle_01_"+side)-wrist.origin
		var across: Vector3 = author.point(pose,"index_01_"+side)-author.point(pose,"pinky_01_"+side)
		var palm_normal := Vector3(clampf(aim.x-wrist.origin.x,-0.18,0.18),-0.45,1.0).normalized()
		var up := Vector3.UP.slide(palm_normal).normalized()
		var edge := up.cross(palm_normal)*-outward
		var palm := HandPose.hand_basis(up,edge)*HandPose.hand_basis(finger_direction,across).inverse()*wrist.basis
		author.set_world_basis(pose,hand_name,wrist.basis.orthonormalized().slerp(palm.orthonormalized(),weight))
		var hand: Vector3 = author.point(pose,"hand_"+side)
		var tip: Vector3 = author.point(pose,"middle_03_"+side)
		hands.append(rig.to_global(tip))
		wrists.append(rig.to_global(hand))
	if previous_hands.is_empty():
		previous_hands = hands.duplicate()
		previous_wrists = wrists.duplicate()
	for bone in rig.get_bone_count():
		rig.set_bone_pose_rotation(bone,pose[bone].basis.orthonormalized().get_rotation_quaternion())
	if age < 1.02: return true
	actor.position = base
	actor.animator.seek(0.0,true)
	return false
