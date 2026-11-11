extends "res://scripts/jump_float_serve.gd"

const TOSS_STEP := 0.36
const SPIN_TAKEOFF := 1.02
const SPIN_CONTACT := 1.43
const SPIN_LAND := 1.87

var sidespin := 0.0
var released_sidespin := 0.0

func configure(actor: Node3D, start := START, yaw := 0.0) -> void:
	super.configure(actor,start,yaw)
	apex = 3.70
	update_path_preview()

func contact_time() -> float:
	return SPIN_CONTACT

func toss_release_time() -> float:
	return TOSS_STEP

func takeoff_time() -> float:
	return SPIN_TAKEOFF

func front_start_limit() -> float:
	return -7.70

func recovery_end() -> float:
	return 1.98

func can_run_after_contact() -> bool:
	return is_finite(contact_clock) and swing_time >= SPIN_LAND

func float_body_scale() -> float:
	return 1.38

func float_step_pose(time: float) -> Array:
	return float_approach(time,SPIN_TAKEOFF,SPIN_LAND,1.12,1.17,TOSS_STEP)

func toss_curve_height() -> float:
	return 1.47

func shape_float_strike(pose: Array, rig: Skeleton3D, author: RefCounted, time: float) -> void:
	var weight := smoothstep(SPIN_TAKEOFF+0.06,SPIN_TAKEOFF+0.23,time)*(1.0-smoothstep(SPIN_CONTACT+0.25,SPIN_LAND+0.09,time))
	if weight <= 0.0: return
	var extension := smoothstep(SPIN_CONTACT-0.17,SPIN_CONTACT,time)
	var follow := smoothstep(SPIN_CONTACT,SPIN_CONTACT+0.29,time)
	var scale_: float = rig.global_basis.get_scale().y
	var shoulder: Vector3 = author.point(pose,"upperarm_r")
	var contact := shoulder+Vector3(-0.04,0.64,0.41)/scale_
	var shot_direction := Vector3(0.20*sidespin,0.0,1.0).normalized()
	SpikeArm.apply(pose,author,contact,weight,extension,follow,1.0,0.72,0.84,0.12,0.0,0.0,shot_direction,0.0,0.22/scale_,true)
	var guide_drop := smoothstep(SPIN_CONTACT-0.18,SPIN_CONTACT+0.14,time)
	SpikeArm.apply_guide_arm(pose,author,Vector3(0.08,0.45,0.48)/scale_,Vector3(0.35,-0.55,0.18),guide_drop,weight,166.0)
	var crunch := smoothstep(SPIN_CONTACT-0.10,SPIN_CONTACT+0.14,time)*(1.0-smoothstep(SPIN_CONTACT+0.19,SPIN_LAND,time))
	author.rotate_world(pose,"spine_02",Vector3.RIGHT,0.34*crunch)

func finish_float_wrist(pose: Array, _rig: Skeleton3D, author: RefCounted, time: float) -> void:
	var snap := smoothstep(SPIN_CONTACT-0.07,SPIN_CONTACT+0.12,time)*(1.0-smoothstep(SPIN_CONTACT+0.21,SPIN_LAND,time))
	SpikeArm.align_wrist_to_forearm(pose,author,0.82*smoothstep(TOSS_STEP,TOSS_STEP+0.22,time))
	author.rotate_world(pose,"hand_r",Vector3.RIGHT,deg_to_rad(24.0)*snap)

func set_sidespin(value: float) -> void:
	sidespin = value
	update_path_preview()

func preview_lane_count() -> int:
	return 1

func preview_lane_offset(_lane: int, progress: float, launch: Vector3) -> Vector3:
	return spin_offset(progress,launch,sidespin)

func begin_serve_curve() -> void:
	released_sidespin = sidespin

func advance_serve_curve(_time: float) -> void:
	pass

func serve_curve_offset(time: float, duration: float) -> Vector3:
	return spin_offset(clampf(time/maxf(duration,0.001),0.0,1.0),velocity,released_sidespin)

func spin_offset(progress: float, launch: Vector3, curve: float) -> Vector3:
	var side := Vector3.UP.cross(launch.slide(Vector3.UP).normalized())
	var envelope := 4.0*progress*(1.0-progress)
	return -side*curve*1.15*envelope+Vector3.UP*0.44*envelope*progress

func spin_serve_ball(delta: float) -> void:
	var axis := Vector3.UP.cross(velocity.slide(Vector3.UP).normalized())+Vector3.UP*released_sidespin
	ball.rotate(axis.normalized(),TAU*8.0*delta)
