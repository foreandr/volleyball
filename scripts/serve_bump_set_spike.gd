extends "res://scripts/attack_drill.gd"

const Underhand = preload("res://scripts/underhand_serve.gd")
const DEMO_SET := Vector3(0.0,0.065,Net.NET_Z-RALLY_SET_NET_CLEARANCE)
const ATTACKER_START := Vector3(0.0,0.04,1.22)

var passer: Node3D
var server: Node3D
var serve_demo: Node3D
var serve_contact := 0.0

func setup_demo() -> void:
	passer = make_demo_player("Passer",Color("458ed5"))
	server = make_demo_player("Server",Color("d9874e"))
	bump.setter = passer
	serve_demo = Underhand.new()
	add_child(serve_demo)
	serve_demo.configure(server,Vector3(0.0,0.04,13.9),PI)
	serve_demo.target = Vector3(0.0,Flight.FLOOR,-3.4)
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
	setter.position = ATTACKER_START
	setter.rotation.y = 0.0
	passer.play_action("idle",0.0)
	passer.animator.advance(0.0)
	passer.rotation.y = 0.0
	serve_demo.reset()
	serve_demo.ball.show()
	serve_demo.serve()
	serve_origin = serve_demo.preview_origin
	serve_velocity = serve_demo.launch_velocity(serve_origin,serve_demo.flight_duration(serve_origin))
	serve_contact = descending_time(serve_origin,serve_velocity,1.15)
	var intercept := flight_point(serve_origin,serve_velocity,serve_contact)
	passer.position = Vector3(intercept.x,0.04,intercept.z-0.47)
	bump.green_forearm_allowance = 0.62
	ball.hide()
	region.hide()
	approach_rings.hide()
	status.text = "Underhand serve"

func receive_cue_time() -> float:
	return serve_contact

func call_rally_set(_passer: Vector3) -> void:
	rally_set_target = DEMO_SET
	region.position = DEMO_SET

func tick_demo(delta: float) -> void:
	if stage == Stage.SERVE and not is_finite(serve_demo.contact_clock):
		serve_demo.step(delta)
		if not is_finite(serve_demo.contact_clock): return
		serve_origin = serve_demo.origin
		serve_velocity = serve_demo.velocity
		serve_demo.ball.hide()
		ball.show()
	serve_demo.step(delta)
	if stage == Stage.SERVE and clock-stage_start >= serve_contact-0.20 and not is_finite(bump.pressed_at):
		queue_set()
	if stage in [Stage.PASS,Stage.SET]:
		approach_space_held = true
		trace_input = queued_approach_input(delta)
	step_jump(delta)
	step(delta)
	match stage:
		Stage.PASS: status.text = "Forearm pass"
		Stage.SET: status.text = "Set" if not jump.active else "Spike approach"
