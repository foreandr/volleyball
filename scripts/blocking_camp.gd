extends "res://scripts/crosscourt_attack_demo.gd"

const Block = preload("res://scripts/match_block.gd")
const HOMES := [-2.15,0.,2.15]
const MANUAL_SLOT := 2
const ROUTES := [Vector3(3.65,2.65,2.7),Vector3(.4,2.65,3.25),Vector3(-.65,2.65,1.45),Vector3(-3.65,2.65,2.7)]
var attackers: Array[Node3D]=[]
const ROUTE_NAMES := ["left","51","pipe","right"]
var random_heights := bool(StorySession.game_options.get_value("blocking","random_heights",false))
var drawn_height := -1
var route_tempos := [2,1,1,2]
var read_delay := .08
var read_x := 0.
var read_lead := 1

func height_preset() -> int:
	return drawn_height if drawn_height>=0 else super.height_preset()

var middle_read_attempted := false
var route := -1
func rep_set_percent() -> float:
	if drawn_height>=0: return SET_HEIGHTS[drawn_height]
	return SET_HEIGHTS[1] if route in [1,2] else super.rep_set_percent()

var blockers: Array[Node3D] = []
var jumps := [null,null,null]
var lateral_speed := [0.,0.,0.]
var attempted := [false,false,false]
var block_sound_count := 0
var deflected := false
var block_held := false
var manual_shuffle_open := false
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

var block_vertical := float(StorySession.game_options.get_value("blocking","vertical_inches",roundf(Block.HEIGHT/.0254)))
var aim_six := false
var read_set := false
var closing := [false,false,true]
var height_control := HSlider.new()
var height_label := Label.new()

func start_drill() -> void:
	# Gameplay trajectories use team-local coordinates. Swap court ends relative
	# to the gym while keeping the net contact mesh in simulation coordinates.
	var switch_ends := Transform3D(Basis(Vector3.UP,PI),Vector3(0.,0.,2.*BallNet.NET_Z))
	var net := gym.get_node("DynamicNet") as Node3D
	var net_pose := net.global_transform
	gym.transform=switch_ends
	net.global_transform=net_pose
	for node in world.get_children():
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
	var randomize_button := CheckButton.new()
	randomize_button.text="Random set height"
	randomize_button.tooltip_text="Draw a new height from 0 to 3 on each feed"
	randomize_button.button_pressed=random_heights
	row.add_child(randomize_button)
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
	return 30.

func allow_cpu_soft_attack() -> bool:
	return false

func reset_feed() -> void:
	manual_shuffle_open=false
	middle_read_attempted=false
	if route<0: attackers.push_front(hitter)
	var former := hitter
	route=rotation_drill.random.randi_range(0,attackers.size()-1)
	for lane in ROUTES.size():
		route_tempos[lane]=rotation_drill.random.randi_range(0,3) if random_heights else (1 if lane in [1,2] else super.height_preset())
	drawn_height=route_tempos[route] if random_heights else -1
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
	block_load.cancel()
	meter_until=-1.
	block_held=false
	for i in blockers.size():
		lateral_speed[i]=0.
		jumps[i]=null
		attempted[i]=false
		blockers[i].position.y=START.y
		blockers[i].play_action("idle")
	super.reset_feed()
	var random := rotation_drill.random as RandomNumberGenerator
	var depth := 4.5 if random.randf()<.8 else random.randf_range(4.,5.)
	var target_x := 4.5-random.randf_range(0.,1.)
	aim_six=not aim_six
	if aim_six: target_x=random.randf_range(-.5,.5)
	if route==3 and not aim_six: target_x=-target_x
	review_setup.x=target_x if active_lane==2 else -target_x
	review_setup.z=BallNet.NET_Z+depth
	cross_court=false
	bounce_line=false
	trace("block_drill_target",{"lane":"six" if aim_six else "line","target_x":target_x,"depth_m":depth})

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
						apply_camera()
						update_prompts(phase)
					elif jump_pressed and not automatic_block:
						if event.is_pressed() and not block_held and jumps[MANUAL_SLOT]==null:
							block_held=true
							block_load.begin(blockers[MANUAL_SLOT])
						elif not event.is_pressed() and block_held:
							released_meter=block_meter()
							meter_until=clock+.65
							var depth := clampf(block_load.seconds/block_load.FULL_LOAD,0.,1.)
							block_held=false
							block_load.cancel()
							if jumps[MANUAL_SLOT]==null: begin_block(MANUAL_SLOT,depth)
				get_viewport().set_input_as_handled()
				return
	super._input(event)

func begin_block(slot: int,loaded := 0.) -> void:
	var jump := Block.new()
	var stamina=blockers[slot].stamina
	if stamina.exhausted or attempted[slot]: return
	jump.jump_height=block_vertical*.0254*stamina.effectiveness()
	stamina.spend(5,"Block jump")
	trace("block_takeoff",{"slot":slot,"vertical_m":jump.jump_height,"stamina":stamina.value})
	jump.aggressive_press=true
	jump.begin(blockers[slot])
	jump.age=Block.START*loaded
	jumps[slot]=jump
	attempted[slot]=true
	if read_set and slot==read_lead and slot!=1 and closing[1] and jumps[1]==null:
		begin_block(1,loaded)

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

func step_attack(delta: float) -> void:
	if phase=="pass" and not manual_shuffle_open and ball.position.distance_to(catch_point)<=1.:
		manual_shuffle_open=true
		trace("manual_block_shuffle_open",{"distance_m":ball.position.distance_to(catch_point)})
	for i in attackers.size():
		if i==route and (attack_jump.active or (phase=="set" and approach_started) or phase=="spike"): continue
		step_hitting_line(i,delta)
	for i in blockers.size():
		step_blocker(i,delta)
	if phase=="cart":
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
			trace("blockers_home",{"positions":str([blockers[0].position,blockers[1].position,blockers[2].position])})
	super.step_attack(delta)

func step_blocker(slot: int,delta: float) -> void:
	var actor := blockers[slot]
	var jump: RefCounted = jumps[slot]
	if jump!=null:
		if slot==MANUAL_SLOT and not automatic_block:
			jump.lean_input=axis(JOY_AXIS_LEFT_X)*camera.global_basis.x.normalized().x
			jump.reach_input=Vector2(axis(Xbox.trigger(true)),axis(Xbox.trigger(false))).clamp(Vector2.ZERO,Vector2.ONE)
		jump.min_hand_x=(blockers[slot-1].position.x+actor.position.x)*.5+.09 if slot>0 else -INF
		jump.max_hand_x=(blockers[slot+1].position.x+actor.position.x)*.5-.09 if slot<2 else INF
		jump.court_aim=Vector3(0.,0.,BallNet.NET_Z-3.)
		if not jump.step(delta,ball.global_position): jumps[slot]=null
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
		read_lead=2 if read_x>1.85 else (0 if read_x< -1.85 else 1)
		var available := maxf(0.,flight_time-elapsed-Block.START-Block.AIR*.5)
		for i in blockers.size():
			var seam := read_x+.61*(i-read_lead)
			var travel := Vector2(seam-blockers[i].position.x,depth_goal-blockers[i].position.z).length()
			closing[i]=maxf(0.,travel-.75)/GroundControls.speed(true,false)<=available or i==read_lead
		read_set=true
		trace("block_set_read",{"set_route":ROUTE_NAMES[route],"route_tempos":route_tempos.duplicate(),"read_x":read_x,"set_height_percent":rep_set_percent(),"set_endpoint":str(endpoint),"far_closes":closing[0],"middle_closes":closing[1],"available_s":available})
	if phase=="set" and read_set:
		if read_lead==2 and slot==1 and closing[slot]: goal=blockers[MANUAL_SLOT].position.x-.61
		elif closing[slot]: goal=read_x+.61*(slot-read_lead)
		else: depth_goal+=2.7
	elif phase=="spike" and not closing[slot]:
		depth_goal+=2.7
	var previous := actor.position.x
	var manual_window := phase in ["set_contact","set"] or (phase=="pass" and manual_shuffle_open)
	var cpu := automatic_block or slot!=MANUAL_SLOT or not manual_window
	var pace := GroundControls.speed(true,false)
	var desired := clampf((goal-previous)*4.,-pace,pace) if cpu else axis(JOY_AXIS_LEFT_X)*camera.global_basis.x.x*pace
	lateral_speed[slot]=move_toward(lateral_speed[slot],desired,8.*delta)
	var low := -4.5 if slot==0 else blockers[slot-1].position.x+.61
	var high := 4.5 if slot==2 else blockers[slot+1].position.x-.61
	var motion := Vector2(lateral_speed[slot],(depth_goal-actor.position.z)*4.).limit_length(pace)*delta
	actor.position.x=clampf(previous+motion.x,low,high)
	actor.position.z+=motion.y
	actor.animator.advance(delta)
	if not shuffle_steps.has(actor):
		shuffle_steps[actor]=preload("res://scripts/directional_footwork.gd").new(actor)
	if slot==MANUAL_SLOT and block_held:
		block_load.update(actor,delta)
		block_load.ring.hide()
	GroundControls.shuffle(actor,shuffle_steps[actor],Vector3((actor.position.x-previous)/maxf(delta,.0001),0.,motion.y/maxf(delta,.0001)),true,delta)
	if read_set and (slot!=1 or read_lead==1) and cpu and closing[slot] and not attempted[slot] and phase=="set" and absf(actor.position.x-read_x)<1.65 and flight_time-elapsed<=Block.START+Block.AIR*.5:
		begin_block(slot)

func advance_spike(delta: float) -> void:
	var previous := ball.global_position
	super.advance_spike(delta)
	if deflected or not launched_attack or not drop_net_hit.is_empty(): return
	for block: RefCounted in jumps:
		if block==null: continue
		for i in block.hands.size():
			var chain := [block.shoulders[i],block.elbows[i],block.wrists[i],block.hands[i]]
			var touched := false
			var stuff := false
			var hit_position := Vector3.ZERO
			for segment in [2,1,0]:
				var closest := Geometry3D.get_closest_points_between_segments(previous,ball.global_position,chain[segment],chain[segment+1])
				var gap := closest[0].distance_to(closest[1])
				if gap <= Contact.BALL_RADIUS+Block.ARM_RADII[segment]:
					touched=true
					hit_position=closest[0]
					stuff=segment==2 and gap<.13 and closest[1].y>BallNet.NET_TOP+.10 and closest[1].z<BallNet.NET_Z-.04
					break
			if not touched: continue
			ball.global_position=hit_position
			if stuff:
				drop_velocity=hit_position.direction_to(block.court_aim)*drop_velocity.length()*.55
			else:
				var side := signf(hit_position.z-BallNet.NET_Z)
				if is_zero_approx(side): side=signf(drop_velocity.z)
				drop_velocity=Vector3(clampf(drop_velocity.x*.20-hit_position.x*.28,-2.8,2.8),clampf(drop_velocity.length()*.23,3.2,5.8),side*clampf(absf(drop_velocity.z)*.19,1.9,4.4))
			spin_acceleration = Vector3.ZERO
			deflected = true
			block_sound_count+=1
			set_meta("blocked_attack",true)
			hand_impact.volume_db=-2.
			hand_impact.play()
			trace("block_hand_contact",{"rep":rep,"stuff":stuff,"outgoing":str(drop_velocity)})
			message.text = "Block touch"
			return
