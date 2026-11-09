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

func step(direction: Vector3, delta: float, step_rate: float) -> void:
	weight = move_toward(weight,1.0 if direction.length()>0.05 else 0.0,delta*7)
	if weight<0.001: return
	travel = travel.lerp(direction,1-exp(-delta*16))
	phase = fposmod(phase+delta*float(recipe.cadence)*step_rate,1.0)
	var rig: Skeleton3D = actor.skeleton
	var pose: Array = []
	for bone in rig.get_bone_count(): pose.append(Transform3D(Basis(rig.get_bone_pose_rotation(bone)),rig.get_bone_pose_position(bone)))
	var pelvis := rig.find_bone("pelvis")
	var parent := rig.get_bone_parent(pelvis)
	pose[pelvis].origin += author.world_pose(pose,parent).basis.inverse()*Vector3(0,(-float(recipe.crouch)+float(recipe.bob)*cos(phase*TAU*2))*weight,0)
	# Shift weight onto the supporting leg while keeping the ready stance.
	var weight_shift := 0.03*sin(phase*TAU)*weight
	pose[pelvis].origin += author.world_pose(pose,parent).basis.inverse()*Vector3(weight_shift,0,0)
	author.rotate_world(pose,"spine_01",Vector3.RIGHT,deg_to_rad(7.0)*travel.z*weight)
	for side in ["l","r"]:
		var offset := fposmod(phase+(0.5 if side=="r" else 0.0),1.0)
		# Half the cycle supports the body; the returning foot clears the floor.
		var stride := (0.5-offset*2) if offset<0.5 else (-0.5+smoothstep(0.5,1.0,offset))
		var lift := 0.0 if offset<0.5 else sin((offset-0.5)*TAU)*float(recipe.foot_lift)
		var ready_foot: Transform3D = author.feet[side]
		var target := ready_foot.origin+travel*stride*float(recipe.stride)*weight+Vector3.UP*lift*weight
		target.x -= ready_foot.origin.x*0.30*absf(travel.z)*weight
		var pole: Vector3 = author.point(author.baseline,"calf_"+side)-author.point(author.baseline,"thigh_"+side)
		author.limb(pose,"thigh_"+side,"calf_"+side,"foot_"+side,target,pole)
		# Roll through the swing and return to a flat shoe at contact.
		var swing := clampf((offset-0.5)*2.0,0.0,1.0)
		var pitch := deg_to_rad(12.0)*sin(swing*TAU)*travel.z*weight
		author.set_world_basis(pose,"foot_"+side,Basis(Vector3.RIGHT,pitch)*ready_foot.basis)
	for bone in rig.get_bone_count():
		rig.set_bone_pose_position(bone,pose[bone].origin)
		rig.set_bone_pose_rotation(bone,pose[bone].basis.get_rotation_quaternion())

