extends SceneTree

func _initialize() -> void:
	check.call_deferred()

func check() -> void:
	var camp=load("res://tools/block_charge_fixture.gd").new()
	camp.solo_setting=true
	root.add_child(camp)
	current_scene=camp
	camp.ready_whistled=true
	camp.phase="feed"
	var heights:Array[float]=[]
	var speeds:Array[float]=[]
	var slot:int=camp.MANUAL_SLOT
	var actor:Node3D=camp.blockers[slot]
	var start:=actor.position
	for frames in [0,12,23,45]:
		camp.jumps[slot]=null
		actor.position=start
		camp.lateral_speed[slot]=0.
		var event:=InputEventJoypadButton.new()
		event.button_index=camp.Xbox.physical(JOY_BUTTON_A)
		event.pressed=true
		camp._input(event)
		for frame in frames: camp.step_blocker(slot,1./60.)
		var available:float=camp.block_vertical*.0254*actor.stamina.effectiveness()
		event.pressed=false
		camp._input(event)
		heights.append(camp.jumps[slot].jump_height/available)
	for held in [false,true]:
		camp.jumps[slot]=null
		actor.position=start
		camp.lateral_speed[slot]=0.
		camp.block_held=held
		if held: camp.block_load.begin(actor)
		for frame in 36: camp.step_blocker(slot,1./60.)
		speeds.append(absf(camp.lateral_speed[slot]))
	print("Camp release height fractions ",heights," upright / deep lateral speeds ",speeds)
	camp.jumps[1]=null
	camp.phase="set"
	camp.elapsed=1.
	camp.flight_time=10.
	camp.read_set=true
	camp.read_lead=1
	camp.closing[1]=true
	camp.blockers[0].position.x=-1.
	camp.blockers[2].position.x=1.
	var pinned:=true
	for side in [-1.,1.]:
		camp.read_x=4.*side
		for frame in 100:
			camp.step_blocker(1,1./60.)
			pinned=pinned and absf(camp.blockers[1].position.x)<=.391
		pinned=pinned and absf(camp.blockers[1].position.x-.39*side)<.005
	print("Middle stops shoulder to shoulder at both pins: ",pinned)
	change_scene_to_file("res://scenes/offline_match.tscn")
	await scene_changed
	var match_game=current_scene.game
	if not match_game.manual:
		match_game.manual=load("res://scripts/match_court_controls.gd").new()
		match_game.add_child(match_game.manual)
		match_game.manual.configure(match_game)
	match_game.phase=match_game.Phase.LIVE
	match_game.serve.player=null
	var matched:=true
	for depth in [0.,.5,1.]:
		match_game.blocks.erase(0)
		match_game.manual.block_buffer=depth
		var available:float=match_game.jump_inches(0,match_game.block_vertical,"Block jump")*.0254*match_game.human.stamina.effectiveness()
		match_game.manual.jump_if_ready()
		matched=matched and match_game.blocks.has(0) and absf(match_game.blocks[0].jump_height/available-(.6+.4*depth))<.001
	print("Match block release fractions 60/80/100 verified: ",matched)
	quit(0 if pinned and matched and absf(heights[0]-.6)<.001 and absf(heights[1]-.81)<.005 and absf(heights[2]-1.)<.001 and heights[2]==heights[3] and speeds[1]<speeds[0] else 1)
