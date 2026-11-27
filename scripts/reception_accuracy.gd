extends RefCounted

const Flight = preload("res://scripts/pass_flight.gd")
const IDEAL_APEX := 6.5 # Two antenna-tip heights above the court.

static func green_seconds(skill:float) -> float:
	return lerpf(.025,.090,clampf(skill/100.,0.,1.))

const SET_WIDTH_FRACTION := 0.20
const SET_TIGHT_FRACTION := 0.16

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
		return gap*(Vector2(2.8,3.15)+Vector2(0.65,0.9)*timing+Vector2(0.40,0.60)*pace+Vector2(0.20,0.30)*spin)
	var difficulty := pace*0.72+spin*0.32
	var outside:=maxf(0.,timing-green_seconds(skill)/.21)
	return Vector2(2.8,1.95)*minf(1.5,outside)*(1.+difficulty*.52)

static func sample_offset(bounds: Vector2) -> Vector3:
	var horizontal := Vector2.from_angle(randf()*TAU)*bounds.x*sqrt(randf_range(0.0001,1.0))
	return Vector3(horizontal.x,bounds.y*(randf()-randf()),horizontal.y)

static func sample_set_offset(bounds: Vector2) -> Vector3:
	if bounds.is_zero_approx(): return Vector3.ZERO
	var width := bounds.x*SET_WIDTH_FRACTION
	var tight := bounds.x*SET_TIGHT_FRACTION
	var horizontal := Vector2.from_angle(randf()*TAU)*sqrt(randf())
	var depth := lerpf(-bounds.x,tight,0.5+0.5*horizontal.y)
	return Vector3(horizontal.x*width,randf_range(-bounds.y,bounds.y),depth)

static func pass_velocity(touch: Vector3, target: Dictionary, angle: float, bounds: Vector2, setting := false) -> Vector3:
	var ideal := Flight.target_velocity(touch,target,angle)
	if bounds.is_zero_approx(): return ideal
	var offset := sample_set_offset(bounds) if setting else sample_offset(bounds)
	var destination: Vector2 = target.position+Vector2(offset.x,offset.z)
	var peak := touch.y+ideal.y*ideal.y/(2.0*Flight.GRAVITY)
	var minimum := float(target.get("minimum_height",touch.y+0.05))
	return Flight.target_velocity(touch,{"position":destination,"fit":"height","height":maxf(minimum,peak+offset.y),"end_y":target.get("end_y",Flight.FLOOR)},angle)
