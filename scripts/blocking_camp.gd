extends "res://scripts/attacking_camp.gd"

const Block = preload("res://scripts/match_block.gd")
var blocker: Node3D
var block: RefCounted
var next_lane := 0
var attempted := false
var deflected := false
var automatic_block := true

func start_drill() -> void:
	blocker = athlete(Vector3(0., START.y, BallNet.NET_Z + .38), "286881")
	blocker.rotation.y = PI
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
	attack_lane = next_lane
	next_set = PINS[attack_lane]
	next_lane = (next_lane + 1) % 3
	block = null
	attempted = false
	deflected = false
	blocker.position.y = START.y
	blocker.play_action("idle")
	super.reset_feed()

func jump_rep() -> bool:
	return true

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
					elif not automatic_block and block == null:
						begin_block()
				get_viewport().set_input_as_handled()
				return
	super._input(event)

func begin_block() -> void:
	block = Block.new()
	block.begin(blocker)
	attempted = true

func step_attack(delta: float) -> void:
	if block != null:
		if not block.step(delta,ball.global_position):
			block = null
	else:
		var goal := clampf(endpoint.x,-4.3,4.3) if phase == "set" else 3.65*lane_offset()
		var previous := blocker.position.x
		if automatic_block:
			blocker.position.x = move_toward(previous,goal,4.8*delta)
		else:
			blocker.position.x = clampf(previous + axis(JOY_AXIS_LEFT_X)*camera.global_basis.x.x*4.8*delta,-4.5,4.5)
		blocker.animator.advance(delta)
		if not shuffle_steps.has(blocker):
			shuffle_steps[blocker] = preload("res://scripts/directional_footwork.gd").new(blocker)
		shuffle_steps[blocker].step(Vector3((previous-blocker.position.x)/maxf(delta*4.8,.0001),0,0),delta,1.,true,true)
		if automatic_block and not attempted and phase == "set" and flight_time-elapsed <= Block.START+Block.AIR*.5:
			begin_block()
	super.step_attack(delta)

func advance_spike(delta: float) -> void:
	var previous := ball.global_position
	super.advance_spike(delta)
	if block == null or deflected or not launched_attack or not drop_net_hit.is_empty(): return
	for i in block.hands.size():
		var closest := Geometry3D.get_closest_points_between_segments(previous,ball.global_position,block.wrists[i],block.hands[i])
		if closest[0].distance_to(closest[1]) > Contact.BALL_RADIUS + .065: continue
		drop_velocity.z = -absf(drop_velocity.z)*.55
		drop_velocity.y = minf(-1.,drop_velocity.y*.5)
		spin_acceleration = Vector3.ZERO
		deflected = true
		message.text = "Block touch"
		break
