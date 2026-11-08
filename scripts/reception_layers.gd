extends RefCounted
const Flight = preload("res://scripts/pass_flight.gd")
static var BODIES: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/animation_recipes/reception_bodies.json"))
var actor: Node3D
var rig: Skeleton3D
var author: RefCounted
var source: Animation
var body_clip: Animation
var body_tracks := {}
var body_name := "Balanced"
var hand_name := "From platform"
var recipe := {}
var speed := 0.0
var angle := 0.0
var contact := 0.6
var preserve_body := false

func _init(player: Node3D, clip: Animation, builder: RefCounted) -> void:
	actor = player
	rig = actor.skeleton
	author = builder
	source = clip
	contact = float(source.get_meta("contact_time",0.6))
	body_clip = load("res://assets/animations/straight_pass_01.tres")
	for bone in rig.get_bone_count():
		var name_ := str(rig.get_bone_name(bone))
		if body_bone(name_):
			var path := NodePath("Armature/Skeleton3D:"+name_)
			body_tracks[bone] = [body_clip.find_track(path,Animation.TYPE_POSITION_3D),body_clip.find_track(path,Animation.TYPE_ROTATION_3D)]

func body_bone(name_: String) -> bool:
	return name_=="pelvis" or name_.begins_with("spine_") or name_.begins_with("neck_") or name_=="Head" or name_.begins_with("thigh_") or name_.begins_with("calf_") or name_.begins_with("foot_") or name_.begins_with("ball_")

func configure(pose: Array) -> void:
	var options: Dictionary = actor.get_meta("reception_options",{})
	body_name = str(options.get("body","Auto"))
	hand_name = str(options.get("hands","From platform"))
	var wrists := []
	var elbows := []
	for side in ["l","r"]:
		elbows.append(rig.global_transform*author.point(pose,"lowerarm_"+side))
		wrists.append(rig.global_transform*author.point(pose,"hand_"+side))
	var hit: Dictionary = preload("res://scripts/forearm_contact.gd").surface(elbows,wrists,0.032*rig.global_basis.get_scale().y)
	var feed := Flight.feed(hit.ball,actor.get_meta("feed_settings",{}))
	speed = feed.incoming.length()
	angle = rad_to_deg(atan2(-feed.incoming.y,Vector2(feed.incoming.x,feed.incoming.z).length()))
	if body_name=="Auto":
		var local: Vector3 = actor.global_basis.inverse()*feed.incoming.normalized()
		if speed>=24 and angle>=52: body_name = "Hip drop"
		elif speed>=18 and angle>=40: body_name = "Knee drop"
		elif absf(local.x)>0.35: body_name = "Split stance"
		elif speed>=12: body_name = "Low base"
		else: body_name = "Balanced"
	preserve_body = body_name=="From clip" or (source.has_meta("reception_body") and not options.get("replace_body",false))
	if preserve_body:
		body_name = str(source.get_meta("reception_body","From clip"))
		recipe = {}
	else: recipe = BODIES.get(body_name,BODIES.Balanced).duplicate()

func apply(pose: Array, time: float) -> Array:
	var result := pose.duplicate()
	if not preserve_body:
		for bone in body_tracks:
			var pair: Array = body_tracks[bone]
			if pair[0]>=0: result[bone].origin = body_clip.position_track_interpolate(pair[0],time)
			if pair[1]>=0: result[bone].basis = Basis(body_clip.rotation_track_interpolate(pair[1],time))
		body(result,time)
	hands(result,time)
	return result

func body(pose: Array, time: float) -> void:
	var prepare := smoothstep(0,maxf(0.1,contact-0.22),time)
	var recover := 1.0-smoothstep(contact+0.58,minf(source.length,contact+1.5),time)
	var brace := smoothstep(contact-0.13,contact+0.20,time)
	var settle := smoothstep(contact-0.02,contact+0.32,time)
	var floor_move := body_name in ["Knee drop","Hip drop"]
	var give := settle if floor_move else brace
	var lower := (float(recipe.lower)*prepare+float(recipe.give)*give)*recover
	var backward := float(recipe.retreat)*give*recover
	var feet := {}
	var poles := {}
	for side in ["l","r"]:
		feet[side] = author.world_pose(pose,rig.find_bone("foot_"+side))
		poles[side] = author.point(pose,"calf_"+side)-author.point(pose,"thigh_"+side)
	var pelvis := rig.find_bone("pelvis")
	var parent := rig.get_bone_parent(pelvis)
	pose[pelvis].origin += author.world_pose(pose,parent).basis.inverse()*Vector3(0,-lower,-backward)
	var lean := deg_to_rad(float(recipe.lean))*prepare*recover
	author.rotate_world(pose,"spine_02",Vector3.RIGHT,lean*0.55)
	author.rotate_world(pose,"spine_03",Vector3.RIGHT,lean*0.45)
	author.rotate_world(pose,"neck_01",Vector3.RIGHT,-lean*0.65)
	for side in ["l","r"]:
		var sign_ := 1.0 if side=="l" else -1.0
		var target: Vector3 = feet[side].origin
		target.x += sign_*float(recipe.wide)*prepare*recover
		target.z += sign_*float(recipe.stagger)*prepare*recover
		var stepping := sin(PI*prepare)*recover
		target.y += stepping*(0.035 if body_name!="Balanced" else 0.0)
		var pole: Vector3 = poles[side]
		var foot_basis: Basis = feet[side].basis
		if body_name=="Knee drop" and side=="r":
			target.z -= 0.34*settle*recover
			target.y += 0.11*settle*recover
			pole = pole.lerp(Vector3(0,-1,0.25),settle*recover)
			foot_basis = Basis(Vector3.RIGHT,deg_to_rad(40)*settle*recover)*foot_basis
		elif body_name=="Hip drop":
			target.z += 0.22*settle*recover
			pole = pole.lerp(Vector3(sign_*0.15,1,0.4),settle*recover)
		author.limb(pose,"thigh_"+side,"calf_"+side,"foot_"+side,target,pole)
		author.set_world_basis(pose,"foot_"+side,foot_basis)

func hands(pose: Array, time: float) -> void:
	if hand_name=="From platform": return
	var weight := smoothstep(0,contact-0.2,time)*(1.0-smoothstep(contact+0.25,contact+0.65,time))
	var curl := 80.0 if hand_name=="Firm clasp" else 45.0
	for side in ["l","r"]:
		for finger in ["index","middle","ring","pinky"]:
			for segment in range(1,4):
				var bone := rig.find_bone("%s_%02d_%s" % [finger,segment,side])
				var desired := rig.get_bone_rest(bone).basis*Basis(Vector3.RIGHT,deg_to_rad(curl))
				pose[bone].basis = Basis(pose[bone].basis.get_rotation_quaternion().slerp(desired.get_rotation_quaternion(),weight))
	author.pose_thumbs(pose,weight,14)
