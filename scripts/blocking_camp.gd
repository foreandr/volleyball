extends "res://scripts/crosscourt_attack_demo.gd"

const Block = preload("res://scripts/match_block.gd")
const HOMES := [-3.,0.,3.]
const MANUAL_SLOT := 2
var blockers: Array[Node3D] = []
var jumps := [null,null,null]
var lateral_speed := [0.,0.,0.]
var attempted := [false,false,false]
var deflected := false
var automatic_block := true

func start_drill() -> void:
	for x: float in HOMES:
		var actor := athlete(Vector3(x,START.y,BallNet.NET_Z+.38),"286881")
		actor.rotation.y=PI
		blockers.append(actor)
	super.start_drill()

func camp_title() -> String:
	return "BLOCKING   /   BLOCK AT THE NET"

func update_prompts(_next: String) -> void:
	var entries := [["View", "Control blocker" if automatic_block else "Watch CPU block"]]
	if not automatic_block:
		entries.append_array([["LS","Shuffle"],[JOY_BUTTON_A,"Block"]])
	entries.append(["D-pad Up/Down","Set height: %d" % height_preset()])
	entries.append([JOY_BUTTON_START,"Settings"])
	Xbox.prompts(controls_row,entries)

func reset_feed() -> void:
	attack_lane = 0
	next_set = Vector3(3.65,2.65,3.)
	deflected=false
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
	review_setup.x=-target_x
	review_setup.z=BallNet.NET_Z+depth
	cross_court=false
	bounce_line=false
	trace("block_drill_target",{"line_offset_m":4.5-target_x,"depth_m":depth})

func _input(event: InputEvent) -> void:
	if not settings.visible and not get_tree().paused:
		if event is InputEventJoypadButton or event is InputEventKey:
			var toggle: bool = event.button_index == JOY_BUTTON_BACK if event is InputEventJoypadButton else event.physical_keycode == KEY_TAB
			var jump_pressed: bool = event.button_index == Xbox.physical(JOY_BUTTON_A) if event is InputEventJoypadButton else event.physical_keycode == KEY_SPACE
			if toggle or jump_pressed:
				if event.is_pressed() and not event.is_echo():
					if toggle:
						automatic_block = not automatic_block
						update_prompts(phase)
					elif not automatic_block and jumps[MANUAL_SLOT] == null:
						begin_block(MANUAL_SLOT)
				get_viewport().set_input_as_handled()
				return
	super._input(event)

func begin_block(slot: int) -> void:
	var jump := Block.new()
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
		if not jump.step(delta,ball.global_position): jumps[slot]=null
		return
	var goal: float=HOMES[slot]
	if phase in ["set_contact","set","spike"]:
		if slot==2: goal=clampf(endpoint.x,1.6,4.25)
		elif slot==1: goal=clampf(endpoint.x-.90,-1.,3.35)
		else: goal=-2.
	var previous := actor.position.x
	var cpu := automatic_block or slot!=MANUAL_SLOT
	var pace := GroundControls.speed(true,false)
	var desired := clampf((goal-previous)*4.,-pace,pace) if cpu else axis(JOY_AXIS_LEFT_X)*camera.global_basis.x.x*pace
	lateral_speed[slot]=move_toward(lateral_speed[slot],desired,8.*delta)
	var low := -4.5 if slot==0 else blockers[slot-1].position.x+.72
	var high := 4.5 if slot==2 else blockers[slot+1].position.x-.72
	actor.position.x=clampf(previous+lateral_speed[slot]*delta,low,high)
	actor.animator.advance(delta)
	if not shuffle_steps.has(actor):
		shuffle_steps[actor]=preload("res://scripts/directional_footwork.gd").new(actor)
	GroundControls.shuffle(actor,shuffle_steps[actor],Vector3((actor.position.x-previous)/maxf(delta,.0001),0.,0.),true,delta)
	if cpu and not attempted[slot] and phase=="set" and absf(actor.position.x-endpoint.x)<1.65 and flight_time-elapsed<=Block.START+Block.AIR*.5:
		begin_block(slot)

func advance_spike(delta: float) -> void:
	var previous := ball.global_position
	super.advance_spike(delta)
	if deflected or not launched_attack or not drop_net_hit.is_empty(): return
	for block: RefCounted in jumps:
		if block==null: continue
		for i in block.hands.size():
			var closest := Geometry3D.get_closest_points_between_segments(previous,ball.global_position,block.wrists[i],block.hands[i])
			if closest[0].distance_to(closest[1]) > Contact.BALL_RADIUS + .065: continue
			drop_velocity.z = -absf(drop_velocity.z)*.55
			drop_velocity.y = minf(-1.,drop_velocity.y*.5)
			spin_acceleration = Vector3.ZERO
			deflected = true
			hand_impact.volume_db=-2.
			hand_impact.play()
			trace("block_hand_contact",{"rep":rep})
			message.text = "Block touch"
			return
