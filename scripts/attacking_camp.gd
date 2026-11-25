extends "res://scripts/indoor_practice.gd"

const Swing = preload("res://scripts/spike_arm_swing.gd")
const START := Vector3(3.65,.04,.76)
var hitter: Node3D
var attack_jump := preload("res://scripts/setter_jump.gd").new()
var swing_time := -1.
var closest_spike_gap := INF
var contact_swing_time := 0.
var cross_court := false
var review_setup := {}
var set_arc_percent := 100.0
var jump_height := JUMP_HEIGHT
var cpu_hitter := true
var approach_started := false
const JUMP_HEIGHT := 33.*.0254
const ATTACK_SET_LIFT := .10
const PLANT_TIME := .30
const SHOT_BUTTONS := [JOY_BUTTON_X,JOY_BUTTON_Y,JOY_BUTTON_B]
var manual_shot := -1
var release_at := INF
var release_grade := INF
var first_palm_at := INF
var depth_error := 0.
var power_scale := 1.

const EARLY_LIMIT := -.18
const LATE_LIMIT := .085
const ATTACK_CONTACT_RADIUS := .30
var reach_assist := Vector3.ZERO
const CLEAN_WINDOW := .018
const METER_START := -.32
const METER_END := .12

func attack_meter_position(error: float) -> float:
	return clampf(inverse_lerp(METER_START,METER_END,error),0.,1.)

func attack_meter_error() -> float:
	if is_finite(release_grade): return release_grade
	if is_finite(first_palm_at):
		return minf(release_at,clock)-first_palm_at
	if phase!="set": return METER_START
	return minf(release_at,clock)-clock+elapsed-flight_time+.08

func clear_attack_input() -> void:
	manual_route=Vector3.ZERO
	manual_shot=-1
	release_at=INF
	release_grade=INF
	first_palm_at=INF
	depth_error=0.
	power_scale=1.

var spikes := 0
var strike_shoulder_offset := Vector3.ZERO
var strike_point := Vector3.ZERO
var last_elbow := Quaternion.IDENTITY
var last_shoulder := Quaternion.IDENTITY
var last_shoulder_time := -1.
var spin_acceleration := Vector3.ZERO
var wrist_history := {}
var wrist_axes := {}
var contact_offset := Vector3.ZERO
var net_clear_time := -1.
const PALM_CONTACT := 2./60.

func start_drill() -> void:
	hitter=athlete(START,"e97937")
	hitter.apply_profile(setter.attributes.duplicate())
	hitter.set_height_cm(193.04)
	register_student(setter,2)
	preload("res://scripts/practice_kit.gd").apply(hitter,false)
	for hoop in targets:
		hoop.hide()
		for collider in hoop.find_children("*","StaticBody3D",true,false):
			collider.collision_layer=0
	for overlay in get_children():
		if overlay.get_script()==preload("res://scripts/tryout_player_ring.gd"):
			overlay.extra_jumps[hitter]=attack_jump
			overlay.setting_cues=false
	energy[hitter]=hitter.stamina
	attack_jump.front_limit=3.65
	attack_jump.attack_arm_lift=true
	super.start_drill()
	if has_meta("live_sampler"): return
	var review := "--review-swings" in OS.get_cmdline_user_args()
	var arm_swing := review or "--edit-arm-swing" in OS.get_cmdline_user_args()
	var arm_lift := arm_swing or "--edit-arm-lift" in OS.get_cmdline_user_args()
	if (arm_lift or "--edit-approach" in OS.get_cmdline_user_args()) and not Engine.has_meta("approach_editor_opened"):
		Engine.set_meta("approach_editor_opened",true)
		edit_approach_frames.call_deferred(arm_lift,arm_swing,false,review,true)

func camp_title() -> String:
	return "ATTACKING   /   APPROACH AND SPIKE"

func update_prompts(_next: String) -> void:
	var entries := [["View","Take control" if cpu_hitter else "Watch CPU attack"]]
	if not cpu_hitter: entries.append_array([["LS","Move"],["LT","Lock on / shuffle"],["RT","Sprint"],[JOY_BUTTON_X,"Hold line"],[JOY_BUTTON_Y,"Hold six"],[JOY_BUTTON_B,"Hold cross"]])
	entries.append([JOY_BUTTON_START,"Settings"])
	Xbox.prompts(controls_row,entries)

func reset_feed() -> void:
	clear_attack_input()
	super.reset_feed()
	camp_call=0
	approach_started=false
	swing_time=-1.
	message.text="Coach toss"
	hitter.position=START
	hitter.rotation.y=0.
	hitter.play_action("idle")
	attack_jump.active=false

func set_destination(origin: Vector3, aim: Vector3, height_index: int) -> Vector3:
	return super.set_destination(origin,aim+Vector3(-1.1,0.,0.),height_index)+Vector3.UP*ATTACK_SET_LIFT

func _input(event: InputEvent) -> void:
	if not settings.visible and not get_tree().paused:
		if (event is InputEventJoypadButton and event.button_index==JOY_BUTTON_BACK or event is InputEventKey and event.physical_keycode==KEY_TAB) and event.is_pressed() and not event.is_echo():
			clear_attack_input()
			cpu_hitter=not cpu_hitter
			update_prompts(phase)
			get_viewport().set_input_as_handled()
			return
		if not cpu_hitter and phase in ["cart","feed","pass","set_contact","set"] and not event.is_echo():
			for index in SHOT_BUTTONS.size():
				var button: bool=event is InputEventJoypadButton and event.button_index==Xbox.physical(SHOT_BUTTONS[index])
				var key: bool=event is InputEventKey and event.physical_keycode==[KEY_SPACE,KEY_Y,KEY_B][index]
				if not (button or key): continue
				if event.is_pressed():
					manual_shot=index
					release_at=INF
					release_grade=INF
				elif manual_shot==index:
					release_grade=attack_meter_error()
					release_at=clock
					trace("attack_release",{"shot":index,"meter_error_ms":roundi(release_grade*1000.),"approach":approach_started})
					if not approach_started: manual_shot=-1
				get_viewport().set_input_as_handled()
				return
		if event is InputEventJoypadButton and event.button_index!=Xbox.physical(JOY_BUTTON_START): return
		if event is InputEventKey and event.physical_keycode!=KEY_ESCAPE: return
	super._input(event)

func step_practice(delta: float) -> void:
	var steps := maxi(1,ceili(delta*90.)) if phase=="set" else 1
	var dt := delta/steps
	for i in steps:
		step_attack(dt)
		smooth_wrists(dt)

func smooth_wrists(delta: float) -> void:
	var rig: Skeleton3D=hitter.skeleton
	for side in ["l","r"]:
		var id := rig.find_bone("hand_"+side)
		var rest := rig.get_bone_rest(id).basis.get_rotation_quaternion()
		if not wrist_axes.has(side):
			var along := rig.get_bone_rest(rig.find_bone("middle_01_"+side)).origin.normalized()
			var across := rig.get_bone_rest(rig.find_bone("index_01_"+side)).origin-rig.get_bone_rest(rig.find_bone("pinky_01_"+side)).origin
			wrist_axes[side]=[along,across.slide(along).normalized()]
		var q := preload("res://scripts/spike_wrist_motion.gd").constrain(rig.get_bone_pose_rotation(id),wrist_history.get(side,rest),rest,wrist_axes[side][0],wrist_axes[side][1],delta)
		if side=="r" and approach_started and attack_jump.active:
			var lock := smoothstep(-.04,.045,attack_jump.elapsed-attack_jump.load_duration())
			if phase=="spike": lock*=1.-smoothstep(PALM_CONTACT,.20,swing_time-contact_swing_time)
			q=q.slerp(preload("res://scripts/spike_wrist_motion.gd").straight_right(rig),lock)
		rig.set_bone_pose_rotation(id,q)
		wrist_history[side]=q

var manual_route := Vector3.ZERO
var prep_velocity := Vector3.ZERO
var bounce_line := false

func step_attack(delta: float) -> void:
	if attack_jump.active:
		attack_jump.step(hitter,delta,Vector2.ZERO)
	else:
		hitter.animator.advance(delta)
		var stick := Vector2(axis(JOY_AXIS_LEFT_X),axis(JOY_AXIS_LEFT_Y)).limit_length(1.)
		var steering := not cpu_hitter and stick.length()>.16
		var lock_on := not cpu_hitter and GroundControls.focus(axis)
		var tracking := cpu_hitter or (manual_shot>=0 and phase=="set" and not steering)
		if tracking and not approach_started and phase in ["cart","feed","pass","set_contact","set"]:
			var entry := Vector3(4.95,START.y,.65)
			if phase in ["set_contact","set"]:
				entry=endpoint+Vector3(1.18,0.,-1.82)
				entry.y=START.y
				if not cpu_hitter:
					var to_set := (endpoint-hitter.position).slide(Vector3.UP)
					if manual_route.is_zero_approx():
						manual_route=to_set.normalized()
						prep_velocity=Vector3.ZERO
					# Close excess distance along the approach line; reserve room for the plant.
					entry=hitter.position+manual_route*maxf(0.,to_set.dot(manual_route)-1.50)
			elif phase=="pass":
				entry.z+=.35*smoothstep(0.,1.,elapsed)
			var desired := ((entry-hitter.position)*(6. if not cpu_hitter else 4.)).limit_length((5.8 if cpu_hitter else 4.3) if phase=="set" else 1.85)
			prep_velocity=prep_velocity.move_toward(desired,(13. if not cpu_hitter else 8.)*delta)
			var travel := prep_velocity*delta
			hitter.position=rotation_drill.move_actor(hitter,travel)
			var watch := (ball.position-hitter.position).slide(Vector3.UP)
			if not cpu_hitter and not lock_on: watch=manual_route
			if watch.length_squared()>.01:
				hitter.rotation.y=rotate_toward(hitter.rotation.y,atan2(watch.x,watch.z),3.5*delta)
			var local := hitter.basis.inverse()*prep_velocity
			if not cpu_hitter and not lock_on and local.length()>2.35:
				hitter.play_ground_gait(local.length())
			else:
				hitter.play_action("idle",.20)
			if not shuffle_steps.has(hitter):
				shuffle_steps[hitter]=preload("res://scripts/directional_footwork.gd").new(hitter)
			if cpu_hitter or lock_on or local.length()<=2.35: shuffle_steps[hitter].step((local/2.).limit_length(1.),delta,clampf(local.length()/2.,.55,1.35),true,true)
		if not tracking and (not approach_started or phase!="set"):
			var amount := clampf((stick.length()-.16)/.84,0.,1.)
			var right := camera.global_basis.x.slide(Vector3.UP).normalized()
			var direction := (right*stick.x+right.cross(Vector3.UP)*stick.y).normalized()
			var sprinting: bool=steering and GroundControls.sprint(axis) and hitter.stamina.can_sprint()
			var desired := direction*amount*GroundControls.speed(lock_on,sprinting)
			prep_velocity=prep_velocity.move_toward(desired,18.*delta)
			hitter.position=rotation_drill.move_actor(hitter,prep_velocity*delta)
			if steering:
				manual_route=Vector3.ZERO
			if lock_on:
				GroundControls.face(hitter,(ball.position if ball.visible else coach.position)-hitter.position,delta)
			elif steering: GroundControls.face(hitter,direction,delta,7.)
			if sprinting and prep_velocity.length()>.12:
				hitter.stamina.spend(hitter.stamina.SPRINT_DRAIN*delta,"Sprint")
			if lock_on: hitter.play_action("idle",.22)
			else: hitter.play_ground_gait(prep_velocity.length())
			if not shuffle_steps.has(hitter): shuffle_steps[hitter]=preload("res://scripts/directional_footwork.gd").new(hitter)
			GroundControls.shuffle(hitter,shuffle_steps[hitter],prep_velocity,lock_on,delta)
	if phase=="spike":
		elapsed+=delta
		swing_time+=delta
		pose_swing()
		advance_spike(delta,cpu_hitter and bounce_line)
		if roll_time>=.5:
			rotation_drill.free_ball(drop_velocity)
			begin("between")
		return
	super.step_practice(delta)
	if phase=="pass": message.text="Coach toss to setter"
	if phase=="set_contact": message.text="Setter contact"

func start_approach(steps := 3, cadence := 1.) -> void:
	if approach_started: return
	last_shoulder_time=-1.
	reach_assist=Vector3.ZERO
	closest_spike_gap=INF
	approach_started=true
	hitter.stamina.spend(5,"Jump")
	var contact_stance := Vector3(endpoint.x+.09,.04,endpoint.z-.09)
	if not cpu_hitter and not manual_route.is_zero_approx():
		contact_stance=Vector3(endpoint.x,START.y,endpoint.z)-manual_route*.09
	var heading := (contact_stance-hitter.position).slide(Vector3.UP).normalized()
	hitter.rotation.y=atan2(heading.x,heading.z)
	attack_jump.begin(hitter,Vector2(-heading.x,heading.z),contact_stance,PLANT_TIME*cadence,jump_height,steps,false,cadence,false,.22)
	var to_ball := (endpoint-hitter.position).slide(Vector3.UP)
	if not to_ball.is_zero_approx(): attack_jump.lead_heading=to_ball.normalized()
	attack_jump.release()

func arm_speed_factor() -> float:
	var effort := float(review_setup.get("power",14.))
	var rating := float(hitter.attributes.get("Arm swing",65))
	return pow(effort/14.,.48)*(1.+(rating-65.)*.004)

func requested_set_arc() -> float:
	return super.requested_set_arc()*set_arc_percent*.01

func effective_attack_height() -> float:
	return jump_height*(attack_jump.takeoff_effectiveness if attack_jump.active else hitter.stamina.effectiveness())

func attack_speed() -> float:
	var strength := float(hitter.attributes.get("Strength",65))
	var effort := float(review_setup.get("power",14.))
	return sqrt(14.*effort)*arm_speed_factor()*(1.+(strength-65.)*.005)

func attack_flight_time(distance: float) -> float:
	return maxf(.05,distance/(attack_speed()*power_scale))

func handle_attack_contact(previous: Vector3,delta: float) -> bool:
	message.text="Approach and spike"
	var remaining := flight_time-elapsed
	var rise := attack_jump.flight_duration(effective_attack_height(),true)*.48
	var distance := (endpoint-hitter.position).slide(Vector3.UP).length()
	var steps := 3
	var cadence := 1.
	if not cpu_hitter:
		if distance<1.25: steps=2
		elif distance>2.25: steps=4
		cadence=.94
	var load_time := cadence*((steps-2)*attack_jump.LEAD_STEP_TIME+PLANT_TIME)
	if (cpu_hitter or (manual_shot>=0 and distance<=3.35)) and remaining<=load_time+rise+.025:
		start_approach(steps,cadence)
	if approach_started and swing_time<0. and remaining<=.16/arm_speed_factor()+(.095 if not has_meta("sampling_attack") else 0.): swing_time=0.
	if swing_time<0. and attack_jump.active and attack_jump.elapsed>attack_jump.load_duration():
		pose_swing()
	if swing_time>=0.:
		swing_time+=delta
		pose_swing()
		var palm := Contact.palm(hitter,"r")
		var nearest := Geometry3D.get_closest_point_to_segment(palm,previous,ball.position)
		if swing_time>=.055 and swing_time<=.30:
			closest_spike_gap=minf(closest_spike_gap,nearest.distance_to(palm))
		if swing_time>=.055 and swing_time<=.30 and nearest.distance_to(palm)<=ATTACK_CONTACT_RADIUS:
			if not cpu_hitter:
				if not is_finite(first_palm_at): first_palm_at=clock
				if manual_shot<0 or not is_finite(release_at):
					if elapsed<flight_time: return false
				else:
					var error := release_grade
					if error<EARLY_LIMIT or error>LATE_LIMIT:
						manual_shot=-1
						return false
					var severity := smoothstep(CLEAN_WINDOW,LATE_LIMIT if error>0. else -EARLY_LIMIT,absf(error))
					power_scale=lerpf(1.,.63,severity)
					depth_error=(-1. if error>0. else 1.)*severity*rotation_drill.random.randf_range(0.,12. if error>0. else 8.)
			if not cpu_hitter and (manual_shot<0 or not is_finite(release_at)):
				return false
			contact_swing_time=swing_time
			strike_point=ball.position
			strike_shoulder_offset=hitter.skeleton.to_local(strike_point)-hitter.skeleton.get_bone_global_pose(hitter.skeleton.find_bone("upperarm_r")).origin
			spikes+=1
			success=true
			feedback="Spike"
			message.text=feedback
			gym.update_board(spikes)
			contact_offset=striking_palm_offset()
			ball.position=palm+contact_offset
			net_clear_time=-1.
			var landing := shot_landing(ball.position)
			var shot_time := attack_flight_time(landing.distance_to(ball.position))
			drop_velocity=(landing-ball.position)/shot_time+Vector3.UP*(4.905*shot_time)
			roll_time=-1.
			trace("spike",{"from":str(ball.position),"palm_gap":nearest.distance_to(palm)})
			begin("spike")
			return true
	if elapsed>=flight_time:
		trace("spike_miss",{"closest_palm_gap_m":closest_spike_gap if is_finite(closest_spike_gap) else -1.,"ball":str(ball.position),"palm":str(Contact.palm(hitter,"r"))})
		feedback="Missed spike"
		message.text=feedback
		success=false
		drop_velocity=(endpoint-source-Vector3.UP*4.*set_arc_height)/flight_time
		begin("drop")
		return true
	return false

func striking_palm_offset() -> Vector3:
	var fingers := Contact.joint(hitter,"middle_01_r")-Contact.joint(hitter,"hand_r")
	var edge := Contact.joint(hitter,"pinky_01_r")-Contact.joint(hitter,"index_01_r")
	return fingers.cross(edge).normalized()*Contact.BALL_RADIUS

func attack_spin_axis(direction: Vector3, spin: int) -> Vector3:
	var top := Vector3.UP.cross(direction).normalized()
	if spin in [1,2]:
		return (top*.8+Vector3.UP*(-.6 if spin==1 else .6)).normalized()
	return top

func advance_spike(delta: float, bounce: bool) -> void:
	var age := swing_time-contact_swing_time
	if age<=PALM_CONTACT+.00001:
		ball.position=Contact.palm(hitter,"r")+striking_palm_offset()
		var landing := shot_landing(strike_point)
		var flight := attack_flight_time(ball.position.distance_to(landing))
		var direction := ball.position.direction_to(landing).slide(Vector3.UP).normalized()
		var speed := landing.distance_to(ball.position)/flight
		var spin := int(review_setup.get("spin",0))
		var force_axis: Vector3=[Vector3.DOWN,Vector3.DOWN*.8+direction.cross(Vector3.UP)*.6,Vector3.DOWN*.8+Vector3.UP.cross(direction)*.6,Vector3.ZERO,Vector3.UP][spin]
		spin_acceleration=force_axis*(minf(3.,speed*.20) if spin==4 else minf(22.,speed*.78))
		# Compensate at launch to keep the selected landing point on the curved path.
		drop_velocity=(landing-ball.position)/flight+(Vector3.UP*9.81-spin_acceleration)*(.5*flight)
		return
	var incoming_basis := ball.basis
	var in_flight := roll_time<0.
	var forward := drop_velocity.slide(Vector3.UP).normalized()
	var descent := drop_velocity.y
	if in_flight: drop_velocity+=spin_acceleration*delta
	advance_missed_ball(delta,bounce)
	if roll_time>=0. or (descent<0. and drop_velocity.y>0.): spin_acceleration=Vector3.ZERO
	if in_flight and roll_time<0. and not forward.is_zero_approx():
		var spin := int(review_setup.get("spin",0))
		var axis := attack_spin_axis(forward,spin)
		var rate := [32.,26.,26.,0.,-18.]
		ball.basis=Basis(axis,float(rate[spin])*delta)*incoming_basis
	if net_clear_time<0. and ball.position.z>=4.+Contact.BALL_RADIUS and ball.position.y>2.43+Contact.BALL_RADIUS:
		net_clear_time=swing_time

func shot_landing(origin: Vector3) -> Vector3:
	if not cpu_hitter and manual_shot>=0:
		var side := -1. if origin.x<0. else 1.
		var aim: Vector2=[Vector2(side*3.75,11.55),Vector2(0.,11.4),Vector2(-side*3.65,8.45)][manual_shot]
		return Vector3(aim.x,Contact.BALL_RADIUS,maxf(origin.z+.45,aim.y+depth_error))
	if not review_setup.is_empty():
		return Vector3(-float(review_setup.get("x",-3.4)),Contact.BALL_RADIUS,review_setup.get("z",11.))
	return Vector3(-3.4 if cross_court else clampf(origin.x,-3.8,3.8),Contact.BALL_RADIUS,11.)

func pose_swing() -> void:
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
			protect_hitting_arm()
		return
	var recovery := smoothstep(.36,.65,swing_time)
	var rig: Skeleton3D=hitter.skeleton
	var pose: Array=[]
	for id in rig.get_bone_count(): pose.append(rig.get_bone_pose(id))
	var reach := smoothstep(.025,.13,swing_time*arm_speed_factor())
	var follow := 0.0
	if phase=="spike":
		var progress := clampf((swing_time-contact_swing_time)*arm_speed_factor()/.32,0.,1.)
		follow=progress*(1.5-.5*progress)
	var author = hitter.get_pose_author()
	var airborne := smoothstep(0.,.12,attack_jump.elapsed-attack_jump.load_duration()) if attack_jump.active else 0.
	var air_age := attack_jump.elapsed-attack_jump.load_duration()
	var apex_offset := air_age-attack_jump.flight_duration(effective_attack_height(),true)*.48
	var load_weight := airborne*(1.-smoothstep(-.14,.14,apex_offset))
	var toward_feed := (source-hitter.position).slide(Vector3.UP).normalized()
	var feed_local := hitter.basis.inverse()*toward_feed
	# A right-handed hitter draws the striking shoulder back on either pin.
	var opening := -deg_to_rad(lerpf(78.,34.,smoothstep(-.8,.8,feed_local.x)))*load_weight
	var hip_turn := opening*.28
	var twist := opening-hip_turn
	var shot_origin := strike_point if phase=="spike" else endpoint
	var shot_local := hitter.basis.inverse()*shot_origin.direction_to(shot_landing(shot_origin))
	var heading := clampf(atan2(shot_local.x,shot_local.z),-1.35,1.35)
	var hip_share := lerpf(.46,.72,smoothstep(.15,.95,absf(heading)))
	hip_turn+=heading*hip_share*smoothstep(-.20,.055,apex_offset)
	twist+=heading*(1.-hip_share)*smoothstep(-.15,.085,apex_offset)
	if phase=="spike":
		var carry := smoothstep(PALM_CONTACT,.27,swing_time-contact_swing_time)
		hip_turn+=heading*.30*carry
		twist+=heading*.13*carry
	# Load the chest through the draw, then release the arch into the strike.
	var draw_load := smoothstep(.055,attack_jump.flight_duration(effective_attack_height(),true)*.48-.11,air_age)
	draw_load *= 1.-smoothstep(-.11,.045,apex_offset)
	var arch := deg_to_rad(9.)*load_weight+deg_to_rad(11.)*draw_load
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
	var clearance := maxf(0.,4.-hitter.global_position.z-.23)
	var reach_length := float(hitter.height_cm)*.006
	var net_angle := asin(clampf(clearance/reach_length,0.,1.))
	var drive := smoothstep(9.,40.,attack_speed())
	var intensity := lerpf(.13,1.,drive)
	var peak_time := lerpf(.235,.175,drive*(.55+.45*athleticism))
	var pike := smoothstep(.015,peak_time,since_hit)*(1.-smoothstep(peak_time,.38,since_hit))
	var chest_fold := minf(deg_to_rad(lerpf(26.,60.,athleticism)),net_angle)*pike*intensity
	author.rotate_world(pose,"spine_01",Vector3.RIGHT,chest_fold*.65)
	author.rotate_world(pose,"spine_02",Vector3.RIGHT,chest_fold*.35)
	var leg_angle := minf(deg_to_rad(lerpf(24.,53.,athleticism)),net_angle)*intensity
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
	var draw_end := attack_jump.flight_duration(effective_attack_height(),true)*.48-.095
	var draw := smoothstep(.035,draw_end,air_age) if attack_jump.active else 0.
	var origin := strike_point if phase=="spike" else ball.position
	var shot_axis := hitter.basis.inverse()*origin.direction_to(shot_landing(origin)).slide(Vector3.UP).normalized()
	var arm_target := rig.to_local(ball.position)
	if phase=="spike":
		arm_target=author.point(pose,"upperarm_r")+strike_shoulder_offset
	Swing.apply(pose,hitter.get_pose_author(),arm_target,maxf(draw,smoothstep(0.,.065,swing_time)),reach,follow,maxf(draw,reach),0.,1. if follow>0. and shot_axis.x>.12 else 0.,Swing.DEFAULT_ELBOW_CLEARANCE,0.,INF,shot_axis,0.,.10,false,true,false,smoothstep(0.,.12,swing_time-net_clear_time) if phase=="spike" and net_clear_time>=0. and int(review_setup.get("spin",0))!=3 else 0.,(hip_turn+twist)*draw_load)
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
	var spin_choice := int(review_setup.get("spin",0))
	var wrap := smoothstep(.055,.14,swing_time)*(1.-smoothstep(.34,.54,swing_time))
	if wrap>0.:
		var wrap_axis := attack_spin_axis(shot_axis,spin_choice)
		var wrap_degrees := [24.,33.,33.,0.,-16.]
		author.rotate_world(pose,"hand_r",wrap_axis,deg_to_rad(float(wrap_degrees[spin_choice]))*wrap)
	var guide_target := rig.to_local(strike_point if phase=="spike" else ball.global_position)
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
	var offset := ball.global_position-rig.to_global(palm_center)
	var wanted := Vector3.ZERO
	if phase=="set" and swing_time>0. and offset.length()>.001:
		var proximity := 1.-smoothstep(ATTACK_CONTACT_RADIUS,.42,offset.length())
		wanted=offset.normalized()*clampf(offset.length()-Contact.BALL_RADIUS,0.,.14)*proximity*reach
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
			release_blend=smoothstep(contact_swing_time+.32/arm_speed_factor(),.65,swing_time)
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
	if phase=="spike" and since_hit>PALM_CONTACT: protect_hitting_arm()

func protect_hitting_arm() -> void:
	var rig: Skeleton3D=hitter.skeleton
	preload("res://scripts/player_arm_clearance.gd").resolve(rig,"r")
	last_shoulder=rig.get_bone_pose_rotation(rig.find_bone("upperarm_r"))

func frame_editor_attacker() -> Node3D:
	return hitter

func edit_approach_frames(arm_lift := false, arm_swing := false, cross := false, review := false, resume_target := false) -> void:
	var setup := StorySession.load_drill_setup("swing_review") if arm_swing else {}
	if arm_swing and not review and not resume_target: setup.x=3.4 if cross else -3.4
	var result: Dictionary=await sample_attack_clip(arm_lift,arm_swing,cross,review,setup)
	StorySession.edit_entry=result.entry
	StorySession.edit_animation=result.clip
	StorySession.animation_draft.clear()
	settings.leave_for_frame_editor()
	MenuPresentation.load_scene("res://scenes/animation_editor.tscn")

func sample_attack_clip(arm_lift: bool,arm_swing: bool,cross: bool,review: bool,setup: Dictionary) -> Dictionary:
	set_meta("sampling_attack",true)
	review_setup=setup.duplicate()
	jump_height=float(setup.get("jump",33.))*.0254
	cross_court=float(setup.get("x",3.4 if cross else -3.4))>0.
	# Warm up from the first step so the editor inherits the live plant pose.
	hitter.position=START+Vector3(setup.get("set_x",0.),0.,setup.get("set_z",0.))
	hitter.rotation.y=0.
	hitter.animator.stop()
	hitter.skeleton.reset_bone_poses()
	last_elbow=Quaternion.IDENTITY
	last_shoulder=Quaternion.IDENTITY
	hitter.play_action("idle",0.)
	hitter.animator.advance(0.)
	endpoint=START+Vector3(-.18,0.,2.20)
	endpoint+=Vector3(review_setup.get("set_x",0.),0.,review_setup.get("set_z",0.))
	approach_started=false
	attack_jump.active=false
	start_approach()
	var recording := preload("res://scripts/match_replay.gd").new()
	var takeoff := attack_jump.load_duration()
	var first_frame := floori((takeoff-.15)*60.) if arm_lift else 0
	var duration := takeoff+.25 if arm_lift else takeoff
	if arm_swing:
		duration=(first_frame+107)/60.
		first_frame=0
		cpu_hitter=true
		flight_time=DURATION[1]
	swing_time=-1.
	if arm_lift:
		phase="set"
		source=setter.position+Vector3.UP*(setter.height_cm*.01+.12)
		endpoint.y=2.65+ATTACK_SET_LIFT+jump_height-JUMP_HEIGHT
	var editor_impacts: Array[Dictionary]=[]
	var last_impact := {}
	var hit_frame := -1
	wrist_history.clear()
	var count := ceili(duration*60.)
	for i in range(count+1):
		if has_meta("live_sampler") and i>0 and i%8==0: await get_tree().process_frame
		var time := minf(i/60.,duration)
		if i>0:
			if attack_jump.active: attack_jump.step(hitter,time-(i-1)/60.,Vector2.ZERO)
			else: hitter.animator.advance(1./60.)
		if arm_lift:
			var remaining := takeoff+attack_jump.flight_duration(effective_attack_height(),true)*.48+.025-time
			if arm_swing and phase in ["spike","drop"]:
				swing_time+=1./60.
				pose_swing()
				if phase=="spike": advance_spike(1./60.,true)
				else: advance_missed_ball(1./60.,true)
			else:
				var previous := ball.position
				ball.position=arc(source,endpoint,clampf(1.-remaining/DURATION[1],0.,1.),APEX[1])
				if arm_swing:
					elapsed=flight_time-remaining
					handle_attack_contact(previous,1./60.)
					if phase=="spike": hit_frame=i-first_frame
				elif time>takeoff: pose_swing()
		smooth_wrists(1./60.)
		if phase=="spike" and not drop_net_hit.is_empty() and drop_net_hit!=last_impact:
			last_impact=drop_net_hit
			var event := drop_net_hit.duplicate()
			var offset := time-first_frame/60.-drop_net_time
			event.time+=offset
			event.release_time+=offset
			editor_impacts.append(event)
		if i<first_frame: continue
		var bones: Array[Transform3D]=[]
		for id in hitter.skeleton.get_bone_count():
			bones.append(hitter.skeleton.get_bone_pose(id))
		recording.frames.append({"time":time-first_frame/60.,"ball":ball.global_transform,"actors":[{"root":hitter.transform,"bones":bones}]})
	var title := "Takeoff and arm lift" if arm_lift else "Three-step approach and backswing"
	if arm_swing: title="Cross-court swing" if cross else "Down-the-line swing"
	recording.index=0
	var clip := recording.bake_recorded_actor(hitter,0,title,recording.frames.size()-1,arm_lift)
	clip.remove_meta("contact_time")
	if arm_lift: clip.set_meta("editor_initial_frame",15)
	clip.set_meta("editor_height_cm",hitter.height_cm)
	var edit_entry :={"id":"camp_attack_arm_lift" if arm_lift else "camp_spike_approach","name":title,"category":"Attacking","type":"Approach"}
	if arm_swing:
		clip.set_meta("editor_net_impacts",editor_impacts)
		clip.set_meta("swing_hit_frame",hit_frame)
		edit_entry={"id":"camp_right_arm_swing","name":title,"category":"Attacking","type":"Spike"}
		edit_entry["aim_x"]=review_setup.get("x",-3.4)
		clip.set_meta("editor_group","Right Arm")
		clip.set_meta("swing_frame_offset",floori((takeoff-.15)*60.))
		clip.set_meta("editor_initial_frame",0)
		clip.set_meta("editor_loop_start",0)
	if arm_swing:
		edit_entry["swing_review"]=true
		clip.set_meta("editor_net_impacts",editor_impacts)
		clip.set_meta("swing_hit_frame",hit_frame)
	remove_meta("sampling_attack")
	return {"entry":edit_entry,"clip":clip}
