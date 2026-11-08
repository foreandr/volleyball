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
var source_ball: MeshInstance3D
var source_ground: MeshInstance3D
var feed_valid := true
var feed_info := {}
var incoming_net := {}
var outgoing_net := {}
var net_audio: AudioStreamPlayer
var net_contact_count := 0
var has_last_time := false

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
	net_audio = AudioStreamPlayer.new()
	net_audio.stream = audio.stream
	net_audio.volume_db = -12
	net_audio.pitch_scale = 0.65
	add_child(net_audio)
	guide = MeshInstance3D.new()
	guide.top_level = true
	add_child(guide)
	guide.global_transform = Transform3D.IDENTITY
	guide.hide()
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

func make_ball() -> ArrayMesh:
	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	var colors := [Color("f5f1dd"),Color("2e64b4"),Color("efd13b")]
	for row in range(12):
		for column in range(24):
			var corners: Array[Vector3] = []
			for corner in [Vector2i(0,0),Vector2i(1,0),Vector2i(1,1),Vector2i(0,1)]:
				var latitude: float = -PI*0.5+PI*(row+corner.y)/12.0
				var longitude: float = TAU*(column+corner.x)/24.0
				corners.append(Vector3(cos(latitude)*cos(longitude),sin(latitude),cos(latitude)*sin(longitude)))
			var color: Color = colors[(int(column/4)+int(row/4))%3]
			for index in [0,1,2,0,2,3]:
				mesh.set_color(color)
				mesh.set_normal(corners[index])
				mesh.add_vertex(corners[index]*RADIUS)
	return mesh.commit()

func configure(player: Node3D, animation: Animation, edits: RefCounted = null) -> void:
	if is_instance_valid(audio): audio.stop()
	if is_instance_valid(net_audio): net_audio.stop()
	actor = player
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
	if active: recalculate()
	else: stop()

func stop() -> void:
	active = false
	last_time = -1
	has_last_time = false
	hide()
	if is_instance_valid(source_ball): source_ball.hide()
	if is_instance_valid(source_ground): source_ground.hide()
	if is_instance_valid(guide): guide.hide()
	if is_instance_valid(audio): audio.stop()
	if is_instance_valid(net_audio): net_audio.stop()

func pose(bone: int, time: float, cache: Dictionary) -> Transform3D:
	if cache.has(bone): return cache[bone]
	var rig: Skeleton3D = actor.skeleton
	var local := rig.get_bone_rest(bone)
	if edit_session != null:
		var frame := time*60
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
	var points := []
	for side in ["l","r"]:
		var elbow: Vector3 = rig.global_transform*pose(rig.find_bone("lowerarm_"+side),time,cache).origin
		var wrist: Vector3 = rig.global_transform*pose(rig.find_bone("hand_"+side),time,cache).origin
		elbows.append(elbow)
		wrists.append(wrist)
		points.append(elbow.lerp(wrist,0.65))
	return Contact.surface(elbows,wrists,0.032*rig.global_basis.get_scale().y)

func recalculate() -> void:
	var hit := platform(contact_time)
	surface_point = hit.surface
	surface_normal = hit.normal
	impact_point = hit.ball
	var before := platform(maxf(0,contact_time-1.0/60))
	var after := platform(minf(clip.length,contact_time+1.0/60))
	surface_velocity = (after.surface-before.surface)/(2.0/60)
	var feed := Flight.feed(impact_point,actor.get_meta("feed_settings",{}))
	feed_info = feed
	incoming = feed.incoming
	feed_duration = feed.duration
	feed_valid = feed.valid
	source_ball.global_position = feed.start
	source_ball.show()
	source_ground.global_position = Vector3(feed.start.x,0.065,feed.start.z)
	source_ground.show()
	outgoing = Contact.rebound(incoming,surface_velocity,surface_normal)
	flight_duration = Flight.landing_time(impact_point,outgoing)
	incoming_net = Net.first_hit(func(time): return Flight.position(feed_info,impact_point,time),-feed_duration,0)
	outgoing_net = {}
	if incoming_net.is_empty(): outgoing_net = Net.first_hit(func(time): return impact_point+outgoing*time+Vector3.DOWN*4.905*time*time,0,flight_duration)
	feed_valid = feed.start.y>=Flight.FLOOR and incoming_net.is_empty()
	feed_info.valid = feed_valid
	update_guide()
	if edit_session != null: cached_revision = edit_session.revision

func animation_time(time: float) -> float:
	return clampf(time,0,clip.length) if incoming_net.is_empty() else 0.0

func cycle_end() -> float:
	var end := contact_time+flight_duration
	if not incoming_net.is_empty(): return maxf(contact_time+float(incoming_net.end_time)+0.5,contact_time+0.5)
	if not outgoing_net.is_empty(): end = contact_time+float(outgoing_net.end_time)
	return maxf(clip.length,end+0.4)

func position_at(elapsed: float) -> Vector3:
	if not incoming_net.is_empty() and elapsed>=incoming_net.time: return Net.after_hit(incoming_net,elapsed)
	if elapsed<0: return Flight.position(feed_info,impact_point,elapsed)
	if not outgoing_net.is_empty() and elapsed>=outgoing_net.time: return Net.after_hit(outgoing_net,elapsed)
	return impact_point+outgoing*elapsed+Vector3.DOWN*4.905*elapsed*elapsed

func crossed(time: float, at: float) -> bool:
	if not has_last_time: return false
	return (last_time<at and time>=at) if time>=last_time else (last_time<at or time>=at)

func output_angle() -> float:
	return Contact.elevation(outgoing)

func update_guide() -> void:
	if not is_instance_valid(guide): return
	var path := ImmediateMesh.new()
	for incoming_path in [true,false]:
		if not incoming_path and not incoming_net.is_empty(): continue
		var first := -feed_duration if incoming_path else 0.0
		var last := 0.0 if incoming_path else flight_duration
		if incoming_path and not incoming_net.is_empty(): last = incoming_net.end_time
		if not incoming_path and not outgoing_net.is_empty(): last = outgoing_net.end_time
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
	var landing := impact_point+outgoing*flight_duration+Vector3.DOWN*4.905*flight_duration*flight_duration
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
	guide.mesh = path
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	guide.material_override = material
	guide.visible = active

func tick(time: float, audible: bool) -> void:
	if not active:
		hide()
		if is_instance_valid(guide): guide.hide()
		return
	if edit_session != null and cached_revision != edit_session.revision: recalculate()
	var elapsed := time-contact_time
	global_position = position_at(elapsed)
	show()
	ball.visible = elapsed>=-feed_duration and time<=cycle_end()
	var squeeze := maxf(0,1.0-absf(elapsed)/0.035) if incoming_net.is_empty() else 0.0
	var net_hit: Dictionary = incoming_net if not incoming_net.is_empty() else outgoing_net
	var net_squeeze := maxf(0,1.0-absf(elapsed-float(net_hit.time))/0.06) if not net_hit.is_empty() else 0.0
	var axis: Vector3 = feed_info.get("spin_axis",Vector3.ZERO)
	var rotation_time := clampf(elapsed+feed_duration,0,feed_duration)
	ball.global_basis = Basis(Quaternion(axis,rotation_time*float(feed_info.get("spin_rate",0)))) if axis.length_squared()>0.1 else Basis.IDENTITY
	ball.scale = Vector3(1.0+0.04*squeeze+0.04*net_squeeze,1.0-0.07*squeeze,1.0+0.04*squeeze-0.12*net_squeeze)
	if audible and incoming_net.is_empty() and crossed(time,contact_time):
		audio.play()
		contact_count += 1
		contacted.emit()
	if audible and not net_hit.is_empty() and crossed(time,contact_time+float(net_hit.time)):
		net_audio.play()
		net_contact_count += 1
		net_contacted.emit()
	last_time = time
	has_last_time = true
