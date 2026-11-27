extends "res://scripts/indoor_practice.gd"

const Swing = preload("res://scripts/spike_arm_swing.gd")
const START := Vector3(3.65,.04,.76)
var hitter: Node3D
var attack_jump := preload("res://scripts/setter_jump.gd").new()
var camp_swing := preload("res://scripts/camp_spike_pose.gd").new()
var swing_time := -1.
var spike_pike_scale := 1.0
var closest_spike_gap := INF
var contact_swing_time := 0.
var cross_court := false
var review_setup := {}
var attack_lane := 0
var setter_station := BASE
var coach_station := Vector3(-3.05,0,-1.7)
var active_lane := 0

var hitter_start := START
var next_set := Vector3(3.65,2.65,3.)
var active_set := next_set

func move_setup_spot(role: String, point: Vector2) -> void:
	match role:
		"Coach": coach_station=Vector3(point.x,coach_station.y,minf(point.y,1.))
		"Setter": setter_station=Vector3(point.x,setter_station.y,minf(point.y,3.))
		"Hitter": hitter_start=Vector3(point.x,START.y,point.y)
		"Set":
			next_set=Vector3(point.x,2.65,point.y)
			attack_lane=0 if point.x>1.5 else (2 if point.x < -1.5 else 1)
	StorySession.save_drill_setup("attack_positions",{"coach":coach_station,"setter":setter_station,"target":next_set,"hitter_start":hitter_start})

func choose_camp_toss() -> Vector3:
	return setter_station

func lane_offset() -> float:
	return [1.,0.,-1.][active_lane]

const SET_HEIGHTS := [15.,40.,70.,130.]

func saved_set_percent() -> float:
	var value := float(StorySession.game_options.get_value("attack","set_height_percent",SET_HEIGHTS[2]))
	# Older saves stored the arc percentage rather than the selected preset.
	if is_equal_approx(value,100.): return SET_HEIGHTS[2]
	if is_equal_approx(value,160.): return SET_HEIGHTS[3]
	return value
var set_arc_percent := SET_HEIGHTS[2] as float

func height_preset() -> int:
	var closest := 0
	for i in range(1,SET_HEIGHTS.size()):
		if absf(set_arc_percent-SET_HEIGHTS[i])<absf(set_arc_percent-SET_HEIGHTS[closest]): closest=i
	return closest

func save_set_height(value: float) -> void:
	if is_equal_approx(value,set_arc_percent): return
	set_arc_percent=value
	StorySession.game_options.set_value("attack","set_height_percent",value)
	StorySession.save_options()
	update_prompts(phase)

var drill_hit_speed := 14.
var jump_height := JUMP_HEIGHT
var feed_started := false
var cpu_hitter := true
const CPU_PAD_DEVICE := -82
var approach_started := false
const JUMP_HEIGHT := 33.*.0254
const ATTACK_SET_LIFT := .10
const PLANT_TIME := .30
const RELEASE_LEAD := .10
const SPIKE_STAMINA_COST := 4.0
const ROLL_STAMINA_COST := 1.5
const SHOT_BUTTONS := [JOY_BUTTON_X,JOY_BUTTON_Y,JOY_BUTTON_B]
const TIP_STAMINA_COST := .5
var tip_shot := false
var held_bumpers: Array[int] = []
var roll_shot := false
var manual_shot := -1
var release_at := INF
var release_grade := INF
var approach_delay := 0.
var first_palm_at := INF
var aim_center := Vector2.INF
var contact_grade := INF
var launched_attack := false
var rebound_age := -1.0
var placement_offset := Vector2.ZERO
var depth_error := 0.

const EARLY_LIMIT := -.18
const LATE_LIMIT := .40
const ATTACK_CONTACT_RADIUS := .46
var planned_contact := Vector3.ZERO
var planned_lunge := Vector3.ZERO
const GRADE_ADVANCE := .305
const CLEAN_EARLY := .085
const CLEAN_LATE := .27
const METER_START := -.32
const METER_END := .45

func attack_meter_position(error: float) -> float:
	return clampf(inverse_lerp(METER_START,METER_END,error),0.,1.)

func attack_meter_error() -> float:
	if is_finite(contact_grade): return contact_grade
	var error := release_grade if is_finite(release_grade) else button_timing_error()
	return error+GRADE_ADVANCE

func attack_contact_height() -> float:
	# Match the open palm in the authored spike pose at jump apex.
	return START.y+hitter.height_cm*.0118+effective_attack_height()*preload("res://scripts/setter_jump.gd").COURT_VERTICAL_SCALE

func planned_attack_contact_height() -> float:
	# A setter who underreads fatigue can leave a tired hitter reaching slightly high.
	var lost_reach := maxf(0.,(jump_height-effective_attack_height())*preload("res://scripts/setter_jump.gd").COURT_VERTICAL_SCALE)
	var read := clampf(setter.effective_rating("Hand setting")/100.,0.,1.)
	return attack_contact_height()+minf(lost_reach,.30)*(1.-read)

func rep_set_percent() -> float:
	return set_arc_percent

func attack_set_duration(height_index: int) -> float:
	var ratio := rep_set_percent()*.01
	# Quick tempos spend less time travelling to the same hand-contact point.
	var quick := smoothstep(.15,.60,ratio)
	return float(DURATION[height_index])*sqrt(ratio)*lerpf(.66,1.,quick)

func start_set_flight() -> void:
	flight_time=attack_set_duration(tempo)
	# arc() adds 4*h*t*(1-t). This gives the ball normal gravity.
	set_arc_height=9.81*flight_time*flight_time/8.

func quick_set_in_flight() -> bool:
	return not has_meta("sampling_attack") and set_arc_height < float(APEX[tempo])*.60

func attack_reference_time() -> float:
	return flight_time

func button_timing_error() -> float:
	if phase not in ["set_contact","set"]: return METER_START-GRADE_ADVANCE
	if not approach_started or endpoint.y>attack_contact_height()+ATTACK_CONTACT_RADIUS:
		return METER_START-GRADE_ADVANCE
	if phase=="set_contact":
		return elapsed-SET_RECEIVE_TIME-push_time-attack_set_duration(tempo)+RELEASE_LEAD
	return elapsed-attack_reference_time()+RELEASE_LEAD

func show_attack_timing(error: float, cleared := false) -> void:
	var clean := error>=-CLEAN_EARLY and error<=CLEAN_LATE
	if clean and not cleared: return
	var color := Color("61ed88") if clean else (Color("f7bd46") if error<0. else Color("f45550"))
	if error<EARLY_LIMIT or error>LATE_LIMIT: color=Color("778088")
	show_player_timing(hitter,"Perfect" if clean else ("Early" if error<0. else "Late"),color)

func clear_attack_input() -> void:
	manual_route=Vector3.ZERO
	roll_shot=false
	tip_shot=false
	manual_shot=-1
	release_at=INF
	release_grade=INF
	approach_delay=0.
	first_palm_at=INF
	aim_center=Vector2.INF
	contact_grade=INF
	launched_attack=false
	rebound_age=-1.
	placement_offset=Vector2.ZERO
	depth_error=0.

var spikes := 0
var strike_shoulder_offset := Vector3.ZERO
var strike_point := Vector3.ZERO
var spin_acceleration := Vector3.ZERO
var wrist_history := {}
var wrist_axes := {}
var contact_offset := Vector3.ZERO
var net_clear_time := -1.
const PALM_CONTACT := 2./60.

var block_sound_count := 0
var spike_sound_count := 0
var hand_impact := AudioStreamPlayer.new()

func build_settings() -> void:
	super.build_settings()
	controls_row.get_parent().add_child(last_block_result)
	last_block_result.hide()
	if scene_file_path!="res://scenes/attacking_camp.tscn": return
	var row := HBoxContainer.new()
	controls_row.get_parent().add_child(row)
	for is_jump in [true,false]:
		var key := "vertical_inches" if is_jump else "hit_speed_mps"
		var slider := HSlider.new()
		slider.min_value=0. if is_jump else 9.
		slider.max_value=60. if is_jump else 40.
		slider.step=1.
		slider.custom_minimum_size=Vector2(140,30)
		slider.focus_mode=Control.FOCUS_NONE
		slider.value=StorySession.game_options.get_value("attack",key,33. if is_jump else 14.)
		var caption := Label.new()
		var format_text := "Attack vertical  %d in" if is_jump else "Hit speed  %.1f km/h"
		row.add_child(caption)
		row.add_child(slider)
		var apply_value := func(value: float):
			caption.text=format_text % (value if is_jump else value*3.6)
			if is_jump: jump_height=value*.0254
			else: drill_hit_speed=value
		apply_value.call(slider.value)
		slider.value_changed.connect(func(value):
			apply_value.call(value)
			StorySession.game_options.set_value("attack",key,value)
			StorySession.save_options()
		)

	block_hud_label=Label.new()
	block_hud_slider=HSlider.new()
	row.add_child(block_hud_label)
	row.add_child(block_hud_slider)
	block_hud_slider.custom_minimum_size=Vector2(110,30)
	block_hud_slider.max_value=60
	block_hud_slider.step=1
	block_hud_slider.focus_mode=Control.FOCUS_NONE
	sync_block_vertical_hud()
	block_hud_slider.value_changed.connect(func(value): set_practice_vertical(0,value))

var block_hud_label: Label
var block_hud_slider: HSlider
var fallback_read := preload("res://scripts/block_shot_read.gd").new()
var shot_read: RefCounted:
	get:
		var wall: Array=get("blockers") if "blockers" in self else practice_blockers
		return wall[0].block_read(hitter) if not wall.is_empty() and hitter!=null else fallback_read
var disguise_read := false

func sync_block_vertical_hud() -> void:
	if is_instance_valid(block_hud_slider):
		block_hud_slider.set_value_no_signal(practice_vertical[0])
		block_hud_label.text="Block vertical  %d in" % practice_vertical[0]

func set_practice_vertical(slot: int,value: float) -> void:
	practice_vertical[slot]=value
	StorySession.game_options.set_value("attack",["right_block_vertical","middle_block_vertical","left_block_vertical"][slot],value)
	StorySession.save_options()
	sync_block_vertical_hud()

func learned_block_offset() -> float:
	return shot_read.shade(BallNet.NET_Z-endpoint.z)

const PracticeBlock = preload("res://scripts/match_block.gd")
var attack_blocker_count := 1
var practice_blockers: Array[Node3D]=[]
var practice_vertical := [float(StorySession.game_options.get_value("attack","right_block_vertical",46.)),float(StorySession.game_options.get_value("attack","middle_block_vertical",46.)),float(StorySession.game_options.get_value("attack","left_block_vertical",46.))]
var practice_jumps := [null,null,null]
var practice_attempted := [false,false,false]
var practice_footwork := []
var practice_touch := false
var quick_results: Array[int]=[]
var last_block_result := Label.new()
var attack_decided := false
var touched_by_middle := false
var middle_commit_order := bool(StorySession.game_options.get_value("attack","commit_middle",false))
var contact_report := ""

func set_middle_commit_order(value: bool) -> void:
	middle_commit_order=value
	StorySession.game_options.set_value("attack","commit_middle",value)
	StorySession.save_options()

func middle_commits() -> bool:
	return middle_commit_order or quick_results.count(1)>=2

func attack_surface_contact(point: Vector3, floor_hit: bool) -> void:
	if attack_decided or phase!="spike" or not launched_attack or has_meta("sampling_attack") or has_meta("live_sampler"): return
	var outside := absf(point.x)>4.5 or absf(point.z-BallNet.NET_Z)>9.
	if not floor_hit and not outside: return
	attack_decided=true
	last_block_result.show()
	if outside:
		last_block_result.text="Block out / "+contact_report if not contact_report.is_empty() else "Out / no block touch"
	elif contact_report.is_empty():
		last_block_result.text="In / no block touch"
	if is_middle_quick():
		var scored := contact_report.is_empty() and not outside and point.z>BallNet.NET_Z and drop_net_hit.is_empty()
		var successful_touch := touched_by_middle and not outside
		quick_results.append(1 if scored or successful_touch else 0)
		if quick_results.size()>10: quick_results.pop_front()

func is_middle_quick() -> bool:
	return absf(active_set.x)<=2.1 and height_preset()<=1

func set_attack_blocker_count(count: int) -> void:
	attack_blocker_count=clampi(count,0,3)
	StorySession.game_options.set_value("attack","blockers",attack_blocker_count)
	StorySession.save_options()
	refresh_practice_blockers()

func refresh_practice_blockers() -> void:
	for i in practice_blockers.size():
		practice_blockers[i].visible=i<attack_blocker_count
		if i>=attack_blocker_count:
			practice_jumps[i]=null
			practice_blockers[i].position.y=START.y
			practice_blockers[i].play_action("idle")

func middle_shade(seconds_to_hit: float) -> float:
	var shade := learned_block_offset()
	if not disguise_read: return shade
	var reveal := 1.-smoothstep(.34,.68,seconds_to_hit)
	return lerpf(-shade*.48,shade,reveal)

func middle_reach(jump: RefCounted, lane: float) -> void:
	if jump.shoulders.size()!=2: return
	var offset: float=lane-jump.actor.position.x
	var left_is_negative: bool=jump.shoulders[0].x<jump.shoulders[1].x
	var negative_open := not is_finite(float(jump.min_hand_x))
	var positive_open := not is_finite(float(jump.max_hand_x))
	var spread := .53*(1.-smoothstep(.12,.45,absf(offset)))
	var kong := smoothstep(.18,.82,absf(offset))
	var negative := maxf(spread,kong if offset<0. else 0.) if negative_open else 0.
	var positive := maxf(spread,kong if offset>0. else 0.) if positive_open else 0.
	jump.reach_input=Vector2(negative,positive) if left_is_negative else Vector2(positive,negative)
	jump.lean_input=clampf(offset,-.85 if negative_open else -.12,.85 if positive_open else .12)

func step_practice_blockers(delta: float) -> void:
	for i in mini(practice_blockers.size(),attack_blocker_count):
		var actor := practice_blockers[i]
		var reverse_close := attack_blocker_count==3 and active_set.x<0.
		var middle_leads := attack_blocker_count>=2 and is_middle_quick()
		var lead_slot := 1 if middle_leads else (2 if reverse_close else 0)
		var jump: RefCounted=practice_jumps[i]
		if jump!=null:
			var lane := endpoint.x+learned_block_offset()
			if phase=="spike" and launched_attack and drop_velocity.z>.1:
				lane=ball.position.x+drop_velocity.x*clampf((BallNet.NET_Z-ball.position.z)/drop_velocity.z,0.,.20)
			var offset := lane-actor.position.x
			if i==lead_slot and jump.age>=PracticeBlock.START and jump.age<PracticeBlock.START+PracticeBlock.AIR*.68:
				var next_x := move_toward(jump.base.x,lane,delta*.85)
				if attack_blocker_count>=2 and not middle_leads:
					var partner_x := practice_blockers[1].position.x
					next_x=maxf(next_x,partner_x+.60) if lead_slot==0 else minf(next_x,partner_x-.60)
				jump.base.x=clampf(move_toward(jump.base.x,next_x,delta*.85),-4.45,4.45)
			if jump.shoulders.size()==2:
				var amount := smoothstep(.22,.78,absf(offset))
				if i==1 and not middle_leads:
					var away := signf(actor.position.x-practice_blockers[lead_slot].position.x)
					amount=smoothstep(.48,.90,absf(offset)) if launched_attack and offset*away>0. and absf(offset)<1.25 else 0.
				var left: bool=(jump.shoulders[0].x-jump.shoulders[1].x)*offset>0.
				jump.reach_input=Vector2(amount,0.) if left else Vector2(0.,amount)
				jump.lean_input=clampf(offset,-.8,.8) if i==0 else signf(offset)*amount*.20
			if middle_leads and i==1:
				jump.min_hand_x=-INF
				jump.max_hand_x=INF
				for partner in practice_blockers:
					if partner==actor or not partner.visible: continue
					var gap := partner.position.x-actor.position.x
					if absf(gap)>1.4: continue
					if gap<0.: jump.min_hand_x=maxf(jump.min_hand_x,actor.position.x+gap*.5+.06)
					else: jump.max_hand_x=minf(jump.max_hand_x,actor.position.x+gap*.5-.06)
				middle_reach(jump,lane)
			if not jump.step(delta,ball.global_position): practice_jumps[i]=null
			continue
		if phase=="set" and elapsed<actor.reaction_seconds(): continue
		var home_x := (1-i)*2.15
		var goal := home_x+clampf(shot_read.prediction,-1.,1.)*(-.35 if disguise_read else .75)
		if phase=="set" or phase=="spike":
			var seam_offset := ((attack_blocker_count-1)*.5-i)*.68
			var shade := learned_block_offset()
			if disguise_read and phase=="set":
				var close_in := smoothstep(.0,.27,elapsed-flight_time+PracticeBlock.START+PracticeBlock.AIR*.5+.23)
				shade=lerpf(-shade*.45,shade,close_in)
			goal=clampf(endpoint.x+shade+seam_offset,-4.4,4.4)
		if i!=lead_slot:
			var toward_lead := signi(lead_slot-i)
			goal=home_x if phase not in ["set","spike"] else clampf(practice_blockers[i+toward_lead].position.x+.68*toward_lead,-4.45,4.45)
		var commit := i==1 and middle_commits() and is_middle_quick()
		var until_hit := flight_time-elapsed
		if middle_leads and i==1 and (phase=="set" or (commit and phase in ["pass","set_contact"])):
			if phase=="pass":
				until_hit=contact_time-elapsed+SET_RECEIVE_TIME+SET_PUSH_TIME+attack_set_duration(chosen_tempo())
			elif phase=="set_contact":
				until_hit=SET_RECEIVE_TIME+push_time-elapsed+attack_set_duration(tempo)
			goal=clampf(active_set.x+middle_shade(until_hit),-4.4,4.4)
		var old_x := actor.position.x
		actor.position.x=move_toward(old_x,goal,GroundControls.speed(true,true)*delta)
		actor.animator.advance(delta)
		practice_footwork[i].block_step(Vector3.RIGHT*(actor.position.x-old_x)/maxf(.0001,delta),goal-old_x,PI,phase=="set",false,delta)
		var may_jump := phase=="set" or (commit and phase in ["pass","set_contact"])
		if may_jump and not practice_attempted[i] and absf(goal-actor.position.x)<.85 and until_hit<=PracticeBlock.START+PracticeBlock.AIR*.5+PracticeBlock.CPU_LEAD:
			jump=PracticeBlock.new()
			jump.track_near_ball=true
			jump.jump_height=float(practice_vertical[i])*.0254
			jump.net_heading=PI
			jump.aggressive_press=true
			jump.court_aim=Vector3(0.,0.,BallNet.NET_Z-3.)
			if i>0: jump.max_hand_x=(actor.position.x+practice_blockers[i-1].position.x)*.5-.06
			if i+1<attack_blocker_count: jump.min_hand_x=(actor.position.x+practice_blockers[i+1].position.x)*.5+.06
			jump.begin(actor)
			practice_jumps[i]=jump
			practice_attempted[i]=true

func start_drill() -> void:
	set_arc_percent=saved_set_percent()
	var positions := StorySession.load_drill_setup("attack_positions")
	coach_station=positions.get("coach",coach_station)
	setter_station=positions.get("setter",setter_station)
	next_set=positions.get("target",next_set)
	attack_lane=0 if next_set.x>1.5 else (2 if next_set.x < -1.5 else 1)
	hitter_start=positions.get("hitter_start",Vector3(START.x*[1.,0.,-1.][attack_lane],START.y,START.z))
	hand_impact.stream=preload("res://assets/audio/hand_impacts.tres")
	hand_impact.max_polyphony=2
	hand_impact.bus=StorySession.IMPACT_BUS
	add_child(hand_impact)
	hitter=athlete(START,"e97937")
	hitter.apply_profile(setter.attributes.duplicate())
	hitter.set_height_cm(193.04)
	register_student(setter,2)
	preload("res://scripts/practice_kit.gd").apply(hitter,false)
	for hoop in targets:
		hoop.hide()
		for collider in hoop.find_children("*","StaticBody3D",true,false):
			collider.collision_layer=0
	for overlay in get_children():
		if overlay.get_script()==preload("res://scripts/tryout_player_ring.gd"):
			overlay.extra_jumps[hitter]=attack_jump
			overlay.setting_cues=false
	energy[hitter]=hitter.stamina
	attack_jump.front_limit=3.65
	attack_jump.attack_arm_lift=true
	super.start_drill()
	if scene_file_path=="res://scenes/attacking_camp.tscn" and not has_meta("live_sampler"):
		attack_blocker_count=clampi(int(StorySession.game_options.get_value("attack","blockers",1)),0,3)
		for i in 3:
			var actor := athlete(Vector3((1-i)*2.15,START.y,BallNet.NET_Z+.38),"286881")
			register_student(actor,7-i)
			preload("res://scripts/practice_kit.gd").apply(actor,false,7-i)
			actor.set_height_cm(195.58)
			actor.rotation.y=PI
			practice_blockers.append(actor)
			practice_footwork.append(preload("res://scripts/directional_footwork.gd").new(actor))
		refresh_practice_blockers()
		if "--control-attacker" in OS.get_cmdline_user_args():
			cpu_hitter=false
			update_prompts(phase)
	if has_meta("live_sampler"): return
	var review := "--review-swings" in OS.get_cmdline_user_args()
	var arm_swing := review or "--edit-arm-swing" in OS.get_cmdline_user_args()
	var arm_lift := arm_swing or "--edit-arm-lift" in OS.get_cmdline_user_args()
	if (arm_lift or "--edit-approach" in OS.get_cmdline_user_args()) and not Engine.has_meta("approach_editor_opened"):
		Engine.set_meta("approach_editor_opened",true)
		edit_approach_frames.call_deferred(arm_lift,arm_swing,false,review,true)

func camp_title() -> String:
	return "ATTACKING   /   APPROACH AND SPIKE"

func update_prompts(_next: String) -> void:
	var entries := [["View","Take control" if cpu_hitter else "Watch CPU attack"]]
	if not cpu_hitter: entries.append_array([["LS","Move"],["LT","Lock on / shuffle"],["RT","Sprint"],[JOY_BUTTON_X,"Hold left"],[JOY_BUTTON_Y,"Hold middle"],[JOY_BUTTON_B,"Hold right"],[JOY_BUTTON_LEFT_SHOULDER,"Roll"],[JOY_BUTTON_RIGHT_SHOULDER,"Tip"]])
	entries.append(["D-pad Up/Down","Set height: %d" % height_preset()])
	entries.append([JOY_BUTTON_START,"Settings"])
	Xbox.prompts(controls_row,entries)

func begin(next: String) -> void:
	if next=="drop" and not has_meta("live_sampler"): attack_floor_pending=true
	if next=="set_contact" and is_instance_valid(hitter) and height_preset()==0:
		trace("zero_set_arrival",{"air_height_m":hitter.position.y-START.y,"air_age_s":attack_jump.elapsed-attack_jump.load_duration() if attack_jump.active else -1.})
	super.begin(next)

func play_attack_setup() -> void:
	for i in practice_blockers.size():
		practice_jumps[i]=null
		practice_blockers[i].position=Vector3((1-i)*2.15,START.y,BallNet.NET_Z+.38)
		practice_blockers[i].play_action("idle")
	setter.position=setter_station
	feed_started=false
	reset_feed()

func reset_feed() -> void:
	practice_attempted=[false,false,false]
	practice_touch=false
	contact_report=""
	attack_decided=false
	touched_by_middle=false
	disguise_read=shot_read.confidence>.54 and rotation_drill.random.randf()<.58
	clear_attack_input()
	active_lane=attack_lane
	active_set=next_set
	var shift := coach_station-rotation_drill.basket.position
	if not shift.is_zero_approx():
		rotation_drill.basket.position+=shift
		for stored in rotation_drill.stock: stored.position+=shift
		coach.position=rotation_drill.basket.to_global(rotation_drill.HANDLE)
	super.reset_feed()
	camp_call=active_lane
	approach_started=false
	swing_time=-1.
	message.text="Coach toss"
	if not cpu_hitter or not feed_started:
		hitter.position=hitter_start if scene_file_path=="res://scenes/attacking_camp.tscn" else Vector3(START.x*lane_offset(),START.y,START.z)
		hitter.rotation.y=0.
	else:
		hitter.position.y=START.y
	feed_started=true
	hitter.play_action("idle")
	attack_jump.active=false

func set_destination(origin: Vector3, aim: Vector3, height_index: int) -> Vector3:
	var airborne := setter.position.y-BASE.y>.12
	var carry: Vector3=jump.horizontal_velocity() if airborne and jump.active else Vector3.ZERO
	var contact: Vector3=setter.reachable_set(origin,aim+active_set-PINS[active_lane],airborne,carry,attack_set_duration(height_index))
	contact.y=planned_attack_contact_height()
	return contact

func select_attack_touch() -> void:
	var bumper := -1 if held_bumpers.is_empty() else int(held_bumpers.back())
	roll_shot=bumper==JOY_BUTTON_LEFT_SHOULDER
	tip_shot=bumper==JOY_BUTTON_RIGHT_SHOULDER

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.button_index in [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN] and not settings.visible and not get_tree().paused:
		if event.pressed:
			var direction := 1 if event.button_index==JOY_BUTTON_DPAD_UP else -1
			var next_height := clampi(height_preset()+direction,0,SET_HEIGHTS.size()-1)
			save_set_height(SET_HEIGHTS[next_height])
			trace("set_height_change",{"button":event.button_index,"preset":height_preset()})
		get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadButton:
		for bumper in [JOY_BUTTON_LEFT_SHOULDER,JOY_BUTTON_RIGHT_SHOULDER]:
			if event.button_index!=Xbox.physical(bumper): continue
			held_bumpers.erase(bumper)
			if event.pressed: held_bumpers.append(bumper)
			if not cpu_hitter and not settings.visible and not get_tree().paused:
				if manual_shot>=0 and not is_finite(release_at): select_attack_touch()
				get_viewport().set_input_as_handled()
				return
	if not settings.visible and not get_tree().paused:
		if (event is InputEventJoypadButton and event.button_index==JOY_BUTTON_BACK or event is InputEventKey and event.physical_keycode==KEY_TAB) and event.is_pressed() and not event.is_echo():
			clear_attack_input()
			cpu_hitter=not cpu_hitter
			update_prompts(phase)
			get_viewport().set_input_as_handled()
			return
		var simulated := event is InputEventJoypadButton and event.device==CPU_PAD_DEVICE
		if (not cpu_hitter or simulated) and phase in ["cart","feed","pass","set_contact","set"] and not event.is_echo():
			for index in SHOT_BUTTONS.size():
				var button: bool=event is InputEventJoypadButton and event.button_index==Xbox.physical(SHOT_BUTTONS[index])
				var key: bool=event is InputEventKey and event.physical_keycode==[KEY_SPACE,KEY_Y,KEY_B][index]
				if not (button or key): continue
				attack_button(index,event.is_pressed())
				get_viewport().set_input_as_handled()
				return
		if event is InputEventJoypadButton and event.button_index!=Xbox.physical(JOY_BUTTON_START): return
		if event is InputEventKey and event.physical_keycode!=KEY_ESCAPE: return
	super._input(event)

func attack_button(index: int, pressed: bool) -> void:
	if pressed:
		if manual_shot!=index: aim_center=Vector2.INF
		manual_shot=index
		select_attack_touch()
		release_at=INF
		release_grade=INF
	elif manual_shot==index:
		release_grade=button_timing_error()
		release_at=clock
		ContactTiming.window("Attack",attack_meter_error(),EARLY_LIMIT,LATE_LIMIT,-CLEAN_EARLY,CLEAN_LATE)
		show_attack_timing(attack_meter_error())
		trace("attack_release",{"shot":index,"meter_error_ms":roundi(attack_meter_error()*1000.),"button_ms":roundi(release_grade*1000.),"approach_delay_ms":roundi(approach_delay*1000.),"approach":approach_started})
		if not approach_started and (phase!="set" or attack_meter_error()<EARLY_LIMIT or attack_meter_error()>LATE_LIMIT): manual_shot=-1

func cpu_pad_button(index: int, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device=CPU_PAD_DEVICE
	event.button_index=Xbox.physical(SHOT_BUTTONS[index])
	event.pressed=pressed
	_input(event)

func drive_cpu_attack() -> void:
	if phase=="pass" and manual_shot<0:
		var lane := 0 if bounce_line or not cross_court else (1 if spikes%4==1 else 2)
		cpu_pad_button(lane,true)
	elif phase in ["set_contact","set"] and manual_shot>=0 and not is_finite(release_at):
		if button_timing_error()+GRADE_ADVANCE>=0.:
			cpu_pad_button(manual_shot,false)

func step_practice(delta: float) -> void:
	var steps := maxi(1,ceili(delta*90.)) if phase=="set" else 1
	var dt := delta/steps
	for i in steps:
		step_attack(dt)
		smooth_wrists(dt)

func smooth_wrists(delta: float) -> void:
	var rig: Skeleton3D=hitter.skeleton
	for side in ["l","r"]:
		var id := rig.find_bone("hand_"+side)
		var rest := rig.get_bone_rest(id).basis.get_rotation_quaternion()
		if not wrist_axes.has(side):
			var along := rig.get_bone_rest(rig.find_bone("middle_01_"+side)).origin.normalized()
			var across := rig.get_bone_rest(rig.find_bone("index_01_"+side)).origin-rig.get_bone_rest(rig.find_bone("pinky_01_"+side)).origin
			wrist_axes[side]=[along,across.slide(along).normalized()]
		var q := preload("res://scripts/spike_wrist_motion.gd").constrain(rig.get_bone_pose_rotation(id),wrist_history.get(side,rest),rest,wrist_axes[side][0],wrist_axes[side][1],delta)
		if side=="r" and approach_started and attack_jump.active:
			var lock := smoothstep(-.04,.045,attack_jump.elapsed-attack_jump.load_duration())
			if phase=="spike": lock*=1.-smoothstep(PALM_CONTACT,.20,swing_time-contact_swing_time)
			q=q.slerp(preload("res://scripts/spike_wrist_motion.gd").straight_right(rig),lock)
		rig.set_bone_pose_rotation(id,q)
		wrist_history[side]=q

var manual_route := Vector3.ZERO
var prep_velocity := Vector3.ZERO
var bounce_line := false

func placement_skill() -> float:
	return clampf(hitter.effective_rating("Spike placement")*.01,0.,1.)

func aim_radius() -> float:
	return lerpf(1.35,.20,placement_skill())

func initial_attack_aim() -> Vector2:
	var lane_x: float=[3.75,0.,-3.75][manual_shot]
	return Vector2(lane_x,BallNet.NET_Z+4.5)

func steer_attack_aim(delta: float) -> void:
	if aim_center==Vector2.INF: aim_center=initial_attack_aim()
	var depth := -axis(JOY_AXIS_LEFT_Y)
	var strength := signf(depth)*maxf(0.,(absf(depth)-.16)/.84)
	var lateral := -axis(JOY_AXIS_LEFT_X)
	var lane := initial_attack_aim().x
	var lateral_input := signf(lateral)*maxf(0.,(absf(lateral)-.16)/.84)
	aim_center.x=clampf(aim_center.x+lateral_input*lerpf(1.5,3.,placement_skill())*delta,lane-2.5,lane+2.5)
	aim_center.y=clampf(aim_center.y+strength*lerpf(6.,13.,placement_skill())*delta,4.65,BallNet.NET_Z+9.+3.048)

func team_controls_approach() -> bool:
	return false

func step_attack(delta: float) -> void:
	step_practice_blockers(delta)
	if cpu_hitter and not has_meta("sampling_attack"): drive_cpu_attack()
	if not cpu_hitter and approach_started and phase=="set" and manual_shot>=0 and not is_finite(release_at):
		steer_attack_aim(delta)
	if attack_jump.active:
		# Bell can send the set wider or tighter after the hitter commits.
		# Adjust the remaining drive while the hitter can still push off the floor.
		if approach_started and phase in ["set_contact","set"] and quick_set_in_flight() and attack_jump.elapsed < attack_jump.load_duration():
			var actual := endpoint
			var correction := (actual-planned_contact).slide(Vector3.UP).limit_length(.45)
			attack_jump.approach_lunge=attack_jump.approach_lunge.move_toward(planned_lunge+correction,2.4*delta)
		attack_jump.step(hitter,delta,Vector2.ZERO)
		hitter.position.z-=BallNet.pose_retreat(hitter,-1.)
	else:
		hitter.animator.advance(delta)
		var stick := Vector2(axis(JOY_AXIS_LEFT_X),axis(JOY_AXIS_LEFT_Y)).limit_length(1.)
		var steering := not cpu_hitter and stick.length()>.16
		var lock_on := not cpu_hitter and GroundControls.focus(axis)
		var tracking := cpu_hitter or (manual_shot>=0 and (phase=="set" or (rep_set_percent()<60. and phase in ["pass","set_contact"])) and not steering)
		var recovering := cpu_hitter and phase in ["spike","between","drop"] and not attack_jump.active
		if not team_controls_approach() and (recovering or (tracking and not approach_started and phase in ["cart","feed","pass","set_contact","set"])):
			var entry := GroundControls.attack_staging(active_set)
			entry.x+=1.18*lane_offset()
			if scene_file_path=="res://scenes/attacking_camp.tscn": entry=hitter_start
			entry.y=START.y
			if phase in ["set_contact","set"]:
				entry=endpoint+Vector3(1.18*lane_offset(),0.,-2.65)
				entry.y=START.y
				if not cpu_hitter:
					var to_set := (endpoint-hitter.position).slide(Vector3.UP)
					if manual_route.is_zero_approx():
						manual_route=to_set.normalized()
						prep_velocity=Vector3.ZERO
					# Close excess distance along the approach line; reserve room for the plant.
					entry=hitter.position+manual_route*maxf(0.,to_set.dot(manual_route)-2.85)
			elif phase=="pass" and height_preset()==0:
				entry=active_set+Vector3(.6*lane_offset(),0.,-2.65)
				entry.y=START.y
			elif phase=="pass" and not cpu_hitter:
				var pin: Vector3=active_set
				var offset := (pin-hitter.position).slide(Vector3.UP)
				entry=hitter.position+offset.normalized()*maxf(0.,offset.length()-2.85)
			
			var far := float(attack_jump.approach_recovery(hitter,(endpoint-hitter.position).slide(Vector3.UP).length())) if phase=="set" else 0.
			var pace := lerpf(5.8 if cpu_hitter else 4.3,6.2,far) if phase=="set" or (phase=="pass" and height_preset()==0) else (3.8 if cpu_hitter else 1.85)
			var desired := ((entry-hitter.position)*(6. if not cpu_hitter else 4.)).limit_length(pace)
			prep_velocity=prep_velocity.move_toward(desired,lerpf(8. if cpu_hitter else 13.,20.,far)*delta)
			var travel := prep_velocity*delta
			hitter.position=rotation_drill.move_actor(hitter,travel)
			var watch := (ball.position-hitter.position).slide(Vector3.UP)
			if cpu_hitter: watch=GroundControls.forward_sight(watch)
			elif not lock_on: watch=manual_route
			if watch.length_squared()>.01:
				hitter.rotation.y=rotate_toward(hitter.rotation.y,atan2(watch.x,watch.z),3.5*delta)
			var local := hitter.basis.inverse()*prep_velocity
			if not cpu_hitter and not lock_on and local.length()>2.35:
				hitter.play_ground_gait(local.length())
			else:
				hitter.play_action("idle",.20)
			if not shuffle_steps.has(hitter):
				shuffle_steps[hitter]=preload("res://scripts/directional_footwork.gd").new(hitter)
			if cpu_hitter or lock_on or local.length()<=2.35: shuffle_steps[hitter].step((local/2.).limit_length(1.),delta,clampf(local.length()/2.,.55,1.35),true,true)
		if not tracking and (not approach_started or phase!="set"):
			var amount := clampf((stick.length()-.16)/.84,0.,1.)
			var right := camera.global_basis.x.slide(Vector3.UP).normalized()
			var direction := (right*stick.x+right.cross(Vector3.UP)*stick.y).normalized()
			var sprinting: bool=steering and GroundControls.sprint(axis) and hitter.stamina.can_sprint()
			var desired := direction*amount*GroundControls.speed(lock_on,sprinting)
			prep_velocity=prep_velocity.move_toward(desired,18.*delta)
			hitter.position=rotation_drill.move_actor(hitter,prep_velocity*delta)
			if steering:
				manual_route=Vector3.ZERO
			if lock_on:
				GroundControls.face(hitter,(ball.position if ball.visible else coach.position)-hitter.position,delta)
			elif steering: GroundControls.face(hitter,direction,delta,7.)
			if sprinting and prep_velocity.length()>.12:
				hitter.stamina.spend(hitter.stamina.SPRINT_DRAIN*delta,"Sprint")
			if lock_on: hitter.play_action("idle",.22)
			else: hitter.play_ground_gait(prep_velocity.length())
			if not shuffle_steps.has(hitter): shuffle_steps[hitter]=preload("res://scripts/directional_footwork.gd").new(hitter)
			GroundControls.shuffle(hitter,shuffle_steps[hitter],prep_velocity,lock_on,delta)
	if phase=="spike":
		elapsed+=delta
		swing_time+=delta
		pose_swing()
		advance_spike(delta)
		if roll_time>=.5 or (rebound_age>=.85 and not (cpu_hitter and bounce_line)):
			rotation_drill.free_ball(drop_velocity)
			begin("between")
		return
	if not approach_started and (has_meta("sampling_attack") or manual_shot>=0):
		if phase=="pass" and (rep_set_percent()<60. or not cpu_hitter):
			var predicted_pin := active_set
			predicted_pin.y=planned_attack_contact_height()
			var set_time := attack_set_duration(chosen_tempo())
			if height_preset()==0:
				var rise := attack_jump.flight_duration(effective_attack_height(),true)*.48
				set_time=minf(set_time,rise-SET_RECEIVE_TIME-SET_PUSH_TIME-.09)
			plan_attack_plant(maxf(0.,contact_time-elapsed)+SET_RECEIVE_TIME+SET_PUSH_TIME+set_time,predicted_pin,delta)
		elif phase=="set_contact":
			plan_attack_plant(maxf(0.,SET_RECEIVE_TIME+push_time-elapsed)+flight_time,endpoint,delta)
	super.step_practice(delta)
	if phase=="pass": message.text="Coach toss to setter"
	if phase=="set_contact": message.text="Setter contact"

func plan_attack_plant(remaining: float,destination: Vector3,delta: float) -> void:
	if approach_started: return
	var rise := attack_jump.flight_duration(effective_attack_height(),true)*.48
	var distance := (destination-hitter.position).slide(Vector3.UP).length()
	var steps := 3
	var cadence := 1.
	if not cpu_hitter:
		if distance<1.25: steps=2
		elif distance>2.25: steps=4
	cadence=lerpf(1. if cpu_hitter else .94,.76,attack_jump.approach_recovery(hitter,distance))
	var load_time := cadence*((steps-2)*attack_jump.LEAD_STEP_TIME+PLANT_TIME)
	var plant_start := load_time+rise+.025

	if distance<=3.35 and (has_meta("sampling_attack") or manual_shot>=0) and remaining<=plant_start:
		if not approach_started:
			approach_delay=maxf(0.,load_time+rise+.025-remaining-delta)
			start_approach(steps,cadence,destination)

func start_approach(steps := 3, cadence := 1.,destination := Vector3.INF) -> void:
	if approach_started: return
	if not destination.is_finite(): destination=endpoint
	camp_swing.last_shoulder_time=-1.
	camp_swing.reach_assist=Vector3.ZERO
	closest_spike_gap=INF
	approach_started=true
	hitter.stamina.spend(5,"Jump")
	var contact_stance := Vector3(destination.x+.09,.04,destination.z-.09)
	if not cpu_hitter and not manual_route.is_zero_approx():
		contact_stance=Vector3(destination.x,START.y,destination.z)-manual_route*.09
	var heading := (contact_stance-hitter.position).slide(Vector3.UP).normalized()
	hitter.rotation.y=atan2(heading.x,heading.z)
	attack_jump.begin(hitter,Vector2(-heading.x,heading.z),contact_stance,PLANT_TIME*cadence,jump_height,steps,false,cadence,false,.38)
	planned_contact=destination
	planned_lunge=attack_jump.approach_lunge
	attack_jump.attack_entry_speed=maxf(0.,prep_velocity.dot(heading))
	var to_ball := (destination-hitter.position).slide(Vector3.UP)
	if not to_ball.is_zero_approx(): attack_jump.lead_heading=to_ball.normalized()
	attack_jump.release()
	if cpu_hitter and allow_cpu_soft_attack() and not tip_shot and not roll_shot:
		var contact := destination
		contact.y=minf(contact.y,attack_contact_height())
		var landing := shot_landing(contact)
		# The launched ball follows the palm, which can be below the planned set.
		contact.y-=ATTACK_CONTACT_RADIUS
		var net_hit := predicted_net_hit(contact,landing)
		var stamina_left: float = hitter.stamina.fraction()
		var conserve := stamina_left<=.30 or (bounce_line and stamina_left<=.50)
		if conserve or not net_hit.is_empty():
			tip_shot=not bounce_line and (landing-contact).slide(Vector3.UP).length()<4.
			roll_shot=not tip_shot
			trace("cpu_soft_attack",{"tip":tip_shot,"stamina":hitter.stamina.fraction(),"contact_height":contact.y})

func allow_cpu_soft_attack() -> bool:
	return true

func roll_reach_fraction() -> float:
	var origin := strike_point if phase=="spike" else endpoint
	var distance := (shot_landing(origin)-origin).slide(Vector3.UP).length()
	return smoothstep(2.,10.,distance)

func arm_speed_factor() -> float:
	if tip_shot: return .90
	if roll_shot:
		return lerpf(.84,1.08,roll_reach_fraction())
	var effort := float(review_setup.get("power",drill_hit_speed))
	return pow(effort/14.,.48)*lerpf(.70,1.20,preload("res://scripts/swing_speed.gd").arm(hitter))

func requested_set_arc() -> float:
	return super.requested_set_arc()*rep_set_percent()*.01

func effective_attack_height() -> float:
	return attack_jump.assisted_height*attack_jump.takeoff_effectiveness if attack_jump.active else jump_height*hitter.stamina.effectiveness()

func attack_speed() -> float:
	var effort := float(review_setup.get("power",drill_hit_speed))
	return preload("res://scripts/swing_speed.gd").kmh(hitter)/3.6*(effort/14.)

static func soft_shot_duration(origin: Vector3, landing: Vector3, tip_shot: bool) -> float:
	var horizontal := (landing-origin).slide(Vector3.UP).length()
	var flight := clampf(horizontal/(5.4 if tip_shot else 7.),.65,1.65)
	var fraction := (BallNet.NET_Z-origin.z)/maxf(.01,landing.z-origin.z)
	if fraction>0. and fraction<1.:
		var lift := BallNet.NET_TOP+Contact.BALL_RADIUS+.18-lerpf(origin.y,landing.y,fraction)
		flight=maxf(flight,sqrt(2.*maxf(0.,lift)/((9.81 if tip_shot else 11.81)*fraction*(1.-fraction))))
	return flight

func attack_flight_time(origin: Vector3, landing: Vector3) -> float:
	if roll_shot or tip_shot: return soft_shot_duration(origin,landing,tip_shot)
	var flight := maxf(.05,origin.distance_to(landing)/(attack_speed()*attack_jump.spike_power_factor()))
	if landing.z>BallNet.NET_Z and origin.z<BallNet.NET_Z:
		var fraction := (BallNet.NET_Z-origin.z)/(landing.z-origin.z)
		var rise := BallNet.NET_TOP+Contact.BALL_RADIUS+.04-lerpf(origin.y,landing.y,fraction)
		if rise>0.:
			var gravity := 9.81-shot_spin_force(origin,landing,flight).y
			flight=maxf(flight,sqrt(2.*rise/(gravity*fraction*(1.-fraction))))
	return flight

func swing_can_contact() -> bool:
	return swing_time>=.055 and swing_time<=.30

func handle_attack_contact(previous: Vector3,delta: float) -> bool:
	message.text="Approach and spike"
	var remaining := attack_reference_time()-elapsed
	plan_attack_plant(flight_time-elapsed,endpoint,delta)
	if approach_started and swing_time<0. and remaining<=.16/arm_speed_factor()+(.095 if not has_meta("sampling_attack") else 0.): swing_time=0.
	if swing_time<0. and attack_jump.active and attack_jump.elapsed>attack_jump.load_duration():
		pose_swing()
	if swing_time>=0.:
		swing_time+=delta
		pose_swing()
		var palm := Contact.joint(hitter,"middle_03_r") if tip_shot else Contact.palm(hitter,"r")
		var nearest := Geometry3D.get_closest_point_to_segment(palm,previous,ball.position)
		var contact_open := swing_can_contact()
		if contact_open:
			closest_spike_gap=minf(closest_spike_gap,nearest.distance_to(palm))
		var at_set_target := has_meta("sampling_attack") or (ball.position-endpoint).slide(Vector3.UP).length()<=.25
		if at_set_target and contact_open and nearest.distance_to(palm)<=ATTACK_CONTACT_RADIUS:
			if not is_finite(first_palm_at): first_palm_at=clock
			var grade := release_grade+GRADE_ADVANCE
			var valid_release := manual_shot>=0 and is_finite(release_at) and grade>=EARLY_LIMIT and grade<=LATE_LIMIT
			if valid_release:
				contact_grade=grade
				show_attack_timing(grade)
				placement_offset=Vector2.from_angle(rotation_drill.random.randf()*TAU)*sqrt(rotation_drill.random.randf())*aim_radius()
				var severity := smoothstep(CLEAN_LATE if grade>0. else CLEAN_EARLY,LATE_LIMIT if grade>0. else -EARLY_LIMIT,absf(grade))
				depth_error=(-1. if grade>0. else 1.)*severity*rotation_drill.random.randf_range(0.,12. if grade>0. else 8.)
			elif not has_meta("sampling_attack"):
				if elapsed<contact_deadline(): return false
				return miss_attack()
			hard_spike_floor_pending=not tip_shot and not roll_shot and attack_speed()*attack_jump.spike_power_factor()>=Contact.HARD_SPIKE_SPEED
			attack_floor_pending=true
			if not tip_shot and not has_meta("live_sampler"):
				hand_impact.volume_db=-2. if hard_spike_floor_pending else (-10. if roll_shot else -6.)
				hand_impact.play()
				spike_sound_count+=1
			contact_swing_time=swing_time
			strike_point=ball.position
			strike_shoulder_offset=hitter.skeleton.to_local(strike_point)-hitter.skeleton.get_bone_global_pose(hitter.skeleton.find_bone("upperarm_r")).origin
			spikes+=1
			success=true
			feedback="Tip" if tip_shot else "Roll shot" if roll_shot else "Spike"
			message.text=feedback
			gym.update_board(spikes)
			contact_offset=striking_palm_offset()
			ball.position=palm+contact_offset
			net_clear_time=-1.
			var landing := shot_landing(ball.position)
			var shot_time := attack_flight_time(ball.position,landing)
			drop_velocity=(landing-ball.position)/shot_time+Vector3.UP*(4.905*shot_time)
			roll_time=-1.
			trace("spike",{"ball_contact":str(strike_point),"intended_contact":str(endpoint),"set_marker":str(active_set),"tip_shot":tip_shot,"roll_shot":roll_shot,"from":str(ball.position),"palm_gap":nearest.distance_to(palm),"contact_grade_ms":roundi(contact_grade*1000.) if is_finite(contact_grade) else null,"approach_delay_ms":roundi(approach_delay*1000.),"button_ms":roundi(release_grade*1000.) if is_finite(release_grade) else null})
			spend_swing_stamina()
			begin("spike")
			return true
	if elapsed>=contact_deadline(): return miss_attack()
	return false

func contact_deadline() -> float:
	return flight_time

func miss_attack() -> bool:
	coach_react("miss")
	trace("spike_miss",{"cpu_hitter":cpu_hitter,"stamina":hitter.stamina.value,"set_height_percent":set_arc_percent,"planned_contact":str(planned_contact),"closest_palm_gap_m":closest_spike_gap if is_finite(closest_spike_gap) else -1.,"ball":str(ball.position),"palm":str(Contact.palm(hitter,"r"))})
	feedback="Missed spike"
	if not cpu_hitter:
		if is_finite(release_grade) and (release_grade+GRADE_ADVANCE<EARLY_LIMIT or release_grade+GRADE_ADVANCE>LATE_LIMIT):
			feedback+="   /   Released too early" if release_grade+GRADE_ADVANCE<EARLY_LIMIT else "   /   Released too late"
		elif is_finite(release_grade) and closest_spike_gap>ATTACK_CONTACT_RADIUS: feedback+="   /   Out of reach"
		elif not is_finite(release_grade): feedback+="   /   No release"
	message.text=feedback
	success=false
	drop_velocity=(endpoint-source-Vector3.UP*4.*set_arc_height)/flight_time
	spend_swing_stamina()
	begin("drop")
	return true

func spend_swing_stamina() -> void:
	if swing_time>=0.:
		hitter.stamina.spend(TIP_STAMINA_COST if tip_shot else ROLL_STAMINA_COST if roll_shot else SPIKE_STAMINA_COST,"Tip" if tip_shot else "Roll shot" if roll_shot else "Spike")

func striking_palm_offset() -> Vector3:
	if tip_shot:
		return Contact.palm(hitter,"r").direction_to(Contact.joint(hitter,"middle_03_r"))*Contact.BALL_RADIUS
	var fingers := Contact.joint(hitter,"middle_01_r")-Contact.joint(hitter,"hand_r")
	var edge := Contact.joint(hitter,"pinky_01_r")-Contact.joint(hitter,"index_01_r")
	return fingers.cross(edge).normalized()*Contact.BALL_RADIUS

func attack_spin_axis(direction: Vector3, spin: int) -> Vector3:
	var top := Vector3.UP.cross(direction).normalized()
	if spin in [1,2]:
		return (top*.8+Vector3.UP*(-.6 if spin==1 else .6)).normalized()
	return top

func advance_missed_ball(delta: float,rebound_floor := false) -> void:
	super.advance_missed_ball(delta,rebound_floor or phase=="drop")

func projected_landing() -> Vector3:
	if phase=="spike" and launched_attack and roll_time<0. and drop_net_hit.is_empty() and not replay_inspector.active and ball.position.y>.15:
		var flight := preload("res://scripts/pass_flight.gd").landing_time(ball.position,drop_velocity,maxf(.1,9.81-spin_acceleration.y))
		return ball.position+drop_velocity*flight+spin_acceleration*.5*flight*flight
	return super.projected_landing()

func advance_spike(delta: float) -> void:
	var age := swing_time-contact_swing_time
	if age<=PALM_CONTACT+.00001:
		ball.position=(Contact.joint(hitter,"middle_03_r") if tip_shot else Contact.palm(hitter,"r"))+striking_palm_offset()
		var landing := shot_landing(strike_point)
		var flight := attack_flight_time(ball.position,landing)
		spin_acceleration=shot_spin_force(ball.position,landing,flight)
		drop_velocity=launch_velocity(ball.position,landing,flight,spin_acceleration)
		return
	if not launched_attack:
		launched_attack=true
		if drop_velocity.z>.1:
			var observers: Array=get("blockers") if "blockers" in self else practice_blockers
			for defender in observers: defender.block_read(hitter).record_velocity(drop_velocity)
		trace("spike_launch",{"origin":str(ball.position),"velocity":str(drop_velocity),"aim":str(aim_center)})
	var incoming_basis := ball.basis
	var in_flight := roll_time<0.
	var forward := drop_velocity.slide(Vector3.UP).normalized()
	var descent := drop_velocity.y
	if in_flight: drop_velocity+=spin_acceleration*delta
	var previous_ball_position := ball.global_position
	var had_net_contact := not drop_net_hit.is_empty()
	advance_missed_ball(delta,true)
	if not practice_blockers.is_empty() and not practice_touch and drop_net_hit.is_empty():
		practice_touch=resolve_block_contact(previous_ball_position,practice_jumps)
	if rebound_age>=0.: rebound_age+=delta
	elif descent<0. and drop_velocity.y>0. and ball.position.y<.45:
		rebound_age=0.
		trace("spike_floor_rebound",{"up_mps":drop_velocity.y})
	if not had_net_contact and not drop_net_hit.is_empty():
		trace("spike_net_contact",{"point":str(drop_net_hit.point),"kind_of_hit":drop_net_hit.kind,"over":drop_net_hit.rollover})
		if not cpu_hitter and not drop_net_hit.rollover:
			var was_clean := contact_grade>=-CLEAN_EARLY and contact_grade<=CLEAN_LATE
			if was_clean: contact_grade=CLEAN_LATE+.001
			show_player_timing(hitter,"Late" if was_clean else "Net",Color("f25454"))
	if not drop_net_hit.is_empty() or roll_time>=0. or (descent<0. and drop_velocity.y>0.): spin_acceleration=Vector3.ZERO
	if in_flight and roll_time<0. and not forward.is_zero_approx():
		var spin := int(review_setup.get("spin",0))
		var axis := attack_spin_axis(forward,spin)
		var rate := [32.,26.,26.,0.,-18.]
		ball.basis=Basis(axis,(4. if tip_shot else float(rate[spin]))*delta)*incoming_basis
	if net_clear_time<0. and ball.position.z>=4.+Contact.BALL_RADIUS and ball.position.y>2.43+Contact.BALL_RADIUS:
		net_clear_time=swing_time
		if not cpu_hitter and drop_net_hit.is_empty() and contact_grade>=-CLEAN_EARLY and contact_grade<=CLEAN_LATE:
			show_attack_timing(contact_grade,true)

func shot_spin_force(origin: Vector3, landing: Vector3, flight: float) -> Vector3:
	if tip_shot: return Vector3.ZERO
	if roll_shot: return Vector3.DOWN*2.
	var direction := origin.direction_to(landing).slide(Vector3.UP).normalized()
	var speed := origin.distance_to(landing)/flight
	var spin := int(review_setup.get("spin",0))
	var axis: Vector3=[Vector3.DOWN,Vector3.DOWN*.8+direction.cross(Vector3.UP)*.6,Vector3.DOWN*.8+Vector3.UP.cross(direction)*.6,Vector3.ZERO,Vector3.UP][spin]
	return axis*(minf(3.,speed*.20) if spin==4 else minf(22.,speed*.78))

func launch_velocity(origin: Vector3, landing: Vector3, flight: float, spin: Vector3) -> Vector3:
	return (landing-origin)/flight+(Vector3.UP*9.81-spin)*(.5*flight)

func predicted_attack_origin() -> Vector3:
	if is_finite(first_palm_at): return Contact.palm(hitter,"r")+striking_palm_offset()
	var shoulder := Contact.joint(hitter,"upperarm_r")
	var elbow := Contact.joint(hitter,"lowerarm_r")
	var wrist := Contact.joint(hitter,"hand_r")
	var reach := shoulder.y-hitter.global_position.y+shoulder.distance_to(elbow)+elbow.distance_to(wrist)+wrist.distance_to(Contact.palm(hitter,"r"))
	var contact_age := maxf(elapsed,flight_time-.08)
	# Follow the descending set to the first height reachable during this jump.
	for i in 25:
		var t := lerpf(contact_age,flight_time,i/24.)
		var air := clampf((attack_jump.elapsed+t-elapsed-attack_jump.load_duration())/maxf(.001,attack_jump.flight_duration(effective_attack_height(),true)),0.,1.)
		var top := START.y+reach+4.*effective_attack_height()*preload("res://scripts/setter_jump.gd").COURT_VERTICAL_SCALE*air*(1.-air)+Contact.BALL_RADIUS
		var point := arc(source,endpoint,t/flight_time,set_arc_height)
		if point.y<=top: return point
	return Vector3(endpoint.x,minf(endpoint.y,START.y+reach+effective_attack_height()*preload("res://scripts/setter_jump.gd").COURT_VERTICAL_SCALE),endpoint.z)

func predicted_net_hit(origin: Vector3, landing: Vector3) -> Dictionary:
	var flight := attack_flight_time(origin,landing)
	var spin := shot_spin_force(origin,landing,flight)
	var velocity := launch_velocity(origin,landing,flight,spin)
	var acceleration := spin+Vector3.DOWN*9.81
	var path := func(t: float) -> Vector3: return origin+velocity*t+acceleration*(.5*t*t)
	return BallNet.first_hit(path,0.,flight)

func predicted_shot_color(origin: Vector3, landing: Vector3) -> Color:
	var hit := predicted_net_hit(origin,landing)
	if not hit.is_empty(): return Color("ffdc58") if hit.rollover else Color("f25454")
	if absf(landing.x)>4.5 or landing.z>BallNet.NET_Z+9.: return Color("ff953d")
	return Color("61ed88")

func shot_landing(origin: Vector3) -> Vector3:
	if not cpu_hitter and manual_shot>=0:
		var aim := initial_attack_aim() if aim_center==Vector2.INF else aim_center
		if roll_shot or tip_shot:
			aim+=placement_offset*.5
			return Vector3(aim.x,Contact.BALL_RADIUS,maxf(BallNet.NET_Z+.65,aim.y+depth_error*.08))
		aim+=placement_offset
		return Vector3(aim.x,Contact.BALL_RADIUS,maxf(origin.z+.45,aim.y+depth_error))
	if not review_setup.is_empty():
		return Vector3(-float(review_setup.get("x",-3.4))+placement_offset.x,Contact.BALL_RADIUS,maxf(BallNet.NET_Z+.45,float(review_setup.get("z",11.))+placement_offset.y+depth_error))
	return Vector3(-3.4 if cross_court else clampf(origin.x,-3.8,3.8),Contact.BALL_RADIUS,11.)

func pose_swing() -> void:
	apply_attack_swing()
	hitter.position.z-=BallNet.pose_retreat(hitter,-1.)

func apply_attack_swing() -> void:
	var origin := strike_point if phase=="spike" else ball.position
	camp_swing.apply(hitter,attack_jump,phase,swing_time,contact_swing_time,ball.global_position,source,endpoint,strike_point,
		shot_landing(origin),strike_shoulder_offset,effective_attack_height(),arm_speed_factor(),attack_speed(),
		spike_pike_scale,int(review_setup.get("spin",0)),net_clear_time,roll_shot,tip_shot,roll_reach_fraction() if roll_shot else 0.)

func frame_editor_attacker() -> Node3D:
	return hitter

func edit_approach_frames(arm_lift := false, arm_swing := false, cross := false, review := false, resume_target := false) -> void:
	var setup := StorySession.load_drill_setup("swing_review") if arm_swing else {}
	if arm_swing and not review and not resume_target: setup.x=3.4 if cross else -3.4
	var result: Dictionary=await sample_attack_clip(arm_lift,arm_swing,cross,review,setup)
	StorySession.edit_entry=result.entry
	StorySession.edit_animation=result.clip
	StorySession.animation_draft.clear()
	settings.leave_for_frame_editor()
	MenuPresentation.load_scene("res://scenes/animation_editor.tscn")

func sample_attack_clip(arm_lift: bool,arm_swing: bool,cross: bool,review: bool,setup: Dictionary) -> Dictionary:
	set_meta("sampling_attack",true)
	review_setup=setup.duplicate()
	jump_height=float(setup.get("jump",33.))*.0254
	cross_court=float(setup.get("x",3.4 if cross else -3.4))>0.
	# Warm up from the first step so the editor inherits the live plant pose.
	hitter.position=START+Vector3(setup.get("set_x",0.),0.,setup.get("set_z",0.))
	hitter.rotation.y=0.
	hitter.animator.stop()
	hitter.skeleton.reset_bone_poses()
	camp_swing.last_elbow=Quaternion.IDENTITY
	camp_swing.last_shoulder=Quaternion.IDENTITY
	hitter.play_action("idle",0.)
	hitter.animator.advance(0.)
	endpoint=START+Vector3(-.18,0.,2.20)
	endpoint+=Vector3(review_setup.get("set_x",0.),0.,review_setup.get("set_z",0.))
	approach_started=false
	attack_jump.active=false
	start_approach()
	var recording := preload("res://scripts/match_replay.gd").new()
	var takeoff := attack_jump.load_duration()
	var first_frame := floori((takeoff-.15)*60.) if arm_lift else 0
	var duration := takeoff+.25 if arm_lift else takeoff
	if arm_swing:
		duration=(first_frame+107)/60.
		first_frame=0
		cpu_hitter=true
		flight_time=DURATION[1]
	swing_time=-1.
	if arm_lift:
		phase="set"
		source=setter.position+Vector3.UP*(setter.height_cm*.01+.12)
		endpoint.y=2.65+ATTACK_SET_LIFT+jump_height-JUMP_HEIGHT
	var editor_impacts: Array[Dictionary]=[]
	var last_impact := {}
	var hit_frame := -1
	wrist_history.clear()
	var count := ceili(duration*60.)
	for i in range(count+1):
		if has_meta("live_sampler") and i>0 and i%8==0: await get_tree().process_frame
		var time := minf(i/60.,duration)
		if i>0:
			if attack_jump.active: attack_jump.step(hitter,time-(i-1)/60.,Vector2.ZERO)
			else: hitter.animator.advance(1./60.)
		if arm_lift:
			var remaining := takeoff+attack_jump.flight_duration(effective_attack_height(),true)*.48+.025-time
			if arm_swing and phase in ["spike","drop"]:
				swing_time+=1./60.
				pose_swing()
				if phase=="spike": advance_spike(1./60.)
				else: advance_missed_ball(1./60.,true)
			else:
				var previous := ball.position
				ball.position=arc(source,endpoint,clampf(1.-remaining/DURATION[1],0.,1.),APEX[1])
				if arm_swing:
					elapsed=flight_time-remaining
					handle_attack_contact(previous,1./60.)
					if phase=="spike": hit_frame=i-first_frame
				elif time>takeoff: pose_swing()
		smooth_wrists(1./60.)
		if phase=="spike" and not drop_net_hit.is_empty() and drop_net_hit!=last_impact:
			last_impact=drop_net_hit
			var event := drop_net_hit.duplicate()
			var offset := time-first_frame/60.-drop_net_time
			event.time+=offset
			event.release_time+=offset
			editor_impacts.append(event)
		if i<first_frame: continue
		var bones: Array[Transform3D]=[]
		for id in hitter.skeleton.get_bone_count():
			bones.append(hitter.skeleton.get_bone_pose(id))
		recording.frames.append({"time":time-first_frame/60.,"ball":ball.global_transform,"actors":[{"root":hitter.transform,"bones":bones}]})
	var title := "Takeoff and arm lift" if arm_lift else "Three-step approach and backswing"
	if arm_swing: title="Cross-court swing" if cross else "Down-the-line swing"
	recording.index=0
	var clip := recording.bake_recorded_actor(hitter,0,title,recording.frames.size()-1,arm_lift)
	clip.remove_meta("contact_time")
	if arm_lift: clip.set_meta("editor_initial_frame",15)
	clip.set_meta("editor_height_cm",hitter.height_cm)
	var edit_entry :={"id":"camp_attack_arm_lift" if arm_lift else "camp_spike_approach","name":title,"category":"Attacking","type":"Approach"}
	if arm_swing:
		clip.set_meta("editor_net_impacts",editor_impacts)
		clip.set_meta("swing_hit_frame",hit_frame)
		edit_entry={"id":"camp_right_arm_swing","name":title,"category":"Attacking","type":"Spike"}
		edit_entry["aim_x"]=review_setup.get("x",-3.4)
		clip.set_meta("editor_group","Right Arm")
		clip.set_meta("swing_frame_offset",floori((takeoff-.15)*60.))
		clip.set_meta("editor_initial_frame",0)
		clip.set_meta("editor_loop_start",0)
	if arm_swing:
		edit_entry["swing_review"]=true
		clip.set_meta("editor_net_impacts",editor_impacts)
		clip.set_meta("swing_hit_frame",hit_frame)
	remove_meta("sampling_attack")
	return {"entry":edit_entry,"clip":clip}

func resolve_block_contact(previous: Vector3,block_jumps: Array, attack_direction := 1.) -> bool:
	if attack_decided: return false
	var best := {}
	var slot := -1
	for n in block_jumps.size():
		var candidate:RefCounted=block_jumps[n]
		if candidate==null: continue
		var hit:Dictionary=candidate.first_block_touch(previous,ball.global_position,Contact.BALL_RADIUS)
		if hit.is_empty() or (not best.is_empty() and hit.fraction>=best.fraction): continue
		best=hit
		slot=n
	if best.is_empty(): return false
	var block:RefCounted=block_jumps[slot]
	var segment:int=best.segment
	var key:int=slot*2+best.side if best.arm else -1-slot*2-best.side
	var side_index:int=best.side if best.arm or segment==0 else -1
	var body_part:String=best.part
	var result:Dictionary=block.block_rebound(best,drop_velocity,attack_direction)
	var stuff:bool=result.stuff
	ball.global_position=best.point
	drop_velocity=result.velocity
	set_meta("block_impact_segment",Vector2i(key,segment))
	spin_acceleration = Vector3.ZERO
	set_meta("blocked_attack",true)
	hand_impact.volume_db=-2.
	hand_impact.play()
	block_sound_count+=1
	var role: String=["Right-side","Middle","Left-side"][slot] if block_jumps==practice_jumps else ["Left-side","Middle","Right-side"][slot]
	var limb := "" if side_index<0 else ("left" if side_index==0 else "right")
	contact_report="%s blocker / %s" % [role,(limb+" "+body_part).strip_edges()]
	message.text=contact_report
	show_player_timing(block.actor,contact_report,Color.WHITE)
	touched_by_middle=slot==1
	last_block_result.text=("Stuff block / " if stuff else "Block touch / ")+contact_report
	last_block_result.show()
	trace("block_hand_contact",{"rep":rep,"blocker":role,"arm":limb,"segment":body_part,"stuff":stuff,"outgoing":str(drop_velocity)})
	return true
