extends RefCounted
const Flight = preload("res://scripts/pass_flight.gd")
const RADIUS := 0.105
const NET_Z := 4.0
const NET_TOP := 2.505
const NET_BOTTOM := 1.45
const NET_HALF_WIDTH := 4.8

static func contact_sound() -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = AudioStreamWAV.load_from_file("res://assets/audio/pass_contact.wav")
	player.volume_db = -12
	player.pitch_scale = 0.65
	return player

static func squeeze(hit: Dictionary, time: float) -> float:
	if hit.is_empty() or float(hit.contact_duration) <= 0.0: return 0.0
	var compression := clampf((time-float(hit.time))/float(hit.contact_duration),0.0,1.0)
	return sin(PI*compression)

static func gap_squared(point: Vector3) -> float:
	var offset := Vector3(maxf(0,absf(point.x)-NET_HALF_WIDTH),maxf(0,maxf(0.04-point.y,point.y-NET_TOP)),maxf(0,absf(point.z-NET_Z)-0.0125))
	return offset.length_squared()

static func first_hit(path: Callable, first: float, last: float) -> Dictionary:
	var bounds := AABB(Vector3(-NET_HALF_WIDTH-RADIUS,0.04-RADIUS,NET_Z-0.0125-RADIUS),Vector3(2*(NET_HALF_WIDTH+RADIUS),NET_TOP-0.04+2*RADIUS,0.025+2*RADIUS))
	var steps := maxi(1,ceili((last-first)*240))
	var previous_time := first
	var previous: Vector3 = path.call(first)
	for index in range(1,steps+1):
		var time := lerpf(first,last,float(index)/steps)
		var point: Vector3 = path.call(time)
		if bounds.has_point(previous) or bounds.intersects_segment(previous,point) is Vector3:
			# Refine the swept sphere against the rounded edges of the net/tape.
			var low := previous_time
			var high := time
			for refinement in range(15):
				var a := lerpf(low,high,1.0/3)
				var b := lerpf(low,high,2.0/3)
				if gap_squared(path.call(a))<gap_squared(path.call(b)): high = b
				else: low = a
			var nearest := (low+high)*0.5
			if gap_squared(path.call(nearest))<=RADIUS*RADIUS+0.000001:
				low = previous_time
				high = nearest
				for refinement in range(15):
					var middle := (low+high)*0.5
					if gap_squared(path.call(middle))<=RADIUS*RADIUS: high = middle
					else: low = middle
				var hit_time := (low+high)*0.5
				var hit: Vector3 = path.call(hit_time)
				var epsilon := 0.0001
				var velocity: Vector3 = (path.call(hit_time+epsilon)-path.call(hit_time-epsilon))/(2*epsilon)
				return impact(hit_time,hit,velocity,1.0 if previous.z>=NET_Z else -1.0)
		previous = point
		previous_time = time
	return {}

static func impact(time: float, point: Vector3, incoming: Vector3, side: float) -> Dictionary:
	var kind := "cloth"
	if point.y<NET_BOTTOM-RADIUS: kind = "under"
	elif point.y>NET_TOP-0.12: kind = "tape"
	var rigidity := 0.35+0.65*pow(clampf(absf(point.x)/NET_HALF_WIDTH,0,1),2)
	var softness := (1.0-smoothstep(1.47,2.05,point.y))*(1.0-0.6*rigidity) if kind == "cloth" else 0.0
	var duration := 0.12 if kind == "cloth" else 0.075
	duration += 0.065*softness
	var stretch := clampf(absf(incoming.z)*duration*1.18/PI,0.025,0.57+0.17*softness)*(1.15-rigidity*0.4)
	var rebound := Vector3(incoming.x*0.55,incoming.y*0.5,side*absf(incoming.z)*(0.24+0.16*rigidity))
	# The looser lower mesh holds the ball briefly and damps the downward slide.
	rebound.z *= 1.0-0.25*softness
	if incoming.y<0: rebound.y = incoming.y*lerpf(0.5,0.15,softness)
	var release := point+Vector3(incoming.x*duration*0.35,incoming.y*duration*lerpf(0.35,0.08,softness),0)
	release.z = NET_Z+side*(RADIUS+0.014)
	var rollover := kind == "tape" and point.y>NET_TOP+0.025 and incoming.y<1
	if kind == "tape":
		rebound.y = clampf(absf(incoming.y)*0.45+absf(incoming.z)*0.10,0.6,2.8)
		rebound.z = incoming.z*0.22 if rollover else side*absf(incoming.z)*0.22
		if rollover:
			release.y = maxf(release.y,NET_TOP+RADIUS+0.02)
			release.z = NET_Z-side*(RADIUS+0.014)
	elif kind == "under":
		# An under-net crossing remains a fault, rather than hitting invisible cloth.
		duration = 0
		stretch = 0
		rebound = Vector3(incoming.x*0.25,minf(0,incoming.y*0.15),side*absf(incoming.z)*0.12)
		release = point
		release.z = NET_Z+side*(RADIUS+0.014)
	if kind!="under": rebound=rebound.normalized()*incoming.length()*.20
	release.y = maxf(Flight.FLOOR,release.y)
	var airborne := Flight.landing_time(release,rebound)
	return {"time":time,"point":point,"incoming":incoming,"side":side,"kind":kind,"rollover":rollover,"softness":softness,"stretch":stretch,"contact_duration":duration,"release_time":time+duration,"release_point":release,"velocity":rebound,"drop_time":airborne,"end_time":time+duration+airborne}

static func after_hit(hit: Dictionary, time: float) -> Vector3:
	if time<float(hit.release_time) and float(hit.contact_duration)>0:
		var u := clampf((time-float(hit.time))/float(hit.contact_duration),0,1)
		var point: Vector3 = hit.point.lerp(hit.release_point,u)
		point.z -= float(hit.side)*float(hit.stretch)*sin(PI*u)
		if hit.rollover: point.y += 0.10*sin(PI*u)
		return point
	var elapsed := clampf(time-float(hit.release_time),0,float(hit.drop_time))
	return hit.release_point+hit.velocity*elapsed+Vector3.DOWN*4.905*elapsed*elapsed

static func state_at(hit: Dictionary, time: float) -> Dictionary:
	if hit.is_empty() or time<float(hit.time): return {"recoverable":false,"phase":"before_net","in_play":true}
	var point := after_hit(hit,time)
	var velocity: Vector3 = (after_hit(hit,time+0.0001)-after_hit(hit,time-0.0001))/0.0002
	var phase := "net_contact" if time<float(hit.release_time) else ("airborne" if time<float(hit.end_time) else "grounded")
	return {"position":point,"velocity":velocity,"phase":phase,"recoverable":phase=="airborne" and hit.kind!="under","in_play":phase!="grounded" and hit.kind!="under","rollover":hit.rollover}

static func surface_offset(hit: Dictionary, time: float, point: Vector3) -> Vector3:
	if hit.is_empty() or hit.kind == "under": return Vector3.ZERO
	var center: Vector3 = hit.point
	center.y = clampf(center.y,1.47,2.47)
	var dx := point.x-center.x
	var dy := point.y-center.y
	var age := time-float(hit.time)-absf(dx)*0.018-absf(dy)*0.03
	if age<0: return Vector3.ZERO
	var duration: float = hit.contact_duration
	var softness := float(hit.get("softness",0))
	var displacement := 0.0
	if age<=duration: displacement = -float(hit.side)*float(hit.stretch)*sin(PI*age/duration)
	else:
		var after := age-duration
		displacement = float(hit.side)*float(hit.stretch)*0.68*(1.0-0.3*softness)*exp(-4.5*after)*sin(26*(1.0-0.25*softness)*after)
	var width := 1.2 if hit.kind=="tape" else 0.75+0.15*softness
	var shape := exp(-dx*dx/(2*width*width)-dy*dy/(0.25+0.1*softness))
	var anchor := clampf((NET_HALF_WIDTH-absf(point.x))/0.5,0,1)
	var center_anchor := maxf(0.1,clampf((NET_HALF_WIDTH-absf(center.x))/0.5,0,1))
	displacement *= shape*minf(1,anchor/center_anchor)
	return Vector3(0,-absf(displacement)*0.08,displacement)
