extends MeshInstance3D

const HandPose = preload("res://scripts/hand_setting_pose.gd")
const Court = preload("res://scripts/preview_court.gd")
const Flight = preload("res://scripts/pass_flight.gd")
const Timing = preload("res://scripts/animation_ball_preview.gd")
const Drive = preload("res://scripts/reception_pass_drive.gd")
const PlatformPose = preload("res://scripts/reception_platform_pose.gd")
const Net = preload("res://scripts/net_collision.gd")
const Contact = preload("res://scripts/forearm_contact.gd")
const PLATFORM_RADIUS := 0.31
const DIVE_CONTACT_ALLOWANCE := 0.09
const MAX_EARLY_ERROR_TIME := 0.66
const BallTimingRing = preload("res://scripts/ball_timing_ring.gd")
const LowSave = preload("res://scripts/player_reception_save.gd")
const SpreadCone = preload("res://scripts/reception_spread_cone.gd")
const GREEN_START := 0.035
const GREEN_END := 0.37
const APPROACH_TIME := 0.60
const PLATFORM_PREP_TIME := 0.26

var setter: Node3D
var hand_setting := false
var quick_hand_receive := false
var catch_only := false
var catch_airborne := false
var setter_jumping := false
var clip: Animation
var contact_frame: float
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
var low_save := LowSave.new()
var pose_started_at := -INF
var cone: MeshInstance3D
var contact_check := {}
var approach_progress := -1.0
var contact_spread := 0.0
var contact_destination := Vector2.ZERO
var touch_time := -INF
var touch: Vector3
var hand_anchor: Vector3
var hand_target := {}
var release_time := -INF
var release_point: Vector3
var outgoing: Vector3
var floor_time := 0.0
var net_hit := {}
var surface := ImmediateMesh.new()
var style := StandardMaterial3D.new()
var last_origin := Vector3.INF
var last_destination := Vector2.INF
var last_height := -INF

func configure(player: Node3D, animation: Animation) -> void:
	setter = player
	clip = animation
	contact_frame = float(clip.get_meta("contact_time"))
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
	cone = SpreadCone.new()
	add_child(cone)
	reset()

func reset() -> void:
	contact_check.clear()
	approach_progress = -1.0
	grade = Timing.Grade.WAITING
	pressed_at = -INF
	low_save.active = false
	pose_started_at = -INF
	cone.hide()
	touch_time = -INF
	release_time = -INF
	hand_target.clear()
	net_hit.clear()
	clear_reach()

func queue_bump(time: float) -> void:
	if grade == Timing.Grade.WAITING and not is_finite(pressed_at):
		pressed_at = time
		clear_reach()

func movement_scale(time: float, arrival: float, ball_position: Vector3) -> float:
	if is_finite(touch_time):
		if catch_only: return 0.0
		if hand_setting: return smoothstep(hand_release_delay(),0.25,time-touch_time)
		return smoothstep(0.045,0.15,time-touch_time)
	if not is_finite(pressed_at) or grade != Timing.Grade.WAITING: return 1.0
	var distance := (ball_position-setter.global_position).slide(Vector3.UP).length()
	if distance > 1.15: return 1.0
	# Let the reception step own the last part of the approach.
	var lead := arrival-time
	var brake := smoothstep(-0.11,-0.025,lead)*(1.0-smoothstep(0.025,0.16,lead))
	return 1.0-brake

func platform_center() -> Vector3:
	if hand_setting: return HandPose.contact_center(setter)
	var rig: Skeleton3D = setter.skeleton
	var elbows := []
	var wrists := []
	for side in ["l","r"]:
		elbows.append(rig.to_global(rig.get_bone_global_pose(rig.find_bone("lowerarm_"+side)).origin))
		wrists.append(rig.to_global(rig.get_bone_global_pose(rig.find_bone("hand_"+side)).origin))
	return Contact.surface(elbows,wrists,0.055).ball

func ready_contact() -> Vector3:
	if hand_setting: return setter.to_global(Vector3(0,HandPose.CONTACT_HEIGHT,HandPose.CONTACT_FORWARD))
	return setter.to_global(Vector3(0,1.04,0.62))

func contact_radius() -> float:
	return HandPose.CONTACT_RADIUS if hand_setting else PLATFORM_RADIUS

func hand_intercept(path: Callable, time: float, end: float) -> Vector3:
	var current: Vector3 = path.call(time)
	var next: Vector3 = path.call(minf(time+0.16,end))
	var center := ready_contact()
	if current.is_equal_approx(next): return center
	var nearest := Geometry3D.get_closest_point_to_segment(center,current,next)
	return center+(nearest-center).limit_length(0.50)

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
		var ahead := APPROACH_TIME*index/19.0
		if time+ahead > end: break
		var point: Vector3 = path.call(time+ahead)
		var next: Vector3 = path.call(time+ahead+0.005)
		if next.y >= point.y: continue
		var distance := point.distance_to(center)
		if distance <= contact_radius():
			var low := maxf(0.0,ahead-APPROACH_TIME/19.0)
			var high := ahead
			for refinement in range(5):
				var mid := (low+high)*0.5
				var sample: Vector3 = path.call(time+mid)
				if sample.distance_to(center) <= contact_radius(): high = mid
				else: low = mid
			return 1.0-high/APPROACH_TIME
		if distance < nearest:
			nearest = distance
			delay = ahead
	return 1.0-delay/APPROACH_TIME if delay >= 0.0 else -1.0

func update_attempt(time: float, previous: float, end: float, path: Callable, incoming: Vector3, delta: float, cue_arrival := INF) -> void:
	contact_check.clear()
	var progress := approach(path,time,end) if grade == Timing.Grade.WAITING else -1.0
	approach_progress = progress
	var attempted := is_finite(pressed_at)
	if attempted and grade == Timing.Grade.WAITING:
		if not is_finite(pose_started_at) and progress >= 1.0-PLATFORM_PREP_TIME/APPROACH_TIME:
			pose_started_at = maxf(pressed_at,time-delta)
		if not hand_setting and not setter_jumping and reach.is_empty(): low_save.plan(setter,path,time,end,clip)
	var elapsed := time-pose_started_at
	var striking := attempted and grade == Timing.Grade.WAITING and (low_save.active or is_finite(pose_started_at)) and time < end and (not catch_only or catch_airborne)
	if striking:
		if hand_setting:
			var target := hand_intercept(path,time,end)
			HandPose.apply(setter,target,smoothstep(0.0,0.062 if quick_hand_receive else 0.105,elapsed))
		elif low_save.active:
			low_save.sample(setter,time,low_save.contact_time+0.07)
		else:
			var windup := lerpf(-0.14,0.0,smoothstep(0.0,GREEN_START,elapsed))
			apply_pose(contact_frame+windup,smoothstep(0.0,0.026,elapsed))
			if not setter_jumping:
				var intercept := advance_reach(path,time,end,delta)
				pose_reach(smoothstep(0.0,1.0,reach_progress),intercept)
		var pancake := low_save.active and low_save.pancake
		var center := LowSave.palm_center(setter) if pancake else platform_center()
		var radius := 0.16 if pancake else contact_radius()
		var near_dive_contact := low_save.active and not pancake and absf(time-low_save.contact_time)<=0.12
		var allowance := DIVE_CONTACT_ALLOWANCE if near_dive_contact else 0.0
		var cutoff := radius+allowance
		var first: Vector3 = path.call(previous)
		var last: Vector3 = path.call(time)
		if center.is_finite() and not first.is_equal_approx(last):
			var point := Geometry3D.get_closest_point_to_segment(center,first,last)
			var gap := point.distance_to(center)
			if not hand_setting and not low_save.active and gap > PLATFORM_RADIUS and gap <= 0.58:
				reach_platform(point-center)
				center = platform_center()
				point = Geometry3D.get_closest_point_to_segment(center,first,last)
			var timing := (cue_arrival if is_finite(cue_arrival) and not low_save.active else time)-pressed_at
			var green := timing >= GREEN_START and timing <= GREEN_END
			var assisted := green and not hand_setting and not low_save.active and point.distance_to(center) > radius and close_body_contact(point,center)
			var gap_after_adjustment := point.distance_to(center)
			var from_setter := point-setter.global_position
			var hand_assisted := (
				hand_setting and green and gap_after_adjustment > radius
				and gap_after_adjustment <= radius+HandPose.GREEN_CONTACT_ALLOWANCE
				and from_setter.slide(Vector3.UP).length() <= 0.80
				and absf(point.y-center.y) <= 0.32
			)
			contact_check = {
				"time":time,"surface":"hands" if hand_setting else ("palm" if pancake else "forearms"),"surface_center":center,
				"ball_point":point,"gap_before_adjustment":gap,"gap":gap_after_adjustment,
				"radius":cutoff,"base_radius":radius,"dive_allowance":allowance,
				"margin":gap_after_adjustment-cutoff,"assist":assisted or hand_assisted,"hand_assist":hand_assisted,
				"accepted":assisted or hand_assisted or gap_after_adjustment <= cutoff,
			}
			if contact_check.accepted:
				touch_time = lerpf(previous,time,first.distance_to(point)/first.distance_to(last))
				touch = point
				if not is_finite(cue_arrival) or low_save.active: timing = touch_time-pressed_at
				if assisted: reach_platform(point-center)
				grade = Timing.Grade.LATE if timing < GREEN_START else (Timing.Grade.EARLY if timing > GREEN_END else Timing.Grade.PERFECT)
				var error := timing_error(timing)*(Timing.PANCAKE_ERROR_SCALE if pancake else 1.0)
				contact_spread = Timing.practice_spread(error)
				contact_destination = destination
				if hand_setting:
					begin_hand_contact(touch,touch_time,error)
				elif pancake:
					outgoing = Timing.pancake_pop(incoming)
					var target := Timing.pancake_target(touch,outgoing)
					contact_destination = target.position
					if error > 0.0: outgoing = Timing.aimed_pass_velocity(touch,target,45.0,error)
				else: outgoing = aim_velocity(touch,error)
				if not hand_setting:
					floor_time = Flight.landing_time(touch,outgoing)
					net_hit = Net.first_hit(func(t): return flight_point(touch,outgoing,t),0.0,floor_time)
					if not net_hit.is_empty(): floor_time = net_hit.end_time
	elif attempted and grade == Timing.Grade.WAITING and time >= end:
		grade = Timing.Grade.MISS
	if low_save.active and not striking and not low_save.finished(time):
		low_save.sample(setter,time,touch_time if is_finite(touch_time) else low_save.contact_time+0.07)
	elif is_finite(touch_time) and not low_save.active:
		var follow := time-touch_time
		if catch_only:
			HandPose.apply(setter,setter.to_global(hand_anchor),1.0)
		elif hand_setting:
			update_hand_push(time,follow)
		elif not hand_setting and follow > 0.0 and follow < 0.36:
			var blend := 1.0-smoothstep(0.12,0.36,follow)
			apply_pose(contact_frame+follow,blend)
			pose_reach(smoothstep(0.0,1.0,reach_progress)*(1.0-smoothstep(0.06,0.32,follow)),touch)
			Drive.apply(setter.skeleton,setter.get_pose_author(),outgoing,Drive.effort(incoming,outgoing),follow,true,incoming,Drive.swing_effort(touch,outgoing))
	var recent_touch := is_finite(touch_time) and time-touch_time <= BallTimingRing.RESULT_DURATION
	if not catch_only and ((grade == Timing.Grade.WAITING and progress >= 0.0) or recent_touch):
		var anticipated := (1.0-maxf(progress,0.0))*APPROACH_TIME
		if is_finite(pressed_at): anticipated += time-pressed_at
		var spread := contact_spread if is_finite(touch_time) else Timing.practice_spread(timing_error(anticipated))
		var target := contact_destination if is_finite(touch_time) else destination
		cone.show_spread(touch if is_finite(touch_time) else ready_contact(),Vector3(target.x,0.075,target.y),spread)
	else:
		cone.hide()

func begin_hand_contact(point: Vector3, time: float, error := 0.0) -> void:
	touch = point
	touch_time = time
	hand_anchor = setter.to_local(point)
	if catch_only: return
	outgoing = aim_velocity(touch,error)
	var endpoint := flight_point(touch,outgoing,Flight.landing_time(touch,outgoing))
	hand_target = {"position":Vector2(endpoint.x,endpoint.z),"height":touch.y+outgoing.y*outgoing.y/(2.0*Flight.GRAVITY),"fit":"height"}

func hand_release_delay() -> float:
	return 0.078 if quick_hand_receive else HandPose.RELEASE_TIME

func update_hand_push(time: float, follow: float) -> void:
	if follow >= 0.32 and is_finite(release_time): return
	var delay := hand_release_delay()
	var scale_ := delay/HandPose.RELEASE_TIME
	var cushion := smoothstep(0.0,0.045*scale_,follow)*(1.0-smoothstep(0.045*scale_,0.11*scale_,follow))
	var extension := smoothstep(0.045*scale_,delay,follow)
	var force := smoothstep(4.0,10.0,outgoing.length())
	var push := outgoing.normalized()*lerpf(0.12,0.33,force)*extension
	var blend := 1.0-smoothstep(0.17,0.32,follow)
	HandPose.apply(setter,setter.to_global(hand_anchor),blend,push,cushion)
	if follow >= delay and not is_finite(release_time):
		release_time = time
		release_point = platform_center()
		outgoing = Flight.target_velocity(release_point,hand_target,45.0)
		floor_time = Flight.landing_time(release_point,outgoing)
		net_hit = Net.first_hit(func(t): return flight_point(release_point,outgoing,t),0.0,floor_time)
		if not net_hit.is_empty(): floor_time = net_hit.end_time

func close_body_contact(point: Vector3, platform: Vector3) -> bool:
	# Give green timing a little forgiveness on balls dropping inside the stance.
	var from_body := point-setter.global_position
	return from_body.slide(Vector3.UP).length() <= 0.42 and absf(point.y-platform.y) <= 0.23 and point.distance_to(platform) <= 0.78

func timing_error(elapsed: float) -> float:
	if elapsed < GREEN_START: return clampf((GREEN_START-elapsed)/GREEN_START,0.0,1.0)
	return clampf((elapsed-GREEN_END)/(MAX_EARLY_ERROR_TIME-GREEN_END),0.0,1.0)

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
		setter.position = Court.clamp_setter(next)
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
