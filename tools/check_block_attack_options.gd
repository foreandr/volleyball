extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	seed(2951)
	change_scene_to_file("res://scenes/block_defense_scenario.tscn")
	await scene_changed
	await process_frame
	var page=current_scene
	page.set_process(false)
	var g=page.game
	g.instructions.clear()
	page.defense.select(2)
	page.offense.select(0)
	page.quality.select(0)
	page.repeat_option.button_pressed=true
	for lane:String in g.ROUTES:
		var cell:Button=page.find_child(lane+"_off",true,false)
		cell.grab_focus()
		for down in [true,false]:
			var event:=InputEventAction.new()
			event.action="ui_accept"
			event.pressed=down
			root.push_input(event,true)
		assert(cell.button_pressed and page.selected_tempos[lane]==-1)
	assert(page.run_button.disabled and not g.start_attack_plan(3,1,page.selected_tempos,true))
	var right:Button=page.find_child("right_2",true,false)
	right.button_pressed=true
	right.pressed.emit()
	assert(not page.run_button.disabled)
	page.setup=page.selected_setup()
	assert(page.restore_tempos(page.setup)==page.selected_tempos)
	assert(page.restore_tempos({"offense":1,"role":1,"tempo":3}).right==3)
	page.show_settings(false)
	page.run_feed(false)
	for rep in 2:
		for tick in 650:
			g.tick_match(1./60.,page.ground)
			if g.released_route!="": break
		assert(g.released_route=="right" and g.released_tempo==2)
		assert(g.expected_hitter==g.feed_hitter and g.attack_lane_for(g.feed_hitter).x< -3.)
		if rep==0:
			g.award(0,"Test feed complete")
			page.toggle_match_replay()
			var before:int=g.feed_number
			for t in 4: page._process(1.)
			assert(g.replay.active and g.feed_number==before)
			page.toggle_match_replay()
			page.show_settings(true)
			page._process(4.)
			assert(g.feed_number==before)
			page.show_settings(false)
			page._process(3.1)
			assert(g.feed_number>before and not g.replay.previous.is_empty())
	print("PASS 20 tempo cells, all-off guard, saved settings, right-side-only repeat and replay/placement preserves the rally")
	var mix:={"left":1,"middle":0,"pipe":3,"right":-1}
	assert(g.start_attack_plan(3,1,mix,true))
	var found:Dictionary={}
	var setter:int=g.first_on(1)+g.lineup_roles[1].find(0)
	g.receiving_team=1
	g.possession_team=1
	g.flight_kind="pass"
	g.touches=1
	for possession in 60:
		g.flight_number=g.feed_number+possession+1
		var hitter:int=g.hitter_for_set(setter)
		var lane:String=g.Formation.attack_route(g.lineup_role(hitter),1)
		assert(mix[lane]>=0 and g.six_set_tempo(hitter,Vector3.ZERO)==mix[lane])
		for frame in 12: assert(g.hitter_for_set(setter)==hitter)
		found[lane]=int(found.get(lane,0))+1
	assert(found.size()==3 and not found.has("right"))
	print("PASS random choices stay fixed through contact and disabled lanes never enter the mix: ",found)
	quit()
