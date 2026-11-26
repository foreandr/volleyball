extends "res://scripts/serving_camp.gd"

const FIVE := Vector3(2.65,.04,-2.2)
var cpu_defense := true
var feed_age := 0.
var attack_landing := Vector3.ZERO

func start_drill() -> void:
	super.start_drill()
	title.text="DIGGING  /  DIG FROM FIVE"
	for actor in passers+[receiving_middle,wall[1],wall[2]]:
		actor.hide()
	coach.show()
	coach.position=Vector3(-.5,.04,10.3)
	GroundControls.face(coach,SETTER_BASE-coach.position,1.,10.)
	update_prompts("ready")

func build_rally_sliders() -> void:
	pass

func update_prompts(_next: String) -> void:
	var mode := "cpu_dig" if cpu_defense else "player_dig"
	if prompt_phase==mode: return
	prompt_phase=mode
	if cpu_defense:
		Xbox.prompts(controls_row,[["View","Control defender"]])
	else:
		Xbox.prompts(controls_row,[["View","Watch CPU"],["LS","Move"],["LT","Shuffle"],["RT","Sprint"],["X","Dig"]])

func _input(event: InputEvent) -> void:
	if not settings.visible and not replay_inspector.active and not get_tree().paused:
		if event is InputEventJoypadButton and event.pressed and event.button_index==Xbox.physical(JOY_BUTTON_BACK):
			cpu_defense=not cpu_defense
			update_prompts("")
			get_viewport().set_input_as_handled()
			return
	super._input(event)

func next_serve() -> void:
	super.next_serve()
	hitter.position=FIVE
	hitter.rotation.y=0.
	receiving_setter.position=SETTER_BASE
	receiver=0
	attack_slot=2
	called_slot=2
	off_blocker=-1
	wall[0].position=Vector3(-4.,.04,BallNet.NET_Z-.85)
	serve_clock=10.
	toss_style=2
	feed_age=0.
	phase="coach_feed"
	attack_landing=Vector3(FIVE.x+randf_range(-1.45,1.45),.145,FIVE.z+randf_range(-.75,.75))
	message.text="Coach toss"

func _process(delta: float) -> void:
	if settings.visible or get_tree().paused or replay_inspector.active: return
	if phase=="coach_feed":
		feed_age+=delta
		ball.position=coach_motion.toss(coach,clampf((feed_age-.45)/.33,0.,1.))
		if feed_age>=.78:
			pass_start=ball.position
			pass_end=SETTER_BASE+Vector3.UP*2.
			pass_duration=1.35
			set_at=pass_duration
			pass_clock=0.
			pass_in_system=true
			phase="serve_pass"
			message.text="Set to four"
		return
	if phase=="serve_return" and cpu_defense and not attack_decided:
		var platform: Reception=dig_platforms[hitter]
		if not is_finite(platform.pressed_at): platform.queue_bump(dig_clock)
	super._process(delta)

func walk_server(delta: float,defending := false) -> void:
	if not cpu_defense:
		super.walk_server(delta,defending)
		return
	var point := FIVE
	if phase=="serve_attack":
		point=pass_end.lerp(attack_landing,.80)
		point.z-=.62
		point.y=.04
	elif phase=="serve_return" and not attack_decided:
		var rise := drop_velocity.y*drop_velocity.y+19.62*(ball.position.y-1.04)
		var ahead := maxf(0.,(drop_velocity.y+sqrt(maxf(0.,rise)))/9.81)
		point=ball.position+drop_velocity*ahead
		point.z-=.62
		point.y=.04
		point.x=clampf(point.x,-5.,5.)
		point.z=clampf(point.z,-5.3,BallNet.NET_Z-.4)
	if not dig_platforms[hitter].low_save.active:
		move_receiver(hitter,point,delta,ball.global_position-hitter.global_position,GroundControls.speed(true,false),true)

func scoring_target(_origin: Vector3) -> Vector3:
	return attack_landing

func choose_rally_attack(_origin: Vector3) -> void:
	pin_attack.swing_aim=pin_frame.to_local(attack_landing)

func try_cover(_previous: Vector3,_delta: float) -> void:
	pass

func step_serve_wall(delta: float) -> void:
	var actor := wall[0]
	var block: RefCounted=wall_jumps[0]
	if block!=null:
		if not block.step(delta,ball.global_position): wall_jumps[0]=null
		return
	if phase!="serve_attack": return
	var six := Vector3(0.,.145,-3.)
	var at_net := (actor.position.z-pass_end.z)/(six.z-pass_end.z)
	var goal := actor.position
	goal.x=lerpf(pass_end.x,six.x,at_net)-.48
	move_receiver(actor,goal,delta,Vector3.BACK,GroundControls.speed(true,false),true)
	if not wall_committed[0] and set_duration-pass_clock<=.46:
		block=PracticeBlock.new()
		block.aggressive_press=true
		block.net_heading=0.
		block.jump_height=wall_vertical_inches*.0254*actor.stamina.effectiveness()
		block.begin(actor)
		wall_committed[0]=true
		wall_jumps[0]=block
		actor.stamina.spend(5,"Block")
