extends RefCounted

const GYM := 16
const EQUIPMENT := 32
const BALL_RADIUS := .105
var capsule := CapsuleShape3D.new()
var camera_shape := SphereShape3D.new()
var ball_shape := SphereShape3D.new()

func _init() -> void:
	capsule.height = 1.72
	capsule.radius = .28
	camera_shape.radius = .14
	ball_shape.radius = BALL_RADIUS

static func solid(node: Node3D,shape: Shape3D,layer: int) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	node.add_child(body)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)

func sweep(world: Node3D,shape: Shape3D,start: Vector3,motion: Vector3,mask: int) -> Dictionary:
	if motion.length_squared()<.0000001: return {}
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = start
	query.collision_mask = mask
	query.motion = motion
	query.margin = .003
	var space := world.get_world_3d().direct_space_state
	var fractions := space.cast_motion(query)
	if fractions[0]>=1: return {}
	query.transform.origin = start+motion*fractions[1]
	query.motion = Vector3.ZERO
	var surface := space.get_rest_info(query)
	return {"fraction":fractions[0],"normal":surface.get("normal",-motion.normalized())}

func travel(world: Node3D,start: Vector3,motion: Vector3,height: float) -> Vector3:
	capsule.height = maxf(.65,height)
	var pos := start
	var remaining := motion
	for i in 3:
		var hit := sweep(world,capsule,pos+Vector3.UP*(capsule.height*.5+.025),remaining,GYM|EQUIPMENT|64)
		if hit.is_empty(): return pos+remaining
		pos += remaining*maxf(0,float(hit.fraction)-.001)
		remaining = (remaining*(1.-float(hit.fraction))).slide(hit.normal)
	return pos

static func joint(actor: Node3D,bone: String) -> Vector3:
	var rig: Skeleton3D = actor.skeleton
	return rig.to_global(rig.get_bone_global_pose(rig.find_bone(bone)).origin)

static func palm(actor: Node3D,side: String) -> Vector3:
	return joint(actor,"hand_"+side).lerp(joint(actor,"middle_01_"+side),.80)

static func track_hands(actor: Node3D,ball: Vector3) -> void:
	var rig: Skeleton3D = actor.skeleton
	var author: RefCounted = actor.get_pose_author()
	var pose: Array = []
	for i in rig.get_bone_count(): pose.append(rig.get_bone_pose(i))
	for side in ["l","r"]:
		var sign_ := 1. if side=="l" else -1.
		var wrist := "hand_"+str(side)
		var shoulder := "upperarm_"+str(side)
		var midpoint: Vector3 = author.point(pose,wrist).lerp(author.point(pose,"middle_01_"+side),.80)
		var wanted := rig.to_local(ball+actor.global_basis.x*sign_*.082+Vector3.DOWN*.060)
		var offset: Vector3 = (wanted-midpoint).limit_length(.45)
		author.limb(pose,shoulder,"lowerarm_"+str(side),wrist,author.point(pose,wrist)+offset,Vector3(sign_*.65,-.55,-.25))
		for name_ in [shoulder,"lowerarm_"+str(side)]:
			var idx := rig.find_bone(name_)
			rig.set_bone_pose_rotation(idx,pose[idx].basis.orthonormalized().get_rotation_quaternion())

static func touched(previous_ball: Vector3,ball: Vector3,previous_hand: Vector3,hand: Vector3) -> bool:
	var a := previous_ball-previous_hand
	var d := ball-hand-a
	var t := clampf(-a.dot(d)/maxf(d.length_squared(),.000001),0,1)
	return (a+d*t).length()<=BALL_RADIUS+.055
