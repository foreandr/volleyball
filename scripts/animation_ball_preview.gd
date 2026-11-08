extends Node3D
signal contacted
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
var ball: MeshInstance3D
var audio: AudioStreamPlayer
var last_time := -1.0
var contact_count := 0
var active := false
var cached_revision := -1
var positions := {}
var rotations := {}

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
	actor = player
	clip = animation
	edit_session = edits
	active = clip.has_meta("contact_time")
	contact_time = float(clip.get_meta("contact_time",0.6))
	last_time = -1
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
	hide()
	if is_instance_valid(audio): audio.stop()

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
	var axis: Vector3 = ((wrists[0]-elbows[0])+(wrists[1]-elbows[1])).normalized()
	var normal: Vector3 = (points[1]-points[0]).cross(axis).normalized()
	if normal.dot(Vector3.UP) < 0: normal = -normal
	if normal.length_squared() < 0.5: normal = Vector3.UP
	var center: Vector3 = (points[0]+points[1])*0.5
	var padding := 0.032*rig.global_basis.get_scale().y
	var half_gap: float = points[0].distance_to(points[1])*0.5
	var clearance := RADIUS+padding
	if half_gap >= clearance:
		center = points[0]
		half_gap = 0
	var separation := sqrt(maxf(0,clearance*clearance-half_gap*half_gap))
	return {"surface":center,"normal":normal,"ball":center+normal*separation}

func recalculate() -> void:
	var hit := platform(contact_time)
	surface_point = hit.surface
	surface_normal = hit.normal
	impact_point = hit.ball
	var before := platform(maxf(0,contact_time-1.0/60))
	var after := platform(minf(clip.length,contact_time+1.0/60))
	surface_velocity = (after.surface-before.surface)/(2.0/60)
	var relative := incoming-surface_velocity
	outgoing = relative-1.85*minf(0,relative.dot(surface_normal))*surface_normal+surface_velocity
	if edit_session != null: cached_revision = edit_session.revision

func tick(time: float, audible: bool) -> void:
	if not active: hide(); return
	if edit_session != null and cached_revision != edit_session.revision: recalculate()
	var elapsed := time-contact_time
	global_position = impact_point+(incoming if elapsed < 0 else outgoing)*elapsed+Vector3.DOWN*4.905*elapsed*elapsed
	visible = time <= minf(clip.length,contact_time+0.85)
	var squeeze := maxf(0,1.0-absf(elapsed)/0.035)
	ball.scale = Vector3(1.0+0.04*squeeze,1.0-0.07*squeeze,1.0+0.04*squeeze)
	ball.rotation = Vector3(time*1.7,time*2.3,0.2)
	var crossed := last_time >= 0 and ((last_time < contact_time and time >= contact_time) if time >= last_time else (last_time < contact_time or time >= contact_time))
	if audible and crossed:
		audio.play()
		contact_count += 1
		contacted.emit()
	last_time = time
