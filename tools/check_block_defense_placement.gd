extends SceneTree

func _initialize(): run.call_deferred()
func mouse_button(pos:Vector2,down:bool):
	var input:=InputEventMouseButton.new()
	input.position=pos
	input.button_index=MOUSE_BUTTON_LEFT
	input.pressed=down
	root.push_input(input,true)

func run():
	change_scene_to_file("res://scenes/block_defense_scenario.tscn")
	await scene_changed
	await process_frame
	var page=current_scene
	page.notes_path="res://work/scenario-placement-test.jsonl"
	page.set_process(false)
	var g=page.game
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		var img=root.get_texture().get_image();img.resize(800,450);img.save_png("res://work/scenario-setup-qa.png")
	g.rules_path="res://work/test-ai-target.cfg"
	g.instructions.clear()
	assert(g.spectator and g.manual==null and g.players.size()==12)
	for i in 12: assert(not g.is_human(i))
	g.start_feed(3,1,1,true)
	page.setup={"defense":3,"offense":1,"role":1,"in_system":true}
	page.running=true
	for tick in 20: g.tick_match(1./60.,page.ground)
	var paused_ball:Vector3=g.ball.global_position
	page.toggle_edit()
	page.replay_button.pressed.emit()
	assert(g.replay.active and not page.editing and not g.replay.playing)
	assert(is_equal_approx(g.replay.clock,g.replay.duration()))
	assert(g.replay.frames.back().trace.scenario_phase==g.phase_key())
	page.timeline.max_value=g.replay.duration()
	page.timeline.value=g.replay.duration()
	page.timeline.value=0.02
	assert(g.replay.clock<.03 and g.ball.global_position.distance_to(paused_ball)>.1)
	page.toggle_edit()
	var actor=g.players[0]
	var initial:Vector3=actor.position
	var at:Vector2=page.camera.unproject_position(actor.global_position+Vector3.UP*.8)
	var goal:Vector2=page.camera.unproject_position(actor.global_position+Vector3(0,0,-1.))
	mouse_button(at,true)
	assert(page.dragged==0)
	var motion:=InputEventMouseMotion.new()
	motion.position=goal
	root.push_input(motion,true)
	mouse_button(goal,false)
	assert(page.dragged==-1 and absf(actor.position.z-initial.z)>.9)
	assert(FileAccess.file_exists(page.notes_path))
	var records=FileAccess.get_file_as_string(page.notes_path).strip_edges().split("\n")
	var rec=JSON.parse_string(records[-1])
	assert(rec.edited_slot==0 and rec.players.size()==12)
	page.toggle_edit()
	assert(actor.position.is_equal_approx(initial))
	var section:String=rec.scenario_phase
	page.replay_button.pressed.emit()
	assert(not g.replay.active and g.ball.global_position.is_equal_approx(paused_ball))
	assert(g.instructions.has_section(section))
	g.instructions.clear()
	assert(g.instructions.load(g.rules_path)==OK)
	g.start_feed(3,1,1,true)
	for tick in 20: g.step_match(1./60.,page.ground)
	assert(g.teaching_moves.has(0))
	assert(actor.position.z<initial.z-.05)
	g.start_feed(3,1,1,false)
	g.step_match(1./60.,page.ground)
	assert(not g.teaching_moves.has(0))
	print("PASS viewport drag, saved placement, resume, learned CPU movement and pass-quality isolation")
	quit()
