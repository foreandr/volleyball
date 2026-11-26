extends "res://scripts/indoor_practice.gd"

const TECHNIQUES := [preload("res://scripts/spin_serve.gd"),preload("res://scripts/jump_float_serve.gd"),preload("res://scripts/standing_float_serve.gd"),preload("res://scripts/underhand_serve.gd")]
const FACE := [JOY_BUTTON_A,JOY_BUTTON_B,JOY_BUTTON_X,JOY_BUTTON_Y]
const LABELS := ["Spin","Float","Standing float","Underhand"]
const HOMES := [Vector3(-2.9,.04,9.2),Vector3(0,.04,10.),Vector3(2.9,.04,9.2)]
var serves := []
var passers: Array[Node3D]=[]
const SERVE_EARLY := -.22
const SERVE_LATE := .075
const SERVE_PERFECT := .055
var float_step_anchor := Vector3.ZERO
var float_sample_anchor := Vector3.ZERO
var float_contact_offset := Vector3.ZERO
var toss_style := 2
var hit_style := 2
var release_time := INF
var serve_clock := 0.
var flight_age := 0.
var destination := Vector3.ZERO
var pass_start := Vector3.ZERO
var pass_clock := 0.
var receiver := 0
var hand_sound := AudioStreamPlayer.new()

func _ready() -> void:
	gym.rear_extension=1.5
	super()

func start_drill() -> void:
	coach.hide()
	rotation_drill.basket.hide()
	for item in rotation_drill.stock: item.hide()
	for target in targets: target.hide()
	score_strip.hide()
	hand_sound.bus=StorySession.IMPACT_BUS
	hand_sound.stream=preload("res://assets/audio/hand_impacts.tres")
	add_child(hand_sound)
	for i in HOMES.size():
		var passer := athlete(HOMES[i],"286881")
		register_student(passer,i+3)
		preload("res://scripts/practice_kit.gd").apply(passer,false,i+3)
		passer.rotation.y=PI
		passer.play_action("idle")
		passers.append(passer)
	for i in TECHNIQUES.size():
		var driver=TECHNIQUES[i].new()
		world.add_child(driver)
		if i==0: driver.camp_approach=true
		driver.configure(setter,Vector3(0,.04,[-8.2,-6.6,-6.1,-6.1][i]))
		driver.hide()
		serves.append(driver)
	var spin=serves[0]
	spin.pose(spin.APPROACH_START)
	float_sample_anchor=setter.position
	serves[1].pose(serves[1].toss_release_time())
	float_step_anchor=setter.position
	spin.pose(spin.SPIN_CONTACT)
	float_contact_offset=Contact.palm(setter,"r")+float_step_anchor-float_sample_anchor-serves[1].preview_origin
	title.text="SERVING"
	Xbox.prompts(controls_row,[["A","Spin"],["B","Jump float"],["X","Standing float"],["Y","Underhand"]])
	apply_camera.call_deferred()
	next_serve()

func apply_camera() -> void:
	place_practice_camera(Vector3(0,1.5,-4.4),distance*.48+2.)

func next_serve() -> void:
	phase="serve_ready"
	serve_clock=0.
	release_time=INF
	var ready=serves[2]
	ready.reset()
	ball.position=ready.ball.position
	ball.show()
	for i in passers.size():
		passers[i].position=HOMES[i]
		passers[i].play_action("idle")
	message.text="Hold to serve"

func _input(event: InputEvent) -> void:
	if get_tree().paused or replay_inspector.active: return
	if settings.visible or event.is_action_pressed("ui_cancel") or (event is InputEventJoypadButton and event.button_index==Xbox.physical(JOY_BUTTON_START)):
		super._input(event)
		return
	if not event is InputEventJoypadButton: return
	var style := -1
	for i in FACE.size():
		if event.button_index==Xbox.physical(FACE[i]): style=i
	if style<0: return
	active_pad=event.device
	handle_serve_button(style,event.pressed)
	get_viewport().set_input_as_handled()

func handle_serve_button(style: int,pressed: bool) -> void:
	if pressed and phase=="serve_ready":
		toss_style=style
		hit_style=style
		serves[style].reset()
		receiver=randi_range(0,2)
		destination=HOMES[receiver]+Vector3(randf_range(-.55,.55),.065,1.1)
		phase="serve_toss"
		message.text=LABELS[style]
	elif phase=="serve_toss":
		if pressed and toss_style<2 and style<2:
			hit_style=style
			release_time=INF
			message.text=LABELS[toss_style]+" toss / "+LABELS[style]+" hit"
		elif not pressed and style==hit_style and not is_finite(release_time):
			release_time=serve_clock

func serve_meter_position(error: float) -> float:
	return clampf(inverse_lerp(SERVE_EARLY-.08,SERVE_LATE+.025,error),0.,1.)

func serve_meter_error() -> float:
	var sample := release_time if is_finite(release_time) else serve_clock
	return sample-(serves[toss_style].contact_time()-SERVE_LATE)

func serve_pose(time: float) -> void:
	var toss=serves[toss_style]
	toss.pose(time)
	if toss_style>=2: return
	var offset: float=time-toss.contact_time()
	var rig: Skeleton3D=setter.skeleton
	if toss_style==1 and time>toss.toss_release_time():
		var spin=serves[0]
		var blend := smoothstep(0.,.13,time-toss.toss_release_time())
		var old_position := setter.position
		var old_pose: Array[Transform3D]=[]
		for i in rig.get_bone_count(): old_pose.append(rig.get_bone_pose(i))
		var sample_time: float=spin.SPIN_CONTACT+offset if offset>=0. else lerpf(spin.APPROACH_START,spin.SPIN_CONTACT,inverse_lerp(toss.toss_release_time(),toss.contact_time(),time))
		spin.pose(sample_time)
		if offset<=0.: toss.ball.position+=float_contact_offset*smoothstep(toss.toss_release_time(),toss.contact_time(),time)
		setter.position=old_position.lerp(float_step_anchor+setter.position-float_sample_anchor,blend)
		for i in rig.get_bone_count(): rig.set_bone_pose(i,old_pose[i].interpolate_with(rig.get_bone_pose(i),blend))
	if hit_style==1:
		var author=setter.get_pose_author()
		var pose: Array=[]
		for i in rig.get_bone_count(): pose.append(rig.get_bone_pose(i))
		serves[1].finish_float_wrist(pose,rig,author,serves[1].contact_time()+offset)
		for joint in ["lowerarm_r","hand_r"]:
			var i := rig.find_bone(joint)
			rig.set_bone_pose_rotation(i,pose[i].basis.orthonormalized().get_rotation_quaternion())

func _process(delta: float) -> void:
	if serves.is_empty() or settings.visible or get_tree().paused: return
	var motion=serves[toss_style]
	if phase=="serve_toss":
		var strike: float=motion.contact_time()
		var previous := serve_clock
		serve_clock+=delta
		serve_pose(minf(serve_clock,strike))
		motion.spin_toss_ball(previous,minf(serve_clock,strike),1.)
		ball.transform=motion.ball.transform
		if serve_clock>=strike:
			var error := serve_meter_error() if is_finite(release_time) else INF
			if error<SERVE_EARLY or error>SERVE_LATE:
				phase="serve_miss"
				message.text="Late" if error>0. else "Early"
				drop_velocity=Vector3.ZERO
				roll_time=-1.
				drop_net_hit.clear()
				drop_net_time=0.
				flight_age=0.
			else:
				var shot=serves[hit_style]
				shot.origin=Contact.palm(setter,"r") if toss_style<2 else ball.position
				shot.apex=maxf(shot.origin.y+.3,4.3 if hit_style==0 else 4.9)
				shot.target=destination+Vector3(0,0,-error*8.)
				shot.planned_duration=shot.flight_duration(shot.origin)
				shot.velocity=shot.launch_velocity(shot.origin,shot.planned_duration)
				shot.begin_serve_curve()
				shot.net_hit=BallNet.first_hit(shot.flight_point,0.,shot.planned_duration)
				shot.ball.basis=ball.basis
				flight_age=0.
				phase="serve_flight"
				message.text=("Perfect" if absf(error)<=SERVE_PERFECT else ("Early" if error<0. else "Late"))+" / "+LABELS[hit_style]
				hand_sound.play()
	elif phase in ["serve_flight","serve_pass","serve_miss"]:
		serve_clock+=delta
		if serve_clock<=motion.recovery_end(): serve_pose(serve_clock)
		if phase=="serve_miss":
			advance_missed_ball(delta,true)
			flight_age+=delta
			if flight_age>1.4: next_serve()
		elif phase=="serve_pass":
			pass_clock+=delta
			var t := clampf(pass_clock/1.25,0.,1.)
			ball.position=pass_start.lerp(Vector3(.5,.11,6.),t)+Vector3.UP*6.*t*(1.-t)
			if pass_clock>1.55: next_serve()
		else:
			var shot=serves[hit_style]
			flight_age+=delta
			shot.advance_serve_curve(flight_age)
			shot.spin_serve_ball(delta)
			ball.basis=shot.ball.basis
			var t := minf(flight_age,shot.planned_duration)
			ball.position=BallNet.after_hit(shot.net_hit,t) if not shot.net_hit.is_empty() and t>=shot.net_hit.time else shot.flight_point(t)
			var passer := passers[receiver]
			var goal := Vector3(ball.position.x,.04,ball.position.z+.35)
			if ball.position.z>BallNet.NET_Z:
				passer.position=passer.position.move_toward(goal,delta*3.)
			if ball.position.z>BallNet.NET_Z and ball.position.y<1.25 and ball.position.distance_to(passer.position+Vector3.UP*.9)<1.05:
				pass_start=ball.position
				pass_clock=0.
				phase="serve_pass"
				passer.play_action("forearm")
			elif flight_age>shot.planned_duration+.45: next_serve()
