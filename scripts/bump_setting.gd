extends MeshInstance3D

const FRONT_LUNGE_STEP = preload("res://assets/animations/front_lunge_step.tres")
const FRONT_LUNGE_ARMS = preload("res://assets/animations/front_lunge_arms.tres")
const ReachPose = preload("res://scripts/forearm_reach_pose.gd")

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
const BallTimingRing = preload("res://scripts/ball_timing_ring.gd")
const LowSave = preload("res://scripts/player_reception_save.gd")
const Accuracy = preload("res://scripts/reception_accuracy.gd")
const SpreadCone = preload("res://scripts/reception_spread_cone.gd")
const GREEN_START := 0.035
const GREEN_END := 0.37
const APPROACH_TIME := 0.60
const PLATFORM_PREP_TIME := 0.26
const FOREARM_RECOVERY_TIME := 0.47

var setter: Node3D
var hand_setting := false
var passing_skill_override := -1.0
var setting_skill_override := -1.0
var quick_hand_receive := false
var defensive_hand_dig := false
var hard_dig := false
var fast_hand_dig := false
var fast_back_receive := false
var rushed_cpu_receive := false
var early_dig_arms: Dictionary = {}
var back_receive_steer := Vector3.ZERO
var allow_auto_dive := true
var tracked_hand_dig := Vector3.INF
var catch_only := false
var catch_airborne := false
var setter_jumping := false
var clip: Animation
var contact_frame: float
var tracks: Array[Vector2i] = []
var custom_backward: Animation
var custom_backward_tracks: Array[Vector2i] = []
var custom_backward_time := 0.0
var ready_pose: Array[Transform3D] = []
var reach := {}
var reach_step := Vector3.ZERO
var reach_travel := Vector3.ZERO
var rear_setup := Vector3.ZERO
var rear_setup_travel := Vector3.ZERO
var rear_follow := 0.0
var reach_progress := 0.0
var destination := Vector2(2.75,3.0)
var height := 3.8
var green_start := GREEN_START
var green_end := GREEN_END
var green_forearm_allowance := 0.0
var green_hand_allowance := 0.0
var grade := Timing.Grade.WAITING
var pressed_at := -INF
var low_save := LowSave.new()
var previous_dig_pose := PackedVector3Array()
var quick_low_save := false
var emergency_low_save := false
var low_save_approach_velocity := Vector3.ZERO
var allow_pancake := true
var pancake_requires_chase := false
var entry_pose: Array[Transform3D] = []
var entry_duration := 0.065
var entry_time := -INF
var reach_changed_at := -INF
var pose_started_at := -INF
var cone: MeshInstance3D
var contact_check := {}
var approach_progress := -1.0
var contact_spread := Vector2.ZERO
var forearm_setting := false
var knee_bend_depth := 0.0
var ready_knee_bend_depth := 0.0
var lunge_bend_depth := 0.0
var defense_ground_y := 0.0
var contact_destination := Vector2.ZERO
var touch_time := -INF
var touch: Vector3
var hand_anchor: Vector3
var hand_catch_from := Vector3.INF
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
	tracks = animation_tracks(clip)
	for bone in rig.get_bone_count():
		var track := tracks[bone]
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

func animation_tracks(animation: Animation) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var rig: Skeleton3D = setter.skeleton
	for bone in rig.get_bone_count():
		var path := NodePath("Armature/Skeleton3D:"+rig.get_bone_name(bone))
		result.append(Vector2i(animation.find_track(path,Animation.TYPE_POSITION_3D),animation.find_track(path,Animation.TYPE_ROTATION_3D)))
	return result

func set_custom_backward(animation: Animation) -> void:
	custom_backward = animation
	if animation != null: custom_backward_tracks = animation_tracks(animation)

func reset() -> void:
	early_dig_arms.clear()
	hard_dig = false
	fast_hand_dig = false
	fast_back_receive = false
	rushed_cpu_receive = false
	back_receive_steer = Vector3.ZERO
	entry_pose.clear()
	reach_changed_at = -INF
	previous_dig_pose.clear()
	tracked_hand_dig = Vector3.INF
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
	var distance := (ball_position-to_local(setter.global_position)).slide(Vector3.UP).length()
	if distance > 1.15: return 1.0
	# Let the reception step own the last part of the approach.
	var lead := arrival-time
	var brake := smoothstep(-0.11,-0.025,lead)*(1.0-smoothstep(0.025,0.16,lead))
	return 1.0-brake

func platform_center() -> Vector3:
	if hand_setting: return to_local(HandPose.contact_center(setter))
	var rig: Skeleton3D = setter.skeleton
	var elbows := []
	var wrists := []
	for side in ["l","r"]:
		elbows.append(rig.to_global(rig.get_bone_global_pose(rig.find_bone("lowerarm_"+side)).origin))
		wrists.append(rig.to_global(rig.get_bone_global_pose(rig.find_bone("hand_"+side)).origin))
	return to_local(Contact.surface(elbows,wrists,0.055).ball)

func hand_dig_face() -> Vector3:
	var rig: Skeleton3D = setter.skeleton
	var head := rig.to_global(rig.get_bone_global_pose(rig.find_bone("Head")).origin)
	return to_local(head+Vector3.UP*0.07)

func hand_dig_height(origin: Vector3, speed: float) -> float:
	return maxf(height+0.55*smoothstep(10.0,28.0,speed),origin.y+0.72)

func ready_contact() -> Vector3:
	if hand_setting and defensive_hand_dig: return hand_dig_face()+global_basis.inverse()*setter.global_basis.z.normalized()*0.30
	if hand_setting: return to_local(setter.to_global(Vector3(0,HandPose.CONTACT_HEIGHT,HandPose.CONTACT_FORWARD)))
	return to_local(setter.to_global(Vector3(0,1.04,0.62)))

func contact_radius() -> float:
	return HandPose.CONTACT_RADIUS if hand_setting else PLATFORM_RADIUS

func hand_intercept(path: Callable, time: float, end: float) -> Vector3:
	var current: Vector3 = path.call(time)
	var next: Vector3 = path.call(minf(time+0.16,end))
	var center := ready_contact()
	if current.is_equal_approx(next): return center
	var nearest := Geometry3D.get_closest_point_to_segment(center,current,next)
	return center+(nearest-center).limit_length(0.50)

func track_hand_dig(path: Callable, time: float, end: float, delta: float) -> Vector3:
	var facing := setter.global_basis.orthonormalized()
	var face := hand_dig_face()
	var origin := to_global(face)
	var start: Vector3 = path.call(time)
	var finish: Vector3 = path.call(minf(time+0.13,end))
	var center := ready_contact()
	var target := Geometry3D.get_closest_point_to_segment(center,start,finish)
	var offset := facing.inverse()*(to_global(target)-origin)
	var overhead := offset.y > 0.18
	offset = offset.clamp(Vector3(-0.26,-0.19,0.05 if overhead else 0.18),Vector3(0.26,0.43,0.50))
	if not tracked_hand_dig.is_finite(): tracked_hand_dig = Vector3(0.0,0.0,0.30)
	tracked_hand_dig = tracked_hand_dig.lerp(offset,1.0-exp(-delta*34.0))
	return to_local(origin+facing*tracked_hand_dig)

func aim_velocity(origin: Vector3, spread := Vector2.ZERO) -> Vector3:
	return Accuracy.pass_velocity(origin,{"position":destination,"fit":"height","height":height},45.0,spread,uses_set_accuracy())

func uses_set_accuracy() -> bool:
	return not defensive_hand_dig and (forearm_setting or (hand_setting and not quick_hand_receive))

func accuracy_bounds(error: float, incoming: Vector3, spin_rps: float) -> Vector2:
	var setting := uses_set_accuracy()
	var skill := StorySession.setting_skill if setting else (StorySession.hand_reception_skill if hand_setting else StorySession.forearm_reception_skill)
	var override := setting_skill_override if setting else passing_skill_override
	if override >= 0.0: skill = override
	var bounds := Accuracy.spread(error,incoming.length(),spin_rps,skill,setting)
	if hand_setting and defensive_hand_dig: bounds = bounds*1.32+Vector2(0.30,0.25)
	if hard_dig:
		var pace := smoothstep(4.0,38.0,incoming.length())
		bounds = bounds.min(Vector2(3.40,2.30))*1.25+Vector2(0.75,0.50)+Vector2(3.60,1.95)*pace
		if low_save.active and not low_save.wide_arm.is_empty():
			bounds = bounds*1.30+Vector2(0.85,0.60)
		if not hand_setting and not setting:
			# Skilled passers absorb pace without removing timing or spin error.
			var control := smoothstep(55.0,100.0,skill)
			bounds = bounds.lerp(Accuracy.spread(error,incoming.length(),spin_rps,skill,false)*0.65+Vector2(0.25,0.18),control)
	if fast_hand_dig: bounds = bounds.max(Vector2(6.0,4.0))*1.5
	return bounds

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

func apply_knee_bend(time := INF) -> void:
	if knee_bend_depth <= 0.001 or low_save.active: return
	var rig: Skeleton3D = setter.skeleton
	var author: RefCounted = setter.get_pose_author()
	var pose: Array[Transform3D] = []
	for bone in rig.get_bone_count(): pose.append(rig.get_bone_pose(bone))
	var pelvis := rig.find_bone("pelvis")
	var parent: Transform3D = author.world_pose(pose,rig.get_bone_parent(pelvis))
	var feet: Array[Transform3D] = []
	var floor_targets: Array[Vector3] = []
	var knee_poles: Array[Vector3] = []
	var hips_across: Vector3 = (author.point(pose,"thigh_l")-author.point(pose,"thigh_r")).normalized()
	var requested_depth := knee_bend_depth
	if reach.get("tier",0) == 2:
		var recovery := 1.0-smoothstep(0.04,0.35,time-touch_time) if is_finite(touch_time) else clampf(knee_bend_depth/maxf(0.001,ready_knee_bend_depth),0.0,1.0)
		requested_depth += lunge_bend_depth*smoothstep(0.28,0.88,reach_progress)*recovery
	var depth := requested_depth
	for side in ["l","r"]:
		var foot: Transform3D = author.world_pose(pose,rig.find_bone("foot_"+side))
		var hip: Vector3 = author.point(pose,"thigh_"+side)
		var knee: Vector3 = author.point(pose,"calf_"+side)
		feet.append(foot)
		var world_foot := rig.to_global(foot.origin)
		if defensive_hand_dig:
			var is_lead: bool = not reach.is_empty() and side == reach.lead
			var step_lift := 0.08*sin(PI*reach_progress) if is_lead else 0.0
			world_foot.y = clampf(world_foot.y,defense_ground_y,defense_ground_y+step_lift)
		floor_targets.append(rig.to_local(world_foot))
		var axis := (foot.origin-hip).normalized()
		var pole := (knee-hip).slide(axis)
		var forward := Vector3(0.16 if side == "l" else -0.16,0.0,1.0)
		knee_poles.append(forward if pole.length_squared() < 0.0004 else pole.normalized())
		var world_hip := rig.to_global(hip)
		# Limit the extra drop for a leg already deeply compressed by the directional clip.
		depth = minf(depth,maxf(0.0,world_hip.y-world_foot.y-0.40))
	if depth <= 0.001: return
	if defensive_hand_dig:
		var separation := (floor_targets[0]-floor_targets[1]).dot(hips_across)
		var correction := maxf(0.0,0.16-separation)*0.5
		floor_targets[0] += hips_across*correction
		floor_targets[1] -= hips_across*correction
	var changed_bones: Array[int] = [pelvis]
	pose[pelvis].origin += parent.basis.inverse()*rig.global_basis.inverse()*(Vector3.DOWN*depth)
	for index in 2:
		var side := "l" if index == 0 else "r"
		var thigh := "thigh_"+side
		var calf := "calf_"+side
		var foot := "foot_"+side
		for joint in [thigh,calf,foot]:
			var bone := rig.find_bone(joint)
			changed_bones.append(bone)
		var hip: Vector3 = author.point(pose,thigh)
		var target := floor_targets[index]
		if defensive_hand_dig:
			var knee: Vector3 = author.point(pose,calf)
			var ankle: Vector3 = author.point(pose,foot)
			var length := hip.distance_to(knee)+knee.distance_to(ankle)-0.002
			var height := target.y-hip.y
			var span := sqrt(maxf(0.0,length*length-height*height))
			target = hip+(target-hip).slide(Vector3.UP).limit_length(span)+Vector3.UP*height
		var axis := (target-hip).normalized()
		var pole := ReachPose.outward_knee_pole(knee_poles[index],axis,hips_across if index == 0 else -hips_across)
		author.limb(pose,thigh,calf,foot,target,pole)
		author.set_world_basis(pose,foot,feet[index].basis)
	for bone in changed_bones:
		rig.set_bone_pose_position(bone,pose[bone].origin)
		rig.set_bone_pose_rotation(bone,pose[bone].basis.orthonormalized().get_rotation_quaternion().normalized())

func dig_bones() -> PackedVector3Array:
	var rig: Skeleton3D = setter.skeleton
	var points := PackedVector3Array()
	for side in ["l","r"]:
		for part in ["lowerarm_","hand_","middle_03_"]:
			var bone := rig.find_bone(part+side)
			points.append(to_local(rig.to_global(rig.get_bone_global_pose(bone).origin)))
	return points

func dig_contact_segment(first: Vector3, last: Vector3, pancake := false, start_pose := PackedVector3Array(), end_pose := PackedVector3Array()) -> PackedVector3Array:
	if end_pose.is_empty(): end_pose = dig_bones()
	if start_pose.is_empty(): start_pose = end_pose
	var closest := PackedVector3Array([first,Vector3.INF])
	var gap := INF
	var samples := 1 if start_pose == end_pose else 5
	for sample in samples:
		var start := float(sample)/samples
		var finish := float(sample+1)/samples
		var phase := (start+finish)*0.5
		var before := first.lerp(last,start)
		var after := first.lerp(last,finish)
		for side in range(1 if pancake else 0,2):
			if low_save.active and not low_save.wide_arm.is_empty() and side != (0 if low_save.wide_arm == "l" else 1): continue
			for index in range(1 if hand_setting or pancake else 0,2):
				var joint := side*3+index
				var from := start_pose[joint].lerp(end_pose[joint],phase)
				var to := start_pose[joint+1].lerp(end_pose[joint+1],phase)
				var pair := Geometry3D.get_closest_points_between_segments(before,after,from,to)
				var distance := pair[0].distance_squared_to(pair[1])
				if distance < gap:
					gap = distance
					closest = pair
	return closest

func begin_dig_transition(time: float, duration := 0.065) -> void:
	entry_duration = duration
	entry_pose.clear()
	entry_time = time
	for bone in setter.skeleton.get_bone_count(): entry_pose.append(setter.skeleton.get_bone_pose(bone))

func blend_dig_transition(time: float) -> void:
	if entry_pose.is_empty(): return
	var weight := smoothstep(0.0,entry_duration,time-entry_time)
	if weight >= 1.0:
		entry_pose.clear()
		return
	var rig: Skeleton3D = setter.skeleton
	for bone in entry_pose.size():
		var pose := entry_pose[bone].interpolate_with(rig.get_bone_pose(bone),weight)
		rig.set_bone_pose_position(bone,pose.origin)
		rig.set_bone_pose_rotation(bone,pose.basis.orthonormalized().get_rotation_quaternion())

func update_attempt(time: float, previous: float, end: float, path: Callable, incoming: Vector3, delta: float, cue_arrival := INF, spin_rps := 0.0, dig_cue := INF) -> void:
	contact_check.clear()
	var progress := approach(path,time,end) if grade == Timing.Grade.WAITING else -1.0
	approach_progress = progress
	var attempted := is_finite(pressed_at)
	var face_dig := hand_setting and defensive_hand_dig
	var strict_dig := is_finite(dig_cue)
	var initial_pose := previous_dig_pose
	if strict_dig and attempted and initial_pose.is_empty(): initial_pose = dig_bones()
	if attempted and grade == Timing.Grade.WAITING:
		var start_dig := strict_dig and (not hand_setting or time >= dig_cue-0.19)
		var start_jump_set := setter_jumping and hand_setting and not face_dig
		var was_diving := low_save.active
		if allow_auto_dive and not hand_setting and not setter_jumping and (reach.is_empty() or quick_low_save):
			low_save.plan(setter,path,time,end,clip,quick_low_save,allow_pancake,pancake_requires_chase,low_save_approach_velocity,emergency_low_save)
		if low_save.active and not was_diving:
			begin_dig_transition(time-delta,clampf(low_save.contact_time-time,delta,0.13))
		if not low_save.active and not is_finite(pose_started_at) and (start_dig or start_jump_set or progress >= 1.0-PLATFORM_PREP_TIME/APPROACH_TIME):
			var platform_in_range := true
			if strict_dig and quick_low_save and not hand_setting:
				var intercept: Vector3 = path.call(clampf(dig_cue,time,end))
				platform_in_range = (intercept-setter.position).slide(Vector3.UP).length() <= 1.35
			if platform_in_range and (not fast_back_receive or time >= dig_cue-0.14):
				pose_started_at = maxf(pressed_at,time-delta)
				if strict_dig and not hand_setting:
					begin_dig_transition(time-delta,clampf(dig_cue-time,delta,0.13))
	var elapsed := time-pose_started_at
	var striking := attempted and grade == Timing.Grade.WAITING and (low_save.active or is_finite(pose_started_at)) and (time < end or (strict_dig and previous < end)) and (not catch_only or catch_airborne)
	if striking:
		if hand_setting:
			apply_knee_bend(time)
			var target := track_hand_dig(path,time,end,delta) if face_dig else hand_intercept(path,time,end)
			var lift_time := 0.048 if face_dig else (0.062 if quick_hand_receive else (0.155 if setter_jumping else 0.105))
			HandPose.apply(setter,to_global(target),smoothstep(0.0,lift_time,elapsed),Vector3.ZERO,0.0,0.0,face_dig,-(global_basis*incoming))
		elif low_save.active:
			var intercept := Vector3.INF
			if low_save.tracks_platform:
				var aim_time := minf(end,clampf(time+0.025,low_save.contact_time-0.055,low_save.contact_time+0.025))
				intercept = path.call(aim_time)
				if low_save.wide_arm.is_empty() and time < low_save.contact_time-0.07:
					var local := setter.basis.inverse()*(intercept-setter.position)
					if absf(local.x) > 0.64 and local.z > -0.38 and absf(local.x) > absf(local.z)*0.92:
						begin_dig_transition(time)
						low_save.wide_arm = setter.animation_side("l" if local.x > 0.0 else "r")
				if not low_save.wide_arm.is_empty():
					# On a fast spike, aiming ahead by a full frame can put the arm past the ball.
					var lead := minf(0.025,0.14/maxf(0.01,incoming.length()))
					intercept = path.call(minf(end,clampf(time+lead,low_save.contact_time-0.055,low_save.contact_time+lead)))
			low_save.sample(setter,time,low_save.contact_time+0.07,intercept)
		else:
			var pose_time := 0.045 if strict_dig else 0.09
			var windup := 0.0 if rushed_cpu_receive else lerpf(-0.14,0.0,smoothstep(0.0,pose_time,elapsed))
			apply_pose(contact_frame+windup,smoothstep(0.0,pose_time,elapsed))
			if not setter_jumping:
				var intercept := advance_reach(path,time,end,delta,is_finite(dig_cue))
				if reach.has("custom_clip"):
					var contact := float(custom_backward.get_meta("contact_time"))
					custom_backward_time = lerpf(maxf(0.0,contact-0.50),contact,smoothstep(0.0,0.85,reach_progress))
					apply_custom_backward(custom_backward_time,smoothstep(0.0,0.32,reach_progress))
				else:
					pose_reach(smoothstep(0.0,1.0,reach_progress),intercept)
		if not hand_setting: apply_knee_bend(time)
		blend_dig_transition(time)
		var keep_platform_low := rushed_cpu_receive and not hand_setting and not low_save.active and not reach.has("custom_clip")
		if keep_platform_low: lower_rushed_platform()
		var hold_arms := rushed_cpu_receive and not hand_setting and not low_save.active and not reach.has("custom_clip") and time > 12.0/60.0+0.00001 and time <= 15.0/60.0+0.00001
		if hold_arms: restore_early_dig_arms()
		var pancake := low_save.active and low_save.pancake
		var center := to_local(LowSave.palm_center(setter)) if pancake else platform_center()
		var radius := 0.16 if pancake else (0.33 if face_dig else contact_radius())
		var near_dive_contact := low_save.active and not pancake and absf(time-low_save.contact_time)<=0.12
		var allowance := DIVE_CONTACT_ALLOWANCE if near_dive_contact else 0.0
		var cutoff := radius+allowance
		var sweep_start := maxf(previous,pressed_at) if strict_dig else previous
		var sweep_end := minf(time,end) if strict_dig else time
		var first: Vector3 = path.call(sweep_start)
		var last: Vector3 = path.call(sweep_end)
		if (center.is_finite() or strict_dig) and sweep_start < sweep_end and (strict_dig or not first.is_equal_approx(last)):
			if not center.is_finite(): center = first
			var point := Geometry3D.get_closest_point_to_segment(center,first,last)
			var gap := point.distance_to(center)
			if not strict_dig and not hand_setting and not low_save.active and gap > PLATFORM_RADIUS and gap <= 0.58:
				reach_platform(point-center)
				center = platform_center()
				point = Geometry3D.get_closest_point_to_segment(center,first,last)
			var timing := (cue_arrival if is_finite(cue_arrival) and not low_save.active else time)-pressed_at
			var green := timing >= green_start and timing <= green_end
			if strict_dig:
				previous_dig_pose = dig_bones()
				var contact := dig_contact_segment(first,last,pancake,initial_pose,previous_dig_pose)
				point = contact[0]
				center = contact[1]
				cutoff = Net.RADIUS+(0.04 if hand_setting or pancake else 0.05)
				if near_dive_contact and low_save.wide_arm.is_empty(): cutoff += 0.015
				if not hand_setting and not low_save.active and not hold_arms:
					# Bring the platform toward the approaching ball, then test the posed bones again.
					var preview: Vector3 = path.call(minf(end,sweep_end+(0.025 if rushed_cpu_receive else 0.070)))
					var live_contact := dig_contact_segment(first,preview,false,previous_dig_pose,previous_dig_pose)
					var offset := live_contact[0]-live_contact[1]
					var steer := (1.0-smoothstep(0.40,0.74,offset.length()))*smoothstep(0.0,0.055,elapsed)
					if fast_back_receive or (steer > 0.0 and offset.length() > 0.07):
						var lift := clampf(-incoming.y*0.016,0.0,0.0 if rushed_cpu_receive else 0.16)
						var adjustment := offset*1.85+Vector3.UP*lift
						if rushed_cpu_receive: adjustment.y = minf(0.0,adjustment.y)
						if fast_back_receive:
							# Move the joined platform as a unit instead of snapping to each preview point.
							back_receive_steer = back_receive_steer.lerp(adjustment.limit_length(0.48)*steer,1.0-exp(-delta*30.0))
							reach_platform(back_receive_steer,smoothstep(0.0,0.055,elapsed),0.48)
						else:
							reach_platform(adjustment,steer,0.54,true)
						if keep_platform_low: lower_rushed_platform()
						previous_dig_pose = dig_bones()
						contact = dig_contact_segment(first,last,false,initial_pose,previous_dig_pose)
						point = contact[0]
						center = contact[1]
			if rushed_cpu_receive and not hand_setting and not low_save.active and time <= 12.0/60.0+0.00001:
				capture_early_dig_arms()
			var gap_after_adjustment := point.distance_to(center)
			var receive_allowance := (0.0 if face_dig else green_hand_allowance) if hand_setting else green_forearm_allowance
			var near_receive := green and not low_save.active and receive_allowance > 0.0 and gap_after_adjustment <= radius+receive_allowance
			var assisted := not strict_dig and green and not hand_setting and not low_save.active and gap_after_adjustment > radius and (near_receive or close_body_contact(point,center))
			var from_setter := point-to_local(setter.global_position)
			var hand_assisted := (
				not strict_dig and hand_setting and not face_dig and green and gap_after_adjustment > radius
				and (near_receive or (
					gap_after_adjustment <= radius+HandPose.GREEN_CONTACT_ALLOWANCE
					and from_setter.slide(Vector3.UP).length() <= 0.80
					and absf(point.y-center.y) <= 0.32
				))
			)
			var face_aligned := true
			if face_dig and not strict_dig:
				var facing := setter.global_basis.orthonormalized()
				var offset := facing.inverse()*global_basis*(point-hand_dig_face())
				var approach_velocity := facing.inverse()*global_basis*incoming
				var in_front := absf(offset.y) <= 0.28 and offset.z >= 0.05 and approach_velocity.z < -0.2
				face_aligned = absf(offset.x) <= 0.29 and offset.z <= 0.68 and in_front
			contact_check = {
				"time":time,"surface":"hands" if hand_setting else ("palm" if pancake else "forearms"),"surface_center":center,
				"ball_point":point,"gap_before_adjustment":gap,"gap":gap_after_adjustment,
				"radius":cutoff,"base_radius":radius,"dive_allowance":allowance,
				"margin":gap_after_adjustment-cutoff,"assist":assisted or hand_assisted,"hand_assist":hand_assisted,
				"accepted":face_aligned and (assisted or hand_assisted or gap_after_adjustment <= cutoff),
			}
			if contact_check.accepted:
				var fraction := first.distance_to(point)/maxf(0.00001,first.distance_to(last))
				touch_time = lerpf(sweep_start,sweep_end,clampf(fraction,0.0,1.0))
				touch = point
				if not is_finite(cue_arrival) or low_save.active: timing = touch_time-pressed_at
				if assisted: reach_platform(point-center)
				grade = Timing.Grade.LATE if timing < green_start else (Timing.Grade.EARLY if timing > green_end else Timing.Grade.PERFECT)
				var error := timing_error(timing)*(Timing.PANCAKE_ERROR_SCALE if pancake else 1.0)
				contact_spread = accuracy_bounds(error,incoming,spin_rps)
				contact_destination = destination
				if face_dig:
					hand_anchor = setter.to_local(to_global(touch))
					release_time = touch_time
					release_point = touch
					outgoing = Accuracy.pass_velocity(touch,{"position":destination,"fit":"height",
						"height":hand_dig_height(touch,incoming.length()),"minimum_height":touch.y+0.32},45.0,contact_spread)
				elif hand_setting:
					begin_hand_contact(touch,touch_time,contact_spread)
				elif pancake:
					outgoing = Timing.pancake_pop(incoming)
					var target := Timing.pancake_target(touch,outgoing)
					contact_destination = target.position
					outgoing = Accuracy.pass_velocity(touch,target,45.0,contact_spread)
				else: outgoing = aim_velocity(touch,contact_spread)
				if not hand_setting or face_dig:
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
		elif face_dig:
			if follow >= 0.0 and follow < 0.22:
				var relax := 1.0-smoothstep(0.035,0.22,follow)
				var recoil := smoothstep(0.0,0.035,follow)*(1.0-smoothstep(0.035,0.13,follow))
				var push := (global_basis*outgoing).normalized()*0.08*recoil
				HandPose.apply(setter,setter.to_global(hand_anchor),relax,push,recoil,0.0,true,-(global_basis*incoming))
		elif hand_setting:
			# The airborne receiving pose already owns the contact frame.
			if not (setter_jumping and striking): update_hand_push(time,follow)
		else:
			follow_forearm(time,incoming)
	if not striking: apply_knee_bend(time)
	var recent_touch := is_finite(touch_time) and time-touch_time <= BallTimingRing.RESULT_DURATION
	if not catch_only and ((grade == Timing.Grade.WAITING and progress >= 0.0) or recent_touch):
		var anticipated := (1.0-maxf(progress,0.0))*APPROACH_TIME
		if attempted:
			anticipated = cue_arrival-pressed_at if is_finite(cue_arrival) and not low_save.active else anticipated+time-pressed_at
		var spread := contact_spread if is_finite(touch_time) else accuracy_bounds(timing_error(anticipated),incoming,spin_rps)
		var target := contact_destination if is_finite(touch_time) else destination
		var source := touch if is_finite(touch_time) else ready_contact()
		var apex := hand_dig_height(source,incoming.length()) if face_dig else height
		var ideal := Flight.target_velocity(source,{"position":target,"fit":"height","height":apex},45.0)
		var peak := flight_point(source,ideal,ideal.y/Flight.GRAVITY)
		var ground := to_global(Vector3(target.x,0.075,target.y))
		if uses_set_accuracy():
			cone.show_set_spread(to_global(source),ground,to_global(peak),spread,global_basis.z.normalized())
		else:
			cone.show_spread(to_global(source),ground,spread.x,to_global(peak),spread.y)
	else:
		cone.hide()

func begin_hand_contact(point: Vector3, time: float, spread := Vector2.ZERO) -> void:
	touch = point
	touch_time = time
	hand_anchor = setter.to_local(to_global(point))
	hand_catch_from = setter.to_local(HandPose.contact_center(setter)) if setter_jumping else Vector3.INF
	if catch_only: return
	outgoing = aim_velocity(touch,spread)
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
	var blend := 1.0-smoothstep(0.22,0.32,follow)
	var after_release := time-release_time if is_finite(release_time) else 0.0
	var torso_follow := smoothstep(0.0,0.10,after_release)
	var anchor := hand_anchor
	if setter_jumping and hand_catch_from.is_finite(): anchor = hand_catch_from.lerp(anchor,smoothstep(0.0,0.065,follow))
	HandPose.apply(setter,setter.to_global(anchor),blend,global_basis*push,cushion,torso_follow)
	if follow >= delay and not is_finite(release_time):
		release_time = time
		release_point = platform_center()
		outgoing = Flight.target_velocity(release_point,hand_target,45.0)
		floor_time = Flight.landing_time(release_point,outgoing)
		net_hit = Net.first_hit(func(t): return flight_point(release_point,outgoing,t),0.0,floor_time)
		if not net_hit.is_empty(): floor_time = net_hit.end_time

func close_body_contact(point: Vector3, platform: Vector3) -> bool:
	# Give green timing a little forgiveness on balls dropping inside the stance.
	var from_body := point-to_local(setter.global_position)
	return from_body.slide(Vector3.UP).length() <= 0.42 and absf(point.y-platform.y) <= 0.23 and point.distance_to(platform) <= 0.78

func timing_error(elapsed: float) -> float:
	return Accuracy.timing_error(elapsed,green_start,green_end)

func clear_reach() -> void:
	reach.clear()
	reach_step = Vector3.ZERO
	reach_travel = Vector3.ZERO
	reach_progress = 0.0
	rear_setup = Vector3.ZERO
	rear_setup_travel = Vector3.ZERO
	rear_follow = 0.0

func advance_reach(path: Callable, time: float, end: float, delta: float, quick_dig := false) -> Vector3:
	var intercept := Vector3.INF
	var lookahead := minf(time+0.30,end)
	if lookahead > time:
		var future: Vector3 = path.call(lookahead)
		var now: Vector3 = path.call(time)
		intercept = Geometry3D.get_closest_point_to_segment(ready_contact(),now,future)
		var offset := intercept-ready_contact()
		var direction := offset.slide(Vector3.UP)
		var planned: Vector3 = reach.get("intercept",Vector3.INF)
		var still_reachable := planned.is_finite() and Geometry3D.get_closest_point_to_segment(planned,path.call(maxf(0.0,time-delta)),future).distance_to(planned) <= contact_radius()
		if quick_dig and not still_reachable and not reach.is_empty() and time-reach_changed_at > 0.12 and direction.length() > 0.32 and reach_step.normalized().dot(direction.normalized()) < 0.48:
			begin_dig_transition(time)
			clear_reach()
			reach_changed_at = time
		if reach.is_empty() and (lookahead >= end or not intercept.is_equal_approx(future)):
			plan_reach(offset)
	if not reach.is_empty():
		var before := reach_progress
		var duration := 0.27 if reach.side_lunge and not rear_setup.is_zero_approx() else (0.19 if reach.tier == 2 else 0.15)
		if quick_dig and not rushed_cpu_receive and (reach.side_lunge or absf(reach_step.x) > 0.45): duration *= 0.68
		reach_progress = minf(1.0,reach_progress+delta/duration)
		var origin := setter.position
		var setup := rear_setup*(smoothstep(0.0,0.50,reach_progress)-smoothstep(0.0,0.50,before))
		setter.position = Court.clamp_setter(origin+setup)
		rear_setup_travel += setter.position-origin
		origin = setter.position
		var lateral_start := 0.28 if not rear_setup.is_zero_approx() else 0.0
		var travel := smoothstep(lateral_start,1.0,reach_progress)-smoothstep(lateral_start,1.0,before)
		setter.position = Court.clamp_setter(origin+reach_step*travel)
		reach_travel += setter.position-origin
	return intercept

func plan_reach(offset: Vector3) -> void:
	var local := setter.basis.inverse()*offset
	var horizontal := offset.slide(Vector3.UP)
	if offset.length() <= PLATFORM_RADIUS or horizontal.length() < 0.12: return
	var tier := Timing.practice_reach_tier(offset)
	if tier == 3: return
	var back := local.z < -absf(local.x)*0.65
	var straight_back := back and -local.z > absf(local.x)*1.4
	var short_back := tier == 1 and straight_back
	var rear_side := tier == 2 and back and not straight_back
	var forward := local.z > absf(local.x)*1.4
	var side := tier == 2 and absf(local.x) > absf(local.z)*1.4
	var intercept := ready_contact()+offset
	var lead := "r" if intercept.x <= 0.0 else "l"
	if rushed_cpu_receive:
		var rig: Skeleton3D = setter.skeleton
		var left := to_local(rig.to_global(rig.get_bone_global_pose(rig.find_bone("foot_"+setter.animation_side("l"))).origin))
		var right := to_local(rig.to_global(rig.get_bone_global_pose(rig.find_bone("foot_"+setter.animation_side("r"))).origin))
		lead = "l" if (left-intercept).slide(Vector3.UP).length_squared() < (right-intercept).slide(Vector3.UP).length_squared() else "r"
	reach = {
		"tier":tier,"back":back and not rear_side,"rear_diagonal":false,
		"intercept":intercept,
		"short_straight_back":short_back,"forward_lunge":forward,
		"lead":lead,"court_lead":true,
		"side_lunge":side or rear_side,"height":offset.y if tier == 2 else 0.0,
		"centered_back":straight_back,"backward":back,
	}
	var limit := 0.68 if side else (0.75 if tier == 2 else 0.46)
	reach_step = horizontal.limit_length(limit)*(1.0 if back and tier == 2 else 0.78)
	if rear_side:
		var forward_axis := setter.basis.z.normalized()
		rear_setup = forward_axis*clampf(horizontal.dot(forward_axis),-0.48,0.0)
		reach_step = horizontal.slide(forward_axis).limit_length(0.68)
	elif straight_back and tier == 2:
		rear_setup = reach_step.normalized()*minf(0.28,reach_step.length()*0.52)
		reach_step -= rear_setup
		if custom_backward != null: reach.custom_clip = custom_backward.resource_name

func backward_reach_active() -> bool:
	return reach.get("backward",false) and (grade == Timing.Grade.WAITING or (is_finite(touch_time) and rear_follow < 0.25))

func follow_forearm(time: float, incoming: Vector3) -> void:
	var follow := time-touch_time
	rear_follow = follow
	if follow <= 0.0 or follow >= FOREARM_RECOVERY_TIME: return
	var blend := 1.0-smoothstep(0.13,FOREARM_RECOVERY_TIME,follow)
	if reach.has("custom_clip"):
		apply_custom_backward(custom_backward_time+follow,blend)
		return
	apply_pose(contact_frame+follow,blend)
	pose_reach(smoothstep(0.0,1.0,reach_progress)*(1.0-smoothstep(0.10,0.40,follow)),touch)
	Drive.apply(setter.skeleton,setter.get_pose_author(),outgoing,Drive.effort(incoming,outgoing),follow,true,incoming,Drive.swing_effort(touch,outgoing))

func pose_reach(weight: float, intercept: Vector3) -> void:
	if reach.is_empty() or weight <= 0.0: return
	var local := setter.basis.inverse()
	var pose_progress := reach_progress
	if not rear_setup.is_zero_approx():
		pose_progress = clampf(inverse_lerp(0.28,1.0,reach_progress),0.0,1.0)
		var step_weight := smoothstep(0.0,0.30,reach_progress)*(1.0-smoothstep(0.30,0.62,reach_progress))
		if step_weight > 0.0:
			var shuffle := {"tier":1,"back":true,"rear_diagonal":false,"short_straight_back":true,
				"forward_lunge":false,"lead":reach.lead,"side_lunge":false,"height":0.0,"centered_back":true}
			setter.pose_reception_reach(local*rear_setup,local*rear_setup_travel,step_weight,
				clampf(reach_progress/0.50,0.0,1.0),ready_pose,shuffle,false,0,intercept)
		weight *= smoothstep(0.0,0.65,pose_progress)
	if weight > 0.0:
		var planted_travel := reach_travel
		if is_finite(touch_time): planted_travel *= 1.0-smoothstep(0.10,0.40,rear_follow)
		setter.pose_reception_reach(local*reach_step,local*planted_travel,weight,pose_progress,ready_pose,reach,false,0,intercept)

		if reach.get("forward_lunge",false) and reach.get("tier",0) == 2:
			var rig: Skeleton3D = setter.skeleton
			# Sample the edited foot lift and plant across the lunge, in place.
			var step_time := clampf(pose_progress,0.0,1.0)*FRONT_LUNGE_STEP.length
			for track in FRONT_LUNGE_STEP.get_track_count():
				var bone := rig.find_bone(FRONT_LUNGE_STEP.track_get_path(track).get_subname(0))
				var saved := FRONT_LUNGE_STEP.rotation_track_interpolate(track,step_time)
				rig.set_bone_pose_rotation(bone,rig.get_bone_pose_rotation(bone).slerp(saved,weight))
			for track in FRONT_LUNGE_ARMS.get_track_count():
				var bone := rig.find_bone(FRONT_LUNGE_ARMS.track_get_path(track).get_subname(0))
				var saved := FRONT_LUNGE_ARMS.rotation_track_interpolate(track,0.0)
				rig.set_bone_pose_rotation(bone,rig.get_bone_pose_rotation(bone).slerp(saved,weight))

func capture_early_dig_arms() -> void:
	var rig: Skeleton3D = setter.skeleton
	for side in ["l","r"]:
		for part in ["clavicle_","upperarm_","lowerarm_","hand_"]:
			var bone := rig.find_bone(part+side)
			early_dig_arms[bone] = rig.get_bone_pose(bone)

func restore_early_dig_arms() -> void:
	var rig: Skeleton3D = setter.skeleton
	for bone in early_dig_arms:
		var pose: Transform3D = early_dig_arms[bone]
		rig.set_bone_pose_position(bone,pose.origin)
		rig.set_bone_pose_rotation(bone,pose.basis.get_rotation_quaternion())

func lower_rushed_platform() -> void:
	var rig: Skeleton3D = setter.skeleton
	var left := rig.get_bone_global_pose(rig.find_bone("hand_l")).origin
	var right := rig.get_bone_global_pose(rig.find_bone("hand_r")).origin
	var hips := rig.get_bone_global_pose(rig.find_bone("pelvis")).origin
	var excess := rig.to_global((left+right)*0.5).y-rig.to_global(hips).y
	if excess > 0.0:
		reach_platform(Vector3.DOWN*excess,1.0,0.35)

func reach_platform(offset: Vector3, weight := 1.0, reach_limit := 0.26, steer_sideways := false) -> void:
	var rig: Skeleton3D = setter.skeleton
	var author: RefCounted = setter.get_pose_author()
	var pose: Array = []
	for bone in rig.get_bone_count(): pose.append(rig.get_bone_pose(bone))
	var grip: Vector3 = (author.point(pose,"hand_l")+author.point(pose,"hand_r"))*0.5
	var shift := rig.global_basis.inverse()*global_basis*offset.limit_length(reach_limit)
	var lateral := Vector3.RIGHT
	var target := grip+shift
	var weight_scale := 0.82
	if steer_sideways:
		var shoulders: Vector3 = (author.point(pose,"upperarm_l")+author.point(pose,"upperarm_r"))*0.5
		# Keep the platform in front of the ribcage even when the steering axis turns.
		target.z = maxf(target.z,shoulders.z+0.28/rig.global_basis.y.length())
		var reach_direction := target-shoulders
		var yaw := clampf(atan2(reach_direction.x,maxf(0.12,reach_direction.z)),-0.80,0.80)
		lateral = lateral.rotated(Vector3.UP,yaw)
		weight_scale = 1.0
	var compact: bool = fast_back_receive or reach.get("tier",0) == 2
	PlatformPose.connect_arms(pose,author,target,weight_scale*weight,0.0 if compact else 0.022,lateral,false,compact)
	for side in ["l","r"]:
		for part in ["upperarm_","lowerarm_","hand_"]:
			var bone := rig.find_bone(part+side)
			rig.set_bone_pose_rotation(bone,pose[bone].basis.get_rotation_quaternion())

func apply_custom_backward(time: float, weight: float) -> void:
	sample_pose(custom_backward,custom_backward_tracks,time,weight,true)

func apply_pose(time: float, weight: float) -> void:
	sample_pose(clip,tracks,time,weight,false)

func sample_pose(animation: Animation, pose_tracks: Array[Vector2i], time: float, weight: float, in_place: bool) -> void:
	var rig: Skeleton3D = setter.skeleton
	time = clampf(time,0.0,animation.length)
	for bone in pose_tracks.size():
		var track := pose_tracks[bone]
		if defensive_hand_dig and bone == 0: continue
		if track.x >= 0 and (not in_place or bone != 0):
			rig.set_bone_pose_position(bone,rig.get_bone_pose_position(bone).lerp(animation.position_track_interpolate(track.x,time),weight))
		if track.y >= 0:
			rig.set_bone_pose_rotation(bone,rig.get_bone_pose_rotation(bone).slerp(animation.rotation_track_interpolate(track.y,time),weight))
