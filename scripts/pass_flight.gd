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

# Signed distance from the outer court lines. Read error is sampled once per flight.
static func reads_out(landing: Vector3, read_error: float, skill := 50.) -> bool:
	var outside := maxf(absf(landing.x)-4.5,absf(landing.z-4.)-9.)
	var uncertainty := lerpf(.10,.05,clampf(skill/100.,0.,1.))
	return outside+clampf(read_error,-1.,1.)*uncertainty>0.

static func reception_backspin(outgoing: Vector3, incoming_rps := 0.) -> Vector3:
	var flat := outgoing.slide(Vector3.UP)
	if flat.is_zero_approx(): return Vector3.ZERO
	return spin_axis(flat,"Backspin")*(clampf(1.+flat.length()*.18,1.,3.5)+.30*clampf(incoming_rps,0.,18.))

static func rotate_reception_ball(ball: Node3D,outgoing: Vector3,seconds: float,incoming_rps := 0.) -> void:
	var spin := reception_backspin(outgoing,incoming_rps)
	if not spin.is_zero_approx(): ball.rotate(spin.normalized(),spin.length()*TAU*seconds)

static func forearm_spin(incoming: Vector3, outgoing: Vector3, incoming_spin: Vector3, radius: float) -> Vector3:
	# Estimate the platform normal from the change in velocity. Friction opposes
	# the ball surface's slip at the contact patch and transfers spin.
	var impulse := outgoing-incoming
	if impulse.is_zero_approx(): return reception_backspin(outgoing,incoming_spin.length())
	var normal := impulse.normalized()
	var contact_arm := -normal*radius
	var slip := (incoming+(incoming_spin*TAU).cross(contact_arm)).slide(normal)
	# Use a compliant contact and bound the friction impulse for clean deflections.
	var friction := (-slip*0.12).limit_length(impulse.length()*0.15)
	var spin := incoming_spin+contact_arm.cross(friction)/(0.67*radius*radius*TAU)
	var back := reception_backspin(outgoing,incoming_spin.length())
	if back.is_zero_approx(): return spin.limit_length(12.)
	var axis := back.normalized()
	return (axis*maxf(back.length(),spin.dot(axis))+spin.slide(axis)*.35).limit_length(12.)

static func air(forward: Vector3, settings: Dictionary) -> Dictionary:
	var radians := deg_to_rad(float(settings.get("angle",40.0)))
	var speed := float(settings.get("speed",14.0))
	var incoming := forward*speed*cos(radians)+Vector3.DOWN*speed*sin(radians)
	var axis := spin_axis(forward,str(settings.get("spin","No spin")))
	var rate := float(settings.get("spin_rate",3.0))*TAU
	# Lightweight Magnus approximation; keep lift bounded at extreme slider values.
	var magnus := (axis*rate).cross(incoming)*0.012
	magnus -= forward*magnus.dot(forward)
	magnus = magnus.limit_length(8.0)
	return {"incoming":incoming,"acceleration":Vector3.DOWN*GRAVITY+magnus,"spin_axis":axis,"spin_rate":rate}

static func feed(hit: Vector3, settings: Dictionary = {}) -> Dictionary:
	if not settings.has("source_height"): return raw_feed(hit,settings)
	var fitted := settings.duplicate()
	var source: Vector2 = fitted.get("source",Vector2(0,12.5))
	var distance_ := maxf(0.1,source.distance_to(Vector2(hit.x,hit.z)))
	var height := float(fitted.source_height)
	var difference := height-hit.y
	var heading := Vector3(hit.x-source.x,0,hit.z-source.y).normalized()
	if fitted.get("fit","angle") == "angle":
		# Hold chosen speed when possible, deriving the physically compatible arrival angle.
		for pass_ in range(3):
			var gravity := maxf(1.0,-air(heading,fitted).acceleration.y)
			var minimum := sqrt(gravity*(difference+sqrt(distance_*distance_+difference*difference)))
			fitted.speed = maxf(float(fitted.get("speed",14.0)),minimum*1.01)
			var square := float(fitted.speed)*float(fitted.speed)
			var discriminant := maxf(0,square*square-gravity*(gravity*distance_*distance_+2*difference*square))
			fitted.angle = clampf(rad_to_deg(atan((square-sqrt(discriminant))/(gravity*distance_))),1,85)
		for iteration in range(6):
			var trial := raw_feed(hit,fitted,false)
			var error: float = trial.start.y-height
			if absf(error)<0.0005: break
			var perturbed := fitted.duplicate()
			perturbed.angle = float(fitted.angle)+0.1
			var derivative: float = (raw_feed(hit,perturbed,false).start.y-trial.start.y)/0.1
			if absf(derivative)<0.0001: break
			fitted.angle = clampf(float(fitted.angle)-clampf(error/derivative,-5,5),1,85)
	# Fit speed as well if spin or an unreachable speed prevented the angle-only solution.
	if fitted.get("fit","angle") == "speed" or absf(raw_feed(hit,fitted,false).start.y-height)>0.01:
		var minimum_angle := rad_to_deg(atan2(difference,distance_))+1.0
		fitted.angle = clampf(maxf(float(fitted.get("angle",40.0)),minimum_angle),1,85)
		var radians := deg_to_rad(float(fitted.angle))
		var gravity := maxf(1.0,-air(heading,fitted).acceleration.y)
		fitted.speed = sqrt(gravity*distance_*distance_/(2*cos(radians)*cos(radians)*maxf(0.01,distance_*tan(radians)-difference)))
		for iteration in range(8):
			var trial := raw_feed(hit,fitted,false)
			var error: float = trial.start.y-height
			if absf(error)<0.0005: break
			var perturbed := fitted.duplicate()
			perturbed.speed = float(fitted.speed)+0.1
			var derivative: float = (raw_feed(hit,perturbed,false).start.y-trial.start.y)/0.1
			if absf(derivative)<0.0001: break
			fitted.speed = clampf(float(fitted.speed)-clampf(error/derivative,-10,10),0.5,120)
	return raw_feed(hit,fitted)

static func raw_feed(hit: Vector3, settings: Dictionary, check_net := true) -> Dictionary:
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
	result.net_height = INF
	if check_net and (result.start.z-4)*(hit.z-4)<0:
		var low := -duration
		var high := 0.0
		for iteration in range(16):
			var middle := (low+high)*0.5
			if (position(result,hit,middle).z>4)==(result.start.z>4): low = middle
			else: high = middle
		result.net_height = position(result,hit,(low+high)*0.5).y
	result.valid = result.start.y>=FLOOR and result.net_height>2.575
	return result

static func position(feed_: Dictionary, hit: Vector3, time: float) -> Vector3:
	var result: Vector3 = hit+feed_.incoming*time+feed_.acceleration*0.5*time*time
	var u := clampf(-time/feed_.duration,0,1)
	var envelope := pow(sin(PI*u),2)
	var flutter := Vector2(sin(19*u+0.8)+0.45*sin(37*u),0.6*sin(27*u+1.2))
	return result+(feed_.side*flutter.x+Vector3.UP*flutter.y)*envelope*float(feed_.get("float_strength",0))*0.25

static func spike_gravity(topspin_rps: float) -> float:
	return GRAVITY+clampf(topspin_rps,0.0,13.0)*0.52

static func landing_time(hit: Vector3, velocity: Vector3, gravity := GRAVITY) -> float:
	return (velocity.y+sqrt(maxf(0,velocity.y*velocity.y+2*gravity*(hit.y-FLOOR))))/gravity

static func distance(hit: Vector3, velocity: Vector3) -> float:
	return Vector2(velocity.x,velocity.z).length()*landing_time(hit,velocity)

static func desired_velocity(hit: Vector3, angle: float, distance_: float) -> Vector3:
	var radians := deg_to_rad(angle)
	var speed_squared := GRAVITY*distance_*distance_/(2.0*cos(radians)*cos(radians)*(hit.y-FLOOR+distance_*tan(radians)))
	var speed := sqrt(maxf(0,speed_squared))
	return Vector3(0,sin(radians),cos(radians))*speed

static func target_velocity(hit: Vector3, target: Dictionary, angle: float) -> Vector3:
	var position_: Vector2 = target.position
	var delta := Vector3(position_.x-hit.x,0,position_.y-hit.z)
	var span := maxf(0.05,delta.length())
	if target.get("fit","angle") == "height":
		var peak := maxf(float(target.get("height",3.0)),hit.y+0.05)
		var vertical := sqrt(2*GRAVITY*(peak-hit.y))
		var duration := (vertical+sqrt(vertical*vertical+2*GRAVITY*(hit.y-FLOOR)))/GRAVITY
		return delta/maxf(0.05,duration)+Vector3.UP*vertical
	var speed := desired_velocity(hit,angle,span)
	return delta.normalized()*speed.z+Vector3.UP*speed.y
