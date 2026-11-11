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

func prepare_serve_pose(time: float, _plant: float, _distance: float, _sink: float, _step_begin := 0.14, _step_end := 0.50, _carry := 0.55, _rear_step := 0.0) -> Array:
	var left_lead := smoothstep(0.06,0.24,time)
	var right_step := smoothstep(0.26,0.46,time)
	var left_plant := smoothstep(0.46,0.61,time)
	var flight := clampf((time-TAKEOFF)/(LAND-TAKEOFF),0.0,1.0)
	var load := smoothstep(0.42,0.57,time)*(1.0-smoothstep(0.57,TAKEOFF,time))
	var lift := 4.0*0.69*flight*(1.0-flight)
	var drift := 0.58*flight
	var ground_travel := 0.30*left_lead+0.41*right_step+0.43*left_plant
	player.position = serve_start+forward*(ground_travel+drift)+Vector3.UP*(lift-0.14*load)
	player.animator.seek(0.0,true)
	var rig: Skeleton3D = player.skeleton
	var author: RefCounted = player.get_pose_author()
	var bones: Array = []
	for bone in rig.get_bone_count(): bones.append(rig.get_bone_pose(bone))
	for side in ["l","r"]:
		var left: bool = side == "l"
		var foot: Vector3 = foot_starts[side]
		var advance := 0.49*left_lead+0.93*left_plant if left else 1.12*right_step
		var step_height := 0.13*(sin(PI*left_lead)+sin(PI*left_plant)) if left else 0.15*sin(PI*right_step)
		foot += forward*(advance+drift)+Vector3.UP*(lift+step_height+0.10*sin(PI*flight))
		author.limb(bones,"thigh_"+side,"calf_"+side,"foot_"+side,rig.to_local(foot),Vector3(0.12 if left else -0.12,0.2,1.0))
	return bones

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
