extends RefCounted

const OUTSIDE_CONTACT := Vector3(-0.32,-0.11,0.03)

const EditSession = preload("res://scripts/animation_edit_session.gd")

# title, draw depth, elbow height, chest coil, shoulder tilt, leg split, leg kick, drive start, finish width, guide height, guide width, elbow width
const STUDIES := [
	["01 Reference sequence", 0.29, 0.24, 0.38, 0.26, 0.24, 0.24, 0.67, 0.30, 0.38, 0.23, 0.36],
	["02 Compact elbow",      0.23, 0.20, 0.29, 0.19, 0.18, 0.20, 0.62, 0.22, 0.29, 0.13, 0.26],
	["03 Deep draw",          0.38, 0.26, 0.43, 0.24, 0.24, 0.28, 0.71, 0.32, 0.39, 0.19, 0.41],
	["04 High elbow",         0.28, 0.36, 0.34, 0.20, 0.21, 0.23, 0.66, 0.25, 0.45, 0.20, 0.30],
	["05 Long guide arm",     0.32, 0.29, 0.41, 0.28, 0.29, 0.23, 0.73, 0.35, 0.52, 0.29, 0.39],
	["06 Hip-led release",    0.31, 0.25, 0.49, 0.23, 0.26, 0.24, 0.70, 0.39, 0.32, 0.20, 0.34],
	["07 Wide scissor",       0.28, 0.28, 0.36, 0.27, 0.39, 0.20, 0.65, 0.31, 0.35, 0.33, 0.39],
	["08 High trail heel",    0.30, 0.23, 0.39, 0.22, 0.22, 0.35, 0.69, 0.30, 0.35, 0.18, 0.34],
	["09 Side reach",         0.33, 0.28, 0.42, 0.37, 0.32, 0.24, 0.72, 0.41, 0.44, 0.36, 0.45],
	["10 Fast arm whip",      0.25, 0.30, 0.32, 0.22, 0.23, 0.22, 0.75, 0.32, 0.30, 0.15, 0.28],
]

static func bake(base: Animation, actor: Node3D, index: int) -> Animation:
	var rig: Skeleton3D = actor.skeleton
	var author: RefCounted = actor.get_pose_author()
	var session := EditSession.new(base,rig)
	var timing: float = base.get_meta("contact_time")
	var prep: float = base.get_meta("study_prep_duration")
	var profile: Array = STUDIES[index]
	var ball: Vector3 = base.get_meta("study_ball_point")+OUTSIDE_CONTACT
	var sampler := func(time: float) -> Array:
		var frame := time*session.frame_rate
		var pose: Array[Transform3D] = []
		for bone in rig.get_bone_count():
			pose.append(Transform3D(Basis(session.source_rotation(bone,frame)),session.source_position(bone,frame)))
		shape(pose,author,profile,ball,(time-prep)/(timing-prep),(time-timing)/(base.length-timing))
		return pose
	var clip: Animation = author.bake({"name":profile[0],"duration":base.length,"contact_time":timing},sampler)
	for key in ["editor_start","editor_group","editor_height_cm"]:
		clip.set_meta(key,base.get_meta(key))
	var feed: Dictionary = base.get_meta("editor_feed").duplicate()
	var offset := OUTSIDE_CONTACT*(float(base.get_meta("editor_height_cm"))/180.0)
	feed.aim += offset
	feed.incoming += offset/float(feed.duration)
	clip.set_meta("editor_feed",feed)
	clip.set_meta("editor_frame_count",25)
	return clip

static func shape(pose: Array[Transform3D], author: RefCounted, profile: Array, ball: Vector3, progress: float, landing: float) -> void:
	var rising := smoothstep(0.03,0.32,progress)
	var drive := smoothstep(float(profile[7]),1.0,progress)
	var settle := smoothstep(0.12,0.92,landing)
	var windup := rising*(1.0-drive)
	var air := rising*(1.0-settle)
	var follow := smoothstep(0.0,0.45,landing)*(1.0-settle)
	var strike_wrist: Vector3 = author.point(pose,"hand_r")
	var strike_palm: Vector3 = strike_wrist.lerp(author.point(pose,"middle_01_r"),0.75)
	strike_wrist += (ball-strike_palm).limit_length(0.33)
	var left_foot: Vector3 = author.point(pose,"foot_l")
	var right_foot: Vector3 = author.point(pose,"foot_r")
	# The pelvis starts to open before the shoulders unwind.
	var hips_open := smoothstep(0.42,float(profile[7])+0.10,progress)
	author.rotate_world(pose,"pelvis",Vector3.UP,float(profile[3])*0.40*air*(2.0*hips_open-1.0))
	author.rotate_world(pose,"pelvis",Vector3.BACK,float(profile[4])*0.45*(windup+0.55*drive*air))
	author.rotate_world(pose,"spine_02",Vector3.RIGHT,-0.19*windup+0.19*follow)
	author.rotate_world(pose,"spine_03",Vector3.UP,-float(profile[3])*windup+float(profile[3])*0.52*follow)
	author.rotate_world(pose,"spine_03",Vector3.BACK,float(profile[4])*0.55*(windup+0.42*drive*air))

	var scissor := smoothstep(0.24,0.88,progress)*(1.0-settle)
	var split: float = profile[5]
	var kick: float = profile[6]
	var lead_hip: Vector3 = author.point(pose,"thigh_l")
	var trail_hip: Vector3 = author.point(pose,"thigh_r")
	var lead_leg := lead_hip+Vector3(split,-0.76,0.14)
	var trail_leg := trail_hip+Vector3(-split*0.46,-0.41+kick*0.32,-0.39-kick*0.58)
	author.limb(pose,"thigh_l","calf_l","foot_l",left_foot.lerp(lead_leg,scissor),Vector3(0.24,0.05,1.0),scissor,167.0)
	author.limb(pose,"thigh_r","calf_r","foot_r",right_foot.lerp(trail_leg,scissor),Vector3(-0.31,0.1,1.0),scissor,150.0)

	var guide: Vector3 = author.point(pose,"upperarm_l")
	var guide_drop := smoothstep(float(profile[7])-0.18,0.96,progress)
	var guide_target := guide+Vector3(profile[10],profile[9],0.53).lerp(Vector3(0.09,-0.43,0.09),guide_drop)
	author.limb(pose,"upperarm_l","lowerarm_l","hand_l",guide_target,Vector3(0.52,-0.48,-0.06),air,158.0)

	var shoulder: Vector3 = author.point(pose,"upperarm_r")
	var chamber := shoulder+Vector3(-float(profile[11]),float(profile[2]),-float(profile[1]))
	var release_start := float(profile[7])
	var elbow_lead := smoothstep(release_start,lerpf(release_start,1.0,0.50),progress)
	var hand_release := smoothstep(lerpf(release_start,1.0,0.49),1.0,progress)
	var pole := Vector3(-1.0,-0.12,-0.34).lerp(Vector3(-0.95,-0.08,0.48),hand_release)
	var finish_target := shoulder+Vector3(float(profile[8]),-0.39,0.34)
	var strike_pose := pose.duplicate()
	var strike_target := strike_wrist.lerp(finish_target,follow)
	author.limb(strike_pose,"upperarm_r","lowerarm_r","hand_r",strike_target,pole,air,lerpf(148.0,132.0,follow))

	# Lead with the elbow while the bent forearm trails behind it.
	author.limb(pose,"upperarm_r","lowerarm_r","hand_r",chamber,Vector3(-1.0,-0.12,-0.34),air,108.0)
	var elbow: Vector3 = author.point(pose,"lowerarm_r")
	var wrist: Vector3 = author.point(pose,"hand_r")
	var upper := (elbow-shoulder).normalized()
	var forearm := (wrist-elbow).normalized()
	var lead_weight := elbow_lead*air
	var elbow_forward := Vector3(-0.95,0.20,0.96).normalized()
	author.aim_joint(pose,"upperarm_r","lowerarm_r",shoulder+upper.slerp(elbow_forward,lead_weight))
	elbow = author.point(pose,"lowerarm_r")
	var trailing := Vector3(-0.34,0.48,-0.92).normalized()
	author.aim_joint(pose,"lowerarm_r","hand_r",elbow+forearm.slerp(trailing,lead_weight))
	for bone in ["upperarm_r","lowerarm_r","hand_r"]:
		var index: int = author.rig.find_bone(bone)
		var load_rotation := pose[index].basis.get_rotation_quaternion()
		var strike_rotation: Quaternion = strike_pose[index].basis.get_rotation_quaternion()
		pose[index].basis = Basis(load_rotation.slerp(strike_rotation,hand_release))
