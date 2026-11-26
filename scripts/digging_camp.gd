extends "res://scripts/serving_camp.gd"

const FIVE := Vector3(2.65,.04,-2.2)
const STICK_DEADZONE := .20
var holding_dig := false
var stick_engaged := false
var dig_direction := Vector2.ZERO
var release_window := 0.
var neutral_platform := Vector3.ZERO
var feed_direction := Vector2.ZERO
var cpu_defense := true
var feed_age := 0.
var attack_landing := Vector3.ZERO

func start_drill() -> void:
	super.start_drill()
	wall_vertical_inches=34.
	pin_attack.jump.max_height=46.*.0254+.2032
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
		Xbox.prompts(controls_row,[["View","Watch CPU"],["A","Hold ready"],["RS","Aim / release to dig"]])

func _input(event: InputEvent) -> void:
	if not settings.visible and not replay_inspector.active and not get_tree().paused:
		if event is InputEventJoypadButton and event.button_index==Xbox.physical(JOY_BUTTON_A):
			active_pad=event.device
			holding_dig=event.pressed
			if holding_dig:
				cpu_defense=false
				dig_direction=Vector2.ZERO
				stick_engaged=false
				update_prompts("")
			get_viewport().set_input_as_handled()
			return
		if not cpu_defense and event is InputEventJoypadButton and event.button_index==StorySession.pad_bindings[1]: return
		if not cpu_defense and event is InputEventJoypadMotion and holding_dig and event.axis in [JOY_AXIS_RIGHT_X,JOY_AXIS_RIGHT_Y]:
			var stick := Vector2(axis(JOY_AXIS_RIGHT_X),axis(JOY_AXIS_RIGHT_Y))
			if event.axis==JOY_AXIS_RIGHT_X: stick.x=event.axis_value
			else: stick.y=event.axis_value
			read_dig_stick(stick)
		if event is InputEventJoypadButton and event.pressed and event.button_index==Xbox.physical(JOY_BUTTON_BACK):
			cpu_defense=not cpu_defense
			holding_dig=false
			stick_engaged=false
			release_window=0.
			update_prompts("")
			get_viewport().set_input_as_handled()
			return
	super._input(event)

func next_serve() -> void:
	super.next_serve()
	holding_dig=false
	stick_engaged=false
	release_window=0.
	dig_direction=Vector2.ZERO
	feed_direction=Vector2(randf_range(-1.,1.),randf_range(-1.,1.)).limit_length(1.)
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
	if phase=="serve_return":
		release_window=maxf(0.,release_window-delta)
		if cpu_defense:
			dig_direction=feed_direction
			var center: Vector3=dig_platforms[hitter].platform_center()
			var closest_time := (center-ball.position).dot(drop_velocity)/maxf(.01,drop_velocity.length_squared())
			if closest_time>=0. and closest_time<.08: release_window=.12
		if release_window>0.: dig_platforms[hitter].queue_bump(dig_clock)
	super._process(delta)

func read_dig_stick(stick: Vector2) -> void:
	if stick.length()>.30:
		dig_direction=stick.normalized()
		stick_engaged=true
	elif stick.length()<STICK_DEADZONE and stick_engaged:
		release_window=.15
		stick_engaged=false

func platform_offset(direction: Vector2) -> Vector3:
	var right := camera.global_basis.x.slide(Vector3.UP).normalized()
	return right*direction.x*.48+Vector3(0.,direction.y*.38,-direction.y*.32)

func walk_server(delta: float,_defending := false) -> void:
	hitter.play_ground_gait(0.)
	hitter.animator.advance(delta)
	if phase=="server_dig": return
	if cpu_defense or holding_dig or release_window>0.:
		var platform: Reception=dig_platforms[hitter]
		platform.sample_pose(platform.clip,platform.tracks,platform.contact_frame,1.,true)
		neutral_platform=platform.platform_center()
		platform.reach_platform(platform_offset(dig_direction),1.,.55,true,true)

func return_struck(actor: Node3D,point: Vector3,velocity: Vector3,spin: float) -> void:
	var contact := (neutral_platform if neutral_platform!=Vector3.ZERO else FIVE+Vector3(0,1.04,.62))+platform_offset(feed_direction)
	var travel := maxf(.30,point.distance_to(contact)/maxf(1.,velocity.length()))
	var launch := (contact-point)/travel+Vector3.UP*4.905*travel
	var flight := preload("res://scripts/pass_flight.gd").landing_time(point,launch)
	var landing := point+launch*flight+Vector3.DOWN*4.905*flight*flight
	pin_attack.swing_aim=pin_frame.to_local(landing)
	super.return_struck(actor,point,launch,spin)

func sample_defensive_contact(platform: Reception,start: float,dt: float,_until_floor: float,path: Callable) -> void:
	if release_window<=0.: return
	var contact := platform.dig_contact_segment(path.call(start),path.call(start+dt))
	if contact[0].distance_to(contact[1])>platform.PLATFORM_RADIUS: return
	platform.touch=contact[0]
	platform.touch_time=start+dt
	platform.outgoing=platform.aim_velocity(platform.touch)
	platform.capture_bump_contact()

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
	if phase=="server_dig":
		move_receiver(actor,Vector3(-4.,.04,BallNet.NET_Z-.85),delta,ball.global_position-actor.global_position,GroundControls.speed(true,false),true)
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
