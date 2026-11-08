extends RefCounted
const Author = preload("res://tools/animation_author.gd")
const Contact = preload("res://scripts/forearm_contact.gd")
static var cache: Dictionary = {}
var actor: Node3D
var source: Animation
var author: RefCounted
var raw_cache := {}
var positions := {}
var rotations := {}
var contact_time := 0.6
var incoming := Vector3(0,-5.5,-4.5)

func _init(player: Node3D, clip: Animation) -> void:
	actor = player
	source = clip
	author = Author.new(actor.skeleton,source)
	contact_time = float(source.get_meta("contact_time",0.6))
	for bone in actor.skeleton.get_bone_count():
		var path := NodePath("Armature/Skeleton3D:"+actor.skeleton.get_bone_name(bone))
		positions[bone] = source.find_track(path,Animation.TYPE_POSITION_3D)
		rotations[bone] = source.find_track(path,Animation.TYPE_ROTATION_3D)

func raw_pose(time: float) -> Array:
	if raw_cache.has(time): return raw_cache[time].duplicate()
	var rig: Skeleton3D = actor.skeleton
	var pose: Array = []
	for bone in rig.get_bone_count():
		var local := rig.get_bone_rest(bone)
		if positions[bone] >= 0: local.origin = source.position_track_interpolate(positions[bone],time)
		if rotations[bone] >= 0: local.basis = Basis(source.rotation_track_interpolate(rotations[bone],time))
		pose.append(local)
	raw_cache[time] = pose
	return pose.duplicate()

func adapted_pose(time: float, pitch: float, lift: float) -> Array:
	var pose := raw_pose(time)
	var rig: Skeleton3D = actor.skeleton
	var recovery := 1.0-smoothstep(contact_time+0.2,minf(source.length,contact_time+0.68),time)
	var platform_weight := smoothstep(0,contact_time-0.12,time)*recovery
	var amount := lift*smoothstep(maxf(0,contact_time-0.18),contact_time+0.18,time)*recovery
	if absf(amount) > 0.000001:
		var feet := {}
		var poles := {}
		for side in ["l","r"]:
			feet[side] = author.world_pose(pose,rig.find_bone("foot_"+side))
			poles[side] = author.point(pose,"calf_"+side)-author.point(pose,"thigh_"+side)
			if amount > 0:
				var hip: Vector3 = author.point(pose,"thigh_"+side)
				var knee: Vector3 = author.point(pose,"calf_"+side)
				var foot: Vector3 = feet[side].origin
				var reach := hip.distance_to(knee)+knee.distance_to(foot)-0.003
				var horizontal := Vector2(hip.x-foot.x,hip.z-foot.z).length_squared()
				amount = minf(amount,maxf(0,foot.y+sqrt(maxf(0,reach*reach-horizontal))-hip.y))
		var pelvis := rig.find_bone("pelvis")
		var parent := rig.get_bone_parent(pelvis)
		pose[pelvis].origin += author.world_pose(pose,parent).basis.inverse()*Vector3.UP*amount
		for side in ["l","r"]:
			author.limb(pose,"thigh_"+side,"calf_"+side,"foot_"+side,feet[side].origin,poles[side])
			author.set_world_basis(pose,"foot_"+side,feet[side].basis)
	for side in ["l","r"]: author.rotate_world(pose,"upperarm_"+side,Vector3.RIGHT,pitch*platform_weight)
	return pose

func surface(time: float, pitch: float, lift: float) -> Dictionary:
	var pose := adapted_pose(time,pitch,lift)
	var rig: Skeleton3D = actor.skeleton
	var elbows := []
	var wrists := []
	for side in ["l","r"]:
		elbows.append(rig.global_transform*author.point(pose,"lowerarm_"+side))
		wrists.append(rig.global_transform*author.point(pose,"hand_"+side))
	return Contact.surface(elbows,wrists,0.032*rig.global_basis.get_scale().y)

func response(pitch: float, lift: float) -> Vector3:
	var hit := surface(contact_time,pitch,lift)
	var before := surface(maxf(0,contact_time-1.0/60),pitch,lift)
	var after := surface(minf(source.length,contact_time+1.0/60),pitch,lift)
	var velocity: Vector3 = (after.surface-before.surface)/(2.0/60)
	return Contact.rebound(incoming,velocity,hit.normal)

func solve(requested: float) -> Dictionary:
	var goal := clampf(requested,10,80)
	var key := "%d/%.2f/%.2f" % [source.get_instance_id(),actor.scale.y,goal]
	if cache.has(key): return cache[key]
	var native_angle := Contact.elevation(response(0,0))
	var lift := clampf((goal-native_angle)*0.0006,-0.01,0.025)
	var low := deg_to_rad(-35)
	var high := deg_to_rad(35)
	var best := 0.0
	var smallest := INF
	for iteration in range(18):
		var pitch := (low+high)*0.5
		var velocity := response(pitch,lift)
		var angle := Contact.elevation(velocity)
		if velocity.z < 0: angle = 180.0-angle
		var error := absf(angle-goal)
		if error < smallest: smallest = error; best = pitch
		if angle > goal: low = pitch
		else: high = pitch
	var description := {"name":source.resource_name,"duration":source.length,"contact_time":contact_time}
	var clip: Animation = author.bake(description,func(time): return adapted_pose(time,best,lift))
	for meta in source.get_meta_list(): clip.set_meta(meta,source.get_meta(meta))
	var outgoing := response(best,lift)
	var actual := Contact.elevation(outgoing)
	clip.set_meta("desired_output_angle",goal)
	clip.set_meta("solved_output_angle",actual)
	var result := {"clip":clip,"requested":goal,"actual":actual,"pitch":rad_to_deg(best),"lift":lift,"error":absf(actual-goal)}
	if cache.size() >= 64: cache.erase(cache.keys()[0])
	cache[key] = result
	return result
