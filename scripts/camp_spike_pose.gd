extends RefCounted

const Jump = preload("res://scripts/setter_jump.gd")
const Swing = preload("res://scripts/spike_arm_swing.gd")
const Contact = preload("res://scripts/gym_physics.gd")
const ATTACK_CONTACT_RADIUS := .46
const PALM_CONTACT := 2./60.
var last_elbow := Quaternion.IDENTITY
var last_shoulder := Quaternion.IDENTITY
var last_shoulder_time := -1.
var reach_assist := Vector3.ZERO

func apply(hitter: Node3D,attack_jump: Jump,phase: String,swing_time: float,contact_swing_time: float,
		ball_world: Vector3,source: Vector3,endpoint: Vector3,strike_point: Vector3,landing: Vector3,
		strike_shoulder_offset: Vector3,height: float,speed_factor: float,speed: float,
		spike_pike_scale: float,spin_choice: int,net_clear_time: float,roll_shot := false,tip_shot := false,roll_reach := 0.) -> void:
	if swing_time>.65:
		if last_shoulder_time>=0.:
			var rig: Skeleton3D=hitter.skeleton
			var id := rig.find_bone("upperarm_r")
			var rest_target := rig.get_bone_pose_rotation(id)
			var gap := last_shoulder.angle_to(rest_target)
			var budget := deg_to_rad(660.)*(swing_time-last_shoulder_time)
			if gap>budget:
				last_shoulder=last_shoulder.slerp(rest_target,budget/gap)
				rig.set_bone_pose_rotation(id,last_shoulder)
				last_shoulder_time=swing_time
			else: last_shoulder_time=-1.
			protect_hitting_arm(hitter)
		return
	var recovery := smoothstep(.36,.65,swing_time)
	var rig: Skeleton3D=hitter.skeleton
	var pose: Array=[]
	for id in rig.get_bone_count(): pose.append(rig.get_bone_pose(id))
	var reach := smoothstep(.025,.13,swing_time*speed_factor)
	var follow := 0.0
	if phase=="spike":
		var progress := clampf((swing_time-contact_swing_time)*speed_factor/.32,0.,1.)
		follow=progress*(1.5-.5*progress)
		if tip_shot: follow*=.16
		if roll_shot: follow*=lerpf(.42,.70,roll_reach)
	var author = hitter.get_pose_author()
	var airborne := smoothstep(0.,.12,attack_jump.elapsed-attack_jump.load_duration()) if attack_jump.active else 0.
	var air_age := attack_jump.elapsed-attack_jump.load_duration()
	var apex_offset := air_age-attack_jump.flight_duration(height,true)*.48
	var load_weight := airborne*(1.-smoothstep(-.14,.14,apex_offset))
	var toward_feed := (source-hitter.global_position).slide(Vector3.UP).normalized()
	var feed_local := hitter.global_basis.inverse()*toward_feed
	# A right-handed hitter draws the striking shoulder back on either pin.
	var opening := -deg_to_rad(lerpf(78.,34.,smoothstep(-.8,.8,feed_local.x)))*load_weight
	var hip_turn := opening*.28
	var twist := opening-hip_turn
	var shot_origin := strike_point if phase=="spike" else endpoint
	var shot_local := hitter.global_basis.inverse()*shot_origin.direction_to(landing)
	var heading := clampf(atan2(shot_local.x,shot_local.z),-1.35,1.35)
	var hip_share := lerpf(.46,.72,smoothstep(.15,.95,absf(heading)))
	hip_turn+=heading*hip_share*smoothstep(-.20,.055,apex_offset)
	twist+=heading*(1.-hip_share)*smoothstep(-.15,.085,apex_offset)
	if phase=="spike":
		var carry := smoothstep(PALM_CONTACT,.27,swing_time-contact_swing_time)
		if tip_shot: carry*=.18
		if roll_shot: carry*=lerpf(.4,.65,roll_reach)
		hip_turn+=heading*.30*carry
		twist+=heading*.13*carry
	# Load the chest through the draw, then release the arch into the strike.
	var draw_load := smoothstep(.055,attack_jump.flight_duration(height,true)*.48-.11,air_age)
	draw_load *= 1.-smoothstep(-.11,.045,apex_offset)
	var arch := (deg_to_rad(9.)*load_weight+deg_to_rad(11.)*draw_load)*spike_pike_scale
	twist-=deg_to_rad(18.)*draw_load
	author.rotate_world(pose,"spine_01",Vector3.RIGHT,-arch*.45)
	author.rotate_world(pose,"spine_02",Vector3.RIGHT,-arch*.55)
	author.rotate_world(pose,"spine_01",Vector3.UP,twist*.45)
	author.rotate_world(pose,"spine_02",Vector3.UP,twist*.55)
	# Raise the striking shoulder in the chest's own lateral plane as the arm reaches.
	var across: Vector3=author.point(pose,"upperarm_l")-author.point(pose,"upperarm_r")
	var bend_axis := Vector3.UP.cross(across).normalized()
	var contact_bend := deg_to_rad(28.)*smoothstep(-.19,-.025,apex_offset)*(1.-smoothstep(.055,.28,apex_offset))
	author.rotate_world(pose,"spine_01",bend_axis,contact_bend*.45)
	author.rotate_world(pose,"spine_02",bend_axis,contact_bend*.55)
	var tuck_age := maxf(0.,air_age-.015)
	var since_hit := swing_time-contact_swing_time if phase=="spike" else 0.
	var extension := smoothstep(-.085,.14,apex_offset)
	var landing_blend := 1.-smoothstep(.19,.33,since_hit)
	var leg_weight := smoothstep(0.,.055,tuck_age)*landing_blend if attack_jump.active else 0.
	var athleticism := clampf(float(hitter.attributes.get("Athleticism",65))/100.,0.,1.)
	var clearance := maxf(0.,absf(4.-hitter.global_position.z)-.23)
	var reach_length := float(hitter.height_cm)*.006
	var net_angle := asin(clampf(clearance/reach_length,0.,1.))
	var drive := smoothstep(9.,40.,speed) if not (roll_shot or tip_shot) else .12
	var intensity := lerpf(.13,1.,drive)
	var peak_time := lerpf(.235,.175,drive*(.55+.45*athleticism))
	var pike := smoothstep(.015,peak_time,since_hit)*(1.-smoothstep(peak_time,.38,since_hit))
	var chest_fold := minf(deg_to_rad(lerpf(26.,60.,athleticism))*spike_pike_scale,net_angle)*intensity*pike
	author.rotate_world(pose,"spine_01",Vector3.RIGHT,chest_fold*.65)
	author.rotate_world(pose,"spine_02",Vector3.RIGHT,chest_fold*.35)
	var leg_angle := minf(deg_to_rad(lerpf(24.,53.,athleticism))*spike_pike_scale,net_angle)*minf(1.,intensity*spike_pike_scale)
	var heel_rise := smoothstep(2./60.,16./60.,air_age)
	var knee_load := leg_weight*(1.-extension)
	var lift_pose := knee_load
	var pelvis := rig.find_bone("pelvis")
	var parent_pose: Transform3D = author.world_pose(pose,rig.get_bone_parent(pelvis))
	pose[pelvis].origin += parent_pose.basis.inverse()*Vector3.BACK*.045*lift_pose/rig.global_basis.z.length()
	rig.set_bone_pose_position(pelvis,pose[pelvis].origin)
	author.rotate_world(pose,"pelvis",Vector3.RIGHT,deg_to_rad(-15.1)*lift_pose)
	author.rotate_world(pose,"pelvis",Vector3.BACK,deg_to_rad(-2.7)*lift_pose)
	for side in ["r","l"]:
		var calf := "calf_"+str(side)
		var foot := "foot_"+str(side)
		var thigh := "thigh_"+str(side)
		var hip: Vector3 = author.point(pose,thigh)
		var leg: Vector3 = (author.point(pose,calf)-hip).normalized()
		var outward := -.12 if side=="r" else .12
		var thigh_axis := Vector3(.33,-.74,.58) if side=="l" else Vector3(-.13,-.80,.59)
		var trailing_thigh := Vector3(.17,-.89,-.43) if side=="l" else Vector3(-.14,-.84,-.53)
		thigh_axis = thigh_axis.normalized().slerp(trailing_thigh.normalized(),lift_pose)
		author.aim_joint(pose,thigh,calf,hip+leg.slerp(thigh_axis.slerp(Vector3(outward,-cos(leg_angle),sin(leg_angle)).normalized(),extension),leg_weight))
		var knee: Vector3 = author.point(pose,calf)
		var shin: Vector3 = (author.point(pose,foot)-knee).normalized()
		# In the edited hang the ankles rise above the knees while the toes hang down.
		var seat := hip+Vector3(outward*.45,-.065,-.17)/rig.global_basis.y.length()
		var full_tuck := (seat-knee).normalized()
		var previous_tuck := Vector3(outward,.83,-.55).normalized()
		var heel := previous_tuck.slerp(full_tuck,lerpf(.28,.84,athleticism))
		var extended := (knee-hip).normalized()
		var blend := heel_rise*landing_blend
		# Unfold in the forward/back plane; a 3D arc can swing an ankle sideways mid-stroke.
		var folded := atan2(heel.z,-heel.y)
		if folded>0.: folded-=TAU
		# Let the heels begin to drop as the tuck peaks, before the full extension.
		folded+=deg_to_rad(12.)*smoothstep(16./60.,28./60.,air_age)
		var fold_angle := lerpf(folded,atan2(extended.z,-extended.y),extension)
		var lateral := lerpf(heel.x,extended.x,extension)
		var plane_length := sqrt(maxf(0.,1.-lateral*lateral))
		var shin_target := Vector3(lateral,-cos(fold_angle)*plane_length,sin(fold_angle)*plane_length)
		author.aim_joint(pose,calf,foot,knee+shin.slerp(shin_target,blend))
		var ankle: Vector3 = author.point(pose,foot)
		var toes := "ball_"+str(side)
		var toe_axis: Vector3 = (author.point(pose,toes)-ankle).normalized()
		var shin_axis := (ankle-knee).normalized()
		var foot_side := Vector3.RIGHT.rotated(Vector3.UP,outward*.85)
		var hanging_toes := shin_axis.cross(foot_side).normalized()
		author.aim_joint(pose,foot,toes,ankle+toe_axis.slerp(hanging_toes,leg_weight))
	# Apply pelvic rotation after solving the tuck so both legs inherit it.
	author.rotate_world(pose,"pelvis",Vector3.UP,hip_turn)
	var draw_end := attack_jump.flight_duration(height,true)*.48-.095
	var draw := smoothstep(.035,draw_end,air_age) if attack_jump.active else 0.
	var origin := strike_point if phase=="spike" else ball_world
	var shot_axis := hitter.global_basis.inverse()*origin.direction_to(landing).slide(Vector3.UP).normalized()
	var arm_target := rig.to_local(ball_world)
	if phase=="spike":
		arm_target=author.point(pose,"upperarm_r")+strike_shoulder_offset
	Swing.apply(pose,hitter.get_pose_author(),arm_target,maxf(draw,smoothstep(0.,.065,swing_time)),reach,follow,maxf(draw,reach),0.,1. if follow>0. and shot_axis.x>.12 else 0.,Swing.DEFAULT_ELBOW_CLEARANCE,0.,INF,shot_axis,0.,.10,false,true,false,smoothstep(0.,.12,swing_time-net_clear_time) if phase=="spike" and net_clear_time>=0. and spin_choice!=3 else 0.,(hip_turn+twist)*draw_load)
	# Pronate through the forearm while the striking hand is drawing back.
	var palm_weight := smoothstep(.015,.11,air_age)*(1.-smoothstep(.10,.65,reach))
	if palm_weight>0. and follow==0.:
		var hand: Vector3=author.point(pose,"hand_r")
		var elbow_point: Vector3=author.point(pose,"lowerarm_r")
		var arm_axis := elbow_point.direction_to(hand)
		var fingers_axis: Vector3=hand.direction_to(author.point(pose,"middle_01_r"))
		var across_hand: Vector3=author.point(pose,"pinky_01_r")-author.point(pose,"index_01_r")
		var normal := fingers_axis.cross(across_hand).normalized().slide(arm_axis)
		var down := Vector3.DOWN.slide(arm_axis)
		if normal.length_squared()>.01 and down.length_squared()>.01:
			var turn := normal.signed_angle_to(down,arm_axis)
			author.rotate_world(pose,"lowerarm_r",arm_axis,turn*palm_weight)
	var wrap := smoothstep(.055,.14,swing_time)*(1.-smoothstep(.34,.54,swing_time))
	if wrap>0. and not tip_shot:
		var wrap_axis := attack_spin_axis(shot_axis,spin_choice)
		var wrap_degrees := [24.,33.,33.,0.,-16.]
		author.rotate_world(pose,"hand_r",wrap_axis,deg_to_rad(float(wrap_degrees[spin_choice]))*wrap)
	var guide_target := rig.to_local(strike_point if phase=="spike" else ball_world)
	var shoulder: Vector3 = author.point(pose,"upperarm_l")
	var guide_drop := maxf(reach,follow)
	Swing.apply_guide_arm(pose,author,guide_target-shoulder,Vector3(.8,.1,-.2),guide_drop,airborne,174.)
	var wrist: Vector3 = author.point(pose,"hand_l")
	var fingers: Vector3 = (author.point(pose,"middle_01_l")-wrist).normalized()
	var point_axis := wrist.direction_to(guide_target)
	author.aim_joint(pose,"hand_l","middle_01_l",wrist+fingers.slerp(point_axis,airborne*(1.-guide_drop)))
	# Roll around the pointing direction so the fingers keep sighting the ball.
	var hand_id := rig.find_bone("hand_l")
	var hand_pose: Transform3D = author.world_pose(pose,hand_id)
	var hand_axis: Vector3 = wrist.direction_to(author.point(pose,"middle_01_l"))
	var forearm_axis: Vector3 = author.point(pose,"lowerarm_l").direction_to(wrist)
	var guide_roll := deg_to_rad(-110.)*smoothstep(0.,.045,air_age)
	author.rotate_world(pose,"lowerarm_l",forearm_axis,guide_roll*.8)
	author.set_world_basis(pose,"hand_l",Basis(hand_axis,guide_roll)*hand_pose.basis)
	# Nudge the authored pose toward the near surface of a reachable ball.
	var palm_center: Vector3=author.point(pose,"hand_r").lerp(author.point(pose,"middle_01_r"),.8)
	var offset := ball_world-rig.to_global(palm_center)
	var wanted := Vector3.ZERO
	if phase=="set" and swing_time>0. and offset.length()>.001:
		var proximity := 1.-smoothstep(ATTACK_CONTACT_RADIUS,.62,offset.length())
		wanted=offset.normalized()*clampf(offset.length()-Contact.BALL_RADIUS,0.,.20)*proximity*reach
	var assist_dt := clampf(swing_time-maxf(0.,last_shoulder_time),0.,.033)
	reach_assist=reach_assist.move_toward(wanted,assist_dt*1.8)
	var shift := rig.global_basis.inverse()*reach_assist
	for bone in ["spine_02","upperarm_r"]:
		var pivot: Vector3=author.point(pose,bone)
		var lever := palm_center-pivot
		var target := lever+shift*(.45 if bone=="spine_02" else .55)
		var axis := lever.cross(target)
		if axis.length_squared()>.00000001:
			author.rotate_world(pose,bone,axis.normalized(),minf(lever.angle_to(target),deg_to_rad(5. if bone=="spine_02" else 8.)))
	var arm_dt := maxf(0.,swing_time-last_shoulder_time)
	for joint in ["pelvis","spine_01","spine_02","thigh_r","thigh_l","calf_r","calf_l","foot_r","foot_l","clavicle_r","upperarm_r","lowerarm_r","hand_r","clavicle_l","upperarm_l","lowerarm_l","hand_l"]:
		var id := rig.find_bone(joint)
		var release_blend := recovery
		if phase=="spike" and joint in ["upperarm_r","lowerarm_r","hand_r"]:
			release_blend=smoothstep(contact_swing_time+.32/speed_factor,.65,swing_time)
		var rotation: Quaternion=pose[id].basis.get_rotation_quaternion().slerp(rig.get_bone_pose_rotation(id),release_blend)
		if joint=="upperarm_r":
			# Near full extension the elbow solver can choose opposite shoulder twists on adjacent frames.
			if phase=="spike" and since_hit>PALM_CONTACT and last_shoulder_time>=0.:
				var gap := last_shoulder.angle_to(rotation)
				var budget := deg_to_rad(660.)*maxf(0.,swing_time-last_shoulder_time)
				if gap>budget: rotation=last_shoulder.slerp(rotation,budget/gap)
			last_shoulder=rotation
			last_shoulder_time=swing_time
		if joint=="lowerarm_r":
			if phase=="spike" and since_hit>PALM_CONTACT:
				var gap := last_elbow.angle_to(rotation)
				var budget := deg_to_rad(840.)*arm_dt
				if gap>budget: rotation=last_elbow.slerp(rotation,budget/gap)
			last_elbow=rotation
		rig.set_bone_pose_rotation(id,rotation)
	if phase=="spike" and since_hit>PALM_CONTACT: protect_hitting_arm(hitter)

func protect_hitting_arm(hitter: Node3D) -> void:
	var rig: Skeleton3D=hitter.skeleton
	preload("res://scripts/player_arm_clearance.gd").resolve(rig,"r")
	last_shoulder=rig.get_bone_pose_rotation(rig.find_bone("upperarm_r"))

static func attack_spin_axis(direction: Vector3, spin: int) -> Vector3:
	var top := Vector3.UP.cross(direction).normalized()
	if spin in [1,2]:
		return (top*.8+Vector3.UP*(-.6 if spin==1 else .6)).normalized()
	return top

