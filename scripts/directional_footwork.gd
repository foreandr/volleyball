extends RefCounted
static var recipe: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/animation_recipes/directional_movement.json"))
var actor: Node3D
var author: RefCounted
var phase := 0.0
var weight := 0.0
var travel := Vector3.ZERO

func _init(player: Node3D) -> void:
	actor = player
	author = preload("res://tools/animation_author.gd").new(actor.skeleton,load("res://assets/animations/goalkeeper_idle.tres"))

func step(direction: Vector3, delta: float) -> void:
	weight = move_toward(weight,1.0 if direction.length()>0.05 else 0.0,delta*7)
	if weight<0.001: return
	travel = travel.lerp(direction,1-exp(-delta*16))
	phase = fposmod(phase+delta*float(recipe.cadence),1.0)
	var rig: Skeleton3D = actor.skeleton
	var pose: Array = []
	for bone in rig.get_bone_count(): pose.append(Transform3D(Basis(rig.get_bone_pose_rotation(bone)),rig.get_bone_pose_position(bone)))
	var pelvis := rig.find_bone("pelvis")
	var parent := rig.get_bone_parent(pelvis)
	pose[pelvis].origin += author.world_pose(pose,parent).basis.inverse()*Vector3(0,(-float(recipe.crouch)+float(recipe.bob)*cos(phase*TAU*2))*weight,0)
	for side in ["l","r"]:
		var offset := fposmod(phase+(0.5 if side=="r" else 0.0),1.0)
		# Half the cycle supports the body; the returning foot clears the floor.
		var stride := (0.5-offset*2) if offset<0.5 else (-0.5+smoothstep(0.5,1.0,offset))
		var lift := 0.0 if offset<0.5 else sin((offset-0.5)*TAU)*float(recipe.foot_lift)
		var target: Vector3 = author.feet[side].origin+travel*stride*float(recipe.stride)*weight+Vector3.UP*lift*weight
		var pole: Vector3 = author.point(author.baseline,"calf_"+side)-author.point(author.baseline,"thigh_"+side)
		author.limb(pose,"thigh_"+side,"calf_"+side,"foot_"+side,target,pole)
		author.set_world_basis(pose,"foot_"+side,author.feet[side].basis)
	for bone in rig.get_bone_count():
		rig.set_bone_pose_position(bone,pose[bone].origin)
		rig.set_bone_pose_rotation(bone,pose[bone].basis.get_rotation_quaternion())

