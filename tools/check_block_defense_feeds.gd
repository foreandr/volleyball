extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	seed(2951)
	change_scene_to_file("res://scenes/block_defense_scenario.tscn")
	await scene_changed
	var page=current_scene
	page.set_process(false)
	var g=page.game
	assert(g.spectator and g.manual==null and g.players.size()==12)
	for i in 12: assert(not g.is_human(i))
	g.instructions.clear()
	var heights:=[]
	var times:=[]
	for tempo in range(4):
		seed(185)
		g.start_feed(3,1,1,true,tempo)
		for tick in 480:
			g.step_match(1./60.,page.ground)
			if g.phase in [g.Phase.DEAD,g.Phase.FINISHED]: break
			if g.phase==g.Phase.LIVE and g.flight_kind=="set": break
		assert(g.phase==g.Phase.LIVE and g.flight_kind=="set" and g.flight_number==g.feed_number+1)
		heights.append(g.last_set_apex)
		times.append(g.arrival(g.attackers[1].set_contact_height(g.last_set_apex)))
		if tempo>0:
			assert(heights[tempo]>heights[tempo-1])
			assert(times[tempo]>times[tempo-1])
	print("Opening pin set apex by tempo (m): ",heights,"; time to hitter (s): ",times)
	var total:=0
	var misses:=[]
	var missed_passes:=0
	for rotation in range(1,7):
		for quality in [true,false]:
			for route:String in g.ROUTES:
				var role:int=g.role_for_route(route,rotation)
				var value:int={"left":1,"middle":0,"pipe":3,"right":2}[route]
				var released:=false
				for attempt in 3:
					assert(g.start_attack_plan(7-rotation,rotation,{route:value},quality))
					assert(g.setter_zones==[7-rotation,rotation])
					assert(g.phase==g.Phase.READY and g.serve_pending)
					var served:=false
					var passed:=false
					for tick in 480:
						g.step_match(1./60.,page.ground)
						if g.phase==g.Phase.LIVE and g.flight_kind=="serve": served=true
						if g.scripted_pass(): passed=served and g.setter_can_run_middle[1]==quality
						if g.phase==g.Phase.LIVE and g.flight_kind=="set":
							assert(passed)
							assert(g.lineup_role(g.expected_hitter)==role)
							assert(g.released_route==route and g.released_tempo==value)
							released=true
							break
						if g.phase in [g.Phase.DEAD,g.Phase.FINISHED]: break
					if released: break
					missed_passes+=1
				if not released: misses.append([rotation,quality,role,g.flight_kind,g.phase])
				total+=1
			await process_frame
	print("Set releases ",total-misses.size(),"/",total,"; feeds missed before set ",missed_passes,"; missing ",misses)
	quit(0 if misses.is_empty() else 1)
