extends RefCounted

var whistle := Node3D.new()
var cord: Array[MeshInstance3D] = []
var sound := AudioStreamPlayer3D.new()
var signal_time := -1.0
var play_count := 0
var raised := 0.0

func fit_whistle(rig: Skeleton3D) -> void:
	rig.add_child(whistle)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color("ced6d6")
	metal.metallic = .65
	metal.roughness = .26
	var chamber := CylinderMesh.new()
	chamber.top_radius = .017
	chamber.bottom_radius = .017
	chamber.height = .025
	var barrel := MeshInstance3D.new()
	barrel.mesh = chamber
	barrel.rotation.z = PI*.5
	barrel.material_override = metal
	whistle.add_child(barrel)
	var stem := MeshInstance3D.new()
	var tube := BoxMesh.new()
	tube.size = Vector3(.019,.011,.034)
	stem.mesh = tube
	stem.position = Vector3(0,.007,-.022)
	stem.material_override = metal
	whistle.add_child(stem)
	var braid := StandardMaterial3D.new()
	braid.albedo_color = Color("25282b")
	for side in 2:
		var strand := MeshInstance3D.new()
		var line := CylinderMesh.new()
		line.top_radius = .0025
		line.bottom_radius = .0025
		line.height = 1
		line.radial_segments = 6
		strand.mesh = line
		strand.material_override = braid
		rig.add_child(strand)
		cord.append(strand)
	whistle.add_child(sound)
	var chirp := AudioStreamWAV.new()
	chirp.format = AudioStreamWAV.FORMAT_16_BITS
	chirp.mix_rate = 22050
	var samples := PackedByteArray()
	samples.resize(15436)
	for i in 7718:
		var t := float(i)/chirp.mix_rate
		var envelope := smoothstep(0,.025,t)*(1-smoothstep(.27,.35,t))
		var wave := sin(TAU*3030*t+.8*sin(TAU*32*t))+.46*sin(TAU*3380*t)
		samples.encode_s16(i*2,int(wave*7500*envelope))
	chirp.data = samples
	sound.stream = chirp
	rig.skeleton_updated.connect(update_whistle.bind(rig))
	update_whistle(rig)

func landmark(rig: Skeleton3D,bone: String,bind_point: Vector3) -> Vector3:
	var index := rig.find_bone(bone)
	return rig.get_bone_global_pose(index)*(rig.get_bone_global_rest(index).affine_inverse()*bind_point)

func update_whistle(rig: Skeleton3D) -> void:
	var chest := landmark(rig,"spine_03",Vector3(0,1.399,.139))
	var mouth := landmark(rig,"Head",Vector3(0,1.633,.128))
	whistle.position = chest.lerp(mouth,raised)
	whistle.rotation.x = lerpf(-1.13,0,raised)
	for i in cord.size():
		var shoulder := landmark(rig,"spine_03",Vector3(-.063 if i==0 else .063,1.538,.064))
		var axis := whistle.position-shoulder
		var direction := axis.normalized()
		var across := direction.cross(Vector3.RIGHT).normalized()
		cord[i].transform = Transform3D(Basis(across,axis,across.cross(direction)),(shoulder+whistle.position)*.5)

func signal_drill(actor: Node3D) -> void:
	signal_time = 0
	actor.play_action("base/Idle",.15)

func step_whistle(actor: Node3D,dt: float) -> bool:
	if signal_time < 0: return false
	var before := signal_time
	signal_time += dt
	actor.animator.advance(dt)
	var rig: Skeleton3D = actor.skeleton
	var author: RefCounted = actor.get_pose_author()
	var pose := []
	for i in rig.get_bone_count(): pose.append(rig.get_bone_pose(i))
	var grip := smoothstep(0,.30,signal_time)*(1-smoothstep(1.44,1.76,signal_time))
	raised = smoothstep(.30,.74,signal_time)*(1-smoothstep(1.12,1.44,signal_time))
	update_whistle(rig)
	var pole := Vector3(signf(author.point(pose,"upperarm_r").x),-.5,.2)
	var wrist: Vector3 = author.point(pose,"hand_r")
	for iteration in 3:
		wrist += whistle.position-author.point(pose,"middle_01_r")
		author.limb(pose,"upperarm_r","lowerarm_r","hand_r",wrist,pole)
	for bone in ["upperarm_r","lowerarm_r"]:
		var i := rig.find_bone(bone)
		rig.set_bone_pose_rotation(i,rig.get_bone_pose_rotation(i).slerp(pose[i].basis.orthonormalized().get_rotation_quaternion(),grip))
	if before < .74 and signal_time >= .74:
		sound.play()
		play_count+=1
	if signal_time >= 1.76: signal_time = -1
	return true
