extends "res://scripts/crosscourt_attack_demo.gd"

const Block = preload("res://scripts/match_block.gd")
const HOMES := [-2.15,0.,2.15]
const MANUAL_SLOT := 2
var ROUTES := [Vector3(3.65,2.65,2.7),Vector3(.4,2.65,3.25),Vector3(-.65,2.65,1.45),Vector3(-3.65,2.65,2.7)]
var attackers: Array[Node3D]=[]
const ROUTE_NAMES := ["left","51","pipe","right"]
var random_heights := bool(StorySession.game_options.get_value("blocking","random_heights",true))
var drawn_height := -1
var route_tempos := [2,1,1,2]
enum AimMode { RANDOM, INTO_BLOCK, AVOID_BLOCK }
var aim_mode := clampi(int(StorySession.game_options.get_value("blocking","aim_mode",0)),0,2)
var aim_committed := false
var read_delay := .08
var read_x := 0.
var read_lead := 1

func height_preset() -> int:
	if route==1: return 0
	return drawn_height if drawn_height>=0 else mini(attack_tempo,1 if route in [1,2] else 2)

var quick_jump := preload("res://scripts/setter_jump.gd").new()
var quick_committed := false
var middle_read_attempted := false
var route := -1
func rep_set_percent() -> float:
	if drawn_height>=0: return SET_HEIGHTS[drawn_height]
	return SET_HEIGHTS[height_preset()]

var blockers: Array[Node3D] = []
var jumps := [null,null,null]
var lateral_speed := [0.,0.,0.]
var attempted := [false,false,false]
var block_sound_count := 0
var deflected := false
var pending_manual_jump := -1.
var block_press_clock := 0.
var block_held := false
var ready_whistled := false
var automatic_block := false
var block_load := preload("res://scripts/tryout_squat.gd").new()
var released_meter := 0.
var meter_until := -1.

func block_meter() -> float:
	if not block_held: return released_meter
	if phase!="set": return 0.
	var load_left := Block.START*(1.-clampf(block_load.seconds/block_load.FULL_LOAD,0.,1.))
	var error := elapsed-flight_time+load_left+Block.AIR*.5
	return clampf(.5+error/.6,0.,1.)

var block_vertical := roundf(Block.HEIGHT/.0254)
var attack_vertical := float(StorySession.game_options.get_value("blocking","attack_vertical",50.))
var attack_tempo := clampi(int(StorySession.game_options.get_value("blocking","attack_tempo",2)),0,2)
var hit_speed := clampf(float(StorySession.game_options.get_value("blocking","hit_speed_mps",30.)),9.,40.)
var randomize_button := CheckButton.new()
var read_set := false
var closing := [false,false,true]
var height_control := HSlider.new()
var height_label := Label.new()

func start_drill() -> void:
	block_vertical=clampf(float(StorySession.game_options.get_value("blocking","vertical_inches",block_vertical)),0.,60.)
	get_viewport().scaling_3d_scale=1.0
	get_viewport().msaa_3d=Viewport.MSAA_2X
	# Gameplay trajectories use team-local coordinates. Swap court ends relative
	# to the gym while keeping the net contact mesh in simulation coordinates.
	var switch_ends := Transform3D(Basis(Vector3.UP,PI),Vector3(0.,0.,2.*BallNet.NET_Z))
	var net := gym.get_node("DynamicNet") as Node3D
	var net_pose := net.global_transform
	gym.transform=switch_ends
	net.global_transform=net_pose
	for node in world.get_children():
		if node is OmniLight3D and absf(node.position.z-BallNet.NET_Z)>1.: node.shadow_enabled=false
		if node is Light3D: node.transform=switch_ends*node.transform
	block_load.configure(world)
	for x: float in HOMES:
		var actor := athlete(Vector3(x,START.y,BallNet.NET_Z+.38),"286881")
		var variant := 5+blockers.size()
		register_student(actor,variant)
		preload("res://scripts/practice_kit.gd").apply(actor,false,variant)
		energy[actor]=actor.stamina
		actor.rotation.y=PI
		blockers.append(actor)
	for i in [1,2,3]:
		var attacker := athlete(ROUTES[i]+Vector3(0.,START.y-2.65,-2.65),"e97937")
		var variant: int=[4,8,9][i-1]
		register_student(attacker,variant)
		preload("res://scripts/practice_kit.gd").apply(attacker,false,variant)
		attacker.set_height_cm(188.)
		attackers.append(attacker)
		energy[attacker]=attacker.stamina
	super.start_drill()
	review_setup.power=attack_speed()
	hitter.set_height_cm(188.)

func build_settings() -> void:
	super.build_settings()
	var row := HBoxContainer.new()
	controls_row.get_parent().add_child(row)
	row.add_child(height_label)
	row.add_child(height_control)
	randomize_button.text="Random set height"
	randomize_button.tooltip_text="Middle: 0. Pipe: 0 or 1. Pins: 0, 1 or 2."
	randomize_button.button_pressed=random_heights
	row.add_child(randomize_button)
	var shot_modes := OptionButton.new()
	for title in ["Random court target","Hit into block","Avoid block"]: shot_modes.add_item(title)
	shot_modes.select(aim_mode)
	shot_modes.item_selected.connect(func(index):
		aim_mode=index
		StorySession.game_options.set_value("blocking","aim_mode",index)
		StorySession.save_options()
	)
	row.add_child(shot_modes)
	randomize_button.toggled.connect(func(enabled):
		random_heights=enabled
		StorySession.game_options.set_value("blocking","random_heights",enabled)
		StorySession.save_options()
	)
	height_control.custom_minimum_size=Vector2(210,30)
	height_control.min_value=0
	height_control.max_value=60
	height_control.step=1
	height_control.value=block_vertical
	height_control.focus_mode=Control.FOCUS_NONE
	height_label.text="Block vertical    %d in" % roundi(block_vertical)
	height_control.value_changed.connect(set_block_vertical)

	var attack_row := HBoxContainer.new()
	controls_row.get_parent().add_child(attack_row)
	var vertical_slider := HSlider.new()
	var vertical_label := Label.new()
	var speed_label := Label.new()
	var speed_slider := HSlider.new()
	for node in [vertical_label,vertical_slider,speed_label,speed_slider]: attack_row.add_child(node)
	for slider in [vertical_slider,speed_slider]:
		slider.custom_minimum_size=Vector2(130,30)
		slider.focus_mode=Control.FOCUS_NONE
		slider.step=1
	vertical_slider.max_value=60
	vertical_slider.value=attack_vertical
	vertical_label.text="Attack vertical  %d in" % attack_vertical
	vertical_slider.value_changed.connect(func(value):
		attack_vertical=value
		vertical_label.text="Attack vertical  %d in" % value
		StorySession.game_options.set_value("blocking","attack_vertical",value)
		StorySession.save_options()
	)
	speed_slider.min_value=9
	speed_slider.max_value=40
	speed_slider.value=hit_speed
	speed_label.text="Hit speed  %d m/s" % hit_speed
	speed_slider.value_changed.connect(func(value):
		hit_speed=value
		review_setup.power=value
		speed_label.text="Hit speed  %d m/s" % value
		StorySession.game_options.set_value("blocking","hit_speed_mps",value)
		StorySession.save_options()
	)

func save_set_height(value: float) -> void:
	attack_tempo=clampi(SET_HEIGHTS.find(value),0,2)
	randomize_button.button_pressed=false
	StorySession.game_options.set_value("blocking","attack_tempo",attack_tempo)
	StorySession.save_options()
	update_prompts(phase)

func set_block_vertical(value: float) -> void:
	block_vertical=value
	height_control.set_value_no_signal(value)
	height_label.text="Block vertical    %d in" % roundi(value)
	StorySession.game_options.set_value("blocking","vertical_inches",value)
	StorySession.save_options()

func frame_editor_blocker() -> Node3D:
	return blockers[MANUAL_SLOT]

func camp_title() -> String:
	return "BLOCKING   /   BLOCK AT THE NET"

func update_prompts(_next: String) -> void:
	var entries := [["View", "Control blocker" if automatic_block else "Watch CPU block"]]
	if not automatic_block:
		entries.append_array([["LS","Shuffle / air lean"],[JOY_BUTTON_A,"Hold A / release to jump"],["LT","Left reach"],["RT","Right reach"]])
	entries.append(["D-pad Up/Down","Set height: %d" % height_preset()])
	entries.append([JOY_BUTTON_START,"Settings"])
	Xbox.prompts(controls_row,entries)

func attack_speed() -> float:
	return hit_speed

func select_attack_touch() -> void:
	roll_shot=false
	tip_shot=false

func allow_cpu_soft_attack() -> bool:
	return false

func reset_feed() -> void:
	ready_whistled=false
	middle_read_attempted=false
	if route<0: attackers.push_front(hitter)
	quick_committed=false
	ROUTES[1].x=.4 if rotation_drill.random.randf()<.5 else 1.8
	var former := hitter
	route=rotation_drill.random.randi_range(0,attackers.size()-1)
	for lane in ROUTES.size():
		var highest := 1 if lane in [1,2] else 2
		route_tempos[lane]=rotation_drill.random.randi_range(0,highest) if random_heights else mini(attack_tempo,highest)
	route_tempos[1]=0
	drawn_height=route_tempos[route]
	jump_height=attack_vertical*.0254
	read_delay=rotation_drill.random.randf_range(.055,.13)
	hitter=attackers[route]
	former.play_action("idle")
	for overlay in get_children():
		if overlay.get_script()==preload("res://scripts/tryout_player_ring.gd"):
			overlay.extra_jumps.erase(former)
			overlay.extra_jumps[hitter]=attack_jump
	wrist_history.clear()
	wrist_axes.clear()
	prep_velocity=Vector3.ZERO
	coach_station=Vector3(-3.1,coach_station.y,-3.)
	attack_jump.front_limit=BallNet.NET_Z-3.05 if route==2 else 3.65
	# Supply a full-strength attacker on each blocking rep.
	hitter.stamina.rested_capacity=hitter.stamina.capacity()
	hitter.stamina.value=hitter.stamina.rested_capacity
	hitter.stamina.exhausted=false
	attack_lane = [0,1,1,2][route]
	next_set = ROUTES[route]
	read_set=false
	closing=[false,false,true]
	deflected=false
	set_meta("blocked_attack",false)
	meter_until=-1.
	for i in blockers.size():
		lateral_speed[i]=0.
		attempted[i]=false
		if jumps[i]!=null or (i==MANUAL_SLOT and block_held): continue
		blockers[i].position.y=START.y
		blockers[i].play_action("idle")
	super.reset_feed()
	var random := rotation_drill.random as RandomNumberGenerator
	review_setup.x=random.randf_range(-4.45,4.45)
	review_setup.z=BallNet.NET_Z+random.randf_range(1.1,8.95)
	aim_committed=false
	cross_court=false
	bounce_line=false

func choose_block_target() -> void:
	aim_committed=true
	if aim_mode==AimMode.RANDOM: return
	var origin := endpoint
	var obstacles: Array[Vector2]=[]
	for slot in blockers.size():
		var actor := blockers[slot]
		if actor.position.z>BallNet.NET_Z+1.2: continue
		var jump: RefCounted=jumps[slot]
		if jump!=null and not jump.hands.is_empty():
			for tip: Vector3 in jump.hands: obstacles.append(Vector2(tip.x,maxf(tip.y,BallNet.NET_TOP+.10)))
		else:
			obstacles.append(Vector2(actor.position.x,BallNet.NET_TOP+.22))
	if obstacles.is_empty(): return
	var best := -INF
	for column in 17:
		for depth in [2.,4.,6.,8.7]:
			var landing := Vector3(lerpf(-4.45,4.45,column/16.),Contact.BALL_RADIUS,BallNet.NET_Z+float(depth))
			var fraction := clampf((BallNet.NET_Z-origin.z)/(landing.z-origin.z),0.,1.)
			var duration := attack_flight_time(origin,landing)
			var spin := shot_spin_force(origin,landing,duration)
			var time := duration*fraction
			var crossing := origin+launch_velocity(origin,landing,duration,spin)*time+(Vector3.DOWN*9.81+spin)*(.5*time*time)
			if crossing.y<BallNet.NET_TOP+Contact.BALL_RADIUS: continue
			var gap := INF
			for hand in obstacles: gap=minf(gap,hand.distance_to(Vector2(crossing.x,crossing.y)))
			var score := gap if aim_mode==AimMode.AVOID_BLOCK else -gap
			if score>best:
				best=score
				review_setup.x=-landing.x
				review_setup.z=landing.z

func _input(event: InputEvent) -> void:
	if not settings.visible and not get_tree().paused:
		if event is InputEventJoypadButton or event is InputEventKey:
			var toggle: bool = event.button_index == JOY_BUTTON_BACK if event is InputEventJoypadButton else event.physical_keycode == KEY_TAB
			var jump_pressed: bool = event.button_index == Xbox.physical(JOY_BUTTON_A) if event is InputEventJoypadButton else event.physical_keycode == KEY_SPACE
			if toggle or jump_pressed:
				if not event.is_echo():
					if toggle and event.is_pressed():
						automatic_block = not automatic_block
						block_load.cancel()
						block_held=false
						pending_manual_jump=-1.
						apply_camera()
						update_prompts(phase)
					elif jump_pressed and not automatic_block:
						if event.is_pressed() and not block_held:
							block_held=true
							block_press_clock=clock
							if jumps[MANUAL_SLOT]==null: block_load.begin(blockers[MANUAL_SLOT])
						elif not event.is_pressed() and block_held:
							released_meter=block_meter()
							meter_until=clock+.65
							var depth := clampf(maxf(block_load.seconds,clock-block_press_clock)/block_load.FULL_LOAD,0.,1.)
							block_held=false
							block_load.cancel()
							if jumps[MANUAL_SLOT]==null: begin_block(MANUAL_SLOT,depth,true)
							else: pending_manual_jump=depth
				get_viewport().set_input_as_handled()
				return
	super._input(event)

func block_read_target(slot: int) -> float:
	var target := read_x if read_set else attackers[1].position.x
	if phase=="spike" and drop_velocity.z>.1:
		var time_to_net := clampf((BallNet.NET_Z-ball.position.z)/drop_velocity.z,0.,.20)
		return ball.position.x+drop_velocity.x*time_to_net
	if read_set and read_lead!=1 and closing[slot]:
		# At a pin each closer owns the next strip of net toward cross court.
		# A third blocker covers two shoulder widths inside the line blocker.
		var inside := signf(-target)
		var cross_width := maxf(0.,BallNet.NET_Z-endpoint.z)*1.5
		return target+inside*minf(.61*absi(slot-read_lead),cross_width)
	if slot==1 and read_set:
		# The middle covers the inside hitting lane alongside the pin blocker.
		return move_toward(target,0.,minf(.50,absf(target)*.28))
	return target

func begin_block(slot: int,loaded := 0.,manual := false) -> void:
	var jump := Block.new()
	var stamina=blockers[slot].stamina
	if not manual and (stamina.exhausted or attempted[slot]): return
	if not manual:
		var actor := blockers[slot]
		var aim_x: float=block_read_target(slot)
		var offset := aim_x-actor.position.x
		var carry := clampf(lateral_speed[slot]*.12,-.24,.24) if read_set else 0.
		var gap := absf(offset-carry)
		if gap>1.10 or actor.position.z>BallNet.NET_Z+.95: return
		if gap>.50:
			var seam_covered := false
			for other in blockers:
				if other==actor or absf(other.position.z-actor.position.z)>.65: continue
				var separation: float=(other.position.x-actor.position.x)*signf(offset)
				if separation>0. and separation<1.4: seam_covered=true
			if seam_covered:
				if gap>.85: return
			else: jump.kong_direction=signf(offset)
	jump.jump_height=block_vertical*.0254*stamina.effectiveness()
	if manual: jump.jump_height=maxf(.10,jump.jump_height)
	stamina.spend(5,"Block jump")
	trace("block_takeoff",{"slot":slot,"vertical_m":jump.jump_height,"stamina":stamina.value})
	jump.net_heading=PI
	jump.aggressive_press=true
	jump.begin(blockers[slot])
	jump.age=Block.START*loaded
	if not manual and jump.kong_direction!=0.: jump.lean_input=jump.kong_direction*.75
	jumps[slot]=jump
	attempted[slot]=true
	if read_set and closing[slot] and slot!=read_lead and not manual:
		var partner := slot+signi(read_lead-slot)
		jump.close_direction=signf(blockers[partner].position.x-blockers[slot].position.x)
	if read_set and slot==read_lead:
		for i in blockers.size():
			if i!=slot and closing[i] and jumps[i]==null and (automatic_block or i!=MANUAL_SLOT):
				begin_block(i,loaded)

var route_velocity := [Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO]

func team_controls_approach() -> bool:
	return true

func ready_spot(i: int) -> Vector3:
	var pin: Vector3=ROUTES[i]
	var outside := 0.55 if i==0 else (-0.55 if i==3 else 0.)
	return Vector3(pin.x+outside,START.y,pin.z-3.45)

func step_hitting_line(i: int,delta: float) -> void:
	var actor := attackers[i]
	var target := ready_spot(i)
	var approach_window := 1.12-.14*float(route_tempos[i])
	var attacking := (phase=="set" and i==route) or phase=="set_contact" or (phase=="pass" and contact_time-elapsed<approach_window)
	if attacking:
		var pin: Vector3=ROUTES[i]
		var progress := 1. if phase in ["set","set_contact"] else clampf(1.-(contact_time-elapsed)/approach_window,0.,1.)
		target=target.lerp(Vector3(pin.x,START.y,pin.z-1.65),progress)
	elif phase in ["set","spike"]:
		if i==route: return
		# Back-row coverage stays deep in six. Opposite pins release inward
		# from their own lane, while the nearby front-row hitter covers short.
		if i==2:
			target=Vector3(clampf(endpoint.x*.22,-1.,1.),START.y,BallNet.NET_Z-5.4)
		else:
			var gap := absf(ROUTES[i].x-endpoint.x)
			target.x=lerpf(ROUTES[i].x,endpoint.x,.32)
			target.z=BallNet.NET_Z-clampf(1.65+gap*.31,1.8,4.1)
	var offset := (target-actor.position).slide(Vector3.UP)
	var velocity: Vector3=route_velocity[i]
	velocity=velocity.move_toward((offset*5.).limit_length(3.8),13.*delta)
	route_velocity[i]=velocity
	if i==route: prep_velocity=velocity
	actor.position=rotation_drill.move_actor(actor,velocity*delta)
	if i!=route or phase=="cart": actor.animator.advance(delta)
	if attacking:
		GroundControls.face(actor,(ROUTES[i]-actor.position).slide(Vector3.UP),delta)
		actor.play_ground_gait(velocity.length())
	else:
		GroundControls.face(actor,ball.position-actor.position,delta)
		actor.play_action("idle",.16)
		if not shuffle_steps.has(actor): shuffle_steps[actor]=preload("res://scripts/directional_footwork.gd").new(actor)
		GroundControls.shuffle(actor,shuffle_steps[actor],velocity,true,delta)

func _process(delta: float) -> void:
	if ready_whistled and not automatic_block and not settings.visible and coach_motion.whistle_cue.signal_time>=0.:
		step_blocker(MANUAL_SLOT,delta)
	super._process(delta)

func step_practice(delta: float) -> void:
	# Cover runners only need one pose per displayed frame. The contact
	# simulation still substeps the ball, striker and active block.
	if phase=="pass" and not quick_committed and contact_time-elapsed<=PLANT_TIME+.32:
		quick_committed=true
		var target := Vector3(ROUTES[1].x,START.y,ROUTES[1].z-.09)
		var runner := attackers[1]
		if route==1:
			if not approach_started: start_approach(3,.84,Vector3(target.x,planned_attack_contact_height(),target.z))
		else:
			var heading := (target-runner.position).slide(Vector3.UP).normalized()
			runner.rotation.y=atan2(heading.x,heading.z)
			quick_jump.attack_arm_lift=true
			quick_jump.front_limit=3.65
			quick_jump.begin(runner,Vector2(-heading.x,heading.z),target,PLANT_TIME*.84,jump_height,3,false,.84,false,.38)
			runner.stamina.spend(5,"Quick decoy jump")
			quick_jump.release()
	for i in attackers.size():
		if i==1 and quick_jump.active:
			quick_jump.step(attackers[i],delta,Vector2.ZERO)
		elif i!=route: step_hitting_line(i,delta)
	super.step_practice(delta)

func step_attack(delta: float) -> void:
	if phase=="set" and not aim_committed and flight_time-elapsed<=.23: choose_block_target()
	if route>=0 and not attack_jump.active and not (phase=="set" and approach_started) and phase!="spike":
		step_hitting_line(route,delta)
	for i in blockers.size():
		step_blocker(i,delta)
	if phase=="cart" and not ready_whistled:
		for i in attackers.size():
			var home := ready_spot(i)
			if elapsed==0. and attackers[i].position.distance_to(home)>.035: return
		for i in blockers.size():
			var home := Vector3(HOMES[i],START.y,BallNet.NET_Z+.38)
			if jumps[i]!=null or blockers[i].position.distance_to(home)>.025: return
		if elapsed==0.:
			for i in blockers.size():
				blockers[i].position=Vector3(HOMES[i],START.y,BallNet.NET_Z+.38)
				lateral_speed[i]=0.
			ready_whistled=true
			coach_motion.whistle_cue.signal_drill(coach)
			trace("blockers_home",{"positions":str([blockers[0].position,blockers[1].position,blockers[2].position])})
	super.step_attack(delta)

func step_blocker(slot: int,delta: float) -> void:
	var actor := blockers[slot]
	var jump: RefCounted = jumps[slot]
	if jump!=null:
		if slot==MANUAL_SLOT and not automatic_block:
			jump.lean_input=axis(JOY_AXIS_LEFT_X)*camera.global_basis.x.normalized().x
			jump.reach_input=Vector2(axis(Xbox.trigger(true)),axis(Xbox.trigger(false))).clamp(Vector2.ZERO,Vector2.ONE)
		jump.min_hand_x=-INF
		jump.max_hand_x=INF
		for other in blockers:
			if other==actor or absf(other.position.z-actor.position.z)>.65: continue
			var offset: float=other.position.x-actor.position.x
			if absf(offset)>1.4: continue
			var seam: float=actor.position.x+offset*.5
			if offset<0.: jump.min_hand_x=maxf(jump.min_hand_x,seam+.09)
			else: jump.max_hand_x=minf(jump.max_hand_x,seam-.09)
		if automatic_block or slot!=MANUAL_SLOT:
			jump.reach_input=Vector2.ZERO
			if jump.shoulders.size()==2 and phase in ["set","spike"]:
				var crossing_x := read_x if phase=="set" and read_set else ball.position.x
				if phase=="spike" and drop_velocity.z>.1:
					var seconds := clampf((actor.position.z-ball.position.z)/drop_velocity.z,0.,.18)
					crossing_x+=drop_velocity.x*seconds
				var miss := crossing_x-actor.position.x
				if jump.kong_direction!=0. and phase=="set": miss=jump.kong_direction*.85
				var open_side: bool=not is_finite(jump.min_hand_x) if miss<0. else not is_finite(jump.max_hand_x)
				if open_side and absf(miss)<1.45:
					var amount := smoothstep(.28,.80,absf(miss))
					var left: bool = (jump.shoulders[0].x-jump.shoulders[1].x)*miss>0.
					jump.reach_input=Vector2(amount,0.) if left else Vector2(0.,amount)
		jump.court_aim=Vector3(0.,0.,BallNet.NET_Z-3.)
		if jump.close_direction!=0. and slot!=read_lead:
			var partner := slot+signi(read_lead-slot)
			var room: float=(blockers[partner].position.x-jump.base.x)*jump.close_direction-.61
			if jump.age>=Block.START and jump.age<Block.START+Block.AIR:
				jump.base.x+=jump.close_direction*minf(maxf(0.,room),.64*delta)
			jump.lean_input=jump.close_direction*.65
		if not jump.step(delta,ball.global_position):
			jumps[slot]=null
			if slot==MANUAL_SLOT and not automatic_block:
				if pending_manual_jump>=0.:
					var load_depth := pending_manual_jump
					pending_manual_jump=-1.
					begin_block(slot,load_depth,true)
				elif block_held: block_load.begin(actor)
		return
	# Read the quick runner's approach once while the pass is still live.
	if slot==1 and phase=="pass" and not middle_read_attempted and contact_time-elapsed<=.10:
		middle_read_attempted=true
		var runner := attackers[1]
		var closing_speed: float=route_velocity[1].z
		if closing_speed>1. and absf(actor.position.x-runner.position.x)<1. and rotation_drill.random.randf()<.35:
			begin_block(1)
			if jumps[1]!=null:
				trace("middle_committed_to_quick",{"runner_speed":closing_speed})
				return
	var goal: float=HOMES[slot]
	var depth_goal := BallNet.NET_Z+.38
	if phase=="set" and not read_set and elapsed>=read_delay:
		var seen_velocity := (ball.position-source)/maxf(elapsed,.001)
		var time_estimate := maxf(0.,flight_time-elapsed)*rotation_drill.random.randf_range(.93,1.07)
		read_x=clampf(ball.position.x+seen_velocity.x*time_estimate,-4.5,4.5)
		read_lead=2 if read_x>2.25 else (0 if read_x< -2.25 else 1)
		var available := maxf(0.,flight_time-elapsed-Block.START-Block.AIR*.5)
		for i in blockers.size():
			var seam := read_x+.61*(i-read_lead)
			var travel := Vector2(seam-blockers[i].position.x,depth_goal-blockers[i].position.z).length()
			closing[i]=maxf(0.,travel-.75)/GroundControls.speed(true,true)<=available or absi(i-read_lead)<=1
		read_set=true
		trace("block_set_read",{"set_route":ROUTE_NAMES[route],"route_tempos":route_tempos.duplicate(),"read_x":read_x,"set_height_percent":rep_set_percent(),"set_endpoint":str(endpoint),"far_closes":closing[0],"middle_closes":closing[1],"available_s":available})
	var late_window := phase=="spike" and elapsed<.18 and ball.position.z<=BallNet.NET_Z+.12 and not deflected
	if (phase=="set" or late_window) and read_set:
		if closing[slot] and slot!=read_lead:
			goal=blockers[read_lead].position.x+.61*(slot-read_lead)
		elif closing[slot]: goal=read_x+.61*(slot-read_lead)
		else: depth_goal+=2.7
	elif phase=="spike" and not closing[slot]:
		depth_goal+=2.7
	var previous := actor.position.x
	var manual_window := ready_whistled and phase!="between"
	var cpu := automatic_block or slot!=MANUAL_SLOT or not manual_window
	var focused := cpu or block_held or GroundControls.focus(axis)
	var sprinting: bool=not cpu and GroundControls.sprint(axis) and actor.stamina.can_sprint()
	var fast_close: bool = cpu and read_set and phase=="set" and closing[slot] and absf(goal-previous)>.65
	var pace := GroundControls.speed(focused,sprinting or fast_close)
	var desired := clampf((goal-previous)*4.,-pace,pace) if cpu else axis(JOY_AXIS_LEFT_X)*camera.global_basis.x.x*pace
	lateral_speed[slot]=move_toward(lateral_speed[slot],desired,(14. if fast_close else 8.)*delta)
	var low := -4.5 if slot==0 else blockers[slot-1].position.x+.61
	var high := 4.5 if slot==2 else blockers[slot+1].position.x-.61
	if not cpu:
		low=-4.5
		high=4.5
	elif slot==1 and not automatic_block and manual_window:
		high=4.5
	var depth_speed := (depth_goal-actor.position.z)*4. if cpu else axis(JOY_AXIS_LEFT_Y)*camera.global_basis.z.z*pace
	var motion := Vector2(lateral_speed[slot],depth_speed).limit_length(pace)*delta
	actor.position.x=clampf(previous+motion.x,low,high)
	actor.position.z=clampf(actor.position.z+motion.y,BallNet.NET_Z+.28,BallNet.NET_Z+9.)
	actor.animator.advance(delta)
	if not shuffle_steps.has(actor):
		shuffle_steps[actor]=preload("res://scripts/directional_footwork.gd").new(actor)
	if slot==MANUAL_SLOT and block_held:
		block_load.update(actor,delta)
		block_load.ring.hide()
	var velocity := Vector3((actor.position.x-previous)/maxf(delta,.0001),0.,motion.y/maxf(delta,.0001))
	if not cpu and not focused:
		GroundControls.face(actor,velocity,delta,6.)
		actor.play_ground_gait(velocity.length())
	elif not cpu:
		if not block_held: actor.play_action("idle",.20)
		var facing := ball.position-actor.position
		var square := 1. if block_held else 1.-smoothstep(.6,1.8,actor.position.z-BallNet.NET_Z)
		var heading := lerp_angle(atan2(facing.x,facing.z),PI,square)
		actor.rotation.y=rotate_toward(actor.rotation.y,heading,delta*6.)
	if sprinting and velocity.length()>.15: actor.stamina.spend(actor.stamina.SPRINT_DRAIN*delta,"Sprint")
	GroundControls.shuffle(actor,shuffle_steps[actor],velocity,focused,delta)
	var last_chance := late_window or (phase=="set" and flight_time-elapsed<=Block.AIR*.5)
	if read_set and (slot==read_lead or attempted[read_lead] or last_chance) and (automatic_block or slot!=MANUAL_SLOT) and cpu and closing[slot] and not attempted[slot] and ((phase=="set" and flight_time-elapsed<=Block.START+Block.AIR*.5) or late_window):
		var preload_fraction := clampf(1.-(flight_time-elapsed-Block.AIR*.5)/Block.START,0.,1.) if phase=="set" else 1.
		begin_block(slot,preload_fraction)

func advance_spike(delta: float) -> void:
	var previous := ball.global_position
	super.advance_spike(delta)
	if deflected or not launched_attack or not drop_net_hit.is_empty(): return
	if resolve_block_contact(previous,jumps):
		deflected=true
		block_sound_count+=1
