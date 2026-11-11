extends "res://scripts/attack_drill.gd"

signal struck(actor: Node3D, point: Vector3, velocity: Vector3, spin: float)

var enabled := false
var spike_strength := 1.0

func configure_for_match(actor: Node3D, readout: Label) -> void:
	swing_practice = false
	var saved := actor.transform
	configure(actor,readout,true)
	actor.transform = saved
	receiver.hide()
	ball.hide()
	bump.hide()
	ready_range.hide()
	approach_rings.hide()
	region.hide()
	set_ball_audio_muted(true)

func start_set(actor: Node3D, origin: Vector3, velocity: Vector3, target: Vector3, shot: Vector3, age: float, held: bool) -> void:
	setter = actor
	bump.setter = actor
	var saved := actor.transform
	super.reset_feed()
	actor.transform = saved
	stage = Stage.SET
	stage_start = clock-age
	pass_origin = origin
	pass_motion = velocity
	pin_arrival = descending_time(origin,velocity,set_contact_height())
	flight_end = Flight.landing_time(origin,velocity)
	rally_set_target = target
	swing_aim = shot
	approach_set_touched_at = stage_start
	approach_space_held = held
	approach_rings.hide()
	bump.hide()
	region.hide()
	swing_target.hide()
	enabled = true

func approach_hand_height() -> float:
	return 2.22

func approach_reach_height() -> float:
	return approach_hand_height()+(jump.max_height-0.2032)*0.91

func set_contact_height() -> float:
	return clampf(approach_reach_height(),2.70,3.38)

func adaptive_approach_timing() -> bool:
	return true

func tick_attack(delta: float) -> void:
	if not enabled: return
	if stage == Stage.SET: queued_approach_input(delta)
	step_jump(delta)
	clock += delta
	var age := clock-stage_start
	if stage == Stage.SET:
		play_pin_ball(age,maxf(0.0,age-delta),delta)
	elif stage == Stage.HIT and age < SWING_FOLLOW_TIME:
		var follow := 1.0-pow(1.0-clampf(age/0.19,0.0,1.0),2.0)
		pose_bow_draw(delta,1.0-smoothstep(0.19,SWING_FOLLOW_TIME,age),swing_contact,swing_contact_extension,follow)
	elif not jump.active:
		enabled = false

func uses_front_right_lift() -> bool:
	return true

func keeps_strike_palm_presented() -> bool:
	return true

func spike_assist_radius() -> float:
	return 0.19

func attack_arm_turn_rate() -> float:
	return deg_to_rad(1580.0)

func spike_speed_multiplier() -> float:
	return spike_strength

func hit_spike(charge: float, point: Vector3, palm_gap := 0.0) -> void:
	super.hit_spike(charge,point,palm_gap)
	struck.emit(setter,to_global(point),global_basis*pass_motion,spike_topspin_rps)
