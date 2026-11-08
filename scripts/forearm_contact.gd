extends RefCounted
const RADIUS := 0.105

static func surface(elbows: Array, wrists: Array, arm_radius: float) -> Dictionary:
	var points := [elbows[0].lerp(wrists[0],0.65),elbows[1].lerp(wrists[1],0.65)]
	var axis: Vector3 = ((wrists[0]-elbows[0])+(wrists[1]-elbows[1])).normalized()
	var normal: Vector3 = (points[1]-points[0]).cross(axis).normalized()
	if normal.dot(Vector3.UP) < 0: normal = -normal
	if normal.length_squared() < 0.5: normal = Vector3.UP
	var center: Vector3 = (points[0]+points[1])*0.5
	var half_gap: float = points[0].distance_to(points[1])*0.5
	var clearance := RADIUS+arm_radius
	if half_gap >= clearance:
		center = points[0]
		half_gap = 0
	return {"surface":center,"normal":normal,"ball":center+normal*sqrt(maxf(0,clearance*clearance-half_gap*half_gap))}

static func rebound(incoming: Vector3, velocity: Vector3, normal: Vector3) -> Vector3:
	var relative := incoming-velocity
	return relative-1.55*minf(0,relative.dot(normal))*normal+velocity

static func elevation(velocity: Vector3) -> float:
	return rad_to_deg(atan2(velocity.y,Vector2(velocity.x,velocity.z).length()))
