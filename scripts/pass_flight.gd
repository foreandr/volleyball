extends RefCounted
const GRAVITY := 9.81
const FLOOR := 0.145

static func spin_axis(forward: Vector3, type: String) -> Vector3:
	match type:
		"Topspin": return Vector3.UP.cross(forward).normalized()
		"Backspin": return -Vector3.UP.cross(forward).normalized()
		"Sidespin left": return Vector3.UP
		"Sidespin right": return Vector3.DOWN
	return Vector3.ZERO

static func air(forward: Vector3, settings: Dictionary) -> Dictionary:
	var radians := deg_to_rad(float(settings.get("angle",40.0)))
	var speed := float(settings.get("speed",14.0))
	var incoming := forward*speed*cos(radians)+Vector3.DOWN*speed*sin(radians)
	var axis := spin_axis(forward,str(settings.get("spin","No spin")))
	var rate := float(settings.get("spin_rate",3.0))*TAU
	# Lightweight Magnus approximation; keep lift bounded at extreme slider values.
	var magnus := (axis*rate).cross(incoming)*0.012
	magnus = magnus.limit_length(8.0)
	return {"incoming":incoming,"acceleration":Vector3.DOWN*GRAVITY+magnus,"spin_axis":axis,"spin_rate":rate}

static func feed(hit: Vector3, settings: Dictionary = {}) -> Dictionary:
	var start_xz: Vector2 = settings.get("source",Vector2(0,12.5))
	var span := Vector2(hit.x,hit.z)-start_xz
	var heading := atan2(span.x,span.y)
	var horizontal := float(settings.get("speed",14.0))*cos(deg_to_rad(float(settings.get("angle",40.0))))
	var duration := span.length()/maxf(0.1,horizontal)
	# Preserve both the dragged source and requested contact velocity as spin curves the flight.
	for iteration in range(8):
		var motion := air(Vector3(sin(heading),0,cos(heading)),settings)
		var offset: Vector3 = -motion.incoming*duration+motion.acceleration*0.5*duration*duration
		var error := Vector2(hit.x+offset.x,hit.z+offset.z)-start_xz
		if error.length_squared()<0.000001: break
		var alternate := air(Vector3(sin(heading+0.001),0,cos(heading+0.001)),settings)
		var shifted: Vector3 = -alternate.incoming*duration+alternate.acceleration*0.5*duration*duration
		var dh := (Vector2(shifted.x,shifted.z)-Vector2(offset.x,offset.z))/0.001
		var dt: Vector3 = -motion.incoming+motion.acceleration*duration
		var determinant := dh.x*dt.z-dt.x*dh.y
		if absf(determinant)<0.00001: break
		heading -= clampf((dt.z*error.x-dt.x*error.y)/determinant,-0.3,0.3)
		duration = maxf(0.1,duration-clampf((-dh.y*error.x+dh.x*error.y)/determinant,-0.3,0.3))
	var result := air(Vector3(sin(heading),0,cos(heading)),settings)
	result.duration = duration
	result.start = hit-result.incoming*duration+result.acceleration*0.5*duration*duration
	result.float_strength = float(settings.get("float_strength",0.6)) if settings.get("spin","") == "Dead float" else 0.0
	result.side = Vector3.UP.cross(Vector3(sin(heading),0,cos(heading)))
	var low := -duration
	var high := 0.0
	for iteration in range(16):
		var middle := (low+high)*0.5
		if position(result,hit,middle).z>4: low = middle
		else: high = middle
	var net := position(result,hit,(low+high)*0.5)
	result.net_height = net.y
	result.valid = result.start.y>=FLOOR and net.y>2.575
	return result

static func position(feed_: Dictionary, hit: Vector3, time: float) -> Vector3:
	var result: Vector3 = hit+feed_.incoming*time+feed_.acceleration*0.5*time*time
	var u := clampf(-time/feed_.duration,0,1)
	var envelope := pow(sin(PI*u),2)
	var flutter := Vector2(sin(19*u+0.8)+0.45*sin(37*u),0.6*sin(27*u+1.2))
	return result+(feed_.side*flutter.x+Vector3.UP*flutter.y)*envelope*float(feed_.get("float_strength",0))*0.25

static func landing_time(hit: Vector3, velocity: Vector3) -> float:
	return (velocity.y+sqrt(maxf(0,velocity.y*velocity.y+2*GRAVITY*(hit.y-FLOOR))))/GRAVITY

static func distance(hit: Vector3, velocity: Vector3) -> float:
	return Vector2(velocity.x,velocity.z).length()*landing_time(hit,velocity)

static func desired_velocity(hit: Vector3, angle: float, distance_: float) -> Vector3:
	var radians := deg_to_rad(angle)
	var speed_squared := GRAVITY*distance_*distance_/(2.0*cos(radians)*cos(radians)*(hit.y-FLOOR+distance_*tan(radians)))
	var speed := sqrt(maxf(0,speed_squared))
	return Vector3(0,sin(radians),cos(radians))*speed
