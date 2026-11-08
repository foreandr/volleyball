extends RefCounted
const GRAVITY := 9.81
const FLOOR := 0.145

static func feed(hit: Vector3) -> Dictionary:
	var start := Vector3(hit.x,3.4,12.5)
	var span := start.z-hit.z
	var fraction := clampf((start.z-4.0)/span,0.05,0.97)
	var straight_height := lerpf(start.y,hit.y,fraction)
	var clearance_time := sqrt(maxf(0,(3.1-straight_height)/(4.905*fraction*(1.0-fraction))))
	var duration := maxf(span/11.0,clearance_time)
	var initial := (hit-start)/duration+Vector3.UP*4.905*duration
	return {"start":start,"duration":duration,"incoming":initial+Vector3.DOWN*GRAVITY*duration}

static func landing_time(hit: Vector3, velocity: Vector3) -> float:
	return (velocity.y+sqrt(maxf(0,velocity.y*velocity.y+2*GRAVITY*(hit.y-FLOOR))))/GRAVITY

static func distance(hit: Vector3, velocity: Vector3) -> float:
	return Vector2(velocity.x,velocity.z).length()*landing_time(hit,velocity)

static func desired_velocity(hit: Vector3, angle: float, distance_: float) -> Vector3:
	var radians := deg_to_rad(angle)
	var speed_squared := GRAVITY*distance_*distance_/(2.0*cos(radians)*cos(radians)*(hit.y-FLOOR+distance_*tan(radians)))
	var speed := sqrt(maxf(0,speed_squared))
	return Vector3(0,sin(radians),cos(radians))*speed
