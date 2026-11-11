extends "res://scripts/serve_bump_set_spike.gd"

var passer: Node3D
var near_teammate: Node3D
var far_partner: Node3D
const TEAMMATE_READY := Vector3(2.35,0.04,10.25)
var rally_active := false
var incoming_cue := 0.0
var serve_source: Node3D
var receive_with_hands := false
var rally_number := 0

func configure_team(readout: Label, build: String) -> void:
	passer = make_demo_player("OpponentPasser",Color("d9874e"))
	configure(passer,readout,true,build)
	far_partner = receiver
	near_teammate = make_demo_player("YourTeammate",Color("2c8fe5"))
	reset_feed()

func reset_feed() -> void:
	if not is_instance_valid(passer): return
	setter = passer
	if is_instance_valid(far_partner): receiver = far_partner
	super.reset_feed()
	rally_active = false
	cpu_second_ball_attack = false
	player_second_ball_attack = false
	manual_set_requested = false
	approach_space_held = false
	carried_jump_lift = 0.0
	swing_to_set_pose.clear()
	passer.position = Vector3(2.1,0.04,-2.85)
	receiver.position = Vector3(-2.1,0.04,-2.85)
	if is_instance_valid(near_teammate): near_teammate.position = TEAMMATE_READY
	for actor in [passer,receiver,near_teammate]:
		if not is_instance_valid(actor): continue
		actor.rotation.y = PI if actor == near_teammate else 0.0
		actor.play_action("idle",0.0)
		actor.animator.advance(0.0)
	ball.hide()
	bump.hide()
	region.hide()
	approach_rings.hide()
	status.text = "Space to serve"

func receive_serve(world_origin: Vector3, world_velocity: Vector3, source: Node3D = null) -> void:
	serve_source = source
	rally_number += 1
	serve_origin = to_local(world_origin)
	serve_velocity = global_basis.inverse()*world_velocity
	incoming_cue = descending_receive_time(1.13)
	receive_with_hands = rally_number%3 == 2
	if receive_with_hands: incoming_cue = descending_receive_time(2.05)
	var catch_point := serve_flight_point(incoming_cue).slide(Vector3.UP)
	if catch_point.distance_squared_to(receiver.position.slide(Vector3.UP)) < catch_point.distance_squared_to(passer.position.slide(Vector3.UP)):
		var other := receiver
		receiver = passer
		passer = other
	setter = passer
	bump.setter = passer
	cpu_set.setter = receiver
	cpu_feet = Footwork.new(receiver)
	far_partner = receiver
	cpu_set_style = (rally_number-1)%4
	cpu_commits_to_spike = randf() < 0.35
	bump.destination = Vector2(randf_range(-1.35,1.35),randf_range(1.7,3.0))
	bump.height = [4.8,6.25,5.45,5.85][(rally_number-1)%4]
	teammate_set_apex = [4.65,5.85,5.25,6.35][(rally_number-1)%4]
	bump.green_forearm_allowance = 0.42
	bump.green_hand_allowance = 0.42
	rally_active = true
	ball.position = serve_origin
	ball.show()
	status.text = "Opponents receiving"

func serve_flight_point(time: float) -> Vector3:
	var point := super.serve_flight_point(time)
	if is_instance_valid(serve_source):
		var drift: Vector3 = serve_source.serve_curve_offset(time,serve_source.planned_duration)
		point += global_basis.inverse()*serve_source.global_basis*drift
	return point

func descending_receive_time(height: float) -> float:
	if not is_instance_valid(serve_source): return descending_time(serve_origin,serve_velocity,height)
	var last: float = serve_source.planned_duration
	for sample in range(1,17):
		var earlier: float = serve_source.planned_duration*(1.0-sample/16.0)
		if serve_flight_point(earlier).y >= height:
			for iteration in 12:
				var middle := (earlier+last)*0.5
				if serve_flight_point(middle).y >= height: earlier = middle
				else: last = middle
			return (earlier+last)*0.5
		last = earlier
	return descending_time(serve_origin,serve_velocity,height)

func receive_cue_time() -> float:
	return incoming_cue

func cpu_set_target_depth() -> float:
	return super.cpu_set_target_depth()-0.60

func call_rally_set(_point: Vector3) -> void:
	var lane: float = [-3.3,0.0,3.3][rally_number%3]
	rally_set_target = Vector3(lane,PIN.y,cpu_set_target_depth())

func tick_opponents(delta: float) -> void:
	if not rally_active: return
	trace_input = Vector2.ZERO
	if stage == Stage.SERVE:
		var time := clock-stage_start
		var point := serve_flight_point(incoming_cue)
		var incoming := (serve_origin-point).slide(Vector3.UP).normalized()
		var offset := 0.40 if receive_with_hands else 0.50
		if not bump.low_save.active:
			move_opponent(passer,point-incoming*offset,5.1,delta)
			face_actor(passer,incoming,delta)
		if time >= incoming_cue-0.22 and not is_finite(bump.pressed_at):
			if receive_with_hands: queue_hand_receive()
			else: queue_set()
	if stage == Stage.PASS:
		try_second_ball_attack()
	if cpu_second_ball_attack:
		if not cpu_commits_to_spike and stage == Stage.SET and is_finite(swing_started):
			if clock-swing_started >= 0.14 or clock >= approach_expected_hit_at-0.055:
				request_manual_set(0)
		if cpu_second_ball_attack:
			if stage == Stage.SET and approach_jump_queued: time_approach_plant(delta)
			step_jump(delta)
			step(delta)
			return
	if not jump.active and (stage == Stage.SET or (stage == Stage.PASS and clock-stage_start > 0.22)):
		var target := rally_set_target-Vector3.BACK*1.45
		move_opponent(passer,target,5.2,delta)
		face_actor(passer,Vector3.BACK,delta)
	if stage == Stage.SET and setter == passer and not jump.active:
		approach_space_held = true
		queued_approach_input(delta)
	step_jump(delta)
	var previous := stage
	step(delta)
	blend_swing_to_set()
	if previous == Stage.PASS and stage == Stage.SET:
		setter = passer
		approach_pressed_at = -INF
		approach_released_at = INF
		approach_jump_queued = false
		aim_swing(Vector3(randf_range(-3.7,3.7),Flight.FLOOR,randf_range(7.5,12.2)))
		status.text = "Opponents attacking"
	if previous == Stage.SERVE and stage == Stage.PASS: status.text = "Opponents setting"

func move_opponent(actor: Node3D, point: Vector3, speed: float, delta: float) -> void:
	var travel := (point-actor.position).slide(Vector3.UP)
	if travel.length() > 0.14:
		actor.position += travel.limit_length(speed*delta)
		actor.play_action("run")
	else:
		actor.play_action("idle")
	actor.animator.advance(delta)

func face_actor(actor: Node3D, direction: Vector3, delta: float) -> void:
	if not direction.is_zero_approx():
		actor.rotation.y = rotate_toward(actor.rotation.y,atan2(direction.x,direction.z),delta*12.0)
