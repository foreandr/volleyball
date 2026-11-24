extends "res://scripts/indoor_practice.gd"

const Swing = preload("res://scripts/spike_arm_swing.gd")
const START := Vector3(3.55,.04,.05)
var hitter: Node3D
var attack_jump := preload("res://scripts/setter_jump.gd").new()
var swing_time := -1.
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
	super.start_drill()

func camp_title() -> String:
	return "ATTACKING   /   APPROACH AND SPIKE"

func update_prompts(_next: String) -> void:
	Xbox.prompts(controls_row,[[JOY_BUTTON_X,"Spike"],[JOY_BUTTON_START,"Settings"]])

func reset_feed() -> void:
	super.reset_feed()
	camp_call=0
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
		if event is InputEventJoypadButton and event.button_index==Xbox.physical(JOY_BUTTON_X) or event is InputEventKey and event.physical_keycode==KEY_SPACE:
			if event.is_pressed() and not event.is_echo() and phase=="set" and swing_time<0.:
				swing_time=0.
			get_viewport().set_input_as_handled()
			return
		if event is InputEventJoypadButton and event.button_index!=Xbox.physical(JOY_BUTTON_START): return
		if event is InputEventKey and event.physical_keycode!=KEY_ESCAPE: return
	super._input(event)

func step_practice(delta: float) -> void:
	hitter.animator.advance(delta)
	if attack_jump.active: attack_jump.step(hitter,delta,Vector2.ZERO)
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

func handle_attack_contact(previous: Vector3,delta: float) -> bool:
	message.text="Approach and spike"
	var plant := Vector3(endpoint.x+.18,.04,endpoint.z-.40)
	if not attack_jump.active:
		var step := (plant-hitter.position).slide(Vector3.UP).limit_length(4.6*delta)
		hitter.position=rotation_drill.move_actor(hitter,step)
		hitter.play_ground_gait(step.length()/maxf(delta,.001))
		if flight_time-elapsed<=.56:
			attack_jump.begin(hitter,Vector2.UP,plant,.20,.88)
			attack_jump.release()
	if swing_time>=0.:
		swing_time+=delta
		pose_swing()
		var palm := Contact.palm(hitter,"r")
		var nearest := Geometry3D.get_closest_point_to_segment(palm,previous,ball.position)
		if swing_time>=.055 and swing_time<=.30 and nearest.distance_to(palm)<=.34:
			strike_point=ball.position
			spikes+=1
			success=true
			feedback="Spike"
			message.text=feedback
			gym.update_board(spikes)
			drop_velocity=(Vector3(clampf(ball.position.x,-3.8,3.8),.15,11.)-ball.position).normalized()*14.
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
	Swing.apply(pose,hitter.get_pose_author(),rig.to_local(strike_point if phase=="spike" else ball.position),1.,reach,follow,1.,0.,0.,Swing.DEFAULT_ELBOW_CLEARANCE,0.,INF,Vector3.BACK,0.,.40,false,true)
	for joint in ["clavicle_r","upperarm_r","lowerarm_r","hand_r","clavicle_l","upperarm_l","lowerarm_l","hand_l"]:
		var id := rig.find_bone(joint)
		rig.set_bone_pose_rotation(id,pose[id].basis.get_rotation_quaternion())
