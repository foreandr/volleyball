extends SceneTree

func _initialize() -> void:
	check.call_deferred()

func click(at:Vector2) -> void:
	for down in [true,false]:
		var event:=InputEventMouseButton.new()
		event.position=at
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=down
		root.push_input(event,true)

func check() -> void:
	var page=load("res://scenes/block_defense_scenario.tscn").instantiate()
	page.roster_path="user://scenario-test-%d-%d.cfg"%[OS.get_process_id(),Time.get_ticks_usec()]
	root.add_child(page)
	page.set_process(false)
	await process_frame
	var g=page.game
	for rotation in range(1,7):
		g.setter_zones.assign([rotation,7-rotation])
		g.apply_receive_substitutions()
		for i in g.players.size():
			var inches:float=g.players[i].height_cm/2.54
			if g.player_identity(i) in [2,5]: assert(is_equal_approx(inches,77.))
			else: assert(inches>=70.99 and inches<=76.01)
			assert(is_equal_approx(g.players[i].scale.y,g.players[i].height_cm/180.))
		for side in 2:
			var first:int=g.first_on(side)+g.lineup_roles[side].find(0)
			var libero:int=g.choose_setter(side,first)
			g.flight_kind="pass"
			g.feed_number=g.flight_number
			g.receiving_team=side
			g.feed_hitter=g.front_middle(side)
			g.rally_hitter=g.front_middle(side)
			g.setter_can_run_middle[side]=true
			g.choose_at_set_contact(libero,Vector3(0,2.2,2.8))
			var hitter:int=g.hitter_for_set(libero)
			assert(g.rally_hitter==hitter and absf(g.set_pin_for(libero).x)>3.)
			assert(g.Formation.attack_route(g.lineup_role(hitter),g.setter_zones[side]) in ["left","right"])
	print("PASS heights and visible scale across six rotations on both teams, including both liberos")
	print("PASS both liberos select a pin even with a scripted middle and an in-system pass in all six rotations")
	page.defense.select(3)
	page.setup=page.selected_setup()
	page.show_settings(false)
	page.run_feed(false)
	var middle:int=g.front_middle(0)
	var identity:int=g.player_identity(middle)
	var actor=g.players[middle]
	var number:int=actor.get_meta("school_jersey_number")
	page.camera.position=Vector3(0,5,-13)
	page.camera.look_at(actor.global_position+Vector3.UP)
	await process_frame
	click(page.camera.unproject_position(actor.global_position+Vector3.UP))
	var panel=page.player_panel
	assert(panel.visible and panel.identity==identity and panel.side==0)
	var energy:float=actor.stamina.fraction()
	panel.controls.height_cm.value=79
	panel.tabs.current_tab=1
	panel.controls.Blocking.value=78
	panel.controls.Speed.value=82
	assert(is_equal_approx(actor.height_cm,79.*2.54) and actor.attributes.Blocking==78)
	assert(is_equal_approx(actor.stamina.fraction(),energy) and actor.get_meta("school_jersey_number")==number)
	var hitter=g.players[g.first_on(1)]
	page.inspect_player(g.first_on(1))
	var drive=g.attackers[1]
	drive.setter=hitter
	for choice in [0,1,0]:
		panel.hand.select(choice)
		panel.hand.item_selected.emit(choice)
		assert(hitter.mirror_animation==(choice==1))
		var palm:Vector3=hitter.to_local(drive.to_global(drive.right_palm()))
		if choice==1: assert(palm.x*hitter.get_meta("right_hand_probe")<0.)
		else: hitter.set_meta("right_hand_probe",palm.x)
	page.inspect_player(middle)
	for tick in 16: g.tick_match(1./60.,page.ground)
	page.toggle_match_replay()
	assert(g.replay.active)
	for width in [800,1280,1920]:
		page.size=Vector2(width,720)
		await process_frame
		await process_frame
		var rail:Control=page.footer.get_parent().get_parent()
		assert(absf(rail.get_rect().get_center().x-width*.5)<2.)
		for item in page.footer.get_children():
			assert(item.global_position.x>=0. and item.get_global_rect().end.x<=width+.5)
	panel.controls.height_cm.value=78
	page.toggle_edit()
	await process_frame
	click(page.reset_button.get_global_rect().get_center())
	assert(not page.editing and not g.replay.active and g.serve_pending)
	for tick in 240:
		g.tick_match(1./60.,page.ground)
		if g.phase==g.Phase.LIVE: break
	assert(g.phase==g.Phase.LIVE and g.flight_kind=="serve")
	assert(page.setup.attacks==page.selected_tempos and int(g.setter_zones[0])==4)
	assert(is_equal_approx(actor.scale.y,78.*2.54/180.))
	g.setter_zones[0]=1
	g.apply_receive_substitutions()
	assert(g.player_identity(middle)==6 and actor.height_cm<=76.01*2.54)
	g.setter_zones[0]=4
	g.apply_receive_substitutions()
	assert(g.player_identity(middle)==identity and actor.attributes.Blocking==78 and is_equal_approx(actor.height_cm,78.*2.54))
	var reloaded=load("res://scripts/block_scenario_roster.gd").new()
	reloaded.path=page.roster_path
	reloaded.load_starters({})
	assert(reloaded.profile(0,identity)==g.roster.profile(0,identity))
	var saved:Dictionary=reloaded.profile(0,identity)
	assert(saved.Speed==82 and actor.attributes.Speed==actor.Profile.effective_skill(saved,"Speed",actor.Profile.build_rules(saved)))
	assert(reloaded.profile(1,identity).height_cm==77.*2.54)
	print("PASS court click, live build and skill edits, stamina, saved roster, replay/placement reset and libero swap")
	print("PASS changing hitting hand mirrors the physical spike palm; replay controls fit 800, 1280 and 1920 widths")
	check_late_close(g)
	check_dumps(g)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(page.roster_path))
	page.free()
	var session=root.get_node("StorySession")
	session.offline_size=2
	session.offline_away_size=2
	session.offline_controller=-1
	change_scene_to_file("res://scenes/offline_match.tscn")
	await scene_changed
	current_scene.set_process(false)
	check_dumps(current_scene.game)
	quit()

func check_dumps(g) -> void:
	for side in 2:
		var setter:int=g.first_on(side)
		if g.six_on_six(): setter+=g.lineup_roles[side].find(0)
		var frame=g.frames[side]
		var contact:=Vector3(0,2.95,3.35)
		for empty_half in ["left","right","short","deep"]:
			var slot:=0
			for i in g.slots_for(1-side):
				var x:float=[-3.5,0.,3.5][slot%3]
				var z:=6.+4.*floorf(slot/3.)
				match empty_half:
					"left": x=1.+slot%3
					"right": x=-1.-slot%3
					"short": z=10.+floorf(slot/3.)
					"deep": z=5.+floorf(slot/3.)
				g.players[i].global_position=frame.to_global(Vector3(x,.04,z))
				slot+=1
			g.phase=g.Phase.LIVE
			g.possession_team=side
			g.receiving_team=side
			g.touches=1
			g.last_player=g.partner_of(setter)
			g.last_was_block=false
			g.flight_kind="pass"
			g.cpu_choice=setter
			g.cpu_dump=true
			g.ball.global_position=frame.to_global(contact)
			g.origin=g.ball.global_position
			g.velocity=Vector3.DOWN*3
			g.elapsed=0.
			g.duration=.5
			g.net_hit.clear()
			g.aim_receive(setter)
			var bump=g.platforms[setter]
			var target:Vector2=bump.destination
			assert((empty_half!="left" or target.x< -2.) and (empty_half!="right" or target.x>2.))
			assert((empty_half!="short" or target.y<7.) and (empty_half!="deep" or target.y>10.))
			var motion:Vector3=bump.aim_velocity(contact)
			assert(g.dump_can_land_in_court(contact,motion))
			g.receive_contact(setter,frame.to_global(contact),frame.global_basis*motion,1)
			assert(g.flight_kind=="dump" and g.receiving_team==1-side and g.net_hit.is_empty())
			var floor_point:Vector3=frame.to_local(g.path_point(g.flight_end()))
			assert(Vector2(floor_point.x,floor_point.z).distance_to(target)<.7)
	print("PASS ",g.team_size,"v",g.away_size," released hand dumps clear the net to open left, right, short and deep court for both teams")

func check_late_close(g) -> void:
	for side in 2:
		g.start_feed(4,1,1,true)
		var middle:int=g.front_middle(side)
		var pin:=-1
		for i in g.slots_for(side):
			if g.Formation.zone(g.lineup_role(i),g.setter_zones[side]) in [2,3,4] and g.formation_home(i,true).x>1.: pin=i
		assert(pin>=0)
		var driver=g.attackers[1-side]
		g.players[pin].position=Vector3(3.65,.04,3.42)
		g.players[middle].position=Vector3(2.12,.04,3.42)
		g.start_block(pin,.3)
		g.blocks[pin].age=.29
		driver.approach_expected_hit_at=driver.clock+.20
		g.defend_pin_set(side,3.65,driver,1./60.)
		assert(g.blocks.has(middle))
		var block=g.blocks[middle]
		assert(block.age==0. and is_finite(block.late_quick_x) and block.seal_angle<0.)
		var ball:=Vector3(g.players[pin].global_position.x,3.4,4.)
		for tick in 16: block.step(1./60.,ball)
		assert(g.players[middle].position.y>.4)
	print("PASS both middles take off from their actual spot after a late pin close and reach with the near hand")
