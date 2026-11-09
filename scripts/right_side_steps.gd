extends RefCounted
const SIZES := ["short","medium","long"]
const SHUFFLE_YAW := deg_to_rad(26.0)
var actor: Node3D
var author: RefCounted
var clips: Array[Animation] = []
var tracks: Array = []
var active := false
var sampled := false
var phase := 0.0
var hold := 0.0
var strength := 0.0
var previous_root := 0.0
var side_sign := 1.0
var travel_direction := Vector2.RIGHT
var last_pose: Array = []
var last_weight := 0.0
const PLAYBACK_RATE := 2.0

func _init(player: Node3D) -> void:
	actor = player
	author = preload("res://tools/animation_author.gd").new(actor.skeleton,load("res://assets/animations/goalkeeper_idle.tres"))
	for size_ in SIZES:
		var clip: Animation = load("res://assets/animations/side_right_"+size_+".res")
		clips.append(clip)
		var indices := []
		for bone in actor.skeleton.get_bone_count():
			var path := NodePath("Armature/Skeleton3D:"+actor.skeleton.get_bone_name(bone))
			indices.append([clip.find_track(path,Animation.TYPE_POSITION_3D),clip.find_track(path,Animation.TYPE_ROTATION_3D)])
		tracks.append(indices)

func advance(direction: Vector2, delta: float) -> float:
	sampled = false
	var requested := absf(direction.x)>0.3
	if requested and signf(direction.x)!=side_sign:
		active = false
		hold = 0
		side_sign = signf(direction.x)
	if requested: travel_direction = direction.normalized()
	if not active:
		if not requested:
			hold = 0
			return 0
		active = true
		phase = 0
		strength = smoothstep(0.04,0.28,hold)*2
		previous_root = 0
	if requested:
		hold += delta
		strength = smoothstep(0.04,0.28,hold)*2
	var a := mini(1,int(strength))
	var b := a+1
	var blend := strength-a
	var duration := lerpf(clips[a].length,clips[b].length,blend)
	phase = minf(1,phase+delta*PLAYBACK_RATE/duration)
	var root := lerpf(root_at(a),root_at(b),blend)
	var displacement := root-previous_root
	previous_root = root
	active = phase<1
	sampled = true
	return displacement

func root_at(index: int) -> float:
	var curve: PackedFloat32Array = clips[index].get_meta("root_right")
	var point := phase*(curve.size()-1)
	var frame := mini(curve.size()-2,int(point))
	return lerpf(curve[frame],curve[frame+1],point-frame)

func apply_pose(amount := 1.0) -> void:
	if not sampled:
		if not last_pose.is_empty(): install(last_pose,last_weight*amount)
		return
	var a := mini(1,int(strength))
	var b := a+1
	var blend := strength-a
	var weight := smoothstep(0,0.10,phase)*(1-smoothstep(0.90,1,phase))
	var rig: Skeleton3D = actor.skeleton
	var pose: Array = []
	for bone in rig.get_bone_count():
		var pa: int = tracks[a][bone][0]
		var pb: int = tracks[b][bone][0]
		var qa: int = tracks[a][bone][1]
		var qb: int = tracks[b][bone][1]
		var position := clips[a].position_track_interpolate(pa,phase*clips[a].length).lerp(clips[b].position_track_interpolate(pb,phase*clips[b].length),blend)
		var rotation := clips[a].rotation_track_interpolate(qa,phase*clips[a].length).slerp(clips[b].rotation_track_interpolate(qb,phase*clips[b].length),blend)
		pose.append(Transform3D(Basis(rotation),position))
	if side_sign<0: pose = mirrored(pose)
	# Turn the captured foot paths into diagonal paths.
	var from := Vector3(-side_sign,0,0)
	var to := Vector3(-travel_direction.x,0,travel_direction.y).normalized()
	# A full forward diagonal turn spreads the feet too far for the low stance.
	var path_turn := Quaternion(from,to)
	if travel_direction.y > 0.0:
		path_turn = Quaternion.IDENTITY.slerp(path_turn,0.6)
	var turn := Basis(path_turn)
	var feet := {}
	for side in ["l","r"]:
		feet[side] = author.world_pose(pose,rig.find_bone("foot_"+side))
	var pelvis_z: float = author.point(pose,"pelvis").z
	var yaw := SHUFFLE_YAW*side_sign
	# Let the spine and shoulders inherit the pelvis turn.
	author.rotate_world(pose,"pelvis",Vector3.UP,yaw)
	for side in ["l","r"]:
		var foot_name: String = "foot_"+side
		var foot: Transform3D = feet[side]
		var ready_foot: Transform3D = author.feet[side]
		var target := ready_foot.origin+turn*(foot.origin-ready_foot.origin)
		var is_lead: bool = (side == "l") == (side_sign < 0)
		var knee_pole := Vector3.BACK if is_lead else Vector3(side_sign,0.0,0.65)
		# Stagger the stance around the lead foot while keeping the captured lift.
		var stagger := 0.39 if is_lead else -0.09
		target.z = lerpf(pelvis_z+stagger,target.z,0.15)
		author.limb(pose,"thigh_"+side,"calf_"+side,foot_name,target,knee_pole)
		author.set_world_basis(pose,foot_name,foot.basis)
		# Align shoe heading without changing the captured ankle pitch or toe flex.
		var toe_direction: Vector3 = author.point(pose,"ball_"+side)-author.point(pose,foot_name)
		toe_direction.y = 0.0
		var toe_out := deg_to_rad(8.0 if side == "l" else -8.0)
		var heading := Vector3.BACK.rotated(Vector3.UP,yaw+toe_out)
		author.rotate_world(pose,foot_name,Vector3.UP,toe_direction.signed_angle_to(heading,Vector3.UP))
	last_pose = pose
	last_weight = weight
	install(pose,weight*amount)

func mirrored(input: Array) -> Array:
	var result: Array = author.baseline.duplicate()
	var rig: Skeleton3D = actor.skeleton
	var reflection := Basis.from_scale(Vector3(-1,1,1))
	for bone in rig.get_bone_count():
		var name_ := str(rig.get_bone_name(bone))
		if not (name_=="pelvis" or name_.begins_with("thigh_") or name_.begins_with("calf_") or name_.begins_with("foot_") or name_.begins_with("ball_")): continue
		var other := name_.trim_suffix("_l")+"_r" if name_.ends_with("_l") else (name_.trim_suffix("_r")+"_l" if name_.ends_with("_r") else name_)
		var source_bone := rig.find_bone(other)
		var world: Transform3D = author.world_pose(input,source_bone)
		var rotation: Basis = reflection*world.basis*rig.get_bone_global_rest(source_bone).basis.inverse()*reflection*rig.get_bone_global_rest(bone).basis
		author.set_world_basis(result,name_,rotation)
		if name_=="pelvis":
			var parent := rig.get_bone_parent(bone)
			var location: Vector3 = reflection*world.origin
			result[bone].origin = author.world_pose(result,parent).affine_inverse()*location
	author.set_world_basis(result,"spine_01",author.world_pose(author.baseline,rig.find_bone("spine_01")).basis)
	return result

func install(pose: Array, weight: float) -> void:
	var rig: Skeleton3D = actor.skeleton
	for bone in rig.get_bone_count():
		rig.set_bone_pose_position(bone,rig.get_bone_pose_position(bone).lerp(pose[bone].origin,weight))
		rig.set_bone_pose_rotation(bone,rig.get_bone_pose_rotation(bone).slerp(pose[bone].basis.get_rotation_quaternion(),weight))
