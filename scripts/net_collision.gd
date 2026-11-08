extends RefCounted
const Flight = preload("res://scripts/pass_flight.gd")
const RADIUS := 0.105
const NET_Z := 4.0
const NET_TOP := 2.505
const NET_HALF_WIDTH := 4.8

static func first_hit(path: Callable, first: float, last: float) -> Dictionary:
	# Sweep the ball volume, so fast shots and tape grazes cannot tunnel through.
	# Below-net crossings are failed shots too: the blocking plane reaches the court.
	var bounds := AABB(Vector3(-NET_HALF_WIDTH-RADIUS,0.04-RADIUS,NET_Z-0.0125-RADIUS),Vector3(2*(NET_HALF_WIDTH+RADIUS),NET_TOP-0.04+2*RADIUS,0.025+2*RADIUS))
	var steps := maxi(1,ceili((last-first)*240))
	var previous_time := first
	var previous: Vector3 = path.call(first)
	for index in range(1,steps+1):
		var time := lerpf(first,last,float(index)/steps)
		var point: Vector3 = path.call(time)
		var intersection: Variant = previous if bounds.has_point(previous) else bounds.intersects_segment(previous,point)
		if intersection is Vector3:
			var fraction := clampf(previous.distance_to(intersection)/maxf(0.000001,previous.distance_to(point)),0,1)
			var hit_time := lerpf(previous_time,time,fraction)
			var hit: Vector3 = path.call(hit_time)
			var epsilon := 0.0001
			var velocity: Vector3 = (path.call(hit_time+epsilon)-path.call(hit_time-epsilon))/(2*epsilon)
			var side := 1.0 if previous.z>=NET_Z else -1.0
			hit.z = NET_Z+side*(RADIUS+0.013)
			var rebound := Vector3(velocity.x*0.25,minf(velocity.y*0.15,1.0),side*absf(velocity.z)*0.12)
			var drop_time := Flight.landing_time(hit,rebound)
			return {"time":hit_time,"point":hit,"velocity":rebound,"end_time":hit_time+drop_time,"drop_time":drop_time}
		previous = point
		previous_time = time
	return {}

static func after_hit(hit: Dictionary, time: float) -> Vector3:
	var elapsed := clampf(time-float(hit.time),0,float(hit.drop_time))
	return hit.point+hit.velocity*elapsed+Vector3.DOWN*4.905*elapsed*elapsed
