extends RefCounted

const ORIGIN := Vector3(-1.2,0.,-.9)
const CELL := Vector3(.8,.65,.6)

static func region(point: Vector3) -> Vector3i:
	return Vector3i(((point-ORIGIN)/CELL).floor()).clamp(Vector3i.ZERO,Vector3i(2,2,2))

static func movement(c: Dictionary) -> bool:
	return c.kind not in ["dive","wide_dive","pancake","overhead"]

static func key(cell: Vector3i) -> String:
	return "%d_%d_%d" % [cell.x,cell.y,cell.z]

static func assignment(cell: Vector3i) -> int:
	var fallback := 2 if cell.x!=1 else 4
	if cell.y==0: fallback=5 if cell.z!=2 else 7
	return int(StorySession.game_options.get_value("dig_regions",key(cell),fallback))

static func legs(actor: Node3D, pose: Array, c: Dictionary, weight: float, flip := false) -> void:
	var rig: Skeleton3D=actor.skeleton
	var author=actor.get_pose_author()
	var side_offset: float=-c.side if flip else c.side
	var pelvis := rig.find_bone("pelvis")
	var parent: Transform3D=author.world_pose(pose,rig.get_bone_parent(pelvis))
	pose[pelvis].origin+=parent.basis.inverse()*Vector3(side_offset*.65,-c.drop,c.forward*.34)*weight
	for side in ["l","r"]:
		var foot: Transform3D=author.feet[side]
		var goal := foot.origin
		if side==("r" if side_offset<0 else "l"):
			goal+=Vector3(side_offset*.91,0,c.forward*.5)*weight
			goal.y+=.07*sin(PI*weight)+float(c.get("knee_lift",0.))*weight
		elif c.kind in ["knee","kneel","low","knee_slide","beach_drop","air_platform"]:
			goal.z-=.25*weight
		var pole := Vector3(.15 if side=="l" else -.15,0,1.)
		if c.get("stack_knee",false) and side==("r" if side_offset<0 else "l"):
			# Bias the knee toward the vertical line above the planted ankle.
			var hip: Vector3=author.point(pose,"thigh_"+side)
			var leg_axis := (goal-hip).normalized()
			var upright := Vector3.UP.slide(leg_axis)
			if upright.length_squared()>.001:
				pole=pole.normalized().lerp(upright.normalized(),.7*weight)
		author.limb(pose,"thigh_"+side,"calf_"+side,"foot_"+side,goal,pole,weight)
		author.set_world_basis(pose,"foot_"+side,foot.basis)
