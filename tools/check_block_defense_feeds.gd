extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	change_scene_to_file("res://scenes/block_defense_scenario.tscn")
	await scene_changed
	var page=current_scene
	page.set_process(false)
	var g=page.game
	g.spectator=true
	g.instructions.clear()
	var heights:=[]
	var times:=[]
	for tempo in range(4):
		seed(185)
		g.start_feed(3,1,1,true,tempo)
		for tick in 150:
			g.step_match(1./60.,page.ground)
			if g.flight_kind=="set": break
		assert(g.flight_kind=="set")
		heights.append(g.last_set_apex)
		times.append(g.arrival(g.attackers[1].set_contact_height(g.last_set_apex)))
		if tempo>0:
			assert(heights[tempo]>heights[tempo-1])
			assert(times[tempo]>times[tempo-1])
	print("Opening pin set apex by tempo (m): ",heights,"; time to hitter (s): ",times)
	var total:=0
	var misses:=[]
	for rotation in range(1,7):
		page.offense.select(rotation-1)
		page.populate_hitters(1)
		for quality in [true,false]:
			for option in page.hitter.item_count:
				var role:int=page.hitter.get_item_id(option)
				g.start_feed(7-rotation,rotation,role,quality)
				assert(g.setter_zones==[7-rotation,rotation])
				assert(g.setter_can_run_middle[1]==quality)
				assert(g.lineup_role(g.rally_hitter)==role)
				var released:=false
				for tick in 150:
					g.step_match(1./60.,page.ground)
					if g.flight_kind=="set":
						assert(g.lineup_role(g.expected_hitter)==role)
						released=true
						break
					if g.phase!=g.Phase.LIVE: break
				if not released: misses.append([rotation,quality,role,g.flight_kind,g.phase])
				total+=1
			await process_frame
	print("Set releases ",total-misses.size(),"/",total,"; missing ",misses)
	quit(0 if misses.is_empty() else 1)
