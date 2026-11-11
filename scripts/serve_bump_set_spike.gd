extends "res://scripts/attack_drill.gd"

const Underhand = preload("res://scripts/underhand_serve.gd")
const BACK_LEFT := Vector3(2.5,0.04,-3.3)
const BACK_RIGHT := Vector3(-2.5,0.04,-3.3)

var server: Node3D
var serve_demo: Node3D
var serve_contact := 0.0

func setup_demo() -> void:
	server = make_demo_player("Server",Color("d9874e"))
	serve_demo = Underhand.new()
	add_child(serve_demo)
	serve_demo.configure(server,Vector3(0.0,0.04,13.9),PI)
	serve_demo.target = Vector3(BACK_LEFT.x,Flight.FLOOR,-4.15)
	serve_demo.aim_ring.hide()
	serve_demo.path_preview.hide()
	reset_feed()

func make_demo_player(role: String, color: Color) -> Node3D:
	var actor := Player.new()
	actor.name = role
	actor.team_color = color
	add_child(actor)
	actor.get_node("DirectionArrows").hide()
	actor.animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	return actor

func reset_feed() -> void:
	super.reset_feed()
	if not is_instance_valid(serve_demo): return
	release_approach_jump()
	setter.position = BACK_LEFT
	setter.rotation.y = 0.0
	receiver.position = BACK_RIGHT
	receiver.rotation.y = 0.0
	bump.destination = Vector2(BACK_RIGHT.x,-1.9)
	bump.height = 4.6
	serve_demo.reset()
	serve_demo.ball.show()
	serve_demo.serve()
	serve_origin = serve_demo.preview_origin
	serve_velocity = serve_demo.launch_velocity(serve_origin,serve_demo.flight_duration(serve_origin))
	serve_contact = descending_time(serve_origin,serve_velocity,1.15)
	bump.green_forearm_allowance = 0.62
	ball.hide()
	region.hide()
	approach_rings.hide()
	status.text = "Underhand serve"

func receive_cue_time() -> float:
	return serve_contact

func tick_demo(delta: float, controls: RefCounted) -> void:
	if stage == Stage.SERVE and not is_finite(serve_demo.contact_clock):
		serve_demo.step(delta)
		if not is_finite(serve_demo.contact_clock): return
		serve_origin = serve_demo.origin
		serve_velocity = serve_demo.velocity
		serve_demo.ball.hide()
		ball.show()
	serve_demo.step(delta)
	controls.read_pace_input()
	trace_input = controls.movement_input()
	if stage in [Stage.PASS,Stage.SET]:
		trace_input = queued_approach_input(delta,controls.sprint_requested)
	approach_from_sprint = false
	trace_sprint = controls.sprint_requested
	if not jump.active and not setter_is_diving():
		var after_pass := stage in [Stage.PASS,Stage.SET]
		if after_pass and trace_input.y > 0.05:
			var heading := atan2(-trace_input.x,trace_input.y)
			setter.rotation.y = rotate_toward(setter.rotation.y,heading,delta*8.0)
		controls.move_player(trace_input,delta,false,ball.position,setter_movement_scale(),court_facing_weight(),not after_pass,jump.front_limit,0.0,0.0,after_pass)
		approach_from_sprint = after_pass and controls.sprinting
	step_jump(delta)
	step(delta)
