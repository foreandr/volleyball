extends RefCounted
static var recipe: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/animation_recipes/directional_movement.json"))
var actor: Node3D
var author: RefCounted
var touched := PackedInt32Array()
var chain := PackedInt32Array()
var pose := []
var phase := 0.0
var weight := 0.0
var travel := Vector3.ZERO

var blocking_steps := false
var swinging := false
var squat_depth := 0.0

func block_step(velocity: Vector3, gap: float, net_yaw: float, ready: bool, held: bool, delta: float) -> void:
	blocking_steps=true
	var speed := velocity.slide(Vector3.UP).length()
	if absf(gap)>1.65 and absf(velocity.x)>1.2 and not held: swinging=true
	if absf(gap)<.38 or speed<.3 or held: swinging=false
	var angle := atan2(velocity.x,velocity.z) if swinging else net_yaw
	actor.rotation.y=rotate_toward(actor.rotation.y,angle,delta*9.)
	actor.set_meta("swing_block_load",move_toward(float(actor.get_meta("swing_block_load",0.)),1. if swinging else 0.,delta*(8. if swinging else 3.)))
	if swinging:
		actor.play_ground_gait(speed)
		weight=0.
		squat_depth=0.
		return
	if held and speed<=.10:
		weight=0.
		squat_depth=0.
		return
	if not held: actor.play_action("idle",.14)
	var depth := .23*(1.-smoothstep(.65,1.8,speed)) if ready and not held else 0.
	squat_depth=move_toward(squat_depth,depth,delta*.70)
	var local := actor.basis.orthonormalized().inverse()*velocity
	step((local/2.35).limit_length(1.),delta,clampf(speed/1.6,.65,1.85),true,true)

func _init(player: Node3D) -> void:
	actor = player
	author = actor.get_pose_author()
	var rig: Skeleton3D=actor.skeleton
	pose.resize(rig.get_bone_count())
	for name in ["pelvis","spine_01","spine_02","thigh_l","calf_l","foot_l","thigh_r","calf_r","foot_r"]:
		var bone := rig.find_bone(name)
		touched.append(bone)
		while bone>=0 and not chain.has(bone):
			chain.append(bone)
			bone=rig.get_bone_parent(bone)

func step(direction: Vector3, delta: float, step_rate: float, continuous := false, grounded_shuffle := false) -> void:
	weight = move_toward(weight,1.0 if direction.length()>0.05 or squat_depth>.001 else 0.0,delta*7)
	if weight<0.001: return
	travel = travel.lerp(direction,1-exp(-delta*16))
	phase = fposmod(phase+delta*float(recipe.cadence)*step_rate,1.0)
	var rig: Skeleton3D = actor.skeleton
	for bone in chain: pose[bone]=Transform3D(Basis(rig.get_bone_pose_rotation(bone)),rig.get_bone_pose_position(bone))
	var original := pose.duplicate() if grounded_shuffle else []
	var pelvis := rig.find_bone("pelvis")
	var parent := rig.get_bone_parent(pelvis)
	pose[pelvis].origin += author.world_pose(pose,parent).basis.inverse()*Vector3(0,(-squat_depth-float(recipe.crouch)+float(recipe.bob)*cos(phase*TAU*2))*weight,0)
	# Shift weight onto the supporting leg while keeping the ready stance.
	var weight_shift := 0.03*sin(phase*TAU)*weight
	if continuous:
		weight_shift += travel.x*0.035*weight
		author.rotate_world(pose,"spine_02",Vector3.BACK,-0.12*travel.x*weight)
	pose[pelvis].origin += author.world_pose(pose,parent).basis.inverse()*Vector3(weight_shift,0,0)
	author.rotate_world(pose,"spine_01",Vector3.RIGHT,deg_to_rad(7.0)*travel.z*weight)
	for side in ["l","r"]:
		var offset := fposmod(phase+(0.5 if side=="r" else 0.0),1.0)
		# Half the cycle supports the body; the returning foot clears the floor.
		var stride := (0.5-offset*2) if offset<0.5 else (-0.5+smoothstep(0.5,1.0,offset))
		var lift := 0.0 if offset<0.5 else sin((offset-0.5)*TAU)*float(recipe.foot_lift)
		if continuous and offset >= 0.5:
			# Match the planted foot's velocity at toe-off and landing.
			var swing_progress := 2.0*offset-1.0
			stride = -0.5-swing_progress+swing_progress*swing_progress*(6.0-4.0*swing_progress)
			lift = pow(sin(PI*swing_progress),2.0)*(.105 if blocking_steps else (.035 if grounded_shuffle else .075))
		var ready_foot: Transform3D = author.feet[side]
		var target := ready_foot.origin+travel*stride*float(recipe.stride)*weight+Vector3.UP*lift*weight
		if not continuous:
			target.x -= ready_foot.origin.x*0.30*absf(travel.z)*weight
		else:
			var stance_width: float = absf(author.feet["l"].origin.x-author.feet["r"].origin.x)
			var lateral_stride := minf(float(recipe.stride),stance_width*(.95 if blocking_steps else .45))
			target.x = ready_foot.origin.x+travel.x*stride*lateral_stride*weight
		var pole: Vector3 = author.point(author.baseline,"calf_"+side)-author.point(author.baseline,"thigh_"+side)
		if blocking_steps and grounded_shuffle:
			var across:Vector3=(author.feet["l"].origin-author.feet["r"].origin).slide(Vector3.UP).normalized()
			pole=Vector3.BACK.slide(across)+across*(.95 if side=="l" else -.95)
		elif continuous:
			pole = Vector3(0.12 if side == "l" else -0.12,0.16,1.0)
		author.limb(pose,"thigh_"+side,"calf_"+side,"foot_"+side,target,pole)
		# Roll through the swing and return to a flat shoe at contact.
		var swing := clampf((offset-0.5)*2.0,0.0,1.0)
		var pitch := deg_to_rad(12.0)*sin(swing*TAU)*travel.z*weight
		author.set_world_basis(pose,"foot_"+side,Basis(Vector3.RIGHT,pitch)*ready_foot.basis)
	for bone in touched:
		if grounded_shuffle:
			pose[bone]=original[bone].interpolate_with(pose[bone],smoothstep(0.,1.,weight))
		rig.set_bone_pose_position(bone,pose[bone].origin)
		rig.set_bone_pose_rotation(bone,pose[bone].basis.get_rotation_quaternion())

