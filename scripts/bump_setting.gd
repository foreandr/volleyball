extends MeshInstance3D

const Flight = preload("res://scripts/pass_flight.gd")
const Timing = preload("res://scripts/animation_ball_preview.gd")
const Drive = preload("res://scripts/reception_pass_drive.gd")
const PlatformPose = preload("res://scripts/reception_platform_pose.gd")
const Net = preload("res://scripts/net_collision.gd")
const Contact = preload("res://scripts/forearm_contact.gd")
const PLATFORM_RADIUS := 0.31
const ATTEMPT_TIME := 0.44

var setter: Node3D
var clip: Animation
var contact_frame: float
var meter: Control
var tracks: Array[Vector2i] = []
var ready_pose: Array[Transform3D] = []
var reach := {}
var reach_step := Vector3.ZERO
var reach_travel := Vector3.ZERO
var reach_progress := 0.0
var destination := Vector2(2.75,3.0)
var height := 3.8
var grade := Timing.Grade.WAITING
var pressed_at := -INF
var in_reach := false
var touch_time := -INF
var touch: Vector3
var outgoing: Vector3
var floor_time := 0.0
var net_hit := {}
var surface := ImmediateMesh.new()
var style := StandardMaterial3D.new()
var last_origin := Vector3.INF
var last_destination := Vector2.INF
var last_height := -INF

func configure(player: Node3D, animation: Animation, timing_meter: Control) -> void:
	setter = player
	clip = animation
	contact_frame = float(clip.get_meta("contact_time"))
	meter = timing_meter
	var rig: Skeleton3D = setter.skeleton
	for bone in rig.get_bone_count():
		var path := NodePath("Armature/Skeleton3D:"+rig.get_bone_name(bone))
		var track := Vector2i(clip.find_track(path,Animation.TYPE_POSITION_3D),clip.find_track(path,Animation.TYPE_ROTATION_3D))
		tracks.append(track)
		var ready := rig.get_bone_pose(bone)
		if track.x >= 0: ready.origin = clip.position_track_interpolate(track.x,0.0)
		if track.y >= 0: ready.basis = Basis(clip.rotation_track_interpolate(track.y,0.0))
		ready_pose.append(ready)
	style.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	style.vertex_color_use_as_albedo = true
	mesh = surface
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	reset()

func reset() -> void:
	grade = Timing.Grade.WAITING
	pressed_at = -INF
	in_reach = false
	touch_time = -INF
	net_hit.clear()
	clear_reach()
	meter.reset_serve()

func queue_bump(time: float) -> void:
	if grade == Timing.Grade.WAITING and time-pressed_at >= ATTEMPT_TIME:
		pressed_at = time
		clear_reach()

func platform_center() -> Vector3:
	var rig: Skeleton3D = setter.skeleton
	var elbows := []
	var wrists := []
	for side in ["l","r"]:
		elbows.append(rig.to_global(rig.get_bone_global_pose(rig.find_bone("lowerarm_"+side)).origin))
		wrists.append(rig.to_global(rig.get_bone_global_pose(rig.find_bone("hand_"+side)).origin))
	return Contact.surface(elbows,wrists,0.055).ball

func ready_contact() -> Vector3:
	return setter.to_global(Vector3(0,1.04,0.62))

func aim_velocity(origin: Vector3, error := 0.0) -> Vector3:
	return Timing.aimed_pass_velocity(origin,{"position":destination,"fit":"height","height":height},45.0,error)

func update_aim() -> void:
	var origin := ready_contact()
	if origin.distance_squared_to(last_origin)<0.0004 and destination==last_destination and height==last_height: return
	last_origin = origin
	last_destination = destination
	last_height = height
	var velocity := aim_velocity(origin)
	var duration := Flight.landing_time(origin,velocity)
	surface.clear_surfaces()
	surface.surface_begin(Mesh.PRIMITIVE_LINES,style)
	surface.surface_set_color(Color("57dfff"))
	var ground := Vector3(destination.x,0.075,destination.y)
	for index in range(40):
		var a := TAU*index/40.0
		var b := TAU*(index+1)/40.0
		surface.surface_add_vertex(ground+Vector3(cos(a),0,sin(a))*0.35)
		surface.surface_add_vertex(ground+Vector3(cos(b),0,sin(b))*0.35)
	for index in range(24):
		surface.surface_add_vertex(flight_point(origin,velocity,duration*index/24.0))
		surface.surface_add_vertex(flight_point(origin,velocity,duration*(index+0.48)/24.0))
	surface.surface_end()

func flight_point(origin: Vector3, velocity: Vector3, time: float) -> Vector3:
	return origin+velocity*time+Vector3.DOWN*0.5*Flight.GRAVITY*time*time

func approach(path: Callable, time: float, end: float) -> float:
	var center := ready_contact()
	var nearest := 1.12
	var delay := -1.0
	for index in range(20):
		var ahead := Timing.APPROACH_WINDOW*index/19.0
		if time+ahead > end: break
		var point: Vector3 = path.call(time+ahead)
		var distance := point.distance_to(center)
		if distance <= PLATFORM_RADIUS: return 1.0-ahead/Timing.APPROACH_WINDOW
		if distance < nearest:
			nearest = distance
			delay = ahead
	return 1.0-delay/Timing.APPROACH_WINDOW if delay >= 0.0 else -1.0

func update_attempt(time: float, previous: float, end: float, path: Callable, incoming: Vector3, delta: float) -> void:
	var elapsed := time-pressed_at
	if grade == Timing.Grade.WAITING:
		var incoming_ball: Vector3 = path.call(time)
		in_reach = in_reach or incoming_ball.distance_to(ready_contact()) <= PLATFORM_RADIUS
	var striking := grade == Timing.Grade.WAITING and elapsed >= 0.0 and elapsed <= ATTEMPT_TIME
	if striking:
		var windup := lerpf(-0.14,0.0,smoothstep(0.0,Timing.GREEN_START,elapsed))
		apply_pose(contact_frame+windup,smoothstep(0.0,0.055,elapsed))
		var intercept := advance_reach(path,time,end,delta)
		pose_reach(smoothstep(0.0,1.0,reach_progress),intercept)
		var center := platform_center()
		var first: Vector3 = path.call(previous)
		var last: Vector3 = path.call(time)
		if not first.is_equal_approx(last):
			var point := Geometry3D.get_closest_point_to_segment(center,first,last)
			var gap := point.distance_to(center)
			if gap > PLATFORM_RADIUS and gap <= 0.58:
				reach_platform(point-center)
				center = platform_center()
				point = Geometry3D.get_closest_point_to_segment(center,first,last)
			if point.distance_to(center) <= PLATFORM_RADIUS:
				touch_time = lerpf(previous,time,first.distance_to(point)/first.distance_to(last))
				touch = point
				var timing := touch_time-pressed_at
				grade = Timing.Grade.LATE if timing < Timing.GREEN_START else (Timing.Grade.EARLY if timing > Timing.GREEN_END else Timing.Grade.PERFECT)
				outgoing = aim_velocity(touch,Timing.practice_timing_error(timing))
				floor_time = Flight.landing_time(touch,outgoing)
				net_hit = Net.first_hit(func(t): return flight_point(touch,outgoing,t),0.0,floor_time)
				if not net_hit.is_empty(): floor_time = net_hit.end_time
	elif grade == Timing.Grade.WAITING and time >= end:
		if not in_reach: grade = Timing.Grade.MISS
		else: grade = Timing.Grade.EARLY if is_finite(pressed_at) else Timing.Grade.LATE
	if is_finite(touch_time):
		var follow := time-touch_time
		if follow > 0.0 and follow < 0.36:
			apply_pose(contact_frame+follow,1.0-smoothstep(0.12,0.36,follow))
			pose_reach(smoothstep(0.0,1.0,reach_progress)*(1.0-smoothstep(0.06,0.32,follow)),touch)
			Drive.apply(setter.skeleton,setter.get_pose_author(),outgoing,Drive.effort(incoming,outgoing),follow,true,incoming,Drive.swing_effort(touch,outgoing))
	elif grade == Timing.Grade.WAITING and elapsed > ATTEMPT_TIME and elapsed < ATTEMPT_TIME+0.12:
		var recovery := 1.0-smoothstep(ATTEMPT_TIME,ATTEMPT_TIME+0.12,elapsed)
		apply_pose(contact_frame,recovery)
		pose_reach(smoothstep(0.0,1.0,reach_progress)*recovery,Vector3.INF)
	meter.update_timing(true,approach(path,time,end) if grade == Timing.Grade.WAITING else -1.0,striking,grade,delta)

func clear_reach() -> void:
	reach.clear()
	reach_step = Vector3.ZERO
	reach_travel = Vector3.ZERO
	reach_progress = 0.0

func advance_reach(path: Callable, time: float, end: float, delta: float) -> Vector3:
	var intercept := Vector3.INF
	var lookahead := minf(time+0.30,end)
	if lookahead > time:
		var future: Vector3 = path.call(lookahead)
		var now: Vector3 = path.call(time)
		intercept = Geometry3D.get_closest_point_to_segment(ready_contact(),now,future)
		if reach.is_empty() and (lookahead >= end or not intercept.is_equal_approx(future)):
			plan_reach(intercept-ready_contact())
	if not reach.is_empty():
		var before := smoothstep(0.0,1.0,reach_progress)
		var duration := 0.19 if reach.tier == 2 else 0.15
		reach_progress = minf(1.0,reach_progress+delta/duration)
		var origin := setter.position
		var next := origin+reach_step*(smoothstep(0.0,1.0,reach_progress)-before)
		setter.position.x = clampf(next.x,-4.0,4.0)
		setter.position.z = clampf(next.z,-4.5,2.5)
		reach_travel += setter.position-origin
	return intercept

func plan_reach(offset: Vector3) -> void:
	var local := setter.basis.inverse()*offset
	var horizontal := offset.slide(Vector3.UP)
	if offset.length() <= PLATFORM_RADIUS or horizontal.length() < 0.12: return
	var tier := Timing.practice_reach_tier(offset)
	if tier == 3: return
	var back := local.z < -absf(local.x)*0.65
	var short_back := tier == 1 and back and -local.z > absf(local.x)*1.4
	var forward := local.z > absf(local.x)*1.4
	var side := tier == 2 and absf(local.x) > absf(local.z)*1.4
	reach = {
		"tier":tier,"back":back,"rear_diagonal":tier == 2 and back and absf(local.x)>0.20,
		"short_straight_back":short_back,"forward_lunge":forward,
		"lead":"r" if (tier == 1 and (forward or short_back)) or local.x < 0.0 else "l",
		"side_lunge":side,"height":offset.y if tier == 2 else 0.0,
	}
	var limit := 0.68 if side else (0.75 if tier == 2 else 0.46)
	reach_step = horizontal.limit_length(limit)*(1.0 if back and tier == 2 else 0.78)

func pose_reach(weight: float, intercept: Vector3) -> void:
	if reach.is_empty() or weight <= 0.0: return
	var local := setter.basis.inverse()
	setter.pose_reception_reach(local*reach_step,local*reach_travel,weight,reach_progress,ready_pose,reach,false,0,intercept)

func reach_platform(offset: Vector3) -> void:
	var rig: Skeleton3D = setter.skeleton
	var author: RefCounted = setter.get_pose_author()
	var pose: Array = []
	for bone in rig.get_bone_count(): pose.append(rig.get_bone_pose(bone))
	var grip: Vector3 = (author.point(pose,"hand_l")+author.point(pose,"hand_r"))*0.5
	var shift := rig.global_basis.inverse()*offset.limit_length(0.26)
	PlatformPose.connect_arms(pose,author,grip+shift,0.82)
	for side in ["l","r"]:
		for part in ["upperarm_","lowerarm_","hand_"]:
			var bone := rig.find_bone(part+side)
			rig.set_bone_pose_rotation(bone,pose[bone].basis.get_rotation_quaternion())

func apply_pose(time: float, weight: float) -> void:
	var rig: Skeleton3D = setter.skeleton
	time = clampf(time,0.0,clip.length)
	for bone in tracks.size():
		var track := tracks[bone]
		if track.x >= 0:
			rig.set_bone_pose_position(bone,rig.get_bone_pose_position(bone).lerp(clip.position_track_interpolate(track.x,time),weight))
		if track.y >= 0:
			rig.set_bone_pose_rotation(bone,rig.get_bone_pose_rotation(bone).slerp(clip.rotation_track_interpolate(track.y,time),weight))
