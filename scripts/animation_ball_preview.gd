extends Node3D
const Contact = preload("res://scripts/forearm_contact.gd")
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
var guide: MeshInstance3D

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
	guide = MeshInstance3D.new()
	guide.top_level = true
	add_child(guide)
	guide.global_transform = Transform3D.IDENTITY
	guide.hide()
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
	if is_instance_valid(guide): guide.hide()
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
	return Contact.surface(elbows,wrists,0.032*rig.global_basis.get_scale().y)

func recalculate() -> void:
	var hit := platform(contact_time)
	surface_point = hit.surface
	surface_normal = hit.normal
	impact_point = hit.ball
	var before := platform(maxf(0,contact_time-1.0/60))
	var after := platform(minf(clip.length,contact_time+1.0/60))
	surface_velocity = (after.surface-before.surface)/(2.0/60)
	outgoing = Contact.rebound(incoming,surface_velocity,surface_normal)
	update_guide()
	if edit_session != null: cached_revision = edit_session.revision

func output_angle() -> float:
	return Contact.elevation(outgoing)

func update_guide() -> void:
	if not is_instance_valid(guide): return
	var path := ImmediateMesh.new()
	path.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for index in range(41):
		var time := float(index)/40.0*1.1
		path.surface_add_vertex(impact_point+outgoing*time+Vector3.DOWN*4.905*time*time)
	path.surface_end()
	guide.mesh = path
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("70b4c5")
	guide.material_override = material
	guide.visible = active

func tick(time: float, audible: bool) -> void:
	if not active:
		hide()
		if is_instance_valid(guide): guide.hide()
		return
	if edit_session != null and cached_revision != edit_session.revision: recalculate()
	var elapsed := time-contact_time
	global_position = impact_point+(incoming if elapsed < 0 else outgoing)*elapsed+Vector3.DOWN*4.905*elapsed*elapsed
	show()
	ball.visible = time <= minf(clip.length,contact_time+0.85)
	var squeeze := maxf(0,1.0-absf(elapsed)/0.035)
	ball.scale = Vector3(1.0+0.04*squeeze,1.0-0.07*squeeze,1.0+0.04*squeeze)
	ball.rotation = Vector3(time*1.7,time*2.3,0.2)
	var crossed := last_time >= 0 and ((last_time < contact_time and time >= contact_time) if time >= last_time else (last_time < contact_time or time >= contact_time))
	if audible and crossed:
		audio.play()
		contact_count += 1
		contacted.emit()
	last_time = time
