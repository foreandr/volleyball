extends "res://scripts/crosscourt_attack_demo.gd"

const Block = preload("res://scripts/match_block.gd")
const HOMES := [-2.15,0.,2.15]
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
var read_set := false
var closing := [false,false,true]
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
	var pivot := Vector3(0.,1.0,BallNet.NET_Z+4.)
	var pitch := deg_to_rad(clampf(45.+(elevation-18.)*.45,30.,60.))
	var arm := Vector3(-sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*distance
	var eye := pivot+arm
	eye=eye.clamp(Vector3(-10.8,.5,-10.5),Vector3(10.8,8.45,14.35))
	var hit := contacts.sweep(world,contacts.camera_shape,pivot,eye-pivot,Contact.GYM)
	camera.position=pivot+(eye-pivot)*float(hit.get("fraction",1.))
	camera.look_at(pivot)
	# Fit both near baseline corners with a margin at the actual viewport aspect.
	var aspect := camera.get_viewport().get_visible_rect().size.aspect()
	var tangent := tan(deg_to_rad(52.)*.5)
	for x in [-4.5,4.5]:
		var point := camera.to_local(Vector3(x,.05,BallNet.NET_Z+9.))
		if point.z<-.05:
			tangent=maxf(tangent,maxf(absf(point.y),absf(point.x)/aspect)/-point.z*1.12)
	camera.fov=clampf(rad_to_deg(2.*atan(tangent)),52.,115.)

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
	read_set=false
	closing=[false,false,true]
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
						elif block_held and phase=="set":
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
	if phase=="cart":
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
		jump.min_hand_x=(blockers[slot-1].position.x+actor.position.x)*.5+.09 if slot>0 else -INF
		jump.max_hand_x=(blockers[slot+1].position.x+actor.position.x)*.5-.09 if slot<2 else INF
		jump.court_aim=Vector3(0.,0.,BallNet.NET_Z-3.)
		if not jump.step(delta,ball.global_position): jumps[slot]=null
		return
	var goal: float=HOMES[slot]
	var depth_goal := BallNet.NET_Z+.38
	if phase=="set" and not read_set:
		var available := maxf(0.,flight_time-elapsed-Block.START-Block.AIR*.5)
		for i in 2:
			var seam := clampf(endpoint.x,1.6,4.25)-.61*(2-i)
			var travel := Vector2(seam-blockers[i].position.x,depth_goal-blockers[i].position.z).length()
			closing[i]=maxf(0.,travel-.35)/GroundControls.speed(true,false)+.14<=available
		read_set=true
		trace("block_set_read",{"far_closes":closing[0],"middle_closes":closing[1],"available_s":available})
	if phase=="set":
		if closing[slot]: goal=clampf(endpoint.x,1.6,4.25)-.61*(2-slot)
		else: depth_goal+=2.7
	elif phase=="spike" and not closing[slot]:
		depth_goal+=2.7
	var previous := actor.position.x
	var cpu := automatic_block or slot!=MANUAL_SLOT or phase!="set"
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
	if cpu and closing[slot] and not attempted[slot] and phase=="set" and absf(actor.position.x-endpoint.x)<1.65 and flight_time-elapsed<=Block.START+Block.AIR*.5:
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
