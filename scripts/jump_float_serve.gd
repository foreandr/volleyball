extends "res://scripts/standing_float_serve.gd"

const TOSS := 0.29
const TAKEOFF := 0.64
const STRIKE := 0.93
const LAND := 1.29

func contact_time() -> float:
	return STRIKE

func toss_release_time() -> float:
	return TOSS

func front_start_limit() -> float:
	return -6.85

func recovery_end() -> float:
	return 1.40

func can_run_after_contact() -> bool:
	return is_finite(contact_clock) and swing_time >= LAND

func float_body_scale() -> float:
	return 1.0

func float_step_pose(time: float) -> Array:
	return float_approach(time,TAKEOFF,LAND,0.69,1.0)

func toss_curve_height() -> float:
	return 0.49

func toss_palm(pose: Array, _rig: Skeleton3D, author: RefCounted, _time: float) -> Vector3:
	return (author.point(pose,"middle_01_l")+author.point(pose,"middle_01_r"))*0.5

func prepare_toss_hands(pose: Array, rig: Skeleton3D, author: RefCounted, time: float) -> void:
	var weight := 1.0-smoothstep(TOSS,TOSS+0.18,time)
	if weight > 0.0: position_toss_hands(pose,rig,author,time,weight)

func position_toss_hands(pose: Array, rig: Skeleton3D, author: RefCounted, time: float, weight: float) -> void:
	var lift := smoothstep(0.08,TOSS,time)
	var scale_: float = rig.global_basis.get_scale().y
	var chest: Vector3 = author.point(pose,"spine_03")
	var center := chest+Vector3(0.0,-0.24+0.52*lift,0.47)/scale_
	for side in ["l","r"]:
		var outward := 1.0 if side == "l" else -1.0
		var wrist := center+Vector3(0.11*outward,-0.07,-0.065)/scale_
		author.limb(pose,"upperarm_"+side,"lowerarm_"+side,"hand_"+side,wrist,Vector3(outward,-0.65,0.18),weight)
		orient_palm(pose,rig,author,side,Vector3.BACK,Vector3.LEFT*outward,weight)
