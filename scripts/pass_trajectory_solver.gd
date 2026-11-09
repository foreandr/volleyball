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
var layers: RefCounted
var restitution := 0.55
var receive_reach := Vector2.ZERO

func _init(player: Node3D, clip: Animation) -> void:
	actor = player
	source = clip
	author = Author.new(actor.skeleton,source)
	contact_time = float(source.get_meta("contact_time",0.6))
	for bone in actor.skeleton.get_bone_count():
		var path := NodePath("Armature/Skeleton3D:"+actor.skeleton.get_bone_name(bone))
		positions[bone] = source.find_track(path,Animation.TYPE_POSITION_3D)
		rotations[bone] = source.find_track(path,Animation.TYPE_ROTATION_3D)
	layers = preload("res://scripts/reception_layers.gd").new(actor,source,author)

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

func adapted_pose(time: float, pitch: float, lift: float, drive := 0.0, yaw := 0.0) -> Array:
	var pose: Array = layers.apply(raw_pose(time),time)
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
	author.rotate_world(pose,"spine_03",Vector3.UP,yaw*platform_weight)
	var offset := time-contact_time
	# One continuous contact stroke; a decaying impulse creates a second arm swing.
	var push := drive*0.10*tanh(offset/0.10)*platform_weight
	var pitch_axis := Basis(Vector3.UP,yaw*platform_weight)*Vector3.RIGHT
	for side in ["l","r"]: author.rotate_world(pose,"upperarm_"+side,pitch_axis,pitch*platform_weight+push)
	if not receive_reach.is_zero_approx():
		apply_receive_reach(pose,receive_reach*platform_weight)
	return pose

func apply_receive_reach(pose: Array, offset: Vector2) -> void:
	var rig: Skeleton3D = actor.skeleton
	var wanted := Vector3(offset.x,0,offset.y)/rig.global_basis.get_scale().y
	var platform_center: Vector3 = (author.point(pose,"hand_l")+author.point(pose,"hand_r"))*0.5
	# Tilt the shoulders into the reach. Add only the travel the tilt cannot supply.
	author.rotate_world(pose,"spine_02",Vector3.RIGHT,wanted.z*1.2)
	author.rotate_world(pose,"spine_02",Vector3.BACK,-wanted.x*1.2)
	var moved_center: Vector3 = (author.point(pose,"hand_l")+author.point(pose,"hand_r"))*0.5
	var correction := wanted+platform_center-moved_center
	correction.y = 0.0
	var shoulder_base := rig.find_bone("spine_03")
	var parent := rig.get_bone_parent(shoulder_base)
	pose[shoulder_base].origin += author.world_pose(pose,parent).basis.inverse()*correction

func surface(time: float, pitch: float, lift: float, drive := 0.0, yaw := 0.0) -> Dictionary:
	var pose := adapted_pose(time,pitch,lift,drive,yaw)
	var rig: Skeleton3D = actor.skeleton
	var elbows := []
	var wrists := []
	for side in ["l","r"]:
		elbows.append(rig.global_transform*author.point(pose,"lowerarm_"+side))
		wrists.append(rig.global_transform*author.point(pose,"hand_"+side))
	return Contact.surface(elbows,wrists,0.032*rig.global_basis.get_scale().y)

func response(pitch: float, lift: float, drive := 0.0, yaw := 0.0) -> Vector3:
	var hit := surface(contact_time,pitch,lift,drive,yaw)
	var before := surface(maxf(0,contact_time-1.0/60),pitch,lift,drive,yaw)
	var after := surface(minf(source.length,contact_time+1.0/60),pitch,lift,drive,yaw)
	var velocity: Vector3 = (after.surface-before.surface)/(2.0/60)
	return Contact.rebound(Flight.feed(hit.ball,actor.get_meta("feed_settings",{})).incoming,velocity,hit.normal,restitution)

func contact_softness(pitch: float, lift: float, yaw: float, target_info: Dictionary, goal: float) -> float:
	var hit := surface(contact_time,pitch,lift,0,yaw)
	var feed := Flight.feed(hit.ball,actor.get_meta("feed_settings",{}))
	var desired := Flight.target_velocity(hit.ball,target_info,goal)
	var impulse: Vector3 = desired-feed.incoming
	var normal := impulse.normalized()
	var before := surface(contact_time-1.0/60,pitch,lift,0,yaw)
	var after := surface(contact_time+1.0/60,pitch,lift,0,yaw)
	var velocity: Vector3 = (after.surface-before.surface)/(2.0/60)
	var closing := maxf(0.1,-(feed.incoming-velocity).dot(normal))
	return clampf(impulse.length()/closing-1.0,0.02,0.65)

func solve(requested: float, distance_ := 6.0) -> Dictionary:
	layers.configure(raw_pose(contact_time))
	receive_reach = actor.get_meta("receive_reach",Vector2.ZERO)
	var goal := clampf(requested,10,85)
	var target_info: Dictionary = actor.get_meta("pass_target",{})
	if target_info.is_empty():
		var point := actor.global_position+actor.global_basis.z*distance_
		target_info = {"position":Vector2(point.x,point.z),"fit":"angle"}
	var key := "%d/%s/%s/%.2f/%s/%s/%s" % [source.get_instance_id(),actor.scale,actor.position,goal,target_info,actor.get_meta("feed_settings",{}),actor.get_meta("reception_options",{})]
	key += "/"+str(receive_reach)
	if cache.has(key): return cache[key]
	var target_position: Vector2 = target_info.position
	var range_ := target_position.distance_to(Vector2(actor.global_position.x,actor.global_position.z))
	var lift := clampf((range_-4.0)*0.003,0,0.025)
	restitution = contact_softness(0,lift,0,target_info,goal)
	var pitch := 0.0
	var drive := 0.0
	var yaw := 0.0
	var smallest := INF
	var best := Vector3.ZERO
	# Fit all three launch-velocity components using platform pitch, twist and contact speed.
	for iteration in range(28):
		if iteration == 14:
			pitch = best.x
			yaw = best.z
			drive = 0
			restitution = contact_softness(pitch,lift,yaw,target_info,goal)
			smallest = INF
		var hit := surface(contact_time,pitch,lift,drive,yaw)
		var target := Flight.target_velocity(hit.ball,target_info,goal)
		var velocity := response(pitch,lift,drive,yaw)
		var error := velocity-target
		if error.length_squared()<smallest:
			smallest = error.length_squared()
			best = Vector3(pitch,drive,yaw)
		if smallest<0.000001: break
		var dp := (response(pitch+0.001,lift,drive,yaw)-velocity)/0.001
		var dd := (response(pitch,lift,drive+0.01,yaw)-velocity)/0.01
		var dy := (response(pitch,lift,drive,yaw+0.001)-velocity)/0.001
		var jacobian := Basis(dp,dd,dy)
		if absf(jacobian.determinant())<0.00001: break
		var change := jacobian.inverse()*error
		pitch = clampf(pitch-clampf(change.x,-0.2,0.2),-1.1,1.1)
		drive = clampf(drive-clampf(change.y,-3,3),-3.5,3.5)
		yaw = clampf(yaw-clampf(change.z,-0.2,0.2),-1.4,1.4)
	var affected: Array[String] = []
	for bone in actor.skeleton.get_bone_count(): affected.append(str(actor.skeleton.get_bone_name(bone)))
	var clip: Animation = author.bake_overrides(source,func(time): return adapted_pose(time,best.x,lift,best.y,best.z),affected)
	var hit := surface(contact_time,best.x,lift,best.y,best.z)
	var outgoing := response(best.x,lift,best.y,best.z)
	var actual := Contact.elevation(outgoing)
	clip.set_meta("reception_body",layers.body_name)
	clip.set_meta("reception_hands",layers.hand_name)
	clip.set_meta("reception_restitution",restitution)
	clip.set_meta("desired_output_angle",goal)
	clip.set_meta("desired_distance",range_)
	clip.set_meta("destination",target_position)
	clip.set_meta("solved_output_angle",actual)
	var landing: Vector3 = hit.ball+outgoing*Flight.landing_time(hit.ball,outgoing)+Vector3.DOWN*4.905*pow(Flight.landing_time(hit.ball,outgoing),2)
	var result := {"clip":clip,"requested":goal,"actual":actual,"pitch":rad_to_deg(best.x),"drive":best.y,"yaw":rad_to_deg(best.z),"lift":lift,"distance":Flight.distance(hit.ball,outgoing),"error":Vector2(landing.x,landing.z).distance_to(target_position),"body":layers.body_name,"restitution":restitution}
	if cache.size()>=64: cache.erase(cache.keys()[0])
	cache[key] = result
	return result
