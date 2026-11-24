extends Node3D
const Flight = preload("res://scripts/pass_flight.gd")
const Net = preload("res://scripts/net_collision.gd")
const Contact = preload("res://scripts/forearm_contact.gd")
signal contacted
signal net_contacted
const RADIUS := 0.105
var actor: Node3D
var clip: Animation
var edit_session: RefCounted
var contact_time := 0.6
var impact_point := Vector3.ZERO
var surface_point := Vector3.ZERO
var surface_normal := Vector3.UP
var surface_velocity := Vector3.ZERO
var incoming := Vector3(0,-5.5,-4.5)
var outgoing := Vector3.ZERO
var feed_duration := 1.3
var flight_duration := 1.0
var ball: MeshInstance3D
var audio: AudioStreamPlayer
var last_time := -1.0
var contact_count := 0
var active := false
var cached_revision := -1
var positions := {}
var rotations := {}
var guide: MeshInstance3D
var spread_cone: MeshInstance3D
var practice_aim_arc: MeshInstance3D
var last_aim_origin := Vector3.INF
var last_aim_velocity := Vector3.INF
var source_ball: MeshInstance3D
var source_ground: MeshInstance3D
var feed_valid := true
const Accuracy = preload("res://scripts/reception_accuracy.gd")
var feed_info := {}
var incoming_net := {}
var outgoing_net := {}
var missed := false
var practice_mode := false
var review_feed := {}
var practice_floor_time := 0.0
enum Grade { WAITING, PERFECT, EARLY, LATE, MISS, BODY_DIG }
const PANCAKE_ERROR_SCALE := 0.4
const GREEN_START := 0.075
const GREEN_END := 0.25
const APPROACH_WINDOW := 0.38
const RECEIVE_RADIUS := 0.25
const METER_NEAR_RADIUS := 0.90
var practice_grade := Grade.WAITING
var practice_in_reach := false
var practice_early_attempt := false
var practice_reach_center := Vector3.INF
var practice_forearms: Array[Vector3] = []
var aim_point := Vector3.ZERO
var net_audio: AudioStreamPlayer
var net_contact_count := 0
var has_last_time := false
var dynamic_net: Node3D
var recovery := {}
var recovery_net := {}

func _ready() -> void:
	ball = MeshInstance3D.new()
	ball.mesh = make_ball()
	var style := StandardMaterial3D.new()
	style.vertex_color_use_as_albedo = true
	style.roughness = 0.7
	style.cull_mode = BaseMaterial3D.CULL_DISABLED
	ball.material_override = style
	add_child(ball)
	audio = AudioStreamPlayer.new()
	audio.stream = AudioStreamWAV.load_from_file("res://assets/audio/pass_contact.wav")
	audio.volume_db = -7
	add_child(audio)
	net_audio = Net.contact_sound()
	add_child(net_audio)
	guide = MeshInstance3D.new()
	guide.top_level = true
	add_child(guide)
	guide.global_transform = Transform3D.IDENTITY
	guide.hide()
	spread_cone = preload("res://scripts/reception_spread_cone.gd").new()
	add_child(spread_cone)
	practice_aim_arc = MeshInstance3D.new()
	practice_aim_arc.name = "ProjectedPassArc"
	practice_aim_arc.top_level = true
	practice_aim_arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(practice_aim_arc)
	practice_aim_arc.global_transform = Transform3D.IDENTITY
	practice_aim_arc.mesh = ImmediateMesh.new()
	var aim_material := StandardMaterial3D.new()
	aim_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	aim_material.albedo_color = Color("8df3ff")
	practice_aim_arc.material_override = aim_material
	practice_aim_arc.hide()
	source_ball = MeshInstance3D.new()
	source_ball.name = "IncomingBall"
	source_ball.mesh = ball.mesh
	var ghost: StandardMaterial3D = style.duplicate()
	ghost.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost.albedo_color = Color(1,1,1,0.65)
	source_ball.material_override = ghost
	source_ball.scale = Vector3.ONE*2.0
	source_ball.top_level = true
	add_child(source_ball)
	source_ball.hide()
	source_ground = MeshInstance3D.new()
	source_ground.name = "SourceHandle"
	var ring := TorusMesh.new()
	ring.inner_radius = 0.30
	ring.outer_radius = 0.42
	source_ground.mesh = ring
	var ring_material := StandardMaterial3D.new()
	ring_material.albedo_color = Color("fff1ad")
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	source_ground.material_override = ring_material
	source_ground.top_level = true
	add_child(source_ground)
	source_ground.hide()
	hide()

const BALL_PALETTES := {
	"Baden": ["faf4e3", "ad2434", "202c55"],
	"Tachikara": ["f5efdf", "176659", "303e51"],
	"Mikasa": ["f5f1dd", "2e64b4", "efd13b"],
	"Molten": ["faf4e7", "cc293c", "196846"],
	"Wilson": ["f7ecdb", "d87625", "333638"]
}

static func make_ball(brand := "Mikasa") -> ArrayMesh:
	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	var colors: Array = BALL_PALETTES.get(brand,BALL_PALETTES["Mikasa"])
	for row in range(12):
		for column in range(24):
			var corners: Array[Vector3] = []
			for corner in [Vector2i(0,0),Vector2i(1,0),Vector2i(1,1),Vector2i(0,1)]:
				var latitude: float = -PI*0.5+PI*(row+corner.y)/12.0
				var longitude: float = TAU*(column+corner.x)/24.0
				corners.append(Vector3(cos(latitude)*cos(longitude),sin(latitude),cos(latitude)*sin(longitude)))
			var color: Color = Color(colors[(int(column/4)+int(row/4))%3])
			for index in [0,1,2,0,2,3]:
				mesh.set_color(color)
				mesh.set_normal(corners[index])
				mesh.add_vertex(corners[index]*RADIUS)
	return mesh.commit()

func configure(player: Node3D, animation: Animation, edits: RefCounted = null) -> void:
	if is_instance_valid(audio): audio.stop()
	if is_instance_valid(net_audio): net_audio.stop()
	actor = player
	dynamic_net = actor.get_parent().get_node_or_null("VolleyballCourt/DynamicNet")
	clip = animation
	edit_session = edits
	active = clip.has_meta("contact_time")
	contact_time = float(clip.get_meta("contact_time",0.6))
	last_time = -1
	has_last_time = false
	cached_revision = -1
	positions.clear()
	rotations.clear()
	var rig: Skeleton3D = actor.skeleton
	for bone in rig.get_bone_count():
		var path := NodePath("Armature/Skeleton3D:"+rig.get_bone_name(bone))
		positions[bone] = clip.find_track(path,Animation.TYPE_POSITION_3D)
		rotations[bone] = clip.find_track(path,Animation.TYPE_ROTATION_3D)
	if clip.has_meta("editor_ball_frames"):
		feed_duration = contact_time
		missed = false
	elif active: recalculate()
	else: stop()

func stop() -> void:
	active = false
	if is_instance_valid(dynamic_net): dynamic_net.sample({},0)
	last_time = -1
	has_last_time = false
	hide()
	if is_instance_valid(source_ball): source_ball.hide()
	if is_instance_valid(source_ground): source_ground.hide()
	if is_instance_valid(guide): guide.hide()
	if is_instance_valid(spread_cone): spread_cone.hide()
	if is_instance_valid(practice_aim_arc): practice_aim_arc.hide()
	if is_instance_valid(audio): audio.stop()
	if is_instance_valid(net_audio): net_audio.stop()

func pose(bone: int, time: float, cache: Dictionary) -> Transform3D:
	if cache.has(bone): return cache[bone]
	var rig: Skeleton3D = actor.skeleton
	var local := rig.get_bone_rest(bone)
	if edit_session != null:
		var frame: float = time*edit_session.frame_rate
		local.origin = edit_session.source_position(bone,frame)+edit_session.position_offset_at(bone,frame)
		local.basis = Basis(edit_session.source_rotation(bone,frame)*edit_session.offset_at(bone,frame))
	else:
		if positions[bone] >= 0: local.origin = clip.position_track_interpolate(positions[bone],time)
		if rotations[bone] >= 0: local.basis = Basis(clip.rotation_track_interpolate(rotations[bone],time))
	var parent := rig.get_bone_parent(bone)
	var result := local if parent < 0 else pose(parent,time,cache)*local
	cache[bone] = result
	return result

func platform(time: float) -> Dictionary:
	var rig: Skeleton3D = actor.skeleton
	var cache := {}
	var elbows := []
	var wrists := []
	for side in ["l","r"]:
		var elbow: Vector3 = rig.global_transform*pose(rig.find_bone("lowerarm_"+side),time,cache).origin
		var wrist: Vector3 = rig.global_transform*pose(rig.find_bone("hand_"+side),time,cache).origin
		elbows.append(elbow)
		wrists.append(wrist)
	return Contact.surface(elbows,wrists,0.032*rig.global_basis.y.length())


func recalculate() -> void:
	practice_reach_center = Vector3.INF
	practice_forearms.clear()
	practice_grade = Grade.WAITING
	practice_in_reach = false
	practice_early_attempt = false
	recovery.clear()
	recovery_net.clear()
	var hit := platform(contact_time)
	surface_point = hit.surface
	surface_normal = hit.normal
	impact_point = hit.ball
	var before := platform(maxf(0,contact_time-1.0/60))
	var after := platform(minf(clip.length,contact_time+1.0/60))
	surface_velocity = (after.surface-before.surface)/(2.0/60)
	var arrows = actor.get_node_or_null("DirectionArrows")
	missed = arrows != null and arrows.selected != 0
	aim_point = impact_point
	if missed:
		aim_point = arrows.landing_target()
		aim_point.y = Flight.FLOOR
		if practice_mode:
			var direction: Vector3 = aim_point-actor.global_position
			direction.y = 0.0
			var reach: float = [0.42,0.85,1.42,1.82,2.33][arrows.selected_distance-1]
			aim_point = impact_point+direction.normalized()*reach
			if arrows.selected_distance == 4:
				aim_point.y = Flight.FLOOR+0.045
			elif arrows.selected_distance == 5 or (arrows.selected_distance == 3 and arrows.selected in [1,2,8]):
				aim_point.y = 0.46
			elif float(actor.get_meta("feed_settings",{}).get("source_height",0.0)) >= 4.6:
				aim_point.y += 0.36
	var feed: Dictionary
	if review_feed.is_empty():
		var settings: Dictionary = actor.get_meta("feed_settings",{})
		feed = Flight.feed(aim_point,settings)
		if practice_mode and missed and (arrows.selected_distance >= 4 or (arrows.selected_distance == 3 and arrows.selected in [1,2,8])):
			# Keep the low dive target reachable across the net without moving the source.
			var fitted := settings.duplicate()
			fitted.fit = "speed"
			for attempt in range(6):
				if Net.first_hit(func(time): return Flight.position(feed,aim_point,time),-float(feed.duration),0.0).is_empty(): break
				fitted.angle = float(settings.get("angle",27.4))+2.0*(attempt+1)
				feed = Flight.feed(aim_point,fitted)
	else:
		aim_point = review_feed.aim
		missed = review_feed.get("require_platform",false) and aim_point.distance_to(impact_point) > 0.20
		feed = review_feed.duplicate()
	feed_info = feed
	incoming = feed.incoming
	feed_duration = feed.duration
	feed_valid = feed.valid
	source_ball.global_position = feed.start
	source_ball.show()
	source_ground.global_position = Vector3(feed.start.x,0.065,feed.start.z)
	source_ground.show()
	outgoing = Vector3.ZERO if missed else Contact.rebound(incoming,surface_velocity,surface_normal,float(clip.get_meta("reception_restitution",0.55)))
	if review_feed.has("spike_outgoing"):
		var rig: Skeleton3D = actor.skeleton
		var cache := {}
		var wrist := pose(rig.find_bone("hand_r"),contact_time,cache).origin
		var knuckle := pose(rig.find_bone("middle_01_r"),contact_time,cache).origin
		var palm := rig.to_global(wrist.lerp(knuckle,0.75))
		missed = palm.distance_to(aim_point)>0.19 or review_feed.spike_outgoing.is_zero_approx()
		outgoing = incoming if missed else review_feed.spike_outgoing
	elif missed and review_feed.get("require_platform",false): outgoing = incoming
	flight_duration = Flight.landing_time(aim_point,outgoing) if not missed or review_feed.get("require_platform",false) or review_feed.has("spike_outgoing") else 0.0
	incoming_net = Net.first_hit(func(time): return Flight.position(feed_info,aim_point,time),-feed_duration,0.0)
	outgoing_net = {}
	if not missed and incoming_net.is_empty(): outgoing_net = Net.first_hit(flight_position,0.0,flight_duration)
	feed_valid = feed.start.y>=Flight.FLOOR and incoming_net.is_empty()
	feed_info.valid = feed_valid
	if practice_mode:
		var gravity := maxf(1.0,-float(feed.acceleration.y))
		practice_floor_time = (incoming.y+sqrt(maxf(0,incoming.y*incoming.y+2*gravity*(aim_point.y-Flight.FLOOR))))/gravity
		outgoing_net.clear()
	update_guide()
	if edit_session != null: cached_revision = edit_session.revision

func practice_position(elapsed: float) -> Vector3:
	var time := minf(elapsed,practice_floor_time)
	if time < 0.0: return Flight.position(feed_info,aim_point,time)
	return aim_point+incoming*time+feed_info.acceleration*0.5*time*time

func reset_practice_serve() -> void:
	practice_grade = Grade.WAITING
	practice_in_reach = false
	practice_early_attempt = false
	if recovery.is_empty(): return
	recovery.clear()
	recovery_net.clear()
	update_guide()

func practice_platform_center() -> Vector3:
	return practice_reach_center if practice_reach_center.is_finite() else platform(contact_time).ball

func practice_intercept(height := -1.0) -> Dictionary:
	if not incoming_net.is_empty(): return {}
	if height < 0.0: height = platform(contact_time).ball.y
	if feed_info.start.y <= height: return {}
	var first := -feed_duration
	var last := practice_floor_time
	for sample in range(14):
		var time := (first+last)*0.5
		if practice_position(time).y > height:
			first = time
		else:
			last = time
	return {"point":practice_position(last),"time":contact_time+last}

func practice_shoulder_intercept() -> Dictionary:
	var rig: Skeleton3D = actor.skeleton
	var cache := {}
	var left := pose(rig.find_bone("upperarm_l"),contact_time,cache).origin
	var right := pose(rig.find_bone("upperarm_r"),contact_time,cache).origin
	var shoulders := rig.global_transform*((left+right)*0.5)
	return practice_intercept(shoulders.y+0.04)

func practice_step_offset(time: float) -> Vector3:
	if practice_grade != Grade.WAITING or not incoming_net.is_empty(): return Vector3.ZERO
	var elapsed := time-contact_time
	var first := maxf(elapsed,-feed_duration)
	var last := minf(elapsed+0.30,practice_floor_time)
	if last <= first: return Vector3.ZERO
	var center: Vector3 = platform(contact_time).ball
	var end := practice_position(last)
	var nearest := Geometry3D.get_closest_point_to_segment(center,practice_position(first),end)
	if last < practice_floor_time and nearest.is_equal_approx(end): return Vector3.ZERO
	var offset := nearest-center
	if offset.length() <= RECEIVE_RADIUS or offset.length() > 1.65: return Vector3.ZERO
	return offset

static func practice_reach_tier(offset: Vector3) -> int:
	if offset.length() > 1.12 or offset.y > 0.62: return 3
	if offset.length() > 0.67 or absf(offset.y) > 0.28: return 2
	return 1

func update_practice_platform() -> void:
	var rig: Skeleton3D = actor.skeleton
	var elbows := []
	var wrists := []
	for side in ["l","r"]:
		elbows.append(rig.global_transform*rig.get_bone_global_pose(rig.find_bone("lowerarm_"+side)).origin)
		wrists.append(rig.global_transform*rig.get_bone_global_pose(rig.find_bone("hand_"+side)).origin)
	var surface := Contact.surface(elbows,wrists,0.032*rig.global_basis.y.length())
	practice_reach_center = surface.ball
	var clearance: Vector3 = surface.ball-surface.surface
	practice_forearms.assign([
		(elbows[0]+elbows[1])*0.5+clearance,
		(wrists[0]+wrists[1])*0.5+clearance,
	])

func practice_approach(time: float, near_radius := METER_NEAR_RADIUS) -> float:
	if not incoming_net.is_empty(): return -1.0
	var elapsed := time-contact_time
	if elapsed < -feed_duration or elapsed > practice_floor_time: return -1.0
	var center := practice_platform_center()
	var nearest := practice_position(elapsed).distance_to(center)
	if nearest <= RECEIVE_RADIUS: return 1.0
	var nearest_delay := 0.0
	# Look ahead along the ball path for the first reachable contact.
	for sample in range(1,20):
		var delay := minf(APPROACH_WINDOW*sample/19.0,practice_floor_time-elapsed)
		var next := practice_position(elapsed+delay)
		var distance := next.distance_to(center)
		if distance <= RECEIVE_RADIUS:
			return 1.0-delay/APPROACH_WINDOW
		if distance < nearest:
			nearest = distance
			nearest_delay = delay
		if delay >= practice_floor_time-elapsed: break
	if nearest <= near_radius:
		return 1.0-nearest_delay/APPROACH_WINDOW
	return -1.0

func try_practice_pass(previous_time: float, time: float, receive_elapsed: float) -> bool:
	if practice_grade != Grade.WAITING or not incoming_net.is_empty(): return false
	var first := maxf(previous_time-contact_time,-feed_duration)
	var last := minf(time-contact_time,practice_floor_time)
	if last < first: return false
	var platform_center := practice_platform_center()
	var previous := practice_position(first)
	var current := practice_position(last)
	var touch := Geometry3D.get_closest_point_to_segment(platform_center,previous,current)
	if touch.distance_to(platform_center)>RECEIVE_RADIUS:
		if not practice_reach_center.is_finite() or practice_forearms.size()!=2: return false
		var points := Geometry3D.get_closest_points_between_segments(previous,current,practice_forearms[0],practice_forearms[1])
		if points[0].distance_to(points[1])>0.19: return false
		touch = points[0]
	practice_in_reach = true
	if receive_elapsed <= 0.0: return false
	var timing_error := practice_timing_error(receive_elapsed)
	if receive_elapsed < GREEN_START:
		practice_grade = Grade.LATE
	elif receive_elapsed > GREEN_END:
		practice_grade = Grade.EARLY
	else:
		practice_grade = Grade.PERFECT
	var bounds := practice_accuracy_bounds(timing_error,last)
	var target: Dictionary = actor.get_meta("pass_target",{})
	var angle := float(clip.get_meta("desired_output_angle",45.0))
	var velocity := Accuracy.pass_velocity(touch,target,angle,bounds)
	recovery = {"time":last,"point":touch,"velocity":velocity,"aim":target.position,"spread":bounds,"end_time":last+Flight.landing_time(touch,velocity)}
	recovery_net = Net.first_hit(func(t): return touch+velocity*(t-last)+Vector3.DOWN*4.905*pow(t-last,2),last,recovery.end_time)
	update_guide()
	return true

func try_pancake(previous_time: float, time: float, receive_elapsed := -1.0) -> bool:
	if practice_grade != Grade.WAITING or not incoming_net.is_empty(): return false
	var first := maxf(previous_time-contact_time,-feed_duration)
	var last := minf(time-contact_time,practice_floor_time)
	if last < first: return false
	var rig: Skeleton3D = actor.skeleton
	var wrist := rig.global_transform*rig.get_bone_global_pose(rig.find_bone("hand_r")).origin
	if wrist.y > 0.17: return false
	var palm := wrist+actor.global_basis.z.normalized()*0.095
	var touch := Geometry3D.get_closest_point_to_segment(palm+Vector3.UP*RADIUS,practice_position(first),practice_position(last))
	if touch.distance_to(palm+Vector3.UP*RADIUS) > 0.13: return false
	var velocity: Vector3 = incoming+feed_info.acceleration*last
	if velocity.y >= 0.0: return false
	var pop := pancake_pop(velocity)
	practice_grade = Grade.PERFECT
	recovery = {"time":last,"point":touch,"velocity":pop,"pancake":true}
	if receive_elapsed >= 0.0:
		var error := practice_timing_error(receive_elapsed)*PANCAKE_ERROR_SCALE
		var target := pancake_target(touch,pop)
		practice_grade = Grade.LATE if receive_elapsed < GREEN_START else (Grade.EARLY if receive_elapsed > GREEN_END else Grade.PERFECT)
		recovery.aim = target.position
		recovery.spread = practice_accuracy_bounds(error,last)
		pop = Accuracy.pass_velocity(touch,target,45.0,recovery.spread)
		recovery.velocity = pop
	recovery.end_time = last+Flight.landing_time(touch,pop)
	recovery_net.clear()
	update_guide()
	return true

static func pancake_pop(incoming: Vector3) -> Vector3:
	return incoming.slide(Vector3.UP).limit_length(1.1)*0.65+Vector3.UP*clampf(-incoming.y*0.48,2.2,4.2)

static func pancake_target(touch: Vector3, pop: Vector3) -> Dictionary:
	var landing := touch+pop*Flight.landing_time(touch,pop)
	return {"position":Vector2(landing.x,landing.z),"height":touch.y+pop.y*pop.y/(2.0*Flight.GRAVITY),"fit":"height"}

func try_body_dig(previous_time: float, time: float) -> bool:
	if not recovery.is_empty() or not incoming_net.is_empty(): return false
	var first := maxf(previous_time-contact_time,-feed_duration)
	var last := minf(time-contact_time,practice_floor_time)
	if last <= first: return false
	var from := practice_position(first)
	var to := practice_position(last)
	var flight := to-from
	if flight.length_squared()<0.000001: return false
	var rig: Skeleton3D = actor.skeleton
	var points := {}
	for name_ in ["Head","neck_01","spine_03","pelvis","upperarm_l","upperarm_r","lowerarm_l","lowerarm_r","hand_l","hand_r","thigh_l","thigh_r","calf_l","calf_r","foot_l","foot_r"]:
		var bone := rig.find_bone(name_)
		if bone >= 0: points[name_] = rig.global_transform*rig.get_bone_global_pose(bone).origin
	var capsules := [
		["Head","neck_01",0.12],["spine_03","pelvis",0.18],
		["upperarm_l","upperarm_r",0.09],
		["upperarm_l","lowerarm_l",0.065],["upperarm_r","lowerarm_r",0.065],
		["lowerarm_l","hand_l",0.045],["lowerarm_r","hand_r",0.045],
		["thigh_l","calf_l",0.085],["thigh_r","calf_r",0.085],
		["calf_l","foot_l",0.060],["calf_r","foot_r",0.060],
	]
	var best := INF
	var contact := Vector3.ZERO
	var normal := Vector3.ZERO
	var body_part := ""
	for capsule in capsules:
		if not points.has(capsule[0]) or not points.has(capsule[1]): continue
		var start: Vector3 = points[capsule[0]]
		var end: Vector3 = points[capsule[1]]
		var clearance := RADIUS+float(capsule[2])
		var nearest := Geometry3D.get_closest_points_between_segments(from,to,start,end)
		if nearest[0].distance_to(nearest[1])>clearance: continue
		var entry := 0.0
		var inside := clampf((nearest[0]-from).dot(flight)/flight.length_squared(),0.0,1.0)
		if from.distance_to(Geometry3D.get_closest_point_to_segment(from,start,end))>clearance:
			for sample in range(8):
				var middle := (entry+inside)*0.5
				var candidate := from+flight*middle
				if candidate.distance_to(Geometry3D.get_closest_point_to_segment(candidate,start,end))>clearance:
					entry = middle
				else:
					inside = middle
		else:
			inside = 0.0
		if inside>=best: continue
		var hit := from+flight*inside
		var difference := hit-Geometry3D.get_closest_point_to_segment(hit,start,end)
		var axis := difference.normalized() if difference.length_squared()>0.0001 else -flight.normalized()
		if flight.dot(axis)>=0.0: continue
		best = inside
		contact = hit
		normal = axis
		body_part = capsule[0]
	if not is_finite(best): return false
	var elapsed := lerpf(first,last,best)
	var velocity: Vector3 = incoming+feed_info.acceleration*elapsed
	var bounce := Contact.rebound(velocity,Vector3.ZERO,normal,0.35)
	practice_grade = Grade.BODY_DIG
	recovery = {"time":elapsed,"point":contact,"velocity":bounce,"body_touch":true,"body_part":body_part,"end_time":elapsed+Flight.landing_time(contact,bounce)}
	recovery_net = Net.first_hit(func(t): return contact+bounce*(t-elapsed)+Vector3.DOWN*4.905*pow(t-elapsed,2),elapsed,recovery.end_time)
	update_guide()
	return true

static func practice_timing_error(receive_elapsed: float) -> float:
	return Accuracy.timing_error(receive_elapsed,GREEN_START,GREEN_END)

func practice_accuracy_bounds(error: float, time: float) -> Vector2:
	var speed := (practice_position(time+0.001)-practice_position(time-0.001)).length()/0.002
	var spin_rps := float(feed_info.get("spin_rate",0.0))/TAU
	return Accuracy.spread(error,speed,spin_rps,StorySession.forearm_reception_skill,false)

func update_practice_cone(show_timing: bool, receive_elapsed: float) -> void:
	var target: Dictionary = actor.get_meta("pass_target",{})
	var has_touch := recovery.has("spread")
	if not show_timing or not target.has("position") or (practice_grade != Grade.WAITING and not has_touch):
		spread_cone.hide()
		return
	var aim: Vector2 = recovery.get("aim",target.position)
	var destination := Vector3(aim.x,0.075,aim.y)
	var origin: Vector3 = recovery.point if has_touch else practice_platform_center()
	var bounds: Vector2 = recovery.spread if has_touch else practice_accuracy_bounds(practice_timing_error(receive_elapsed),0.0)
	var ideal := Flight.target_velocity(origin,target,float(clip.get_meta("desired_output_angle",45.0)))
	var peak := origin+ideal*(ideal.y/Flight.GRAVITY)-Vector3.UP*ideal.y*ideal.y/(2.0*Flight.GRAVITY)
	spread_cone.show_spread(origin,destination,bounds.x,peak,bounds.y)

func update_practice_aim(show_aim: bool) -> void:
	var target: Dictionary = actor.get_meta("pass_target",{})
	var arrows = actor.get_node_or_null("DirectionArrows")
	var pancake: bool = practice_mode and arrows != null and arrows.selected_distance == 4
	practice_aim_arc.visible = show_aim and target.has("position") and not pancake
	if not practice_aim_arc.visible: return
	var origin := practice_platform_center()
	var angle := float(clip.get_meta("desired_output_angle",45.0))
	var velocity := Flight.target_velocity(origin,target,angle)
	if origin.distance_squared_to(last_aim_origin)<0.0004 and velocity.distance_squared_to(last_aim_velocity)<0.0004:
		return
	last_aim_origin = origin
	last_aim_velocity = velocity
	var duration := Flight.landing_time(origin,velocity)
	var path: ImmediateMesh = practice_aim_arc.mesh
	path.clear_surfaces()
	path.surface_begin(Mesh.PRIMITIVE_LINES)
	for index in range(34):
		for fraction in [0.0,0.58]:
			var time: float = (index+fraction)*duration/34.0
			path.surface_add_vertex(origin+velocity*time+Vector3.DOWN*0.5*Flight.GRAVITY*time*time)
	path.surface_end()

func practice_pass_velocity(touch: Vector3) -> Vector3:
	var target: Dictionary = actor.get_meta("pass_target",{})
	return Flight.target_velocity(touch,target,float(clip.get_meta("desired_output_angle",45.0)))

func finish_practice_serve() -> void:
	if practice_grade != Grade.WAITING: return
	if not practice_in_reach:
		practice_grade = Grade.MISS
	else:
		practice_grade = Grade.EARLY if practice_early_attempt else Grade.LATE

func animation_time(time: float) -> float:
	return clampf(time,0,clip.length) if incoming_net.is_empty() else 0.0

func cycle_end() -> float:
	if clip.has_meta("editor_ball_frames"): return clip.length
	if not recovery.is_empty():
		var last: float = recovery_net.end_time if not recovery_net.is_empty() else recovery.end_time
		return maxf(clip.length,contact_time+last+0.5)
	var end := contact_time+(practice_floor_time if practice_mode else flight_duration)
	if not incoming_net.is_empty(): return maxf(contact_time+float(incoming_net.end_time)+0.5,contact_time+0.5)
	if not outgoing_net.is_empty(): end = contact_time+float(outgoing_net.end_time)
	return maxf(clip.length,end+0.4)

func position_at(elapsed: float) -> Vector3:
	if not recovery.is_empty() and elapsed>=recovery.time:
		if not recovery_net.is_empty() and elapsed>=recovery_net.time: return Net.after_hit(recovery_net,elapsed)
		var age := clampf(elapsed-float(recovery.time),0,float(recovery.end_time)-float(recovery.time))
		return recovery.point+recovery.velocity*age+Vector3.DOWN*4.905*age*age
	if not incoming_net.is_empty() and elapsed>=incoming_net.time: return Net.after_hit(incoming_net,elapsed)
	if practice_mode: return practice_position(elapsed)
	if elapsed<0.0: return Flight.position(feed_info,aim_point,elapsed)
	if not outgoing_net.is_empty() and elapsed>=outgoing_net.time: return Net.after_hit(outgoing_net,elapsed)
	return flight_position(elapsed)

func flight_position(elapsed: float) -> Vector3:
	var age := clampf(elapsed,0,flight_duration)
	return aim_point+outgoing*age+Vector3.DOWN*4.905*age*age

func recovery_state(time: float) -> Dictionary:
	var elapsed := time-contact_time
	if not recovery.is_empty() and elapsed>=recovery.time:
		return Net.state_at(recovery_net,elapsed) if not recovery_net.is_empty() else {"recoverable":false,"phase":"played","in_play":elapsed<float(recovery.end_time)}
	var hit: Dictionary = incoming_net if not incoming_net.is_empty() else outgoing_net
	return Net.state_at(hit,elapsed)

# Gameplay can apply the next player touch while the rebound is still airborne.
func recover(time: float, velocity: Vector3) -> bool:
	var state := recovery_state(time)
	if not state.recoverable: return false
	var elapsed := time-contact_time
	recovery = {"time":elapsed,"point":state.position,"velocity":velocity,"end_time":elapsed+Flight.landing_time(state.position,velocity)}
	recovery_net = Net.first_hit(func(t): return recovery.point+velocity*(t-elapsed)+Vector3.DOWN*4.905*pow(t-elapsed,2),elapsed,recovery.end_time)
	last_time = time-0.000001
	has_last_time = true
	update_guide()
	return true

func crossed(time: float, at: float) -> bool:
	if not has_last_time: return false
	return (last_time<at and time>=at) if time>=last_time else (last_time<at or time>=at)

func output_angle() -> float:
	return Contact.elevation(outgoing)

func update_guide() -> void:
	if not is_instance_valid(guide): return
	var path := ImmediateMesh.new()
	for incoming_path in [true,false]:
		if not incoming_path and ((practice_mode and recovery.is_empty()) or (not practice_mode and missed) or not incoming_net.is_empty()): continue
		var first := -feed_duration if incoming_path else 0.0
		var last := 0.0 if incoming_path else flight_duration
		if incoming_path and not incoming_net.is_empty(): last = incoming_net.end_time
		if not incoming_path and not outgoing_net.is_empty(): last = outgoing_net.end_time
		if practice_mode and incoming_net.is_empty():
			if incoming_path:
				last = practice_floor_time if recovery.is_empty() else float(recovery.time)
			else:
				first = recovery.time
				last = recovery_net.end_time if not recovery_net.is_empty() else recovery.end_time
		elif not recovery.is_empty():
			if not incoming_path or not incoming_net.is_empty(): last = recovery_net.end_time if not recovery_net.is_empty() else recovery.end_time
		path.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		var blocked: bool = not incoming_net.is_empty() if incoming_path else not outgoing_net.is_empty()
		path.surface_set_color(Color("df776d") if blocked else (Color("e5bd72") if incoming_path else Color("70d5e5")))
		for index in range(121):
			var time := lerpf(first,last,float(index)/120)
			path.surface_add_vertex(position_at(time))
		path.surface_end()
	path.surface_begin(Mesh.PRIMITIVE_LINES)
	path.surface_set_color(Color("a7a485"))
	path.surface_add_vertex(source_ground.global_position)
	path.surface_add_vertex(source_ball.global_position)
	path.surface_end()
	var landing := flight_position(flight_duration)
	var target_info: Dictionary = actor.get_meta("pass_target",{})
	if target_info.has("position"):
		landing.x = target_info.position.x
		landing.z = target_info.position.y
	path.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	path.surface_set_color(Color("70d5e5"))
	for index in range(33):
		var angle := TAU*index/32.0
		path.surface_add_vertex(Vector3(landing.x+cos(angle)*0.2,0.055,landing.z+sin(angle)*0.2))
	path.surface_end()
	if missed:
		path.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		path.surface_set_color(Color("ff4848"))
		for index in range(33):
			var angle := TAU*index/32.0
			path.surface_add_vertex(Vector3(aim_point.x+cos(angle)*0.17,0.06,aim_point.z+sin(angle)*0.17))
		path.surface_end()
	guide.mesh = path
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	guide.material_override = material
	guide.visible = active

func tick(time: float, audible: bool) -> void:
	if clip != null and clip.has_meta("editor_ball_frames"):
		var samples: Array = clip.get_meta("editor_ball_frames")
		var sample := clampf(time*60.0,0.0,samples.size()-1)
		var first := floori(sample)
		global_transform = samples[first].interpolate_with(samples[mini(first+1,samples.size()-1)],sample-first)
		ball.show()
		show()
		return
	if not active:
		hide()
		if is_instance_valid(guide): guide.hide()
		return
	if edit_session != null and cached_revision != edit_session.revision: recalculate()
	var elapsed := time-contact_time
	global_position = position_at(elapsed)
	show()
	ball.visible = elapsed>=-feed_duration and time<=cycle_end()
	var squeeze := maxf(0,1.0-absf(elapsed)/0.035) if incoming_net.is_empty() and not missed and not practice_mode else 0.0
	var net_hit: Dictionary = incoming_net if not incoming_net.is_empty() else outgoing_net
	if not recovery_net.is_empty() and elapsed>=recovery_net.time: net_hit = recovery_net
	if is_instance_valid(dynamic_net): dynamic_net.sample(net_hit,elapsed)
	var net_squeeze := Net.squeeze(net_hit,elapsed)
	var axis: Vector3 = feed_info.get("spin_axis",Vector3.ZERO)
	var rotation_time := clampf(elapsed+feed_duration,0,feed_duration)
	if not net_hit.is_empty() and elapsed>net_hit.time:
		rotation_time = minf(feed_duration,float(net_hit.time)+feed_duration)+maxf(0,minf(elapsed,float(net_hit.end_time))-float(net_hit.time))*0.25
	ball.global_basis = Basis(Quaternion(axis,rotation_time*float(feed_info.get("spin_rate",0)))) if axis.length_squared()>0.1 else Basis.IDENTITY
	ball.scale = Vector3(1.0+0.04*squeeze+0.04*net_squeeze,1.0-0.07*squeeze,1.0+0.04*squeeze-0.12*net_squeeze)
	if audible and not practice_mode and incoming_net.is_empty() and not missed and crossed(time,contact_time):
		audio.play()
		contact_count += 1
		contacted.emit()
	if audible and not net_hit.is_empty() and crossed(time,contact_time+float(net_hit.time)):
		net_audio.play()
		net_contact_count += 1
		net_contacted.emit()
	if audible and not recovery.is_empty() and crossed(time,contact_time+float(recovery.time)):
		audio.play()
		contact_count += 1
		contacted.emit()
	last_time = time
	has_last_time = true
