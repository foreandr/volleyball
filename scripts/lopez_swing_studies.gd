extends RefCounted

const OUTSIDE_CONTACT := Vector3(-0.32,-0.11,0.03)

const SpikeArm = preload("res://scripts/spike_arm_swing.gd")
const Flight = preload("res://scripts/pass_flight.gd")
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

static func bake(base: Animation, actor: Node3D, index: int, crosscourt := false, shot_target := Vector3.INF) -> Animation:
	var rig: Skeleton3D = actor.skeleton
	var author: RefCounted = actor.get_pose_author()
	var session := EditSession.new(base,rig)
	var timing: float = base.get_meta("contact_time")
	var prep: float = base.get_meta("study_prep_duration")
	var draw_start := prep+float(base.get_meta("study_draw_delay",SpikeArm.DEFAULT_DRAW_DELAY))-SpikeArm.BASE_DRAW_DELAY
	var elbow_clearance: float = base.get_meta("study_elbow_clearance",SpikeArm.DEFAULT_ELBOW_CLEARANCE)
	var profile: Array = STUDIES[index]
	var ball: Vector3 = base.get_meta("study_ball_point")+OUTSIDE_CONTACT
	var feed: Dictionary = base.get_meta("editor_feed").duplicate()
	var offset := OUTSIDE_CONTACT*(float(base.get_meta("editor_height_cm"))/180.0)
	feed.aim += offset
	feed.incoming += offset/float(feed.duration)
	var outgoing: Vector3 = feed.spike_outgoing
	var target := shot_target if shot_target.is_finite() else Vector3(-2.5 if crosscourt else feed.aim.x,Flight.FLOOR,10.5)
	var travel: Vector3 = target-feed.aim
	var flight_time := travel.slide(Vector3.UP).length()/maxf(outgoing.slide(Vector3.UP).length(),0.1)
	feed.spike_outgoing = travel/flight_time+Vector3.UP*Flight.GRAVITY*flight_time*0.5
	var shot_turn := SpikeArm.follow_heading(target,feed.aim)
	var palm_finish := SpikeArm.finish_palm_direction(target,feed.aim,not crosscourt)
	var base_turn := SpikeArm.follow_heading(base.get_meta("study_base_aim"),feed.aim)
	var duration := base.length+0.12
	var sampler := func(time: float) -> Array:
		var frame := minf(time,base.length)*session.frame_rate
		var pose: Array[Transform3D] = []
		for bone in rig.get_bone_count():
			pose.append(Transform3D(Basis(session.source_rotation(bone,frame)),session.source_position(bone,frame)))
		shape(pose,author,profile,ball,(time-draw_start)/(timing-draw_start),(time-timing)/(base.length-timing),crosscourt,shot_turn-base_turn,palm_finish,elbow_clearance)
		return pose
	var title: String = profile[0]+(" Crosscourt" if crosscourt else "")
	var clip: Animation = author.bake({"name":title,"duration":duration,"contact_time":timing},sampler)
	for key in ["editor_start","editor_group","editor_height_cm"]:
		clip.set_meta(key,base.get_meta(key))
	clip.set_meta("editor_feed",feed)
	clip.set_meta("editor_frame_count",25)
	return clip

static func shape(pose: Array[Transform3D], author: RefCounted, profile: Array, ball: Vector3, progress: float, landing: float, crosscourt: bool, aim_turn: float, palm_finish: float, elbow_clearance: float) -> void:
	var rising := smoothstep(0.03,0.32,progress)
	var drive := smoothstep(float(profile[7]),1.0,progress)
	var settle := smoothstep(0.12,0.92,landing)
	var windup := rising*(1.0-drive)
	var air := rising*(1.0-settle)
	var sweep := 1.0-pow(1.0-clampf(landing/0.56,0.0,1.0),2.0)
	var finish_hold := sweep*(1.0-smoothstep(0.59,1.22,landing))
	var strike_wrist: Vector3 = author.point(pose,"hand_r")
	var strike_palm: Vector3 = strike_wrist.lerp(author.point(pose,"middle_01_r"),0.75)
	strike_wrist += (ball-strike_palm).limit_length(0.33)
	var left_foot: Vector3 = author.point(pose,"foot_l")
	var right_foot: Vector3 = author.point(pose,"foot_r")
	# The pelvis starts to open before the shoulders unwind.
	var hips_open := smoothstep(0.29,1.03,progress)
	author.rotate_world(pose,"pelvis",Vector3.UP,float(profile[3])*0.40*air*(2.0*hips_open-1.0))
	author.rotate_world(pose,"pelvis",Vector3.BACK,float(profile[4])*0.45*(windup+0.55*drive*air))
	author.rotate_world(pose,"spine_02",Vector3.RIGHT,-0.19*windup+0.25*finish_hold)
	author.rotate_world(pose,"spine_03",Vector3.UP,-float(profile[3])*windup+aim_turn*finish_hold)
	author.rotate_world(pose,"spine_03",Vector3.BACK,float(profile[4])*0.55*(windup+0.42*drive*air))

	var scissor := smoothstep(0.14,0.98,progress)*(1.0-settle)*(1.0-smoothstep(0.0,0.80,sweep))
	var split: float = profile[5]
	var kick: float = profile[6]
	var lead_hip: Vector3 = author.point(pose,"thigh_l")
	var trail_hip: Vector3 = author.point(pose,"thigh_r")
	var lead_leg := lead_hip+Vector3(split,-0.76,0.14)
	var trail_leg := trail_hip+Vector3(-split*0.46,-0.41+kick*0.32,-0.39-kick*0.58)
	author.limb(pose,"thigh_l","calf_l","foot_l",left_foot.lerp(lead_leg,scissor),Vector3(0.24,0.05,1.0),scissor,167.0)
	author.limb(pose,"thigh_r","calf_r","foot_r",right_foot.lerp(trail_leg,scissor),Vector3(-0.31,0.1,1.0),scissor,150.0)

	var guide_drop := smoothstep(float(profile[7])-0.18,0.96,progress)
	var guide_reach := Vector3(profile[10],profile[9],0.53)
	SpikeArm.apply_guide_arm(pose,author,guide_reach,Vector3(0.52,-0.48,-0.06),guide_drop,air,158.0)

	var shoulder: Vector3 = author.point(pose,"upperarm_r")
	var outside: Vector3 = (shoulder-author.point(pose,"upperarm_l")).normalized()
	var chamber_width := float(profile[11])+elbow_clearance-SpikeArm.BASE_ELBOW_CLEARANCE
	var chamber := shoulder+outside*chamber_width+Vector3(0.0,float(profile[2]),-float(profile[1]))
	var release_start := float(profile[7])
	var elbow_lead := smoothstep(release_start,lerpf(release_start,1.0,0.50),progress)
	var hand_release := smoothstep(lerpf(release_start,1.0,0.49),1.0,progress)
	var pole := Vector3(-1.0,-0.12,-0.34).lerp(Vector3(-0.95,-0.08,0.48),hand_release)
	var finish_target := SpikeArm.hip_finish(pose,author,crosscourt,float(profile[8])*0.19)
	var strike_target := SpikeArm.follow_through_target(pose,author,shoulder,strike_wrist,finish_target,sweep)
	pole = pole.lerp(Vector3(-0.85,0.04,-0.33),sweep)
	var strike_pose := pose.duplicate()
	var strike_weight := rising*(1.0-smoothstep(0.59,1.22,landing))
	author.limb(strike_pose,"upperarm_r","lowerarm_r","hand_r",strike_target,pole,1.0,lerpf(148.0,172.0,sweep))
	SpikeArm.align_finish_wrist(strike_pose,author,sweep)
	if palm_finish < 0.0:
		SpikeArm.roll_finish_palm(strike_pose,author,palm_finish,maxf(0.38*hand_release,sweep))

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
	SpikeArm.blend_right_arm(pose,strike_pose,author,hand_release*strike_weight)
	SpikeArm.align_wrist_to_forearm(pose,author,0.90*windup)
	if palm_finish > 0.0:
		var recovery := 1.0-smoothstep(0.59,1.22,landing)
		SpikeArm.roll_finish_palm(pose,author,palm_finish*recovery,maxf(0.90*rising,sweep))
