extends RefCounted

const Flight = preload("res://scripts/pass_flight.gd")

static func timing_error(lead: float, earliest: float, latest: float) -> float:
	var ideal := lerpf(earliest,latest,0.40)
	var window := ideal-earliest if lead < ideal else latest-ideal
	var miss := absf(lead-ideal)/maxf(window,0.025)
	return clampf(0.24*miss*miss,0.0,1.0)

static func spread(timing: float, speed: float, spin_rps: float, skill: float, setting: bool) -> Vector2:
	var gap := 1.0-clampf(skill/100.0,0.0,1.0)
	var pace := smoothstep(8.0,29.0,speed)
	var spin := smoothstep(0.4,9.0,absf(spin_rps))
	if setting:
		return gap*(Vector2(2.9,2.2)+Vector2(1.55,1.45)*timing+Vector2(0.65,0.55)*pace+Vector2(0.35,0.28)*spin)
	var difficulty := pace*0.72+spin*0.32
	return Vector2(0.11,0.09)+Vector2(1.4,1.15)*difficulty+Vector2(2.15,1.75)*gap+Vector2(1.65,1.55)*timing*(1.0+difficulty*0.52)

static func sample_offset(bounds: Vector2) -> Vector3:
	var horizontal := Vector2.from_angle(randf()*TAU)*bounds.x*sqrt(randf_range(0.0001,1.0))
	return Vector3(horizontal.x,bounds.y*(randf()-randf()),horizontal.y)

static func pass_velocity(touch: Vector3, target: Dictionary, angle: float, bounds: Vector2) -> Vector3:
	var ideal := Flight.target_velocity(touch,target,angle)
	if bounds.is_zero_approx(): return ideal
	var offset := sample_offset(bounds)
	var destination: Vector2 = target.position+Vector2(offset.x,offset.z)
	var peak := touch.y+ideal.y*ideal.y/(2.0*Flight.GRAVITY)
	var minimum := float(target.get("minimum_height",touch.y+0.05))
	return Flight.target_velocity(touch,{"position":destination,"fit":"height","height":maxf(minimum,peak+offset.y)},angle)
