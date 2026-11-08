extends RefCounted
const Flight = preload("res://scripts/pass_flight.gd")
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

func adapted_pose(time: float, pitch: float, lift: float, drive := 0.0) -> Array:
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
	var offset := time-contact_time
	var push := drive*offset*exp(-pow(offset/0.14,2))*platform_weight
	for side in ["l","r"]: author.rotate_world(pose,"upperarm_"+side,Vector3.RIGHT,pitch*platform_weight+push)
	return pose

func surface(time: float, pitch: float, lift: float, drive := 0.0) -> Dictionary:
	var pose := adapted_pose(time,pitch,lift,drive)
	var rig: Skeleton3D = actor.skeleton
	var elbows := []
	var wrists := []
	for side in ["l","r"]:
		elbows.append(rig.global_transform*author.point(pose,"lowerarm_"+side))
		wrists.append(rig.global_transform*author.point(pose,"hand_"+side))
	return Contact.surface(elbows,wrists,0.032*rig.global_basis.get_scale().y)

func response(pitch: float, lift: float, drive := 0.0) -> Vector3:
	var hit := surface(contact_time,pitch,lift,drive)
	var before := surface(maxf(0,contact_time-1.0/60),pitch,lift,drive)
	var after := surface(minf(source.length,contact_time+1.0/60),pitch,lift,drive)
	var velocity: Vector3 = (after.surface-before.surface)/(2.0/60)
	return Contact.rebound(Flight.feed(hit.ball).incoming,velocity,hit.normal)

func solve(requested: float, distance_ := 6.0) -> Dictionary:
	var goal := clampf(requested,10,80)
	var key := "%d/%s/%s/%.2f/%.2f" % [source.get_instance_id(),actor.scale,actor.position,goal,distance_]
	if cache.has(key): return cache[key]
	var lift := clampf((distance_-4.0)*0.003,0,0.025)
	var pitch := 0.0
	var drive := 0.0
	var smallest := INF
	var best := Vector2.ZERO
	# Fit platform pitch and contact-time arm speed to the requested launch velocity.
	for iteration in range(14):
		var hit := surface(contact_time,pitch,lift,drive)
		var target := Flight.desired_velocity(hit.ball,goal,distance_)
		var velocity := response(pitch,lift,drive)
		var horizontal := Vector2(velocity.x,velocity.z).length()
		var error := Vector2(velocity.y-target.y,horizontal-target.z)
		if error.length_squared() < smallest:
			smallest = error.length_squared()
			best = Vector2(pitch,drive)
		if smallest < 0.000001: break
		var dp := response(pitch+0.001,lift,drive)-velocity
		var dd := response(pitch,lift,drive+0.01)-velocity
		var a := dp.y/0.001
		var b := dd.y/0.01
		var c := (Vector2(velocity.x+dp.x,velocity.z+dp.z).length()-horizontal)/0.001
		var d := (Vector2(velocity.x+dd.x,velocity.z+dd.z).length()-horizontal)/0.01
		var determinant := a*d-b*c
		if absf(determinant)<0.00001: break
		pitch = clampf(pitch-clampf((d*error.x-b*error.y)/determinant,-0.2,0.2),-0.75,0.75)
		drive = clampf(drive-clampf((-c*error.x+a*error.y)/determinant,-3,3),-18,18)
	var affected: Array[String] = ["pelvis","upperarm_l","upperarm_r","thigh_l","thigh_r","calf_l","calf_r","foot_l","foot_r"]
	var clip: Animation = author.bake_overrides(source,func(time): return adapted_pose(time,best.x,lift,best.y),affected)
	var hit := surface(contact_time,best.x,lift,best.y)
	var outgoing := response(best.x,lift,best.y)
	var actual := Contact.elevation(outgoing)
	clip.set_meta("desired_output_angle",goal)
	clip.set_meta("desired_distance",distance_)
	clip.set_meta("solved_output_angle",actual)
	var result := {"clip":clip,"requested":goal,"actual":actual,"pitch":rad_to_deg(best.x),"drive":best.y,"lift":lift,"distance":Flight.distance(hit.ball,outgoing),"error":absf(actual-goal)}
	if cache.size() >= 64: cache.erase(cache.keys()[0])
	cache[key] = result
	return result
