extends "res://scripts/blocking_practice.gd"

const DEFENSE_START := Vector3(2.15,0.04,-1.30)
const ZONE_FIVE_TARGETS := [Vector2(-4.2,10.4),Vector2(-3.7,10.9),Vector2(-4.35,10.0)]

var dig: MeshInstance3D
var next_dig_lane := 0
var dig_pressed_at := -INF
var dig_sound_played := false

func load_setup() -> void:
	player_attacks = false

func configure_block(actor: Node3D, readout: Label, build: String) -> void:
	super.configure_block(actor,readout,build)
	receiver.show()
	dig = BumpSetting.new()
	dig.top_level = true
	add_child(dig)
	dig.global_transform = Transform3D.IDENTITY
	dig.configure(actor,bump.clip)
	dig.destination = Vector2(0.0,1.8)
	dig.height = 3.4
	dig.green_start = 0.01
	dig.green_end = 0.50
	dig.green_forearm_allowance = 0.30
	dig.green_hand_allowance = 0.45
	actor.position = DEFENSE_START
	actor.rotation.y = 0.0

func reset_feed() -> void:
	var defender_position: Vector3 = blocker.position
	super.reset_feed()
	blocker.position = defender_position
	stage = Stage.PASS
	approach_space_held = false
	setter.position = Vector3(1.78,0.04,1.82)
	rally_set_target = Vector3(PIN.x,0.065,PIN.z)
	active_cpu_set_style = 2
	cpu_stand = Vector3(0.15,0.04,2.62)
	receiver.position = cpu_stand
	pass_origin = Vector3(-0.75,1.15,0.10)
	var incoming_side := (pass_origin-cpu_stand).slide(Vector3.UP).normalized()
	receiver.rotation.y = atan2(incoming_side.x,incoming_side.z)
	cpu_contact_point = cpu_stand+incoming_side*HandPose.CONTACT_FORWARD*receiver.scale.z
	cpu_contact_point.y = cpu_set_contact_height()
	cpu_contact_time = 0.86
	pass_motion = (cpu_contact_point-pass_origin)/cpu_contact_time+Vector3.UP*Flight.GRAVITY*cpu_contact_time*0.5
	ball.position = pass_origin
	var lane: Vector2 = ZONE_FIVE_TARGETS[next_dig_lane]
	next_dig_lane = (next_dig_lane+1)%ZONE_FIVE_TARGETS.size()
	aim_swing(Vector3(lane.x,Flight.FLOOR,lane.y))
	swing_target.hide()
	approach_rings.hide()
	dig_pressed_at = -INF
	dig_sound_played = false
	if is_instance_valid(dig):
		dig.reset()
		dig.hand_setting = false
		dig.hide()
	status.text = "Left pin to zone 5"

func follow_receive(_time: float) -> void:
	pass

func cpu_set_apex() -> float:
	return set_apex

func play_cpu_set(time: float, delta: float) -> void:
	super.play_cpu_set(time,delta)
	if stage == Stage.SET:
		approach_space_held = true
		approach_set_touched_at = clock
		region.hide()
		swing_target.hide()

func queue_dig(use_hands: bool) -> void:
	if stage not in [Stage.SET,Stage.HIT] or is_finite(dig.touch_time): return
	if stage == Stage.SET and not jump.active: return
	if stage == Stage.HIT and clock-stage_start >= flight_end: return
	if stage == Stage.HIT and is_finite(dig.pressed_at): return
	dig_pressed_at = clock
	dig.hand_setting = use_hands
	dig.quick_hand_receive = use_hands

func aim_dig(point: Vector3) -> void:
	dig.destination = Vector2(clampf(point.x,-5.5,5.5),clampf(point.z,-5.0,3.7))

func defense_move_scale() -> float:
	if stage != Stage.HIT: return 1.0
	var time := clock-stage_start
	if dig.low_save.active and not dig.low_save.finished(time): return 0.0
	return dig.movement_scale(time,flight_end,dig.to_local(ball.global_position))

func tick_block(delta: float) -> void:
	if stage == Stage.SET: queued_approach_input(delta)
	step_jump(delta)
	step(delta)

func play_pin_ball(time: float, previous: float, delta: float) -> void:
	super.play_pin_ball(time,previous,delta)
	if stage == Stage.SET: status.text = "Left pin to zone 5"

func play_spike(time: float, delta: float) -> void:
	if not swing_net_hit.is_empty():
		super.play_spike(time,delta)
		return
	if is_finite(dig_pressed_at) and not is_finite(dig.pressed_at):
		if dig_pressed_at >= stage_start-0.32:
			dig.queue_bump(dig_pressed_at-stage_start)
		dig_pressed_at = -INF
	var path := func(t: float) -> Vector3:
		return to_global(flight_point(pass_origin,pass_motion,minf(t,flight_end)))
	var incoming := global_basis*(pass_motion+Vector3.DOWN*Flight.GRAVITY*time)
	dig.show()
	dig.update_aim()
	dig.update_attempt(time,maxf(0.0,time-delta),flight_end,path,incoming,delta)
	if not is_finite(dig.touch_time):
		super.play_spike(time,delta)
		if stage == Stage.HIT and time >= flight_end: status.text = "Spike down"
		return
	if not dig_sound_played:
		dig_sound_played = true
		if not ball_audio_muted: spike_audio.play()
	if time < SWING_FOLLOW_TIME:
		var follow := 1.0-pow(1.0-clampf(time/0.19,0.0,1.0),2.0)
		pose_bow_draw(delta,1.0-smoothstep(0.19,SWING_FOLLOW_TIME,time),swing_contact,swing_contact_extension,follow)
	status.text = BallTimingRing.result_text(dig.grade,"dig")
	if dig.hand_setting and not is_finite(dig.release_time):
		ball.global_position = dig.touch.lerp(dig.platform_center(),smoothstep(0.0,0.05,time-dig.touch_time))
		return
	var launch: float = dig.release_time if dig.hand_setting else dig.touch_time
	var origin: Vector3 = dig.release_point if dig.hand_setting else dig.touch
	var age := time-launch
	if not dig.net_hit.is_empty() and age >= dig.net_hit.time:
		ball.global_position = Net.after_hit(dig.net_hit,age)
	else:
		ball.global_position = flight_point(origin,dig.outgoing,minf(age,dig.floor_time))
	if age >= dig.floor_time and age-delta < dig.floor_time: play_floor_sound()
	if age >= dig.floor_time+0.55 and not jump.active: reset_feed()
