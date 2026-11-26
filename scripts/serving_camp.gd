extends "res://scripts/attacking_camp.gd"

const TECHNIQUES := [preload("res://scripts/spin_serve.gd"),preload("res://scripts/jump_float_serve.gd"),preload("res://scripts/standing_float_serve.gd"),preload("res://scripts/underhand_serve.gd")]
const FACE := [JOY_BUTTON_A,JOY_BUTTON_B,JOY_BUTTON_X,JOY_BUTTON_Y]
const LABELS := ["Spin","Float","Standing float","Underhand"]
const HOMES := [Vector3(-2.9,.04,9.2),Vector3(0,.04,10.),Vector3(2.9,.04,9.2)]
var serves := []
var passers: Array[Node3D]=[]
const JUMP_SERVE_VERTICAL := 57.*.0254
const JUMP_TOSS_APEX := [6.4,5.1]
const SERVE_EARLY := -.22
const SERVE_LATE := .075
const SERVE_PERFECT := .055
var toss_airborne := false
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
	jump_height=JUMP_SERVE_VERTICAL
	hitter=setter
	cpu_hitter=false
	attack_jump.attack_arm_lift=true
	attack_jump.back_limit=-10.5
	attack_jump.load_lead_arm_clip()
	world.add_child(hand_impact)
	hand_impact.bus=StorySession.IMPACT_BUS
	hand_impact.stream=preload("res://assets/audio/hand_impacts.tres")
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
		driver.configure(setter,Vector3(0,.04,[-8.2,-6.6,-6.1,-6.1][i]))
		driver.hide()
		serves.append(driver)
	title.text="SERVING"
	update_prompts("ready")
	apply_camera.call_deferred()
	next_serve()

func update_prompts(_next: String) -> void:
	if prompt_phase=="serving": return
	prompt_phase="serving"
	Xbox.prompts(controls_row,[["A","Spin"],["B","Jump float"],["X","Standing float"],["Y","Underhand"],["LS","Aim"]])

func apply_camera() -> void:
	place_practice_camera(Vector3(0,1.5,-4.4),distance*.48+2.)

func update_serve_aim(delta: float) -> void:
	var stick := Vector2(axis(JOY_AXIS_LEFT_X),axis(JOY_AXIS_LEFT_Y))
	if stick.length()>.16:
		var right := camera.global_basis.x.slide(Vector3.UP).normalized()
		var forward := -camera.global_basis.z.slide(Vector3.UP).normalized()
		destination+=(right*stick.x-forward*stick.y)*5.*delta
		destination.x=clampf(destination.x,-4.5,4.5)
		destination.z=clampf(destination.z,BallNet.NET_Z+.2,BallNet.NET_Z+9.)
	var shot=serves[hit_style]
	for driver in serves:
		driver.visible=driver==shot
		driver.ball.hide()
		driver.aim_ring.hide()
	if toss_style<2:
		shot.preview_origin=endpoint if toss_airborne else setter.position+setter.basis.z*2.15+Vector3.UP*(attack_contact_height()-setter.position.y)
	shot.apex=maxf(shot.preview_origin.y+.3,4.3 if hit_style==0 else 4.9)
	shot.target=destination
	shot.update_path_preview()

func contact_deadline() -> float:
	return flight_time+.12

func next_serve() -> void:
	for driver in serves: driver.hide()
	clear_attack_input()
	attack_jump.active=false
	approach_started=false
	swing_time=-1.
	toss_airborne=false
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
	if toss_style<2 and not toss_airborne: return SERVE_EARLY-1.
	var sample := release_time if is_finite(release_time) else serve_clock
	var strike: float=serves[toss_style].contact_time()
	if toss_airborne: strike=serves[toss_style].toss_release_time()+flight_time
	return sample-(strike-SERVE_LATE)

func shot_landing(_origin: Vector3) -> Vector3:
	return destination

func self_set_step(motion, previous_time: float,delta: float) -> bool:
	var release: float=motion.toss_release_time()
	if serve_clock<release:
		motion.pose(serve_clock)
		ball.transform=motion.ball.transform
		return false
	if not toss_airborne:
		motion.pose(release)
		source=motion.ball.position
		ball.position=source
		endpoint=hitter.position+hitter.basis.z.normalized()*2.15
		endpoint.y=attack_contact_height()
		active_set=endpoint
		var apex := maxf(JUMP_TOSS_APEX[toss_style],maxf(source.y,endpoint.y)+.1)
		flight_time=sqrt(2.*(apex-source.y)/9.81)+sqrt(2.*(apex-endpoint.y)/9.81)
		set_arc_height=9.81*flight_time*flight_time/8.
		manual_shot=1
		aim_center=Vector2(destination.x,destination.z)
		toss_airborne=true
	var previous := ball.position
	elapsed=serve_clock-release
	var progress := elapsed/flight_time
	ball.position=source.lerp(endpoint,progress)+Vector3.UP*4.*set_arc_height*progress*(1.-progress)
	motion.spin_toss_ball(previous_time,serve_clock,1.)
	ball.basis=motion.ball.basis
	phase="set"
	if attack_jump.active: attack_jump.step(hitter,delta,Vector2.ZERO)
	if is_finite(release_time):
		release_at=release_time
		var error := serve_meter_error()
		release_grade=remap(error,SERVE_EARLY,SERVE_LATE,EARLY_LIMIT,LATE_LIMIT)-GRADE_ADVANCE
	var finished := handle_attack_contact(previous,delta)
	var hit := phase=="spike"
	phase="serve_toss"
	if finished and not hit:
		phase="serve_miss"
		roll_time=-1.
		drop_net_hit.clear()
		drop_net_time=0.
		flight_age=0.
	return hit

func _process(delta: float) -> void:
	if serves.is_empty() or settings.visible or get_tree().paused: return
	hitter.stamina.recover(delta)
	var motion=serves[toss_style]
	if phase=="serve_toss":
		update_serve_aim(delta)
		var strike: float=motion.contact_time()
		var previous := serve_clock
		serve_clock+=delta
		var hit := false
		if toss_style<2:
			hit=self_set_step(motion,previous,delta)
		else:
			motion.pose(minf(serve_clock,strike))
			ball.transform=motion.ball.transform
			hit=serve_clock>=strike
		if hit:
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
				receiver=0
				for i in range(1,passers.size()):
					if HOMES[i].distance_squared_to(shot.target)<HOMES[receiver].distance_squared_to(shot.target): receiver=i
				shot.planned_duration=shot.flight_duration(shot.origin)
				shot.velocity=shot.launch_velocity(shot.origin,shot.planned_duration)
				shot.begin_serve_curve()
				shot.net_hit=BallNet.first_hit(shot.flight_point,0.,shot.planned_duration)
				shot.ball.basis=ball.basis
				flight_age=0.
				phase="serve_flight"
				message.text=("Perfect" if absf(error)<=SERVE_PERFECT else ("Early" if error<0. else "Late"))+" / "+LABELS[hit_style]
				if toss_style>=2: hand_sound.play()
	elif phase in ["serve_flight","serve_pass","serve_miss"]:
		serves[hit_style].hide()
		serve_clock+=delta
		if toss_style<2:
			if attack_jump.active: attack_jump.step(hitter,delta,Vector2.ZERO)
			if swing_time>=0. and swing_time<=.65:
				swing_time+=delta
				var state := phase
				phase="spike" if state!="serve_miss" else "drop"
				pose_swing()
				phase=state
		elif serve_clock<=motion.recovery_end(): motion.pose(serve_clock)
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
