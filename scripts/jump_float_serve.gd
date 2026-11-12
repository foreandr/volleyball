extends "res://scripts/standing_float_serve.gd"

const TOSS := 0.25
const TAKEOFF := 0.77
const STRIKE := 1.11
const LAND := 1.49

var float_jump_height := 0.88

func set_jump_height(value: float) -> void:
	float_jump_height = value
	if elapsed < 0.0 and not running: reset()

func contact_time() -> float:
	return STRIKE

func toss_release_time() -> float:
	return TOSS

func takeoff_time() -> float:
	return TAKEOFF

func front_start_limit() -> float:
	return -7.12

func recovery_end() -> float:
	return 1.57

func can_run_after_contact() -> bool:
	return is_finite(contact_clock) and swing_time >= LAND

func float_body_scale() -> float:
	return 1.0

func float_step_pose(time: float) -> Array:
	return float_approach(time,TAKEOFF,LAND,float_jump_height,1.12)

func toss_curve_height() -> float:
	return 0.94

func toss_palm(pose: Array, _rig: Skeleton3D, author: RefCounted, _time: float) -> Vector3:
	return (author.point(pose,"middle_01_l")+author.point(pose,"middle_01_r"))*0.5

func prepare_toss_hands(pose: Array, rig: Skeleton3D, author: RefCounted, time: float) -> void:
	var toss := toss_release_time()
	var takeoff := takeoff_time()
	var weight := 1.0-smoothstep(toss,toss+0.21,time)
	if weight > 0.0: position_toss_hands(pose,rig,author,time,weight)
	var drive_weight := smoothstep(toss+0.07,lerpf(toss,takeoff,0.42),time)*(1.0-smoothstep(takeoff+0.015,takeoff+0.19,time))
	if drive_weight <= 0.0: return
	var scale_: float = rig.global_basis.y.length()
	var lift := smoothstep(takeoff-0.18,takeoff+0.055,time)
	for side in ["l","r"]:
		var outward := 1.0 if side == "l" else -1.0
		var shoulder: Vector3 = author.point(pose,"upperarm_"+side)
		var back := Vector3(0.10*outward,-0.39,-0.44)
		var up := Vector3(0.07*outward,0.43,0.33)
		var arm_path := back.lerp(up,lift)+Vector3.RIGHT*outward*0.22*sin(PI*lift)
		var hand := shoulder+arm_path/scale_
		author.limb(pose,"upperarm_"+side,"lowerarm_"+side,"hand_"+side,hand,Vector3(outward,-0.30,0.28),drive_weight)

func shape_float_strike(pose: Array, rig: Skeleton3D, author: RefCounted, time: float) -> void:
	var weight := smoothstep(TAKEOFF+0.07,TAKEOFF+0.20,time)*(1.0-smoothstep(STRIKE+0.23,LAND+0.06,time))
	if weight <= 0.0: return
	var extension := smoothstep(STRIKE-0.16,STRIKE,time)
	var follow := 0.64*smoothstep(STRIKE,STRIKE+0.26,time)
	var scale_: float = rig.global_basis.y.length()
	var shoulder: Vector3 = author.point(pose,"upperarm_r")
	var contact := shoulder+Vector3(-0.04,0.61,0.36+SERVE_CONTACT_LEAD)/scale_
	var shot_direction := Vector3.BACK
	SpikeArm.apply(pose,author,contact,weight,extension,follow,1.0,0.80,0.8,0.09,0.0,0.0,shot_direction,0.86,0.14/scale_,true)
	var guide_drop := smoothstep(STRIKE-0.12,STRIKE+0.12,time)
	SpikeArm.apply_guide_arm(pose,author,Vector3(0.08,0.39,0.38)/scale_,Vector3(0.35,-0.55,0.18),guide_drop,weight*0.68,163.0)
	var straighten := smoothstep(STRIKE-0.05,STRIKE+0.21,time)*(1.0-smoothstep(STRIKE+0.24,LAND,time))
	author.rotate_world(pose,"spine_02",Vector3.RIGHT,-0.17*straighten)

func position_toss_hands(pose: Array, rig: Skeleton3D, author: RefCounted, time: float, weight: float) -> void:
	var lift := smoothstep(0.08,toss_release_time(),time)
	var scale_: float = rig.global_basis.y.length()
	var chest: Vector3 = author.point(pose,"spine_03")
	var center := chest+Vector3(0.0,-0.24+0.60*lift,0.47)/scale_
	for side in ["l","r"]:
		var outward := 1.0 if side == "l" else -1.0
		var wrist := center+Vector3(0.11*outward,-0.07,-0.065)/scale_
		author.limb(pose,"upperarm_"+side,"lowerarm_"+side,"hand_"+side,wrist,Vector3(outward,-0.65,0.18),weight)
		orient_palm(pose,rig,author,side,Vector3.BACK,Vector3.LEFT*outward,0.42*weight)
