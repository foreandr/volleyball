extends "res://scripts/indoor_practice.gd"

const Swing = preload("res://scripts/spike_arm_swing.gd")
const START := Vector3(3.65,.04,.76)
var hitter: Node3D
var attack_jump := preload("res://scripts/setter_jump.gd").new()
var swing_time := -1.
var contact_swing_time := 0.
var cross_court := false
var review_setup := {}
var jump_height := JUMP_HEIGHT
var cpu_hitter := true
var approach_started := false
const JUMP_HEIGHT := 33.*.0254
const ATTACK_SET_LIFT := .10
const PLANT_TIME := .30
var spikes := 0
var strike_point := Vector3.ZERO

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
		if overlay.get_script()==preload("res://scripts/tryout_player_ring.gd"): overlay.hide()
	attack_jump.front_limit=3.65
	attack_jump.attack_arm_lift=true
	super.start_drill()
	var reload_review := Engine.has_meta("reload_swing_review")
	if reload_review: Engine.remove_meta("reload_swing_review")
	var reload_frame := Engine.has_meta("reload_swing_frame")
	var review := reload_review or (not reload_frame and "--review-swings" in OS.get_cmdline_user_args())
	var arm_swing := reload_frame or review or "--edit-arm-swing" in OS.get_cmdline_user_args()
	var arm_lift := arm_swing or "--edit-arm-lift" in OS.get_cmdline_user_args()
	if (arm_lift or "--edit-approach" in OS.get_cmdline_user_args()) and (reload_frame or reload_review or not Engine.has_meta("approach_editor_opened")):
		Engine.set_meta("approach_editor_opened",true)
		edit_approach_frames.call_deferred(arm_lift,arm_swing,false,review)

func camp_title() -> String:
	return "ATTACKING   /   APPROACH AND SPIKE"

func update_prompts(_next: String) -> void:
	var entries := [["View","Take control" if cpu_hitter else "Watch CPU attack"]]
	if not cpu_hitter: entries.append_array([["LS","Move"],[JOY_BUTTON_LEFT_SHOULDER,"Approach jump"],[JOY_BUTTON_X,"Spike"]])
	entries.append([JOY_BUTTON_START,"Settings"])
	Xbox.prompts(controls_row,entries)

func reset_feed() -> void:
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
			cpu_hitter=not cpu_hitter
			update_prompts(phase)
			get_viewport().set_input_as_handled()
			return
		if not cpu_hitter and phase=="set" and event is InputEventJoypadButton and event.button_index==Xbox.physical(JOY_BUTTON_LEFT_SHOULDER) and event.pressed:
			start_approach()
			get_viewport().set_input_as_handled()
			return
		if event is InputEventJoypadButton and event.button_index==Xbox.physical(JOY_BUTTON_X) or event is InputEventKey and event.physical_keycode==KEY_SPACE:
			if not cpu_hitter and event.is_pressed() and not event.is_echo() and phase=="set" and swing_time<0.:
				swing_time=0.
			get_viewport().set_input_as_handled()
			return
		if event is InputEventJoypadButton and event.button_index!=Xbox.physical(JOY_BUTTON_START): return
		if event is InputEventKey and event.physical_keycode!=KEY_ESCAPE: return
	super._input(event)

func step_practice(delta: float) -> void:
	if attack_jump.active:
		attack_jump.step(hitter,delta,Vector2.ZERO)
	else:
		hitter.animator.advance(delta)
		if cpu_hitter and not approach_started and phase in ["set_contact","set"]:
			var entry := Vector3(endpoint.x+.18,START.y,endpoint.z-2.20)
			var travel := (entry-hitter.position).limit_length(5.8*delta)
			hitter.position=rotation_drill.move_actor(hitter,travel)
			hitter.play_ground_gait(travel.length()/maxf(delta,.001))
		if not cpu_hitter and not approach_started:
			var stick := Vector2(axis(JOY_AXIS_LEFT_X),axis(JOY_AXIS_LEFT_Y)).limit_length(1.)
			var right := camera.global_basis.x.slide(Vector3.UP).normalized()
			var travel := (right*stick.x+right.cross(Vector3.UP)*stick.y)*3.8 if stick.length()>.16 else Vector3.ZERO
			hitter.position=rotation_drill.move_actor(hitter,travel*delta)
			hitter.play_ground_gait(travel.length())
	if phase=="spike":
		elapsed+=delta
		swing_time+=delta
		pose_swing()
		advance_missed_ball(delta)
		if roll_time>=.5:
			rotation_drill.free_ball(drop_velocity)
			begin("between")
		return
	super.step_practice(delta)
	if phase=="pass": message.text="Coach toss to setter"
	if phase=="set_contact": message.text="Setter contact"

func start_approach() -> void:
	if approach_started: return
	approach_started=true
	var contact_stance := Vector3(endpoint.x+.18,.04,endpoint.z-.30)
	var heading := (contact_stance-hitter.position).slide(Vector3.UP).normalized()
	hitter.rotation.y=atan2(heading.x,heading.z)
	attack_jump.begin(hitter,Vector2(-heading.x,heading.z),contact_stance,PLANT_TIME,jump_height,3,false,1.,false,.22)
	var to_ball := (endpoint-hitter.position).slide(Vector3.UP)
	if not to_ball.is_zero_approx(): attack_jump.lead_heading=to_ball.normalized()
	attack_jump.release()

func handle_attack_contact(previous: Vector3,delta: float) -> bool:
	message.text="Approach and spike"
	var remaining := flight_time-elapsed
	var rise := attack_jump.flight_duration(jump_height,true)*.48
	if cpu_hitter and remaining<=attack_jump.LEAD_STEP_TIME+PLANT_TIME+rise+.025: start_approach()
	if cpu_hitter and approach_started and swing_time<0. and remaining<=.16: swing_time=0.
	if swing_time<0. and attack_jump.active and attack_jump.elapsed>attack_jump.load_duration():
		pose_swing()
	if swing_time>=0.:
		swing_time+=delta
		pose_swing()
		var palm := Contact.palm(hitter,"r")
		var nearest := Geometry3D.get_closest_point_to_segment(palm,previous,ball.position)
		if swing_time>=.055 and swing_time<=.30 and nearest.distance_to(palm)<=Contact.BALL_RADIUS+.065:
			contact_swing_time=swing_time
			strike_point=ball.position
			spikes+=1
			success=true
			feedback="Spike"
			message.text=feedback
			gym.update_board(spikes)
			var landing := shot_landing(ball.position)
			var shot_time := .68
			if not review_setup.is_empty(): shot_time=landing.distance_to(ball.position)/float(review_setup.get("power",14.))
			drop_velocity=(landing-ball.position)/shot_time+Vector3.UP*(4.905*shot_time)
			roll_time=-1.
			trace("spike",{"from":str(ball.position),"palm_gap":nearest.distance_to(palm)})
			begin("spike")
			return true
	if elapsed>=flight_time:
		feedback="Missed spike"
		message.text=feedback
		success=false
		drop_velocity=(endpoint-source-Vector3.UP*4.*APEX[tempo])/flight_time
		begin("drop")
		return true
	return false

func shot_landing(origin: Vector3) -> Vector3:
	if not review_setup.is_empty():
		return Vector3(review_setup.get("x",3.4),Contact.BALL_RADIUS,review_setup.get("z",11.))
	return Vector3(-3.4 if cross_court else clampf(origin.x,-3.8,3.8),Contact.BALL_RADIUS,11.)

func pose_swing() -> void:
	if swing_time>.50: return
	var rig: Skeleton3D=hitter.skeleton
	var pose: Array=[]
	for id in rig.get_bone_count(): pose.append(rig.get_bone_pose(id))
	var reach := smoothstep(.025,.13,swing_time)
	var follow := smoothstep(.16,.46,swing_time)
	var author = hitter.get_pose_author()
	var airborne := smoothstep(0.,.12,attack_jump.elapsed-attack_jump.load_duration()) if attack_jump.active else 0.
	var load_weight := airborne*(1.-smoothstep(.025,.23,swing_time))
	var toward_feed := (source-hitter.position).slide(Vector3.UP).normalized()
	var open_axis := hitter.basis.inverse()*(toward_feed+Vector3.BACK*1.1)
	var twist := clampf(atan2(open_axis.x,open_axis.z),-.85,.85)*load_weight
	var hip_turn := twist*.50
	var feed_local := hitter.basis.inverse()*toward_feed
	twist = clampf(atan2(feed_local.x,feed_local.z),-1.48,1.48)*load_weight-hip_turn
	author.rotate_world(pose,"spine_01",Vector3.RIGHT,deg_to_rad(-9.)*load_weight)
	author.rotate_world(pose,"spine_01",Vector3.UP,twist*.45)
	author.rotate_world(pose,"spine_02",Vector3.UP,twist*.55)
	var air_age := attack_jump.elapsed-attack_jump.load_duration()
	# Drive the hips through takeoff and let the heels trail until the strike.
	var tuck_age := maxf(0.,air_age-.015)
	var since_hit := swing_time-contact_swing_time if phase=="spike" else 0.
	# Ease out of the tuck during the forward stroke, finishing two ticks after contact.
	var extension_phase := clampf((swing_time-.065)/.11,0.,.70)
	if phase=="spike":
		var at_contact := clampf((contact_swing_time-.065)/.11,0.,.70)
		extension_phase = lerpf(at_contact,1.,clampf(since_hit/.030,0.,1.))
	var extension := smoothstep(0.,1.,extension_phase)
	var landing_blend := 1.-smoothstep(.19,.33,since_hit)
	var leg_weight := smoothstep(0.,.055,tuck_age)*landing_blend if attack_jump.active else 0.
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
		author.aim_joint(pose,thigh,calf,hip+leg.slerp(thigh_axis.slerp(Vector3(outward,-.87,.49).normalized(),extension),leg_weight))
		var knee: Vector3 = author.point(pose,calf)
		var shin: Vector3 = (author.point(pose,foot)-knee).normalized()
		# In the edited hang the ankles rise above the knees while the toes hang down.
		var seat := hip+Vector3(outward*.45,-.065,-.17)/rig.global_basis.y.length()
		var full_tuck := (seat-knee).normalized()
		var previous_tuck := Vector3(outward,.83,-.55).normalized()
		var heel := previous_tuck.slerp(full_tuck,.63)
		var extended := (knee-hip).normalized()
		var blend := maxf(knee_load,airborne)*landing_blend
		# Unfold in the forward/back plane; a 3D arc can swing an ankle sideways mid-stroke.
		var folded := atan2(heel.z,-heel.y)
		if folded>0.: folded-=TAU
		var fold_angle := lerpf(folded,atan2(extended.z,-extended.y),extension)
		var lateral := lerpf(heel.x,extended.x,extension)
		var plane_length := sqrt(maxf(0.,1.-lateral*lateral))
		var shin_target := Vector3(lateral,-cos(fold_angle)*plane_length,sin(fold_angle)*plane_length)
		author.aim_joint(pose,calf,foot,knee+shin.slerp(shin_target,blend))
		var ankle: Vector3 = author.point(pose,foot)
		var toes := "ball_"+str(side)
		var toe_axis: Vector3 = (author.point(pose,toes)-ankle).normalized()
		var shin_axis := (ankle-knee).normalized()
		var hanging_toes := Vector3.FORWARD.slide(shin_axis).normalized()
		author.aim_joint(pose,foot,toes,ankle+toe_axis.slerp(hanging_toes,knee_load))
	# Apply pelvic rotation after solving the tuck so both legs inherit it.
	author.rotate_world(pose,"pelvis",Vector3.UP,hip_turn)
	var draw_end := attack_jump.flight_duration(jump_height,true)*.48-.095
	var draw := smoothstep(.035,draw_end,air_age) if attack_jump.active else 0.
	var origin := strike_point if phase=="spike" else ball.position
	var shot_axis := hitter.basis.inverse()*origin.direction_to(shot_landing(origin)).slide(Vector3.UP).normalized()
	Swing.apply(pose,hitter.get_pose_author(),rig.to_local(strike_point if phase=="spike" else ball.position),maxf(draw,smoothstep(0.,.065,swing_time)),reach,follow,maxf(draw,reach),0.,1. if cross_court else 0.,Swing.DEFAULT_ELBOW_CLEARANCE,0.,INF,shot_axis,0.,.10,false,true)
	var guide_target := rig.to_local(strike_point if phase=="spike" else ball.global_position)
	var shoulder: Vector3 = author.point(pose,"upperarm_l")
	var guide_drop := maxf(reach,follow)
	Swing.apply_guide_arm(pose,author,guide_target-shoulder,Vector3(.8,.1,-.2),guide_drop,airborne,174.)
	var wrist: Vector3 = author.point(pose,"hand_l")
	var fingers: Vector3 = (author.point(pose,"middle_01_l")-wrist).normalized()
	var point_axis := wrist.direction_to(guide_target)
	author.aim_joint(pose,"hand_l","middle_01_l",wrist+fingers.slerp(point_axis,airborne*(1.-guide_drop)))
	for joint in ["pelvis","spine_01","spine_02","thigh_r","thigh_l","calf_r","calf_l","foot_r","foot_l","clavicle_r","upperarm_r","lowerarm_r","hand_r","clavicle_l","upperarm_l","lowerarm_l","hand_l"]:
		var id := rig.find_bone(joint)
		rig.set_bone_pose_rotation(id,pose[id].basis.get_rotation_quaternion())

func frame_editor_attacker() -> Node3D:
	return hitter

func edit_approach_frames(arm_lift := false, arm_swing := false, cross := false, review := false) -> void:
	cross_court=cross
	if review or arm_swing:
		review_setup=StorySession.load_drill_setup("swing_review")
		if not review and not Engine.has_meta("reload_swing_frame"):
			review_setup.x=-3.4 if cross else 3.4
		if Engine.has_meta("reload_swing_frame"): Engine.remove_meta("reload_swing_frame")
		jump_height=float(review_setup.get("jump",33.))*.0254
		cross_court=float(review_setup.get("x",3.4))<1.
	# Warm up from the first step so the editor inherits the live plant pose.
	hitter.position=START
	hitter.rotation.y=0.
	hitter.play_action("idle",0.)
	hitter.animator.advance(0.)
	endpoint=START+Vector3(-.18,0.,2.20)
	endpoint+=Vector3(review_setup.get("set_x",0.),0.,review_setup.get("set_z",0.))
	approach_started=false
	start_approach()
	var recording := preload("res://scripts/match_replay.gd").new()
	var takeoff := attack_jump.load_duration()
	var first_frame := floori((takeoff-.15)*60.) if arm_lift else 0
	var duration := takeoff+.25 if arm_lift else takeoff
	if arm_swing:
		duration=(first_frame+50)/60.
		cpu_hitter=true
		flight_time=DURATION[1]
	swing_time=-1.
	if arm_lift:
		phase="set"
		source=setter.position+Vector3.UP*(setter.height_cm*.01+.12)
		endpoint.y=2.65+ATTACK_SET_LIFT+jump_height-JUMP_HEIGHT
	var hit_frame := -1
	var count := ceili(duration*60.)
	for i in range(count+1):
		var time := minf(i/60.,duration)
		if i>0: attack_jump.step(hitter,time-(i-1)/60.,Vector2.ZERO)
		if arm_lift:
			var remaining := takeoff+attack_jump.flight_duration(jump_height,true)*.48+.025-time
			if arm_swing and phase in ["spike","drop"]:
				swing_time+=1./60.
				pose_swing()
				advance_missed_ball(1./60.)
			else:
				var previous := ball.position
				ball.position=arc(source,endpoint,clampf(1.-remaining/DURATION[1],0.,1.),APEX[1])
				if arm_swing:
					elapsed=flight_time-remaining
					handle_attack_contact(previous,1./60.)
					if phase=="spike": hit_frame=i-first_frame
				elif time>takeoff: pose_swing()
		if i<first_frame: continue
		var bones: Array[Transform3D]=[]
		for id in hitter.skeleton.get_bone_count():
			bones.append(hitter.skeleton.get_bone_pose(id))
		recording.frames.append({"time":time-first_frame/60.,"ball":ball.global_transform,"actors":[{"root":hitter.transform,"bones":bones}]})
	var title := "Takeoff and arm lift" if arm_lift else "Three-step approach and backswing"
	if arm_swing: title="Cross-court swing" if cross else "Down-the-line swing"
	recording.index=0
	StorySession.edit_animation=recording.bake_recorded_actor(hitter,0,title,recording.frames.size()-1,arm_lift)
	StorySession.edit_animation.remove_meta("contact_time")
	if arm_lift: StorySession.edit_animation.set_meta("editor_initial_frame",15)
	StorySession.edit_animation.set_meta("editor_height_cm",hitter.height_cm)
	StorySession.edit_entry={"id":"camp_attack_arm_lift" if arm_lift else "camp_spike_approach","name":title,"category":"Attacking","type":"Approach"}
	if arm_swing:
		StorySession.edit_entry={"id":"camp_right_arm_swing","name":title,"category":"Attacking","type":"Spike"}
		StorySession.edit_entry["aim_x"]=review_setup.get("x",3.4)
		StorySession.edit_animation.set_meta("editor_group","Right Arm")
		StorySession.edit_animation.set_meta("editor_initial_frame",10)
		StorySession.edit_animation.set_meta("editor_loop_start",10)
	if review:
		StorySession.edit_entry["swing_review"]=true
		StorySession.edit_animation.set_meta("swing_hit_frame",hit_frame)
	StorySession.animation_draft.clear()
	settings.leave_for_frame_editor()
	MenuPresentation.load_scene("res://scenes/animation_editor.tscn")
