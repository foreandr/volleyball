extends "res://scripts/attack_drill.gd"

const Underhand = preload("res://scripts/underhand_serve.gd")
const BACK_LEFT := Vector3(2.5,0.04,-3.3)
const BACK_RIGHT := Vector3(-2.5,0.04,-3.3)

var server: Node3D
var serve_demo: Node3D
var serve_contact := 0.0
var serve_to_partner := false
var partner_receiving := false
var user_player: Node3D
var teammate: Node3D
var manual_set_requested := false
var manual_set_apex := SET_APEX
var manual_set_target := Vector3.INF
var set_lane_center := 0.0

func setup_demo() -> void:
	user_player = setter
	teammate = receiver
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
	if is_instance_valid(serve_demo):
		partner_receiving = serve_to_partner
		setter = teammate if partner_receiving else user_player
		receiver = user_player if partner_receiving else teammate
		bump.setter = setter
		cpu_set.setter = receiver
	super.reset_feed()
	if not is_instance_valid(serve_demo): return
	release_approach_jump()
	manual_set_requested = false
	manual_set_target = Vector3.INF
	setter.position = BACK_RIGHT if partner_receiving else BACK_LEFT
	setter.rotation.y = 0.0
	receiver.position = BACK_LEFT if partner_receiving else BACK_RIGHT
	receiver.rotation.y = 0.0
	bump.destination = Vector2(receiver.position.x,-1.9)
	serve_demo.target = Vector3(setter.position.x,Flight.FLOOR,-4.15)
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
	status.text = "Serve to teammate" if partner_receiving else "Serve to you"

func receive_cue_time() -> float:
	return super.receive_cue_time() if bump.hand_setting else serve_contact

func set_pass_aim(point: Vector3) -> void:
	if partner_receiving: return
	bump.destination = Vector2(clampf(point.x,-4.35,4.35),clampf(point.z,-4.8,3.45))

func aim_manual_set(point: Vector3) -> void:
	if not partner_receiving or stage not in [Stage.SERVE,Stage.PASS]: return
	if stage == Stage.PASS and is_finite(cpu_set.touch_time): return
	manual_set_target = point
	if stage == Stage.PASS: update_manual_set_target()

func adjust_manual_set_height(amount: float) -> void:
	if stage == Stage.PASS and is_finite(cpu_set.touch_time): return
	manual_set_apex = clampf(manual_set_apex+amount,4.2,7.5)
	if stage == Stage.PASS: update_manual_set_target()

func request_manual_set(technique: int) -> void:
	if not partner_receiving or stage != Stage.PASS or is_finite(cpu_set.touch_time): return
	manual_set_requested = true
	active_cpu_set_style = technique
	cpu_contact_time = maxf(clock-stage_start,descending_time(pass_origin,pass_motion,cpu_set_contact_height()))
	cpu_contact_point = flight_point(pass_origin,pass_motion,cpu_contact_time)
	var incoming := (pass_origin-cpu_contact_point).slide(Vector3.UP).normalized()
	cpu_stand = Court.clamp_setter(Vector3(cpu_contact_point.x,CPU_HOME.y,cpu_contact_point.z)-incoming*HandPose.CONTACT_FORWARD*receiver.scale.z,ATTACK_FRONT_LIMIT)

func set_requested() -> bool:
	return not partner_receiving or manual_set_requested

func cpu_set_apex() -> float:
	return manual_set_apex if partner_receiving else SET_APEX

func update_manual_set_target() -> void:
	if manual_set_target.is_finite():
		rally_set_target.x = clampf(manual_set_target.x,maxf(-4.35,set_lane_center-APPROACH_RADII[1]),minf(4.35,set_lane_center+APPROACH_RADII[1]))
	cpu_set_launch(cpu_contact_point)
	if is_instance_valid(rally_set_call): rally_set_call.text = "Set height %.1f m" % manual_set_apex

func cpu_set_launch(origin: Vector3) -> Vector3:
	var apex := cpu_set_apex()
	var contact := descending_time(origin,Vector3.UP*sqrt(2.0*Flight.GRAVITY*(apex-origin.y)),RALLY_SET_CONTACT_HEIGHT)
	var floor_time := Flight.landing_time(origin,Vector3.UP*sqrt(2.0*Flight.GRAVITY*(apex-origin.y)))
	var target_depth := Net.NET_Z-RALLY_SET_NET_CLEARANCE
	if partner_receiving and manual_set_target.is_finite():
		target_depth = clampf(manual_set_target.z,minf(target_depth,origin.z+0.35),target_depth)
	var safe_floor := Net.NET_Z-0.16
	rally_set_target.z = minf(target_depth,lerpf(origin.z,safe_floor,contact/floor_time))
	region.position = rally_set_target
	return set_toward_pin(origin,rally_set_target,apex,RALLY_SET_CONTACT_HEIGHT)

func call_rally_set(passer: Vector3) -> void:
	set_lane_center = passer.x
	var candidates: Array[int] = []
	for zone in RALLY_SET_ZONES:
		if absf(rally_zone_x(zone)-passer.x) <= APPROACH_RADII[1]:
			candidates.append(zone)
	if candidates.is_empty():
		candidates.append(clampi(roundi(3.0-passer.x*RALLY_SET_ZONES/9.0),0,RALLY_SET_ZONES-1))
	if candidates.size() > 1: candidates.erase(rally_set_index)
	rally_set_index = candidates.pick_random()
	rally_set_target = Vector3(rally_zone_x(rally_set_index),PIN.y,Net.NET_Z-RALLY_SET_NET_CLEARANCE)
	if partner_receiving: update_manual_set_target()
	else: cpu_set_launch(cpu_contact_point)
	region.show()
	if is_instance_valid(rally_set_call):
		if not partner_receiving: rally_set_call.text = "Set to Zone %d" % ((rally_set_index+1)*10)
		rally_set_call.show()

func tick_demo(delta: float, controls: RefCounted) -> void:
	if stage == Stage.SERVE and not is_finite(serve_demo.contact_clock):
		serve_demo.step(delta)
		if not is_finite(serve_demo.contact_clock): return
		serve_origin = serve_demo.origin
		serve_velocity = serve_demo.velocity
		serve_demo.ball.hide()
		ball.show()
	serve_demo.step(delta)
	if partner_receiving:
		if stage == Stage.SERVE and clock-stage_start >= serve_contact-0.20 and not is_finite(bump.pressed_at):
			queue_set()
		if stage in [Stage.PASS,Stage.SET] and not jump.active:
			var run_target := rally_set_target-Vector3.BACK*1.95
			setter.position = setter.position.move_toward(Vector3(run_target.x,setter.position.y,run_target.z),4.5*delta)
			approach_space_held = true
			trace_input = queued_approach_input(delta)
		step_jump(delta)
		step(delta)
		if stage == Stage.PASS and not manual_set_requested: status.text = "Your set  |  Q, E / I, or Space"
		return
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
