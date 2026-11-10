extends "res://scripts/setting_drill.gd"

signal shot_sequence_changed(playing: bool)

const Court = preload("res://scripts/preview_court.gd")
const SpikeArm = preload("res://scripts/spike_arm_swing.gd")
const HandPose = preload("res://scripts/hand_setting_pose.gd")
const Footwork = preload("res://scripts/directional_footwork.gd")
const PIN := Vector3(3.55,0.065,3.35)
const ATTACK_FRONT_LIMIT := 3.55
const APPROACH_MIN_PLANT_TIME := 0.20
const APPROACH_SET_TURN_RATE := 3.1
const APPROACH_START := Vector3(3.10,0.04,-0.05)
const APPROACH_RADII := [1.15,1.8,2.5]
const RECEIVE_START := Vector3(3.05,0.04,-3.10)
const ATTACK_SERVE_SOURCE := Vector3(3.05,2.8,8.5)
const CPU_HOME := Vector3(-0.55,0.04,3.10)
const PIN_HEIGHT := 2.75
const SET_APEX := 5.0
const SET_TOPSPIN_RPS := 2.2
const LOW_BOW_FRAME := 1.0/30.0

enum Stage { SERVE, PASS, SET, HIT, MISS, SHANK, APPROACH_RETURN }
const SWING_CHARGE_TIME := 0.65
const SWING_REACH := 1.55
const SWING_CONTACT_HEIGHT := 2.22
const PALM_RADIUS := 0.065
const ASSISTED_PALM_RADIUS := 0.24
const SWING_FOLLOW_TIME := 0.49
const DEFAULT_BOUNCINESS := 2.25
const DEFAULT_BACKSWING_BEND := 85.0
const DEFAULT_BACKSWING_REACH := 0.48
const SEQUENCE_SET_X := [3.55,0.0,-3.55]
const SEQUENCE_SHOT_X := [
	[3.55,0.0,-3.55],
	[2.0,0.0,-3.55],
	[-3.55,0.0,3.55],
]
const SHOT_AIM_HALF_WIDTH := 7.5
const SHOT_AIM_NEAR := 4.3
const SHOT_AIM_FAR := 16.0
var stage := Stage.SERVE
var swing_practice := true
var approach_practice := false
var takeoff_yaw := 0.0
var approach_jump_queued := false
var approach_space_held := false
var approach_intercept := Vector3.INF
var approach_start := APPROACH_START
var approach_set_target := PIN
var approach_set_apex := SET_APEX
var approach_setup_drag := ""
var approach_rings: Node3D
var approach_pressed_at := -INF
var approach_released_at := INF
var approach_set_touched_at := INF
var approach_expected_hit_at := INF
var approach_run_speed := 0.0
var shot_sequence_index := -1
var manual_shot_aim := Vector3.ZERO
var practice_takeoff := PIN+Vector3(-0.70,RECEIVE_START.y-PIN.y,-0.98)
var practice_set_target := PIN
var practice_setup_path := "user://attack_practice.cfg"
var torso_rotation_scale := 2.0
var leg_kickback_scale := 2.0
var leg_rotation_scale := 1.0
var air_turn_speed := 240.0
var draw_delay := SpikeArm.DEFAULT_DRAW_DELAY
var elbow_clearance := SpikeArm.DEFAULT_ELBOW_CLEARANCE
var backswing_bend := DEFAULT_BACKSWING_BEND
var backswing_reach := DEFAULT_BACKSWING_REACH
var stage_start := 0.0
var serve_target: Vector3
var pass_origin: Vector3
var pass_motion: Vector3
var cpu_contact_time := 0.0
var cpu_contact_point: Vector3
var cpu_stand: Vector3
var cpu_set: MeshInstance3D
var cpu_feet: RefCounted
var pin_arrival := 0.0
var flight_end := 0.0
var swing_started := -INF
var swing_charge_started := -INF
var swing_released := -INF
var swing_drive_started := -INF
var swing_drive_duration := 0.15
var previous_palm := Vector3.INF
var swing_hand_speed := 0.0
var swing_impact_speed := 0.0
var swing_aim := Vector3(PIN.x,Flight.FLOOR,9.5)
var swing_contact_aim: Vector3
var swing_finish_pose: Array[Transform3D] = []
var approach_arm_transition: Array[Transform3D] = []
var swing_palm_roll := 0.0
var swing_contact: Vector3
var swing_contact_extension := 1.0
var swing_power := 0.0
var spike_topspin_rps := 0.0
var ball_bounciness := DEFAULT_BOUNCINESS
var spike_bounce_speed := 0.0
var swing_net_hit := {}
var dynamic_net: Node3D
var net_audio: AudioStreamPlayer
var spike_audio: AudioStreamPlayer
var floor_audio: AudioStreamPlayer
var ball_audio_muted := false
var net_sound_played := false
var mute_net := false
var swing_target: MeshInstance3D

func _ready() -> void:
	dynamic_net = get_parent().get_node_or_null("VolleyballCourt/DynamicNet")
	net_audio = Net.contact_sound()
	add_child(net_audio)
	spike_audio = create_ball_sound(preload("res://assets/audio/spike_smack.wav"),-6.0)
	floor_audio = create_ball_sound(preload("res://assets/audio/ball_floor.wav"),-9.0)
	load_practice_target()
	build_approach_rings()

func build_approach_rings() -> void:
	approach_rings = Node3D.new()
	add_child(approach_rings)
	approach_rings.hide()
	for i in APPROACH_RADII.size():
		var radius: float = APPROACH_RADII[i]
		var mesh := TorusMesh.new()
		mesh.inner_radius = radius-0.023
		mesh.outer_radius = radius
		mesh.rings = 48
		mesh.ring_segments = 8
		var ring := MeshInstance3D.new()
		ring.mesh = mesh
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color("64edba") if i == 0 else Color("8ba1bd")
		ring.material_override = material
		approach_rings.add_child(ring)

func place_approach_setup(point: Vector3, place_set: bool, restart := true) -> void:
	var position := Court.clamp_setter(Vector3(point.x,0.04,point.z),ATTACK_FRONT_LIMIT)
	if place_set:
		approach_set_target = Vector3(position.x,PIN.y,position.z)
		region.position = approach_set_target
		region.show()
	else:
		approach_start = position
		setter.position = position
		approach_rings.position = Vector3(position.x,0.061,position.z)
	if restart: reset_feed()

func create_ball_sound(stream: AudioStream, volume: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume
	add_child(player)
	return player

func set_ball_audio_muted(muted: bool) -> void:
	ball_audio_muted = muted
	if muted:
		spike_audio.stop()
		floor_audio.stop()
		net_audio.stop()

func play_floor_sound() -> void:
	if not ball_audio_muted: floor_audio.play()

func _exit_tree() -> void:
	show_attack_net({},0.0)
	super._exit_tree()

func show_attack_net(hit: Dictionary, elapsed: float) -> void:
	if is_instance_valid(dynamic_net): dynamic_net.sample(hit,elapsed)
	var squeeze := Net.squeeze(hit,elapsed)
	if is_instance_valid(ball):
		ball.scale = Vector3(1.0+0.04*squeeze,1.0+0.04*squeeze,1.0-0.12*squeeze)
	if hit.is_empty() or elapsed < float(hit.time):
		if net_sound_played and is_instance_valid(net_audio): net_audio.stop()
		net_sound_played = false
	elif not mute_net and not net_sound_played and is_instance_valid(net_audio):
		net_sound_played = true
		if not ball_audio_muted: net_audio.play()

func load_practice_target() -> void:
	var config := ConfigFile.new()
	if config.load(practice_setup_path) != OK: return
	var point: Variant = config.get_value("practice","set_target",PIN)
	if point is Vector3 and point.is_finite():
		practice_set_target = clamp_practice_target(point)

func move_practice_target(point: Vector3) -> void:
	practice_set_target = clamp_practice_target(point)
	var config := ConfigFile.new()
	config.set_value("practice","set_target",practice_set_target)
	var error := config.save(practice_setup_path)
	if error != OK: push_warning("Could not save the swing practice target: %s" % error_string(error))

func clamp_practice_target(point: Vector3) -> Vector3:
	return Vector3(clampf(point.x,-4.5,4.5),PIN.y,clampf(point.z,-5.0,4.0))

func reset_feed() -> void:
	if trace.feed > 0:
		trace.write("feed_end",clock,{"result":status.text,"closest_check":trace.closest_check},true)
	if shot_sequence_index >= 0 and stage in [Stage.HIT,Stage.MISS]:
		shot_sequence_index += 1
		if shot_sequence_index == 9: stop_shot_sequence()
	clock = 0.0
	stage_start = 0.0
	stage = Stage.SERVE
	if cpu_set == null:
		cpu_set = BumpSetting.new()
		add_child(cpu_set)
		cpu_set.configure(receiver,bump.clip)
		cpu_set.hand_setting = true
		cpu_set.hide()
		cpu_feet = Footwork.new(receiver)
	receiver.animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	receiver.play_action("idle")
	receiver.position = CPU_HOME
	receiver.rotation.y = PI
	cpu_set.reset()
	jump.active = false
	approach_jump_queued = false
	approach_intercept = Vector3.INF
	approach_setup_drag = ""
	approach_rings.visible = approach_practice
	approach_pressed_at = -INF
	approach_released_at = INF
	approach_set_touched_at = INF
	approach_expected_hit_at = INF
	approach_run_speed = 0.0
	jump.front_limit = ATTACK_FRONT_LIMIT
	setter.position = RECEIVE_START
	setter.rotation.y = 0.0
	bump.reset()
	bump.green_start = 0.01
	bump.green_end = 0.60
	bump.green_forearm_allowance = 0.30
	bump.green_hand_allowance = 0.15
	bump.show()
	bump.hand_setting = false
	bump.quick_hand_receive = false
	bump.catch_only = false
	bump.destination = Vector2(-0.55,3.0)
	bump.height = 3.8
	serve_target = RECEIVE_START+Vector3(0.0,1.13,-0.17)
	serve_velocity = (serve_target-ATTACK_SERVE_SOURCE)/SERVE_TIME+Vector3.UP*Flight.GRAVITY*SERVE_TIME*0.5
	ball.position = ATTACK_SERVE_SOURCE
	ball.rotation = Vector3.ZERO
	region.position = PIN
	region.hide()
	swing_started = -INF
	swing_charge_started = -INF
	swing_released = -INF
	swing_drive_started = -INF
	previous_palm = Vector3.INF
	swing_net_hit.clear()
	show_attack_net({},0.0)
	swing_finish_pose.clear()
	approach_arm_transition.clear()
	swing_palm_roll = 0.0
	if swing_target == null:
		swing_target = region.duplicate()
		add_child(swing_target)
	swing_target.hide()
	timing_cue.hide()
	if swing_practice:
		start_swing_practice()
		return
	if approach_practice:
		stage = Stage.PASS
		bump.hide()
		setter.position = approach_start
		region.position = approach_set_target
		pass_origin = Vector3(-2.0,1.25,-1.0)
		face_receiver(pass_origin-receiver.position,PI)
		cpu_stand = CPU_HOME
		var incoming := (pass_origin-cpu_stand).slide(Vector3.UP).normalized()
		cpu_contact_point = cpu_stand+incoming*HandPose.CONTACT_FORWARD*receiver.scale.z
		cpu_contact_point.y += HandPose.CONTACT_HEIGHT*receiver.scale.y
		cpu_contact_time = 0.90
		pass_motion = (cpu_contact_point-pass_origin)/cpu_contact_time+Vector3.UP*Flight.GRAVITY*cpu_contact_time*0.5
		ball.position = pass_origin
		region.show()
		aim_swing(swing_aim)
		status.text = "Setter receiving pass"
		trace.begin_feed({"mode":"approach_practice","source":pass_origin,"velocity":pass_motion,"pin":approach_set_target,"start":setter.position})
		return
	status.text = "Receive  |  Q forearms, I / E hands"
	trace.begin_feed({"mode":"attacking","source":ATTACK_SERVE_SOURCE,"serve_velocity":serve_velocity,"pin":PIN})

func toggle_shot_sequence() -> void:
	if shot_sequence_index >= 0:
		stop_shot_sequence()
	else:
		manual_shot_aim = swing_aim
		shot_sequence_index = 0
		shot_sequence_changed.emit(true)
	stage = Stage.SET
	reset_feed()

func stop_shot_sequence() -> void:
	if shot_sequence_index < 0: return
	shot_sequence_index = -1
	aim_swing(manual_shot_aim)
	shot_sequence_changed.emit(false)

func set_swing_practice(enabled: bool, approach := false) -> void:
	stop_shot_sequence()
	approach_space_held = false
	swing_practice = enabled
	approach_practice = approach
	reset_feed()

func start_swing_practice() -> void:
	stage = Stage.SET
	bump.hide()
	var pin := PIN
	var set_target := practice_set_target
	var takeoff := practice_takeoff
	if shot_sequence_index >= 0:
		var lane := floori(shot_sequence_index/3.0)
		pin.x = SEQUENCE_SET_X[lane]
		set_target = pin
		takeoff = pin+Vector3(-0.40,RECEIVE_START.y-PIN.y,-0.83)
		aim_swing(Vector3(SEQUENCE_SHOT_X[lane][shot_sequence_index%3],Flight.FLOOR,9.5))
	setter.position = takeoff
	region.position = set_target
	receiver.rotation.y = atan2(pin.x-CPU_HOME.x,pin.z-CPU_HOME.z)
	var source := receiver.to_global(Vector3(0.0,HandPose.CONTACT_HEIGHT,HandPose.CONTACT_FORWARD))
	var velocity := set_toward_pin(source,pin)
	var lead := 0.72
	var preroll := descending_time(source,velocity,PIN_HEIGHT)-lead
	pass_origin = flight_point(source,velocity,preroll)
	pass_motion = velocity+Vector3.DOWN*Flight.GRAVITY*preroll+(set_target-pin)/lead
	jump.begin(setter,Vector2(0.0,0.65))
	for frame in range(16): jump.step(setter,1.0/60.0,Vector2.ZERO)
	jump.release()
	setter.rotation.y = incoming_set_heading()
	pin_arrival = lead
	flight_end = Flight.landing_time(pass_origin,pass_motion)
	ball.position = pass_origin
	region.show()
	aim_swing(swing_aim)
	swing_started = clock
	status.text = ""
	trace.begin_feed({"mode":"swing_practice","source":pass_origin,"velocity":pass_motion,"pin":set_target,"takeoff":takeoff})

func set_key() -> int:
	return KEY_Q if stage == Stage.SERVE else KEY_NONE

func can_aim_set() -> bool:
	return stage == Stage.SERVE and not is_finite(bump.touch_time)

func set_pass_aim(point: Vector3) -> void:
	# The landing marker is beyond the setter’s overhead interception point.
	bump.destination = Vector2(clampf(point.x,-3.0,3.0),clampf(point.z,0.0,4.5))

func queue_hand_receive() -> void:
	if stage != Stage.SERVE or is_finite(bump.touch_time): return
	if is_finite(bump.pressed_at):
		if bump.hand_setting or is_finite(bump.pose_started_at): return
		bump.reset()
	bump.hand_setting = true
	bump.quick_hand_receive = true
	queue_set()

func receive_cue_time() -> float:
	if not bump.hand_setting: return SERVE_TIME
	var height := RECEIVE_START.y+HandPose.CONTACT_HEIGHT*setter.scale.y+HandPose.CONTACT_RADIUS
	var latest := descending_time(ATTACK_SERVE_SOURCE,serve_velocity,height)
	if not jump.active: return latest
	var earliest := descending_time(ATTACK_SERVE_SOURCE,serve_velocity,height+jump.height)
	if earliest < 0.0: return latest
	var jump_start := clock-stage_start-jump.elapsed
	for iteration in range(10):
		var midpoint := (earliest+latest)*0.5
		var progress := clampf((midpoint-jump_start-jump.load_duration())/jump.air_time,0.0,1.0)
		var hand_height := height+4.0*jump.height*progress*(1.0-progress)
		if flight_point(ATTACK_SERVE_SOURCE,serve_velocity,midpoint).y > hand_height:
			earliest = midpoint
		else:
			latest = midpoint
	return latest

func incoming_set_heading() -> float:
	var incoming := pass_motion.slide(Vector3.UP)
	return setter.rotation.y if incoming.is_zero_approx() else atan2(-incoming.x,-incoming.z)

func court_facing_weight() -> float:
	if stage == Stage.SET and jump.active: return 0.0
	return 0.5 if stage == Stage.PASS or stage == Stage.SET else 0.0

func aim_swing(point: Vector3) -> void:
	swing_aim = Vector3(clampf(point.x,-SHOT_AIM_HALF_WIDTH,SHOT_AIM_HALF_WIDTH),Flight.FLOOR,clampf(point.z,SHOT_AIM_NEAR,SHOT_AIM_FAR))
	swing_target.position = Vector3(swing_aim.x,0.065,swing_aim.z)
	swing_target.show()

func swing_input(pressed: bool) -> void:
	if swing_practice or approach_practice or stage != Stage.SET: return
	if not pressed:
		if is_finite(swing_started) and not is_finite(swing_released): swing_released = clock
		return
	if is_finite(swing_started) and not is_finite(swing_released): return
	start_attack_swing()

func capture_approach_arm_pose() -> void:
	var rig: Skeleton3D = setter.skeleton
	approach_arm_transition.clear()
	for bone in rig.get_bone_count(): approach_arm_transition.append(rig.get_bone_pose(bone))

func start_attack_swing() -> void:
	if approach_practice: capture_approach_arm_pose()
	swing_started = clock
	swing_charge_started = -INF
	swing_released = -INF
	swing_drive_started = -INF
	previous_palm = Vector3.INF
	status.text = "Swing queued"
	trace.write("swing_start",clock,{"player":setter.position,"aim":swing_aim},true)

func swing_charge() -> float:
	if approach_practice:
		return approach_hold_charge(approach_expected_hit_at)
	return clampf((minf(clock,swing_released if is_finite(swing_released) else clock)-swing_charge_started)/(0.48 if swing_practice else SWING_CHARGE_TIME),0.0,1.0)

func approach_hold_charge(contact_clock: float) -> float:
	if not is_finite(approach_pressed_at): return 0.0
	if not is_finite(contact_clock) or not is_finite(approach_set_touched_at): return 0.15
	var window := maxf(0.001,contact_clock-approach_set_touched_at)
	var hold_start := maxf(approach_pressed_at,approach_set_touched_at)
	var hold_end := minf(minf(clock,contact_clock),approach_released_at)
	return lerpf(0.15,1.0,clampf((hold_end-hold_start)/window,0.0,1.0))

func queue_set() -> void:
	if stage != Stage.SERVE: return
	bump.queue_bump(clock-stage_start)
	trace.write("attack_input",clock,{"stage":stage,"technique":"hands" if bump.hand_setting else "forearms","aim":bump.destination,"height":bump.height,"position":setter.position,"ball":ball.position},true)

func setter_is_diving() -> bool:
	if not bump.low_save.active: return false
	if stage == Stage.SERVE: return not bump.low_save.finished(clock-stage_start)
	return stage == Stage.PASS and not bump.low_save.finished(bump.touch_time+clock-stage_start)

func queue_jump(direction: Vector2) -> void:
	if approach_practice:
		approach_space_held = true
		try_queue_approach(true)
		return
	if jump.active or setter_is_diving() or stage in [Stage.HIT,Stage.SHANK]: return
	begin_attack_jump(direction)

func try_queue_approach(log_rejection: bool) -> void:
	if stage not in [Stage.PASS,Stage.SET] or is_finite(approach_pressed_at): return
	var intercept := find_approach_intercept()
	if not intercept.is_finite():
		if log_rejection:
			status.text = unavailable_approach_status()
			trace.write("approach_rejected",clock,{"target":approach_set_target,"range":APPROACH_RADII[0]+REGION_RADIUS,"reason":status.text},true)
		return
	approach_pressed_at = clock
	approach_jump_queued = true
	trace.write("approach_press",clock,{"stage":stage,"position":setter.position,"intercept":intercept,"two_step":true},true)

func release_approach_jump() -> void:
	approach_space_held = false
	if is_finite(approach_pressed_at) and not is_finite(approach_released_at):
		approach_released_at = clock
		trace.write("approach_release",clock,{"held":clock-approach_pressed_at},true)

func unavailable_approach_status() -> String:
	return "Too late to plant" if find_approach_intercept(false).is_finite() else "Set outside two-step reach"

func find_approach_intercept(respect_timing := true) -> Vector3:
	var origin := pass_origin if stage == Stage.SET else cpu_contact_point
	var velocity := pass_motion if stage == Stage.SET else set_toward_pin(origin,approach_set_target,approach_set_apex)
	var apex := origin.y+velocity.y*velocity.y/(2.0*Flight.GRAVITY)
	var earliest := descending_time(origin,velocity,minf(apex-0.15,3.59))
	var latest := descending_time(origin,velocity,3.10)
	if respect_timing and stage == Stage.SET:
		earliest = maxf(earliest,clock-stage_start+APPROACH_MIN_PLANT_TIME+0.10)
	if earliest > latest: return Vector3.INF
	for sample in 7:
		var point := flight_point(origin,velocity,lerpf(earliest,latest,sample/6.0))
		if (point-setter.position).slide(Vector3.UP).length() <= APPROACH_RADII[0]+REGION_RADIUS: return point
	return Vector3.INF

func queued_approach_input(delta: float) -> Vector2:
	approach_run_speed = 0.0
	if stage == Stage.APPROACH_RETURN:
		var offset := (approach_start-setter.position).slide(Vector3.UP)
		approach_run_speed = minf(3.2,offset.length()/delta)
		return Vector2(-offset.x,offset.z).normalized()
	if approach_space_held and not approach_jump_queued and not jump.active: try_queue_approach(false)
	if not approach_jump_queued:
		return Vector2.ZERO if jump.active else trace_input
	if stage == Stage.SET: time_two_step_plant(delta)
	return Vector2.ZERO

func time_two_step_plant(delta: float) -> void:
	var ball_target := find_approach_intercept()
	if not ball_target.is_finite(): return
	var toward := (ball_target-setter.position).slide(Vector3.UP)
	var distance_weight := smoothstep(0.15,APPROACH_RADII[0],toward.length())
	var set_apex := pass_origin.y+pass_motion.y*pass_motion.y/(2.0*Flight.GRAVITY)
	var height_weight := smoothstep(4.2,5.0,set_apex)
	var jump_height := jump.max_height*lerpf(0.94,1.0,maxf(distance_weight,height_weight))-0.2032
	var air_time := jump.flight_duration(jump_height,true)
	var contact_height := minf(ball_target.y,2.32+jump_height*0.91)
	var contact_at := descending_time(pass_origin,pass_motion,contact_height)
	var time_before_lift := contact_at-(clock-stage_start)-air_time*0.54
	var plant_time := lerpf(0.30,jump.APPROACH_LOAD_TIME,distance_weight)+0.15
	if time_before_lift > plant_time+delta: return
	approach_jump_queued = false
	approach_expected_hit_at = stage_start+contact_at
	approach_intercept = flight_point(pass_origin,pass_motion,contact_at)
	var direction := (approach_intercept-setter.position).slide(Vector3.UP).normalized()
	begin_attack_jump(Vector2(-direction.x,direction.z),clampf(time_before_lift,APPROACH_MIN_PLANT_TIME,plant_time),jump_height)

func begin_attack_jump(direction: Vector2, plant_time := 0.36, jump_height := 0.0) -> void:
	takeoff_yaw = setter.rotation.y
	var ball_target := Vector3.INF
	if approach_practice:
		ball_target = approach_intercept
	jump.begin(setter,direction,ball_target,plant_time,jump_height)
	trace.write("jump",clock,{"position":setter.position,"direction":jump.heading,"plant_time":jump.load_duration(),"assisted_height":jump_height},true)

func step_jump(delta: float) -> void:
	jump.load_bend_extra = deg_to_rad(backswing_bend)*0.36 if approach_practice else 0.0
	jump.load_arm_extra = backswing_reach*0.85 if approach_practice else 0.0
	if approach_practice and jump.active and jump.elapsed < jump.load_duration():
		var yaw := atan2(jump.heading.x,jump.heading.z)
		setter.rotation.y = rotate_toward(setter.rotation.y,yaw,delta*12.0)
		takeoff_yaw = setter.rotation.y
	super.step_jump(delta)

func setter_movement_scale() -> float:
	if stage == Stage.SERVE:
		return bump.movement_scale(clock-stage_start,receive_cue_time(),ball.position)
	return 1.0

func step(delta: float) -> void:
	if approach_practice:
		approach_rings.position = Vector3(setter.position.x,0.061,setter.position.z)
	clock += delta
	var time := clock-stage_start
	var previous := maxf(0.0,time-delta)
	restore_torso_lean(receiver)
	receiver.animator.advance(delta)
	apply_torso_lean(receiver)
	match stage:
		Stage.SERVE: play_serve(time,previous,delta)
		Stage.PASS:
			if not approach_practice: follow_receive(time)
			play_cpu_set(time,delta)
		Stage.SHANK:
			follow_receive(time)
			play_shank(time,previous)
		Stage.SET:
			if approach_practice: face_receiver(approach_set_target-receiver.position,delta*APPROACH_SET_TURN_RATE)
			if not swing_practice:
				cpu_set.update_hand_push(cpu_set.release_time+time,cpu_set.release_time+time-cpu_set.touch_time)
			play_pin_ball(time,previous,delta)
		Stage.HIT: play_spike(time,delta)
		Stage.MISS:
			if time >= (0.26 if swing_practice else 0.85) and (not approach_practice or not jump.active): finish_attack_rep()
		Stage.APPROACH_RETURN:
			if setter.position.distance_to(approach_start) < 0.04: reset_feed()
	if stage == Stage.SERVE or stage == Stage.SET: trace.check_contact(bump.contact_check)
	if clock >= trace.next_sample: trace.sample(clock,trace_snapshot(clock-stage_start))

func trace_snapshot(time: float) -> Dictionary:
	var velocity := Vector3.ZERO
	match stage:
		Stage.SERVE: velocity = serve_velocity+Vector3.DOWN*Flight.GRAVITY*time
		Stage.PASS,Stage.SET,Stage.HIT,Stage.SHANK: velocity = pass_motion+Vector3.DOWN*Flight.GRAVITY*time
	var platform: Vector3 = bump.platform_center()
	return {
		"stage":stage,"result":status.text,"ball_position":ball.position,"ball_velocity":velocity,
		"player_position":setter.position,"cpu_position":receiver.position,
		"ball_to_player":ball.position.distance_to(setter.position),
		"ball_to_cpu":ball.position.distance_to(receiver.position),
		"ball_to_platform":ball.position.distance_to(platform),
		"contact_check":bump.contact_check,"jumping":jump.active,
		"reach":bump.reach,"reach_step":bump.reach_step,"rear_setup":bump.rear_setup,"reach_progress":bump.reach_progress,
	}

func play_serve(time: float, previous: float, delta: float) -> void:
	var path := func(t): return flight_point(ATTACK_SERVE_SOURCE,serve_velocity,t)
	var end := Flight.landing_time(ATTACK_SERVE_SOURCE,serve_velocity)
	ball.position = path.call(minf(time,end))
	var cue := receive_cue_time()
	timing_cue.update_timing(time,cue,bump.green_start,bump.green_end)
	bump.update_aim()
	bump.update_attempt(time,previous,end,path,serve_velocity+Vector3.DOWN*Flight.GRAVITY*time,delta,cue)
	if is_finite(bump.touch_time):
		if bump.hand_setting and not is_finite(bump.release_time):
			ball.position = bump.touch.lerp(bump.platform_center(),smoothstep(0.0,0.05,time-bump.touch_time))
			return
		pass_origin = bump.release_point if bump.hand_setting else bump.touch
		pass_motion = bump.outgoing
		var head_height := CPU_HOME.y+HandPose.CONTACT_HEIGHT*receiver.scale.y
		cpu_contact_time = descending_time(pass_origin,pass_motion,head_height)
		if cpu_contact_time <= 0.0:
			shank("Pass was too low to set")
			return
		cpu_contact_point = flight_point(pass_origin,pass_motion,cpu_contact_time)
		if cpu_contact_point.z >= 3.75 or (not bump.net_hit.is_empty() and bump.net_hit.time < cpu_contact_time):
			shank("Pass went past the setter")
			return
		bump.hide()
		var incoming := (pass_origin-cpu_contact_point).slide(Vector3.UP).normalized()
		cpu_stand = Court.clamp_setter(Vector3(cpu_contact_point.x,CPU_HOME.y,cpu_contact_point.z)-incoming*HandPose.CONTACT_FORWARD*receiver.scale.z,ATTACK_FRONT_LIMIT)
		stage = Stage.PASS
		stage_start = clock
		status.text = "CPU setting to the pin"
		trace.write("player_pass",clock,{"point":pass_origin,"velocity":pass_motion,"cpu_contact":cpu_contact_point,
			"grade":bump.grade,"reach":bump.reach,"contact":bump.contact_check},true)
	elif time >= end:
		play_floor_sound()
		miss("Serve missed")

func follow_receive(time: float) -> void:
	if bump.hand_setting: return
	var receive_time: float = bump.touch_time+time
	if setter_is_diving():
		bump.low_save.sample(setter,receive_time,bump.touch_time)
	elif not bump.low_save.active:
		bump.follow_forearm(receive_time,serve_velocity+Vector3.DOWN*Flight.GRAVITY*bump.touch_time)

func shank(message: String, elapsed := 0.0) -> void:
	trace.check_contact(bump.contact_check)
	miss(message)
	stage = Stage.SHANK
	stage_start = clock-elapsed
	bump.hide()

func play_shank(time: float, previous: float) -> void:
	var hit: Dictionary = bump.net_hit
	var end := Flight.landing_time(pass_origin,pass_motion) if hit.is_empty() else float(hit.end_time)
	show_attack_net(hit,time)
	if not hit.is_empty() and time >= hit.time:
		ball.position = Net.after_hit(hit,minf(time,end))
	else:
		ball.position = flight_point(pass_origin,pass_motion,minf(time,end))
	if previous < end and time >= end: play_floor_sound()
	if previous >= end: reset_feed()

func face_receiver(direction: Vector3, max_turn: float) -> void:
	if direction.slide(Vector3.UP).length_squared() > 0.0001:
		var yaw := atan2(direction.x,direction.z)
		receiver.rotation.y = rotate_toward(receiver.rotation.y,yaw,max_turn)

func play_cpu_set(time: float, delta: float) -> void:
	if is_finite(cpu_set.touch_time):
		var push_time: float = time-cpu_set.touch_time
		if approach_practice:
			var anchor: Vector3 = receiver.to_global(cpu_set.hand_anchor)
			face_receiver(approach_set_target-receiver.position,delta*APPROACH_SET_TURN_RATE)
			cpu_set.hand_anchor = receiver.to_local(anchor)
		cpu_set.update_hand_push(time,push_time)
		ball.position = cpu_set.platform_center()
		if is_finite(cpu_set.release_time):
			pass_origin = cpu_set.release_point
			pass_motion = cpu_set.outgoing
			pin_arrival = descending_time(pass_origin,pass_motion,PIN_HEIGHT)
			flight_end = Flight.landing_time(pass_origin,pass_motion)
			stage = Stage.SET
			stage_start = clock
			bump.reset()
			bump.hand_setting = false
			trace.closest_check.clear()
			trace.closest_margin = INF
			status.text = "Space to jump  |  Hold left-click to spike"
			region.show()
			aim_swing(swing_aim)
			trace.write("cpu_set",clock,{"point":pass_origin,"velocity":pass_motion,"pin_arrival":pin_arrival},true)
		return
	ball.position = flight_point(pass_origin,pass_motion,minf(time,cpu_contact_time))
	var travel := (cpu_stand-receiver.position).limit_length(3.2*delta)
	receiver.position += travel
	var toward_ball := (ball.position-receiver.position).slide(Vector3.UP)
	if toward_ball.length_squared() < 0.09 and travel.is_zero_approx():
		toward_ball = (pass_origin-cpu_contact_point).slide(Vector3.UP)
	var lead := cpu_contact_time-time
	if approach_practice and lead < 0.30:
		var target := approach_set_target-receiver.position
		var preturn := 1.0-smoothstep(0.0,0.30,lead)
		var yaw := lerp_angle(atan2(toward_ball.x,toward_ball.z),atan2(target.x,target.z),preturn*0.28)
		face_receiver(Vector3(sin(yaw),0.0,cos(yaw)),delta*lerpf(9.0,APPROACH_SET_TURN_RATE,preturn))
	else:
		face_receiver(toward_ball,delta*9.0)
	cpu_feet.step(receiver.basis.inverse()*travel/maxf(delta*3.2,0.001),delta,1.4,true)
	if lead <= 0.22:
		HandPose.apply(receiver,cpu_contact_point,1.0-smoothstep(0.0,0.22,lead))
	if time >= cpu_contact_time:
		if receiver.position.distance_to(cpu_stand)>0.60:
			shank("CPU could not reach the pass",time)
			return
		cpu_set.height = approach_set_apex if approach_practice else SET_APEX
		var ideal := set_toward_pin(cpu_contact_point,approach_set_target if approach_practice else PIN,cpu_set.height)
		var target := flight_point(cpu_contact_point,ideal,Flight.landing_time(cpu_contact_point,ideal))
		cpu_set.destination = Vector2(target.x,target.z)
		cpu_set.begin_hand_contact(cpu_contact_point,time)
		if approach_practice: approach_set_touched_at = clock

func play_pin_ball(time: float, previous: float, delta: float) -> void:
	if approach_practice and not is_finite(approach_pressed_at):
		status.text = "Hold Space to charge the spike" if find_approach_intercept().is_finite() else unavailable_approach_status()
	var spin_axis := Vector3.UP.cross(pass_motion).normalized()
	if not spin_axis.is_zero_approx(): ball.rotate(spin_axis,TAU*SET_TOPSPIN_RPS*delta)
	ball.position = flight_point(pass_origin,pass_motion,minf(time,flight_end))
	timing_cue.update_timing(time,pin_arrival,BumpSetting.GREEN_START,BumpSetting.GREEN_END)
	var in_air := jump.active and setter.position.y > jump.start.y+0.02
	var air_age := maxf(0.0,jump.elapsed-jump.load_duration())
	if approach_practice and in_air and not is_finite(swing_started): start_attack_swing()
	if in_air and not swing_practice and (air_age < 0.10 or not is_finite(swing_started)):
		var incoming_yaw := incoming_set_heading()
		if approach_practice:
			var glance := clampf(angle_difference(takeoff_yaw,incoming_yaw),-deg_to_rad(25.0),deg_to_rad(25.0))
			incoming_yaw = takeoff_yaw+glance
		var turn_rate := 420.0 if approach_practice else 720.0
		setter.rotation.y = rotate_toward(setter.rotation.y,incoming_yaw,deg_to_rad(turn_rate)*delta)
	if is_finite(swing_started) and in_air:
		if not is_finite(swing_charge_started): swing_charge_started = clock
		var charge := swing_charge()
		status.text = "Swing power  |  %d%%" % roundi(charge*100.0)
		var airborne := setter.position.y > jump.start.y+0.08
		var duration := lerpf(0.21,0.09,charge)+(0.035 if approach_practice else 0.0)
		var predicted := flight_point(pass_origin,pass_motion,minf(time+duration,flight_end))
		var toward_ball := predicted-setter.global_position
		if not is_finite(swing_drive_started) and airborne and time >= pin_arrival-0.46:
			if toward_ball.slide(Vector3.UP).length() <= SWING_REACH and toward_ball.y <= SWING_CONTACT_HEIGHT:
				swing_drive_started = clock
				swing_drive_duration = duration
				swing_hand_speed = 0.0
		var load := smoothstep(0.0,0.26 if approach_practice else 0.18,clock-swing_charge_started)
		var estimated_contact := descending_time(pass_origin,pass_motion,PIN_HEIGHT+1.0)
		var draw_reference := estimated_contact-5.0*LOW_BOW_FRAME
		var hold_delay := 0.0 if swing_practice else minf(0.12,0.24-draw_delay)*charge
		var draw_end := draw_reference+draw_delay+hold_delay
		var draw_progress := smoothstep(draw_end-7.0*LOW_BOW_FRAME,draw_end,time)
		# An early draw holds the low chamber until the lift window opens.
		var lift_start := clampf(draw_end-LOW_BOW_FRAME,draw_reference+SpikeArm.DEFAULT_DRAW_DELAY-LOW_BOW_FRAME,estimated_contact-0.04)
		var arm_lift := smoothstep(lift_start,estimated_contact,time)
		if approach_practice:
			draw_progress = 1.0
			arm_lift = smootherstep(0.08,0.26,clock-swing_started)
		if airborne:
			var expected_contact := flight_point(pass_origin,pass_motion,estimated_contact)
			var shot := swing_aim-expected_contact
			var target_yaw := atan2(shot.x,shot.z)
			var turn_weight := smoothstep(0.0,0.12,clock-swing_charge_started)
			if not swing_practice: turn_weight *= smoothstep(0.10,0.22,air_age)
			setter.rotation.y = rotate_toward(setter.rotation.y,target_yaw,deg_to_rad(air_turn_speed)*turn_weight*delta)
		var drive := clock-swing_drive_started if is_finite(swing_drive_started) else -INF
		var approach_point := flight_point(pass_origin,pass_motion,clampf(maxf(time+0.12,pin_arrival-0.14),0.0,flight_end))
		var drive_phase := clampf(drive/swing_drive_duration,0.0,1.0)
		var extension := smootherstep(0.08,1.0,drive_phase) if approach_practice else smoothstep(0.0,1.0,drive_phase*(1.18-0.18*drive_phase))
		if drive < 0.0:
			pose_bow_draw(delta,load,approach_point,0.0,0.0,draw_progress,arm_lift)
		else:
			var follow := smoothstep(swing_drive_duration+0.035,swing_drive_duration+0.16,drive)
			var contact_target := approach_point.lerp(ball.position,smoothstep(0.0,0.50,extension))
			pose_bow_draw(delta,load,contact_target,extension,follow,draw_progress,arm_lift)
		var palm := right_palm()
		if airborne and drive > 0.0 and drive <= swing_drive_duration+0.12 and previous_palm.is_finite():
			swing_impact_speed = palm.distance_to(previous_palm)/maxf(delta,0.001)
			swing_hand_speed = maxf(swing_hand_speed,swing_impact_speed)
			var previous_ball := flight_point(pass_origin,pass_motion,previous)
			var before := previous_ball-previous_palm
			var after := ball.position-palm
			var fraction := hand_contact_fraction(before,after)
			var palm_gap := Geometry3D.get_closest_point_to_segment(Vector3.ZERO,before,after).length()
			# Give the real palm a chance to meet the ball before accepting an assisted hit.
			var leaving_reach := after.dot(after-before) >= 0.0 or drive+delta > swing_drive_duration+0.12
			if approach_practice and fraction < 0.0 and leaving_reach:
				fraction = hand_contact_fraction(before,after,ASSISTED_PALM_RADIUS)
			if fraction >= 0.0:
				swing_contact_extension = extension
				var contact_charge := approach_hold_charge(clock-(time-previous)*(1.0-fraction)) if approach_practice else charge
				hit_spike(contact_charge,previous_ball.lerp(ball.position,fraction),palm_gap)
				return
		previous_palm = palm
	if time >= flight_end:
		play_floor_sound()
		var result := "Spike missed"
		if approach_practice and not is_finite(approach_pressed_at):
			result = "Set went untouched"
		miss(result)

func smootherstep(start: float, end: float, time: float) -> float:
	var t := clampf((time-start)/(end-start),0.0,1.0)
	return t*t*t*(t*(t*6.0-15.0)+10.0)

func right_palm() -> Vector3:
	var rig: Skeleton3D = setter.skeleton
	var wrist := rig.get_bone_global_pose(rig.find_bone("hand_r")).origin
	var knuckle := rig.get_bone_global_pose(rig.find_bone("middle_01_r")).origin
	var index := rig.get_bone_global_pose(rig.find_bone("index_01_r")).origin
	var pinky := rig.get_bone_global_pose(rig.find_bone("pinky_01_r")).origin
	var palm_normal := (knuckle-wrist).cross(pinky-index).normalized()
	return rig.to_global(wrist.lerp(knuckle,0.75)+palm_normal*0.018)

func hand_contact_fraction(before: Vector3, after: Vector3, palm_radius := PALM_RADIUS) -> float:
	var radius := BallPreview.RADIUS+palm_radius
	var gap := before.length_squared()-radius*radius
	if gap <= 0.0: return 0.0
	var relative := after-before
	var length_squared := relative.length_squared()
	if length_squared <= 0.000001: return -1.0
	var projection := before.dot(relative)
	var discriminant := projection*projection-length_squared*gap
	if discriminant < 0.0: return -1.0
	var entry := (-projection-sqrt(discriminant))/length_squared
	return entry if entry >= 0.0 and entry <= 1.0 else -1.0

func hit_spike(charge: float, point: Vector3, palm_gap := 0.0) -> void:
	if approach_practice: capture_approach_arm_pose()
	spike_bounce_speed = 0.0
	if not ball_audio_muted: spike_audio.play()
	swing_contact = point
	ball.position = point
	swing_power = charge
	spike_topspin_rps = clampf(swing_impact_speed*0.55,4.0,10.0)
	pass_origin = swing_contact
	swing_contact_aim = swing_aim
	var target := swing_contact_aim-pass_origin
	var speed := clampf(swing_hand_speed*2.2,1.0,32.0)
	if approach_practice:
		var palm_bonus := lerpf(0.95,1.05,smoothstep(5.0,15.0,swing_hand_speed))
		var contact_bonus := lerpf(1.12,0.74,smoothstep(BallPreview.RADIUS,BallPreview.RADIUS+ASSISTED_PALM_RADIUS,palm_gap))
		speed = lerpf(12.0,27.0,charge)*palm_bonus*contact_bonus
	elif not swing_practice:
		var completion := smoothstep(0.22,0.93,swing_contact_extension)
		speed *= lerpf(0.56,1.0,charge)*lerpf(0.65,1.0,completion)
	var duration := target.slide(Vector3.UP).length()/speed
	pass_motion = target/duration+Vector3.UP*Flight.GRAVITY*duration*0.5
	flight_end = duration
	swing_net_hit = Net.first_hit(func(t): return flight_point(pass_origin,pass_motion,t),0.0,duration)
	stage = Stage.HIT
	stage_start = clock
	region.hide()
	timing_cue.hide()
	status.text = "Spike  |  %d%% power" % roundi(charge*100.0)
	trace.write("spike",clock,{"point":swing_contact,"aim":swing_aim,"velocity":pass_motion,"power":charge,"palm_gap":palm_gap,"swing":SpikeArm.SWING_NAME,"palm_speed":swing_impact_speed,"peak_palm_speed":swing_hand_speed,"topspin_rps":spike_topspin_rps,"net":not swing_net_hit.is_empty()},true)

func play_spike(time: float, delta: float) -> void:
	show_attack_net(swing_net_hit,time)
	var spin_axis := Vector3.UP.cross(pass_motion).normalized()
	if not spin_axis.is_zero_approx(): ball.rotate(spin_axis,TAU*spike_topspin_rps*delta)
	var hit_net := not swing_net_hit.is_empty()
	var landing_time := float(swing_net_hit.end_time) if hit_net else flight_end
	var bounce_end := landing_time
	if hit_net and time >= swing_net_hit.time:
		ball.position = Net.after_hit(swing_net_hit,minf(time,landing_time))
		status.text = "Spike hit the net"
	else:
		ball.position = flight_point(pass_origin,pass_motion,minf(time,landing_time))
	if time >= landing_time:
		var ground := Vector3(ball.position.x,Flight.FLOOR,ball.position.z)
		var fall_time := float(swing_net_hit.drop_time) if hit_net else landing_time
		var landing_velocity: Vector3 = swing_net_hit.velocity if hit_net else pass_motion
		landing_velocity += Vector3.DOWN*Flight.GRAVITY*fall_time
		if spike_bounce_speed == 0.0:
			play_floor_sound()
			spike_bounce_speed = clampf(-landing_velocity.y*0.58,3.8,6.5)*sqrt(ball_bounciness)
		var bounce_velocity := landing_velocity.slide(Vector3.UP)*0.25+Vector3.UP*spike_bounce_speed
		var bounce_time := Flight.landing_time(ground,bounce_velocity)
		bounce_end += bounce_time
		if time-delta < bounce_end and time >= bounce_end: play_floor_sound()
		ball.position = flight_point(ground,bounce_velocity,minf(time-landing_time,bounce_time))
	if time < SWING_FOLLOW_TIME:
		var follow := 1.0-pow(1.0-clampf(time/0.19,0.0,1.0),2.0)
		pose_bow_draw(delta,1.0-smoothstep(0.19,SWING_FOLLOW_TIME,time),swing_contact,swing_contact_extension,follow)
	if time >= maxf(SWING_FOLLOW_TIME,bounce_end) and not jump.active: finish_attack_rep()

func finish_attack_rep() -> void:
	if approach_practice:
		stage = Stage.APPROACH_RETURN
		return
	reset_feed()

func pose_bow_draw(delta: float, weight: float, contact: Vector3, extension := 0.0, follow := 0.0, draw_progress := 1.0, arm_lift := 1.0) -> void:
	var rig: Skeleton3D = setter.skeleton
	var author: RefCounted = setter.get_pose_author()
	var pose: Array[Transform3D] = []
	for bone in rig.get_bone_count(): pose.append(rig.get_bone_pose(bone))
	var drive_age := clock-swing_drive_started if is_finite(swing_drive_started) else 0.0
	var rotation_phase := smoothstep(0.0,swing_drive_duration+0.02,drive_age) if is_finite(swing_drive_started) else 0.0
	var shot_aim := swing_contact_aim if stage == Stage.HIT else swing_aim
	var power := swing_power if stage == Stage.HIT else swing_charge()
	var rotation_weight := weight*torso_rotation_scale*lerpf(0.48,1.22,power)
	var drive_turn := lerpf(-0.57,0.36,rotation_phase)
	var turn := lerpf(drive_turn,0.0,follow)
	var airborne := smoothstep(0.08,0.45,setter.position.y-jump.start.y)
	var leg_release := smoothstep(0.0,1.0,rotation_phase)
	var leg_turn := tanh(turn*rotation_weight*0.75)*0.32*leg_release*leg_rotation_scale*airborne
	var kick_release := 0.32*leg_release*smoothstep(0.0,1.5,leg_rotation_scale)
	var straighten := smoothstep(0.12,0.88,follow)*weight*smoothstep(0.03,0.22,setter.position.y-jump.start.y)
	if not is_zero_approx(leg_turn):
		var spine: Transform3D = author.world_pose(pose,rig.find_bone("spine_01"))
		var hips: Vector3 = author.point(pose,"pelvis")
		author.rotate_world(pose,"pelvis",(spine.origin-hips).normalized(),leg_turn)
		author.set_world_basis(pose,"spine_01",spine.basis)
	var kick_load := smoothstep(0.0,0.30,clock-swing_charge_started)
	var tuck := airborne*weight*kick_load*minf(leg_kickback_scale,1.0)*(1.0-0.75*follow)
	if tuck > 0.0 or straighten > 0.0:
		for side in ["l","r"]:
			var thigh: String = "thigh_"+side
			var calf: String = "calf_"+side
			var foot: String = "foot_"+side
			var hip: Vector3 = author.point(pose,thigh)
			var knee: Vector3 = author.point(pose,calf)
			var ankle: Vector3 = author.point(pose,foot)
			var outward := 1.0 if side == "l" else -1.0
			var thigh_axis := (knee-hip).normalized().slerp(Vector3(0.18*outward,-1.0,0.16).normalized().rotated(Vector3.UP,leg_turn),tuck)
			var heel_lift := (0.24 if side == "r" else 0.10)+0.78*maxf(0.0,leg_kickback_scale-1.0)
			var kick_axis := Vector3(0.07*outward,heel_lift,-1.0).normalized()
			var release_axis := kick_axis.slerp(Vector3(0.07*outward,-1.0,-0.15).normalized(),kick_release)
			var shin_axis := (ankle-knee).normalized().slerp(release_axis.rotated(Vector3.UP,leg_turn),tuck)
			author.aim_joint(pose,thigh,calf,hip+thigh_axis)
			knee = author.point(pose,calf)
			author.aim_joint(pose,calf,foot,knee+shin_axis.slerp(thigh_axis,straighten*0.98))
	# Tilt after the leg solve so the hips carry the tucked legs into the reach.
	var reach_weight := airborne*weight*maxf(0.72*arm_lift,extension)
	reach_weight *= 1.0-smoothstep(0.0,0.85,follow)
	if approach_practice: reach_weight *= 0.28
	var lean := airborne_reach_lean(contact)*reach_weight
	author.rotate_world(pose,"pelvis",Vector3.RIGHT,lean.x)
	author.rotate_world(pose,"pelvis",Vector3.BACK,lean.y)
	var ball_target := rig.to_local(contact)
	# Twist the ribcage around its own axis so the lean stays independent.
	var chest_axis: Vector3 = (author.point(pose,"neck_01")-author.point(pose,"spine_03")).normalized()
	var chest_yaw := clampf(turn*rotation_weight,-1.45,1.45)
	author.rotate_world(pose,"spine_03",chest_axis,chest_yaw)
	var load_back := 1.0-smoothstep(0.04,0.55,extension)
	var backswing_weight := draw_progress*(1.0-arm_lift)*(1.0-smoothstep(0.0,0.38,extension))
	var contact_crunch := smoothstep(0.42,0.95,extension)
	var pitch := deg_to_rad((-50.0-torso_lean_degrees)*load_back+11.5*contact_crunch+backswing_bend*backswing_weight)
	if stage == Stage.HIT:
		var hit_age := clock-stage_start
		var forward_crunch := smoothstep(0.0,0.09,hit_age)
		pitch = lerpf(pitch,deg_to_rad(30.0-torso_lean_degrees),forward_crunch)
		pitch *= 1.0-smoothstep(0.10,0.27,hit_age)
	if approach_practice:
		pitch *= 0.38
		if stage == Stage.SET:
			var rise_age := clock-swing_started
			var arch := smootherstep(0.08,0.25,rise_age)*(1.0-smootherstep(0.25,0.43,rise_age))
			pitch = lerpf(pitch,deg_to_rad(-40.0),arch)
	author.rotate_world(pose,"spine_01",Vector3.RIGHT,pitch*0.45*weight)
	author.rotate_world(pose,"spine_02",Vector3.RIGHT,pitch*0.55*weight)
	var neck: Vector3 = author.point(pose,"neck_01")
	var gaze := ball_target-neck
	var flat_gaze := gaze.slide(Vector3.UP)
	var ball_pitch := clampf(atan2(gaze.y,flat_gaze.length()),-0.45,0.45)
	var ball_yaw := clampf(atan2(gaze.x,gaze.z),-0.85,0.85)
	var yaw_weight := smoothstep(0.05,0.45,flat_gaze.length())
	author.rotate_world(pose,"neck_01",Vector3.UP,(ball_yaw*0.5-chest_yaw*0.55)*yaw_weight*weight)
	author.rotate_world(pose,"neck_01",Vector3.RIGHT,(-pitch*0.72-ball_pitch*0.32)*weight)
	var line_weight := shot_line_weight(shot_aim,contact)
	if stage == Stage.HIT and weight < 1.0 and not swing_finish_pose.is_empty():
		if line_weight < 0.5:
			SpikeArm.recover_same_side_arm(pose,swing_finish_pose,author,weight)
		else:
			SpikeArm.blend_arm(pose,swing_finish_pose,author,weight)
		SpikeArm.blend_arm(pose,swing_finish_pose,author,weight,"l")
		SpikeArm.open_strike_hand(pose,author,0.94*weight)
	else:
		var palm_finish := SpikeArm.finish_palm_weight(shot_aim,contact,line_weight >= 0.5)
		# Smooth the roll through the near-vertical hand angle using game time.
		var roll_step := deg_to_rad(2700.0)*delta
		var shot_direction := (rig.to_local(shot_aim)-ball_target).normalized()
		var compact_finish := SpikeArm.compact_finish_weight(shot_aim,contact,line_weight < 0.5)
		var arm_weight := 1.0 if approach_practice and stage == Stage.SET else weight
		swing_palm_roll = SpikeArm.apply(pose,author,ball_target,arm_weight,extension,follow,draw_progress,arm_lift,line_weight,palm_finish,elbow_clearance,swing_palm_roll,roll_step,shot_direction,compact_finish,backswing_reach*backswing_weight,approach_practice)
		var guide_drop := maxf(smoothstep(0.07,0.83,extension),smoothstep(0.0,0.62,follow))
		SpikeArm.apply_guide_arm(pose,author,Vector3(0.06,0.43,0.64-backswing_reach*backswing_weight*0.6),Vector3(0.26,-0.55,0.15),guide_drop,arm_weight,172.0)
		if stage == Stage.HIT and follow >= 0.90:
			swing_finish_pose = pose.duplicate()
	if approach_practice and not approach_arm_transition.is_empty():
		var handoff_age := clock-stage_start if stage == Stage.HIT else clock-swing_started
		if stage == Stage.SET and handoff_age < 0.43:
			var front_pose := pose.duplicate()
			var across: Vector3 = (author.point(pose,"upperarm_l")-author.point(pose,"upperarm_r")).normalized()
			var up: Vector3 = (author.point(pose,"neck_01")-author.point(pose,"spine_01")).normalized()
			var forward := across.cross(up).normalized()
			for side in ["r","l"]:
				var upper: String = "upperarm_"+side
				var shoulder: Vector3 = author.point(pose,upper)
				var outward := across*(1.0 if side == "l" else -1.0)
				var elbow: Vector3 = author.point(pose,"lowerarm_"+side)
				var wrist: Vector3 = author.point(pose,"hand_"+side)
				var arm_length := shoulder.distance_to(elbow)+elbow.distance_to(wrist)
				var overhead := clampf((handoff_age-0.08)/0.18,0.0,1.0)
				var front := (forward*sin(deg_to_rad(80.0))-up*cos(deg_to_rad(80.0))).normalized()
				var lift_direction := front.slerp(Vector3.UP,overhead)
				var target := shoulder+lift_direction*lerpf(0.54,arm_length*0.995,overhead)-outward*lerpf(0.07,0.02,overhead)
				# Keep the elbow bend on the same side as the hand passes overhead.
				var elbow_pole := lerp_angle(0.0,PI*0.5,overhead)
				var bend := forward*sin(elbow_pole)-up*cos(elbow_pole)-outward*0.10
				author.limb(front_pose,upper,"lowerarm_"+side,"hand_"+side,target,bend,1.0,lerpf(155.0,174.0,overhead))
				var front_weight := 1.0-smootherstep(0.21,0.39 if side == "r" else 0.43,handoff_age)
				SpikeArm.blend_arm(pose,front_pose,author,front_weight,side)
				var source_weight := 1.0-smootherstep(0.0,0.12,handoff_age)
				SpikeArm.blend_arm(pose,approach_arm_transition,author,source_weight,side)
		elif stage == Stage.HIT:
			var source_weight := 1.0-smootherstep(0.0,0.09,handoff_age)
			if source_weight > 0.0:
				SpikeArm.blend_arm(pose,approach_arm_transition,author,source_weight)
				SpikeArm.blend_arm(pose,approach_arm_transition,author,source_weight,"l")
	for bone in rig.get_bone_count():
		rig.set_bone_pose_rotation(bone,pose[bone].basis.get_rotation_quaternion())

func shot_line_weight(target: Vector3, origin: Vector3) -> float:
	# Only an inward angle crosses the court. Outward aim can still run down the near sideline.
	var lateral := target.x-origin.x
	var inward := absf(lateral) if is_zero_approx(origin.x) else -signf(origin.x)*lateral
	var across_court := inward/maxf(target.z-origin.z,0.1)
	return 1.0-smoothstep(0.16,0.38,across_court)

func airborne_reach_lean(contact: Vector3) -> Vector2:
	var drift: Vector3 = jump.horizontal_velocity()*0.12
	var reach := setter.to_local(contact-drift)-Vector3(-0.24,0.0,0.28)
	var tilt := Vector2(reach.z,-reach.x)
	var angle := clampf((tilt.length()-0.10)*1.20,0.0,0.68)
	return tilt.normalized()*angle

func miss(message: String) -> void:
	stage = Stage.MISS
	stage_start = clock
	status.text = message
	swing_target.hide()
	trace.write("attack_miss",clock,{"ball":ball.position,"player":setter.position,"closest_check":trace.closest_check},true)

func set_toward_pin(origin: Vector3, pin := PIN, apex := SET_APEX) -> Vector3:
	var rise := sqrt(2.0*Flight.GRAVITY*(apex-origin.y))
	var duration := (rise+sqrt(2.0*Flight.GRAVITY*(apex-PIN_HEIGHT)))/Flight.GRAVITY
	return (pin-origin).slide(Vector3.UP)/duration+Vector3.UP*rise

func descending_time(origin: Vector3, velocity: Vector3, height: float) -> float:
	var square := velocity.y*velocity.y+2.0*Flight.GRAVITY*(origin.y-height)
	return (velocity.y+sqrt(square))/Flight.GRAVITY if square >= 0.0 else -1.0
