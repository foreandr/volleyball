extends "res://scripts/indoor_practice.gd"

const Swing = preload("res://scripts/spike_arm_swing.gd")
const START := Vector3(3.65,.04,.76)
var hitter: Node3D
var attack_jump := preload("res://scripts/setter_jump.gd").new()
var swing_time := -1.
var cpu_hitter := true
var approach_started := false
const JUMP_HEIGHT := 1.08
const PLANT_TIME := .30
var spikes := 0
var strike_point := Vector3.ZERO

func start_drill() -> void:
	hitter=athlete(START,"e97937")
	hitter.apply_profile(setter.attributes.duplicate())
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
	if "--edit-approach" in OS.get_cmdline_user_args() and not Engine.has_meta("approach_editor_opened"):
		Engine.set_meta("approach_editor_opened",true)
		edit_approach_frames.call_deferred()

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
	return super.set_destination(origin,aim+Vector3(-1.1,0.,0.),height_index)

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
	attack_jump.begin(hitter,Vector2(-heading.x,heading.z),contact_stance,PLANT_TIME,JUMP_HEIGHT,3,false,1.,false,.22)
	attack_jump.release()

func handle_attack_contact(previous: Vector3,delta: float) -> bool:
	message.text="Approach and spike"
	var remaining := flight_time-elapsed
	var rise := attack_jump.flight_duration(JUMP_HEIGHT,true)*.48
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
			strike_point=ball.position
			spikes+=1
			success=true
			feedback="Spike"
			message.text=feedback
			gym.update_board(spikes)
			var landing := Vector3(clampf(ball.position.x,-3.8,3.8),Contact.BALL_RADIUS,11.)
			var shot_time := .68
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

func pose_swing() -> void:
	if swing_time>.50: return
	var rig: Skeleton3D=hitter.skeleton
	var pose: Array=[]
	for id in rig.get_bone_count(): pose.append(rig.get_bone_pose(id))
	var reach := smoothstep(.025,.13,swing_time)
	var follow := smoothstep(.16,.46,swing_time)
	var author = hitter.get_pose_author()
	var airborne := smoothstep(0.,.12,attack_jump.elapsed-attack_jump.load_duration()) if attack_jump.active else 0.
	var load_weight := airborne*(1.-reach)
	var twist := deg_to_rad(-38.)*load_weight
	author.rotate_world(pose,"spine_01",Vector3.UP,twist*.45)
	author.rotate_world(pose,"spine_02",Vector3.UP,twist*.55)
	for side in ["r","l"]:
		var calf := "calf_"+str(side)
		var foot := "foot_"+str(side)
		var knee: Vector3 = author.point(pose,calf)
		var shin: Vector3 = (author.point(pose,foot)-knee).normalized()
		var outward := -.12 if side=="r" else .12
		var heel := Vector3(outward,.32 if side=="r" else .09,-1.).normalized()
		var extended := Vector3(outward,-1.,-.14).normalized()
		var blend := airborne*(1.-follow)
		author.aim_joint(pose,calf,foot,knee+shin.slerp(heel.slerp(extended,reach),blend))
	Swing.apply(pose,hitter.get_pose_author(),rig.to_local(strike_point if phase=="spike" else ball.position),maxf(airborne,smoothstep(0.,.065,swing_time)),reach,follow,1.,0.,0.,Swing.DEFAULT_ELBOW_CLEARANCE,0.,INF,Vector3.BACK,0.,.10,false,true)
	for joint in ["spine_01","spine_02","calf_r","calf_l","clavicle_r","upperarm_r","lowerarm_r","hand_r","clavicle_l","upperarm_l","lowerarm_l","hand_l"]:
		var id := rig.find_bone(joint)
		rig.set_bone_pose_rotation(id,pose[id].basis.get_rotation_quaternion())

func frame_editor_attacker() -> Node3D:
	return hitter

func edit_approach_frames() -> void:
	# Sample the same planted approach used on court, ending exactly at liftoff.
	hitter.position=START
	hitter.rotation.y=0.
	hitter.play_action("idle",0.)
	hitter.animator.advance(0.)
	endpoint=START+Vector3(-.18,0.,2.20)
	approach_started=false
	start_approach()
	var recording := preload("res://scripts/match_replay.gd").new()
	var duration := attack_jump.load_duration()
	var count := ceili(duration*60.)
	for i in range(count+1):
		var time := minf(i/60.,duration)
		if i>0: attack_jump.step(hitter,time-(i-1)/60.,Vector2.ZERO)
		var bones: Array[Transform3D]=[]
		for id in hitter.skeleton.get_bone_count():
			bones.append(hitter.skeleton.get_bone_pose(id))
		recording.frames.append({"time":time,"actors":[{"root":hitter.transform,"bones":bones}]})
	var title := "Three-step approach and backswing"
	recording.index=0
	StorySession.edit_animation=recording.bake_recorded_actor(hitter,0,title,count,false)
	StorySession.edit_animation.set_meta("editor_height_cm",hitter.height_cm)
	StorySession.edit_entry={"id":"camp_spike_approach","name":title,"category":"Attacking","type":"Approach"}
	StorySession.animation_draft.clear()
	settings.leave_for_frame_editor()
	MenuPresentation.load_scene("res://scenes/animation_editor.tscn")
