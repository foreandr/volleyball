extends RefCounted
## Left-side receive styles. Angles are in degrees and stance offsets are in rig space.
## Name, lean, turn, shoulder tilt, hip shift, side step, stagger, drop, preparation time.
const LEFT_ARROW := 7
const STYLES := [
	["Quiet shoulder", 5, 11, 8, 0.03, 0.00, 0.00, 0.02, 0.26],
	["High shoulder", 6, 16, 19, 0.04, 0.00, 0.02, 0.02, 0.28],
	["Soft lean", 12, 16, 10, 0.06, 0.03, 0.00, 0.04, 0.32],
	["Late tilt", 12, 20, 19, 0.06, 0.02, 0.02, 0.04, 0.18],
	["Turn and hold", 8, 29, 13, 0.08, 0.04, 0.02, 0.04, 0.34],
	["Left foot forward", 10, 20, 12, 0.09, 0.09, 0.15, 0.05, 0.34],
	["Left foot back", 11, 20, 15, 0.08, 0.08, -0.14, 0.05, 0.34],
	["Quick stagger", 13, 23, 13, 0.11, 0.14, 0.10, 0.07, 0.23],
	["Wide stagger", 13, 22, 16, 0.13, 0.24, 0.13, 0.08, 0.40],
	["Low stagger", 15, 23, 15, 0.15, 0.17, 0.14, 0.14, 0.38],
	["Side step and set", 12, 23, 11, 0.15, 0.23, 0.02, 0.09, 0.41],
	["Side step and tilt", 18, 25, 19, 0.16, 0.24, 0.04, 0.10, 0.36],
	["Quick side reach", 18, 29, 17, 0.13, 0.16, -0.04, 0.09, 0.21],
	["Long side reach", 19, 32, 17, 0.18, 0.27, 0.04, 0.12, 0.39],
	["Low side reach", 22, 25, 16, 0.19, 0.27, 0.05, 0.18, 0.39],
	["Deep side lunge", 23, 28, 22, 0.23, 0.34, 0.08, 0.16, 0.43],
	["Deep drop step", 20, 27, 19, 0.21, 0.31, -0.14, 0.16, 0.43],
	["Shoulder scoop", 16, 34, 25, 0.13, 0.13, -0.06, 0.14, 0.29],
	["Extended platform", 17, 38, 13, 0.18, 0.19, 0.11, 0.09, 0.36],
	["Emergency reach", 25, 27, 20, 0.26, 0.35, -0.08, 0.17, 0.29],
]

static func bake(actor: Node3D, base: Animation, index: int) -> Animation:
	var sampler = preload("res://scripts/pass_trajectory_solver.gd").new(actor,base)
	var bones: Array[String] = ["pelvis","spine_02","spine_03","neck_01"]
	for side in ["l","r"]:
		for part in ["thigh","calf","foot","upperarm","lowerarm","hand"]:
			bones.append(part+"_"+side)
	var style: Array = STYLES[index-1]
	var clip: Animation = sampler.author.bake_overrides(base,func(time): return pose_at(sampler,time,style),bones)
	clip.resource_name = style[0]
	clip.set_meta("receive_arrow",LEFT_ARROW)
	return clip

static func pose_at(sampler: RefCounted, time: float, style: Array) -> Array:
	var pose: Array = sampler.raw_pose(time)
	var author: RefCounted = sampler.author
	var rig: Skeleton3D = author.rig
	var contact: float = sampler.contact_time
	var prepare := smoothstep(contact-float(style[8]),contact-0.05,time)
	var recover := 1.0-smoothstep(contact+0.10,minf(sampler.source.length,contact+0.58),time)
	var weight := prepare*recover
	if weight <= 0.0001: return pose

	var left_foot: Transform3D = author.world_pose(pose,rig.find_bone("foot_l"))
	var right_foot: Transform3D = author.world_pose(pose,rig.find_bone("foot_r"))
	var left_pole: Vector3 = author.point(pose,"calf_l")-author.point(pose,"thigh_l")
	var right_pole: Vector3 = author.point(pose,"calf_r")-author.point(pose,"thigh_r")
	var pelvis := rig.find_bone("pelvis")
	var parent := rig.get_bone_parent(pelvis)
	var hip_shift := Vector3(float(style[4]),-float(style[7]),0.0)*weight
	pose[pelvis].origin += author.world_pose(pose,parent).basis.inverse()*hip_shift
	var side_step: float = style[5]
	var stagger: float = style[6]
	var step_lift := 0.065*minf(1.0,(absf(side_step)+absf(stagger))/0.25)
	var foot_travel := Vector3(side_step*weight,step_lift*(sin(PI*prepare)+sin(PI*recover)),stagger*weight)
	for side in ["l","r"]:
		var foot := left_foot if side == "l" else right_foot
		var target := foot.origin+foot_travel if side == "l" else foot.origin
		var pole := left_pole if side == "l" else right_pole
		author.limb(pose,"thigh_"+side,"calf_"+side,"foot_"+side,target,pole)
		author.set_world_basis(pose,"foot_"+side,foot.basis)

	var lean := deg_to_rad(float(style[1]))*weight
	var turn := deg_to_rad(float(style[2]))*weight
	var tilt := deg_to_rad(float(style[3]))*weight
	author.rotate_world(pose,"spine_02",Vector3.BACK,-lean)
	author.rotate_world(pose,"spine_03",Vector3.UP,turn*0.6)
	author.rotate_world(pose,"spine_03",Vector3.BACK,-tilt*0.5)
	author.rotate_world(pose,"neck_01",Vector3.BACK,(lean+tilt*0.5)*0.62)
	author.rotate_world(pose,"neck_01",Vector3.UP,-turn*0.33)

	# Both hands travel around the same pivot to keep the forearm platform together.
	var shoulder_center: Vector3 = (author.point(pose,"upperarm_l")+author.point(pose,"upperarm_r"))*0.5
	var swing := Basis(Vector3.UP,turn*0.40)*Basis(Vector3.RIGHT,-tilt*0.22)
	var hand_center: Vector3 = (author.point(pose,"hand_l")+author.point(pose,"hand_r"))*0.5
	var extension := swing*(hand_center-shoulder_center).normalized()*0.025*weight
	for side in ["l","r"]:
		var hand: Transform3D = author.world_pose(pose,rig.find_bone("hand_"+side))
		var pole: Vector3 = author.point(pose,"lowerarm_"+side)-author.point(pose,"upperarm_"+side)
		var target := shoulder_center+swing*(hand.origin-shoulder_center)+extension
		author.limb(pose,"upperarm_"+side,"lowerarm_"+side,"hand_"+side,target,swing*pole)
		author.set_world_basis(pose,"hand_"+side,swing*hand.basis)
	return pose
