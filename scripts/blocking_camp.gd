extends "res://scripts/crosscourt_attack_demo.gd"

const Block = preload("res://scripts/match_block.gd")
const HOMES := [-3.,0.,3.]
const MANUAL_SLOT := 2
var blockers: Array[Node3D] = []
var jumps := [null,null,null]
var lateral_speed := [0.,0.,0.]
var attempted := [false,false,false]
var deflected := false
var block_held := false
var automatic_block := true
var block_vertical := float(StorySession.game_options.get_value("blocking","vertical_inches",roundf(Block.HEIGHT/.0254)))
var aim_six := false
var middle_reset := true
var far_read := false
var far_closing := false
var height_control := HSlider.new()
var height_label := Label.new()

func start_drill() -> void:
	for x: float in HOMES:
		var actor := athlete(Vector3(x,START.y,BallNet.NET_Z+.38),"286881")
		var variant := 5+blockers.size()
		register_student(actor,variant)
		preload("res://scripts/practice_kit.gd").apply(actor,false,variant)
		energy[actor]=actor.stamina
		actor.rotation.y=PI
		blockers.append(actor)
	super.start_drill()

func build_settings() -> void:
	super.build_settings()
	var row := HBoxContainer.new()
	controls_row.get_parent().add_child(row)
	row.add_child(height_label)
	row.add_child(height_control)
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

func apply_camera() -> void:
	var saved_yaw := yaw
	yaw+=PI
	super.apply_camera()
	yaw=saved_yaw

func camp_title() -> String:
	return "BLOCKING   /   BLOCK AT THE NET"

func update_prompts(_next: String) -> void:
	var entries := [["View", "Control blocker" if automatic_block else "Watch CPU block"]]
	if not automatic_block:
		entries.append_array([["LS","Shuffle"],[JOY_BUTTON_A,"Hold A / release to jump"]])
	entries.append(["D-pad Up/Down","Set height: %d" % height_preset()])
	entries.append([JOY_BUTTON_START,"Settings"])
	Xbox.prompts(controls_row,entries)

func allow_cpu_soft_attack() -> bool:
	return false

func reset_feed() -> void:
	# Supply a full-strength attacker on each blocking rep.
	hitter.stamina.rested_capacity=hitter.stamina.capacity()
	hitter.stamina.value=hitter.stamina.rested_capacity
	hitter.stamina.exhausted=false
	attack_lane = 0
	next_set = Vector3(3.65,2.65,3.)
	middle_reset=true
	far_read=false
	far_closing=false
	deflected=false
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
	review_setup.x=-target_x
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
						block_held=false
						apply_camera()
						update_prompts(phase)
					elif jump_pressed and not automatic_block:
						if event.is_pressed():
							block_held=jumps[MANUAL_SLOT]==null
						elif block_held:
							block_held=false
							if jumps[MANUAL_SLOT]==null: begin_block(MANUAL_SLOT)
				get_viewport().set_input_as_handled()
				return
	super._input(event)

func begin_block(slot: int) -> void:
	var jump := Block.new()
	var stamina=blockers[slot].stamina
	if stamina.exhausted: return
	jump.jump_height=block_vertical*.0254*stamina.effectiveness()
	stamina.spend(5,"Block jump")
	trace("block_takeoff",{"slot":slot,"vertical_m":jump.jump_height,"stamina":stamina.value})
	jump.aggressive_press=true
	jump.begin(blockers[slot])
	jumps[slot]=jump
	attempted[slot]=true

func step_attack(delta: float) -> void:
	for i in blockers.size():
		step_blocker(i,delta)
	super.step_attack(delta)

func step_blocker(slot: int,delta: float) -> void:
	var actor := blockers[slot]
	var jump: RefCounted = jumps[slot]
	if jump!=null:
		jump.min_hand_x=(blockers[slot-1].position.x+actor.position.x)*.5+.09 if slot>0 else -INF
		jump.max_hand_x=(blockers[slot+1].position.x+actor.position.x)*.5-.09 if slot<2 else INF
		jump.court_aim=Vector3(0.,0.,BallNet.NET_Z-3.)
		if not jump.step(delta,ball.global_position): jumps[slot]=null
		return
	var goal: float=HOMES[slot]
	var depth_goal := BallNet.NET_Z+.38
	if slot==1 and absf(actor.position.x)<.12: middle_reset=false
	if phase in ["pass","set_contact","set"]:
		var pin := endpoint.x if phase=="set" else active_set.x
		if slot==2: goal=clampf(pin,1.6,4.25)
		elif slot==1 and not middle_reset: goal=clampf(pin-.61,-1.,3.64)
		elif slot==0:
			var close_x := clampf(pin-1.22,-1.6,3.03)
			if not far_read:
				var available := attack_set_duration(chosen_tempo())
				if phase=="pass": available+=maxf(0.,contact_time-elapsed)
				var travel := Vector2(close_x-actor.position.x,depth_goal-actor.position.z).length()
				far_closing=available-Block.START-Block.AIR*.5 >= travel/GroundControls.speed(true,false)+.18
				far_read=true
				trace("far_block_read",{"close":far_closing,"available":available})
			if far_closing: goal=close_x
			else: depth_goal+=2.7
	elif phase=="spike" and slot==0 and not far_closing:
		depth_goal+=2.7
	var previous := actor.position.x
	var cpu := automatic_block or slot!=MANUAL_SLOT
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
	GroundControls.shuffle(actor,shuffle_steps[actor],Vector3((actor.position.x-previous)/maxf(delta,.0001),0.,motion.y/maxf(delta,.0001)),true,delta)
	if cpu and (slot!=0 or far_closing) and not attempted[slot] and phase=="set" and absf(actor.position.x-endpoint.x)<1.65 and flight_time-elapsed<=Block.START+Block.AIR*.5:
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
			for segment in 3:
				var closest := Geometry3D.get_closest_points_between_segments(previous,ball.global_position,chain[segment],chain[segment+1])
				if closest[0].distance_to(closest[1]) <= Contact.BALL_RADIUS+.065:
					touched=true
					break
			if not touched: continue
			var toward: Vector3=ball.global_position.direction_to(block.court_aim)
			var normal: Vector3=(toward-drop_velocity.normalized()).normalized()
			drop_velocity=drop_velocity.bounce(normal)*.55
			spin_acceleration = Vector3.ZERO
			deflected = true
			hand_impact.volume_db=-2.
			hand_impact.play()
			trace("block_hand_contact",{"rep":rep})
			message.text = "Block touch"
			return
