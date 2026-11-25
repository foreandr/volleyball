extends "res://scripts/indoor_practice.gd"

const TECHNIQUES := [preload("res://scripts/spin_serve.gd"),preload("res://scripts/jump_float_serve.gd"),preload("res://scripts/standing_float_serve.gd"),preload("res://scripts/underhand_serve.gd")]
const FACE := [JOY_BUTTON_A,JOY_BUTTON_B,JOY_BUTTON_X,JOY_BUTTON_Y]
const LABELS := ["Spin","Float","Standing float","Underhand"]
const HOMES := [Vector3(-2.9,.04,9.2),Vector3(0,.04,10.),Vector3(2.9,.04,9.2)]
var serves := []
var passers: Array[Node3D]=[]
var timing := preload("res://scripts/ball_timing_ring.gd").new()
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

func start_drill() -> void:
	coach.hide()
	rotation_drill.basket.hide()
	for item in rotation_drill.stock: item.hide()
	for target in targets: target.hide()
	score_strip.hide()
	world.add_child(timing)
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
		driver.configure(setter,Vector3(0,.04,[-8.2,-6.6,-6.1,-6.1][i]))
		driver.hide()
		serves.append(driver)
	title.text="SERVING"
	Xbox.prompts(controls_row,[["A","Spin"],["B","Jump float"],["X","Standing float"],["Y","Underhand"]])
	apply_camera.call_deferred()
	next_serve()

func apply_camera() -> void:
	place_practice_camera(Vector3(0,1.5,-4.4),distance*.48)

func next_serve() -> void:
	phase="serve_ready"
	serve_clock=0.
	release_time=INF
	timing.hide()
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

func serve_pose(time: float) -> void:
	var toss=serves[toss_style]
	var offset: float=time-toss.contact_time()
	var blend := smoothstep(-.20,-.04,offset)*(1.-smoothstep(.10,.28,offset))
	if hit_style==toss_style or blend<=0.:
		toss.pose(time)
		return
	var strike=serves[hit_style]
	strike.pose(strike.contact_time()+offset)
	var rig: Skeleton3D=setter.skeleton
	var arm := {}
	for joint in ["upperarm_r","lowerarm_r","hand_r"]:
		var bone := rig.find_bone(joint)
		arm[bone]=rig.get_bone_pose_rotation(bone)
	toss.pose(time)
	for bone in arm:
		rig.set_bone_pose_rotation(bone,rig.get_bone_pose_rotation(bone).slerp(arm[bone],blend))

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
		timing.position=setter.position
		var ideal := strike-.075
		timing.update_timing(serve_clock,ideal,-.055,.055)
		if serve_clock>=strike:
			timing.hide()
			var error := release_time-ideal
			if absf(error)>.22:
				phase="serve_miss"
				message.text="Late" if error>0. else "Early"
				drop_velocity=Vector3.ZERO
				roll_time=-1.
				drop_net_hit.clear()
				drop_net_time=0.
				flight_age=0.
			else:
				var shot=serves[hit_style]
				shot.origin=Contact.palm(setter,"r") if hit_style!=toss_style else ball.position
				shot.apex=maxf(shot.origin.y+.3,4.3 if hit_style==0 else 4.9)
				shot.target=destination+Vector3(0,0,-error*8.)
				shot.planned_duration=shot.flight_duration(shot.origin)
				shot.velocity=shot.launch_velocity(shot.origin,shot.planned_duration)
				shot.begin_serve_curve()
				shot.net_hit=BallNet.first_hit(shot.flight_point,0.,shot.planned_duration)
				shot.ball.basis=ball.basis
				flight_age=0.
				phase="serve_flight"
				message.text=("Perfect" if absf(error)<=.055 else ("Early" if error<0. else "Late"))+" / "+LABELS[hit_style]
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
