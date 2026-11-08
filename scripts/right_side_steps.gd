extends RefCounted
const SIZES := ["short","medium","long"]
var actor: Node3D
var author: RefCounted
var clips: Array[Animation] = []
var tracks: Array = []
var active := false
var sampled := false
var phase := 0.0
var hold := 0.0
var strength := 0.0
var previous_root := 0.0

func _init(player: Node3D) -> void:
	actor = player
	author = preload("res://tools/animation_author.gd").new(actor.skeleton,load("res://assets/animations/goalkeeper_idle.tres"))
	for size_ in SIZES:
		var clip: Animation = load("res://assets/animations/side_right_"+size_+".res")
		clips.append(clip)
		var indices := []
		for bone in actor.skeleton.get_bone_count():
			var path := NodePath("Armature/Skeleton3D:"+actor.skeleton.get_bone_name(bone))
			indices.append([clip.find_track(path,Animation.TYPE_POSITION_3D),clip.find_track(path,Animation.TYPE_ROTATION_3D)])
		tracks.append(indices)

func advance(direction: Vector2, delta: float) -> float:
	sampled = false
	var requested := direction.x>0.35 and absf(direction.y)<0.3
	if not active:
		if not requested:
			hold = 0
			return 0
		active = true
		phase = 0
		strength = smoothstep(0.08,0.5,hold)*2
		previous_root = 0
	if requested:
		hold += delta
		strength = smoothstep(0.08,0.5,hold)*2
	var a := mini(1,int(strength))
	var b := a+1
	var blend := strength-a
	var duration := lerpf(clips[a].length,clips[b].length,blend)
	phase = minf(1,phase+delta/duration)
	var root := lerpf(root_at(a),root_at(b),blend)
	var displacement := root-previous_root
	previous_root = root
	active = phase<1
	sampled = true
	return displacement

func root_at(index: int) -> float:
	var curve: PackedFloat32Array = clips[index].get_meta("root_right")
	var point := phase*(curve.size()-1)
	var frame := mini(curve.size()-2,int(point))
	return lerpf(curve[frame],curve[frame+1],point-frame)

func apply_pose() -> void:
	if not sampled: return
	var a := mini(1,int(strength))
	var b := a+1
	var blend := strength-a
	var weight := smoothstep(0,0.10,phase)*(1-smoothstep(0.90,1,phase))
	var rig: Skeleton3D = actor.skeleton
	for bone in rig.get_bone_count():
		var pa: int = tracks[a][bone][0]
		var pb: int = tracks[b][bone][0]
		var qa: int = tracks[a][bone][1]
		var qb: int = tracks[b][bone][1]
		var position := clips[a].position_track_interpolate(pa,phase*clips[a].length).lerp(clips[b].position_track_interpolate(pb,phase*clips[b].length),blend)
		var rotation := clips[a].rotation_track_interpolate(qa,phase*clips[a].length).slerp(clips[b].rotation_track_interpolate(qb,phase*clips[b].length),blend)
		rig.set_bone_pose_position(bone,rig.get_bone_pose_position(bone).lerp(position,weight))
		rig.set_bone_pose_rotation(bone,rig.get_bone_pose_rotation(bone).slerp(rotation,weight))
