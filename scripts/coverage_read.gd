extends RefCounted

# Recent uncovered landings carry the most weight. A clean contact eases the read.
var pressure := Vector2.ZERO
var confidence := 0.

func beaten(point: Vector3) -> void:
	var lane := Vector2(point.x,point.z)
	var nearby := confidence>0. and pressure.distance_to(lane)<2.
	pressure=pressure.lerp(lane,.4) if nearby else lane
	confidence=minf(1.,confidence+.32) if nearby else .32

func covered() -> void:
	confidence*=.82

func position_for(home: Vector3, libero := false) -> Vector3:
	var gap := pressure-Vector2(home.x,home.z)
	# The nearest lane takes a full step; adjoining lanes shift less to cover the seam.
	var support := lerpf(1.,.16,smoothstep(1.3,6.5,absf(gap.x)))
	var shift := Vector2(clampf(gap.x,-1.35,1.35)*support,clampf(gap.y,-2.,2.) if libero else clampf(gap.y,-1.35,1.35)*support)*confidence
	return Vector3(clampf(home.x+shift.x,-4.35,4.35),home.y,home.z+shift.y)
