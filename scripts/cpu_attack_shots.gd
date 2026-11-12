extends RefCounted

const Net = preload("res://scripts/net_collision.gd")
const Flight = preload("res://scripts/pass_flight.gd")

static func plan(contact: Vector3, preferred: Vector3, speed: float, spin: float,
		defenders: Array[Vector3], walls: Array[Vector3]) -> Dictionary:
	if contact.z >= Net.NET_Z-0.04 or speed < 1.0:
		return {}
	var gravity := Flight.spike_gravity(spin)
	var best := {}
	var best_score := -INF
	var line := clampf(contact.x,-4.08,4.08)
	var lanes := [line,-4.08,-2.35,0.0,2.35,4.08]
	var depths := [4.95,5.55,6.35,7.35,9.75,12.35]
	for x in lanes:
		for depth in depths:
			var target := Vector3(x,Flight.FLOOR,depth)
			var offset := target-contact
			var run := offset.slide(Vector3.UP).length()
			for pace in [1.0,0.80,0.58]:
				var duration: float = run/(speed*pace)
				var motion := offset/duration+Vector3.UP*0.5*gravity*duration
				if not clears_tape(contact,motion,gravity):
					continue
				var height_over_block := -INF
				var near_block := false
				var blocked := false
				for wall in walls:
					var time := (wall.z-contact.z)/motion.z
					if time <= 0.0 or time >= duration:
						continue
					var at_wall := path(contact,motion,gravity,time)
					if absf(at_wall.x-wall.x) > 0.83:
						continue
					near_block = true
					height_over_block = maxf(height_over_block,at_wall.y-wall.y)
					blocked = blocked or at_wall.y < wall.y+0.23
				if blocked:
					continue
				var gap := 5.0
				for defender in defenders:
					gap = minf(gap,(target-defender).slide(Vector3.UP).length())
				var reaction_margin := gap/6.5-duration
				var score: float = reaction_margin*3.0+0.35*pace
				var type := "Avoid block" if not walls.is_empty() else "Hard driven"
				var steepness := clampf(-motion.y/maxf(1.0,speed),0.0,1.3)
				var open_floor := smoothstep(1.0,2.7,gap)
				if not near_block and depth <= 6.35 and pace >= 0.8 and steepness >= 0.25:
					score += 1.6*open_floor+steepness*0.85
					type = "Steep hammer"
				elif near_block and depth >= 9.75 and absf(x-line) < 0.40:
					score += 0.48+minf(height_over_block,0.55)*0.48
					type = "High line"
				elif pace <= 0.58 and depth <= 7.35 and absf(x-contact.x) >= 2.0:
					score += 0.95*open_floor
					type = "Sharp cut"
				score -= (target-contact).slide(Vector3.UP).angle_to((preferred-contact).slide(Vector3.UP))*0.22
				if score > best_score:
					best_score = score
					best = {"type":type,"target":target,"motion":motion}
	for wall in walls:
		if absf(wall.x) < 3.25 or wall.y < Net.NET_TOP+Net.RADIUS:
			continue
		var outside := signf(wall.x)
		var edge := wall+Vector3(outside*0.41,-0.05,0)
		var offset := edge-contact
		var time := offset.slide(Vector3.UP).length()/speed
		if time < 0.025 or time > 0.19 or offset.z <= 0.1:
			continue
		var motion := offset/time+Vector3.UP*0.5*gravity*time
		if not clears_tape(contact,motion,gravity):
			continue
		var score := 0.5+smoothstep(3.25,4.1,absf(wall.x))*0.75
		if score > best_score:
			best_score = score
			best = {"type":"Wipe block","target":edge,"motion":motion}
	return best

static func path(contact: Vector3, motion: Vector3, gravity: float, time: float) -> Vector3:
	return contact+motion*time+Vector3.DOWN*0.5*gravity*time*time

static func clears_tape(contact: Vector3, motion: Vector3, gravity: float) -> bool:
	for depth in [Net.NET_Z-0.12,Net.NET_Z,Net.NET_Z+0.12]:
		var time: float = maxf(0.0,(depth-contact.z)/motion.z)
		var point := path(contact,motion,gravity,time)
		if point.y < Net.NET_TOP+Net.RADIUS+0.045 or absf(point.x) > Net.NET_HALF_WIDTH-Net.RADIUS-0.16:
			return false
	return true
