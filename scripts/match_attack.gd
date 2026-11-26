extends "res://scripts/attack_drill.gd"

signal struck(actor: Node3D, point: Vector3, velocity: Vector3, spin: float)

var enabled := false
var camp_swing := preload("res://scripts/camp_spike_pose.gd").new()
var feed_origin := Vector3.ZERO
var contact_offset := Vector3.ZERO
var contact_phase := 0.
var live_swing_phase := 0.
var chase_late_sets := false
var decoy_swing := false
var rally_shot := "spike"
var drill_speed_mps := 0.
var spike_strength := 1.0
# Jog_Fwd is a loop. The leading ankle reaches support at 0.023 s and half a cycle later.
const JOG_LEFT_PLANT_PHASE := 0.025
var run_into_plant := false
var run_entry_velocity := Vector3.ZERO

func run_left_plant_distance() -> float:
	var animator: AnimationPlayer = setter.animator
	var length := animator.current_animation_length
	return fposmod(JOG_LEFT_PLANT_PHASE*length-animator.current_animation_position,length)

func record_run_footfalls(before: float, after: float, length: float) -> bool:
	var advance := fposmod(after-before,length)
	var left_landed := false
	for foot in ["left","right"]:
		var phase := JOG_LEFT_PLANT_PHASE+(0.5 if foot == "right" else 0.0)
		var distance := fposmod(length*phase-before,length)
		if distance <= 0.00001 or distance > advance+0.00001: continue
		var actual: String = foot
		if setter.mirror_animation: actual = "right" if foot == "left" else "left"
		trace.write("approach_run_footfall",clock,{"foot":actual,"position":setter.position})
		left_landed = left_landed or foot == "left"
	return left_landed

func queue_run_plant(velocity: Vector3) -> void:
	var intercept := find_approach_intercept(true,0)
	if not intercept.is_finite(): return
	approach_steps = 2
	approach_pressed_at = clock
	approach_space_held = true
	approach_jump_queued = true
	run_into_plant = true
	run_entry_velocity = velocity
	trace.write("approach_run_plant",clock,{"foot":setter.animation_side("l"),"remaining_steps":2,"position":setter.position,"velocity":velocity},true)

func begin_attack_jump(direction: Vector2, plant_time := 0.36, jump_height := 0.0, tempo := 1.0) -> void:
	super.begin_attack_jump(direction,plant_time,jump_height,tempo)
	if run_into_plant and jump.active:
		setter.animator.speed_scale = 1.0
		jump.carry_run_into_plant(run_entry_velocity)

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
	rally_shot="spike"
	feed_origin=origin
	jump.attack_arm_lift=chase_late_sets
	jump.reserve_two_step_runway=chase_late_sets
	camp_swing.last_shoulder_time=-1.
	camp_swing.reach_assist=Vector3.ZERO
	bump.setter = actor
	run_into_plant = false
	run_entry_velocity = Vector3.ZERO
	var saved := actor.transform
	super.reset_feed()
	actor.transform = saved
	stage = Stage.SET
	stage_start = clock-age
	pass_origin = origin
	pass_motion = velocity
	var apex := origin.y+maxf(0.0,velocity.y)**2/(2.0*Flight.GRAVITY)
	pin_arrival = descending_time(origin,velocity,set_contact_height(apex))
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

func set_contact_height(apex := INF) -> float:
	return minf(clampf(approach_reach_height(),2.70,3.38),maxf(2.62,apex-0.22))

func apex_for_set_time(origin_height: float, apex: float, minimum_time: float) -> float:
	var rise := sqrt(2.0*Flight.GRAVITY*(apex-origin_height))
	if descending_time(Vector3.UP*origin_height,Vector3.UP*rise,set_contact_height(apex)) >= minimum_time:
		return apex
	# Find the lowest arc that gives the hitter the required time to the contact point.
	var low := apex
	var high := maxf(apex,set_contact_height())+0.5*Flight.GRAVITY*minimum_time**2
	for sample in 10:
		var middle := (low+high)*0.5
		rise = sqrt(2.0*Flight.GRAVITY*(middle-origin_height))
		if descending_time(Vector3.UP*origin_height,Vector3.UP*rise,set_contact_height(middle)) < minimum_time:
			low = middle
		else:
			high = middle
	return high

func adaptive_approach_timing() -> bool:
	return true

func tick_attack(delta: float) -> void:
	if not enabled: return
	if stage == Stage.SET:
		if not (chase_late_sets and absf(rally_set_target.x)>2.5):
			queued_approach_input(delta)
		if chase_late_sets and not jump.active and not is_finite(swing_started):
			chase_committed_set(delta)
	step_jump(delta)
	clock += delta
	var age := clock-stage_start
	if stage == Stage.SET:
		play_pin_ball(age,maxf(0.0,age-delta),delta)
		if decoy_swing and stage==Stage.SET and jump.active and is_finite(swing_started) and age>=pin_arrival:
			hit_spike(1.,right_palm())
	elif stage == Stage.HIT and age < SWING_FOLLOW_TIME:
		var follow := 1.0-pow(1.0-clampf(age/0.19,0.0,1.0),2.0)
		pose_bow_draw(delta,1.0-smoothstep(0.19,SWING_FOLLOW_TIME,age),swing_contact,swing_contact_extension,follow)
	elif not jump.active:
		enabled = false

func chase_committed_set(delta: float) -> void:
	var remaining := pin_arrival-(clock-stage_start)
	if remaining<-.08: return
	var contact := flight_point(pass_origin,pass_motion,pin_arrival)
	var plant := spike_body_target(contact)
	var gap := (plant-setter.position).slide(Vector3.UP)
	var rise := jump.flight_duration(jump.max_height-.2032,true)*.46
	var full_approach := absf(contact.x)>2.5 and gap.length()>.8 and remaining>=rise+jump.LEAD_STEP_TIME+.10
	var lead := jump.LEAD_STEP_TIME if full_approach else 0.
	var runway := 1.7 if full_approach else 1.35
	if remaining>rise+lead+.18:
		if gap.length()>runway:
			var step := gap.limit_length(minf(gap.length()-runway,4.8*delta))
			setter.position+=step
			setter.rotation.y=rotate_toward(setter.rotation.y,atan2(gap.x,gap.z),8.*delta)
			setter.play_travel_gait(step/maxf(delta,.001))
		else:
			setter.play_ground_gait(0.)
		setter.animator.advance(delta)
		return
	if gap.length()>2.1:
		var step := gap.limit_length(4.8*delta)
		setter.position+=step
		setter.play_ground_gait(step.length()/maxf(delta,.001))
		setter.animator.advance(delta)
		return
	approach_jump_queued=false
	approach_steps=3 if full_approach else 2
	approach_intercept=contact
	approach_expected_hit_at=stage_start+pin_arrival
	begin_attack_jump(Vector2.ZERO,clampf(remaining-rise-lead,.115,.25),jump.max_height-.2032)
	jump.release()

func spike_body_target(ball_target: Vector3) -> Vector3:
	var shot := (swing_aim-ball_target).slide(Vector3.UP).normalized()
	var hitting_side := shot.cross(Vector3.UP)
	if setter.mirror_animation: hitting_side = -hitting_side
	var target := ball_target-shot*0.38-hitting_side*0.32
	target.z = minf(target.z,jump.front_limit)
	return target

func approach_heading_yaw() -> float:
	if not chase_late_sets or absf(rally_set_target.x)<2.5: return super.approach_heading_yaw()
	# The pin can chase a wide ball with its feet while opening into the court.
	var inward := -signf(rally_set_target.x)
	return atan2(inward*clampf(jump.heading.x*inward,.20,.65),maxf(.65,jump.heading.z))

func approach_glide_distance() -> float:
	return .38 if chase_late_sets else .27

func uses_air_reach_assist() -> bool:
	return true

func step_jump(delta: float) -> void:
	var original := trace_input
	if stage == Stage.SET and jump.active and approach_intercept.is_finite() and jump.elapsed > jump.load_duration():
		var air_age: float = jump.elapsed-jump.load_duration()
		var predicted := setter.position+jump.horizontal_velocity()*0.10
		var error := (spike_body_target(approach_intercept)-predicted).slide(Vector3.UP)
		var gain := smootherstep(0.10,0.29,air_age)*0.92
		var steering := error.limit_length(0.46)*gain/0.46
		trace_input = original+Vector2(-steering.x,steering.z)
	super.step_jump(delta)
	trace_input = original

func uses_front_right_lift() -> bool:
	return true

func keeps_strike_palm_presented() -> bool:
	return true

func can_drive_to(offset: Vector3,duration: float) -> bool:
	if not chase_late_sets: return super.can_drive_to(offset,duration)
	var reach: float=SWING_CONTACT_HEIGHT*setter.height_cm/180.
	var available_rise := maxf(0.,jump.start.y+jump.height-setter.position.y)
	return offset.slide(Vector3.UP).length()<=SWING_REACH and offset.y<=reach+minf(.60,available_rise)+.18

func drive_lead_time(duration: float) -> float:
	return duration+.055 if chase_late_sets else super.drive_lead_time(duration)

func spike_assist_radius() -> float:
	return PALM_RADIUS if chase_late_sets else .19

func sync_approach_arm_lift() -> bool:
	return not chase_late_sets

func attack_arm_turn_rate() -> float:
	if stage == Stage.SET and clock-swing_started <= 0.26: return deg_to_rad(3200.0)
	return deg_to_rad(1580.0)

func spike_speed_multiplier() -> float:
	return spike_strength

func pose_bow_draw(delta: float, weight: float, contact: Vector3, extension := 0., follow := 0., draw_progress := 1., arm_lift := 1., frame: Node3D = null) -> void:
	if not chase_late_sets:
		super.pose_bow_draw(delta,weight,contact,extension,follow,draw_progress,arm_lift,frame)
		return
	var speed := drill_speed_mps if drill_speed_mps>0. else 25.
	var factor := pow(speed/14.,.48)*(1.+(float(setter.attributes.get("Arm swing",65))-65.)*.004)
	var hit := stage==Stage.HIT
	var swing_age := contact_phase+clock-stage_start if hit else clock-stage_start-pin_arrival+.13/factor
	if not hit:
		var rig: Skeleton3D=setter.skeleton
		var shoulder := rig.to_global(rig.get_bone_global_pose(rig.find_bone("upperarm_r")).origin)
		var distance := shoulder.distance_to(ball.global_position)
		var arm_length: float=setter.height_cm*.0042
		var proximity := 1.-smoothstep(arm_length+.10,arm_length+.65,distance)
		swing_age=minf(swing_age,lerpf(.025,.13,proximity)/factor)
		live_swing_phase=swing_age
	var height := jump.assisted_height*jump.takeoff_effectiveness
	camp_swing.apply(setter,jump,"spike" if hit else "set",swing_age,contact_phase,ball.global_position,
		to_global(feed_origin),to_global(rally_set_target),to_global(swing_contact) if hit else ball.global_position,
		to_global(swing_aim),contact_offset,height,factor,speed,1.,0,-1.,rally_shot=="roll",rally_shot=="tip",.35,true)

func hit_spike(charge: float, point: Vector3, palm_gap := 0.0) -> void:
	if chase_late_sets:
		contact_phase=live_swing_phase
		if not decoy_swing:
			for modifier in setter.skeleton.get_children():
				if modifier.has_method("mark_spike_contact"):
					modifier.mark_spike_contact(setter.get_pose_author(),to_global(point))
		var rig: Skeleton3D=setter.skeleton
		contact_offset=rig.to_local(to_global(point))-rig.get_bone_global_pose(rig.find_bone("upperarm_r")).origin
	super.hit_spike(charge,point,palm_gap)
	if decoy_swing: return
	if drill_speed_mps>0.:
		var displacement := swing_contact_aim-point
		var g := Flight.GRAVITY
		var term := drill_speed_mps*drill_speed_mps-g*displacement.y
		var discriminant := term*term-g*g*displacement.length_squared()
		if discriminant>=0. and displacement.length_squared()>.01:
			flight_end=sqrt(2.*displacement.length_squared()/(term+sqrt(discriminant)))
			pass_motion=displacement/flight_end+Vector3.UP*.5*g*flight_end
	struck.emit(setter,to_global(point),global_basis*pass_motion,spike_topspin_rps)
