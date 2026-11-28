extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var shots=preload("res://scripts/cpu_attack_shots.gd")
	var defenders:Array[Vector3]=[]
	var walls:Array[Vector3]=[]
	var low:=Vector3(0.,2.05,.2)
	var roll:Dictionary=shots.plan(low,Vector3(0,.105,10),26.,9.,defenders,walls)
	assert(roll.get("type","")=="Roll shot")
	var gravity:float=shots.Flight.spike_gravity(roll.spin)
	var duration:float=shots.Flight.landing_time(low,roll.motion,gravity)
	assert(shots.Net.first_hit(func(t): return shots.path(low,roll.motion,gravity,t),0.,duration).is_empty())
	assert(shots.path(low,roll.motion,gravity,duration).distance_to(roll.target)<.01)
	var session=root.get_node("StorySession")
	session.offline_size=6
	session.offline_away_size=6
	session.offline_controller=-1
	change_scene_to_file("res://scenes/offline_match.tscn")
	await scene_changed
	var match_scene=current_scene
	var g=match_scene.game
	for side in 2:
		g.receiving_team=side
		g.flight_kind="serve"
		g.cpu_choice=g.first_on(side)
		for i in g.slots_for(side):
			g.players[i].position=g.formation_home(i,false)
		var before: Array=[]
		for i in g.slots_for(side): before.append(g.players[i].position)
		g.position_attack(.05)
		var moving:=0
		for i in g.slots_for(side):
			if before[i-g.first_on(side)].distance_to(g.players[i].position)>.0001: moving+=1
		assert(moving>=3)
		var setter:int=g.first_on(side)+g.lineup_roles[side].find(0)
		var middle_id:int=g.front_middle(side)
		var pipe_id:int=g.first_on(side)+g.lineup_roles[side].find(4)
		for i in g.slots_for(1-side): g.players[i].position=g.formation_home(i,true)
		g.players[pipe_id].position.z=-2.
		g.players[middle_id].position=g.attack_lane_for(middle_id)-Vector3.BACK*1.65
		g.players[middle_id].position.y=g.PLAYER_GROUND_Y
		g.rally_setter=setter
		g.rally_hitter=pipe_id
		g.next_touch_cue=g.elapsed+.48
		g.choose_at_set_contact(setter,Vector3(0,2,3))
		assert(g.rally_hitter!=pipe_id)
		g.prepare_middle_quick(side,.016)
		assert(g.set_jumps[middle_id].active and not g.middle_showing_quick(side))
		assert(g.set_jumps[middle_id].lead_time>0.)
		var approach_start:Vector3=g.players[middle_id].position
		for tick in 28: g.advance_set_jumps(1./60.)
		assert(g.players[middle_id].position.z>approach_start.z+.3)
		assert(g.middle_showing_quick(side))
		g.read_pipe(side)
		var pipe_lane:Vector3=g.attack_lane_for(pipe_id)
		g.players[pipe_id].position=pipe_lane+Vector3(1.2,0.,-1.)
		g.rally_hitter=pipe_id
		g.choose_at_set_contact(setter,Vector3(0,2,3))
		assert(g.rally_hitter==middle_id)
		assert(g.set_pin_for(setter).is_equal_approx(g.attack_lane_for(middle_id)))
		var pin_id:int=g.first_on(side)+g.lineup_roles[side].find(1)
		assert(signf(g.formation_home(pin_id,true).x)==signf(g.attack_lane_for(pin_id).x))
		g.rally_hitter=pin_id
		g.choose_at_set_contact(setter,Vector3(0,2,3))
		assert(g.rally_hitter==pin_id)
		g.rally_hitter=middle_id
		g.players[pipe_id].position.x=pipe_lane.x
		g.choose_at_set_contact(setter,Vector3(0,2,3))
		assert(g.rally_hitter==middle_id)
		g.rally_hitter=-1
		g.choose_at_set_contact(setter,Vector3(0,2,3))
		assert(g.rally_hitter==pipe_id)
		g.choose_at_set_contact(setter,Vector3(0,2,0))
		assert(g.rally_hitter!=pipe_id)
		var jump=g.set_jumps[middle_id]
		var frame=g.frames[side]
		var altitude:float=g.players[middle_id].position.y
		g.launch(frame.to_global(Vector3(0,2,2)),frame.global_basis*Vector3(0,5,2),"set",setter,0.,middle_id,frame.to_global(g.attack_lane_for(middle_id)))
		assert(g.attackers[side].jump==jump and jump.active and is_equal_approx(altitude,g.players[middle_id].position.y))
		jump.active=false
		g.players[middle_id].position.y=g.PLAYER_GROUND_Y
		g.setter_can_run_middle[side]=true
		g.serve.moved_after_contact=true
		g.serve.contact_clock=0.
		g.serve.swing_time=g.serve.recovery_end()+1.
		var block_middle:int=g.front_middle(1-side)
		for i in g.slots_for(1-side): g.players[i].position=g.formation_home(i,true)
		var pipe_driver=g.attackers[side]
		pipe_driver.rally_set_target=Vector3(.95,.065,.85)
		g.expected_hitter=pipe_id
		g.flight_kind="set"
		g.receiving_team=side
		g.last_player=-1
		for tick in 90:
			g.match_clock+=1./60.
			pipe_driver.approach_expected_hit_at=pipe_driver.clock+maxf(.26,1.4-tick/60.)
			g.position_defense(1./60.)
		print("pipe defense ",side," ",g.blocks.keys()," middle ",block_middle," ",g.players[block_middle].position," assignment ",g.defender_assignment)
		assert(g.blocks.has(block_middle) and g.blocks.size()>=2)
		for i in g.blocks: assert(g.Formation.zone(g.lineup_role(i),g.setter_zones[1-side]) in [2,3,4])
		g.blocks.clear()
		for i in g.slots_for(1-side): g.players[i].position=g.formation_home(i,true)
		var opposing_middle:int=g.first_on(1-side)+g.lineup_roles[1-side].find(2)
		for x in [-1.4,1.4]:
			g.players[opposing_middle].position.x=x
			g.read_pipe(side)
			assert(g.pipe_gap[side]*x>0.)
		for i in g.slots_for(side):
			if g.lineup_role(i) not in [1,4] or g.attack_lane_for(i).z>1.: continue
			g.rally_hitter=i
			for j in 12:
				var rise:float=g.cpu_set_apex(setter,Vector3(0,2,-2),g.attack_lane_for(i),4.)-g.attackers[side].set_contact_height()
				assert(is_equal_approx(rise,.47))
		for i in g.slots_for(side):
			if g.lineup_role(i) not in [2,5] or not g.attack_lane_for(i).is_finite(): continue
			g.rally_hitter=i
			var quick:=0
			for j in 1000:
				var apex:float=g.cpu_set_apex(setter,Vector3(0,2,2),g.attack_lane_for(i),5.)
				var rise:float=apex-g.attackers[side].set_contact_height()
				assert(is_equal_approx(rise,.18) or is_equal_approx(rise,.47))
				if rise<.3: quick+=1
			assert(quick>840 and quick<960)
			g.last_player=-1
			g.expected_hitter=i
			g.flight_kind="set"
			var defender:int=-1
			for j in g.slots_for(1-side):
				if g.lineup_role(j) in [2,5] and g.attack_lane_for(j).is_finite(): defender=j
			assert(defender>=0)
			var driver=g.attackers[side]
			driver.rally_set_target=Vector3(0.,.065,3.2)
			driver.approach_expected_hit_at=driver.clock+.27
			g.players[defender].position=Vector3(0.,.04,3.42)
			g.elapsed=.6
			g.position_defense(.016)
			assert(g.defender_assignment[1-side]==defender and g.blocks.has(defender))
			g.blocks.clear()
		for wing:float in [-1.,1.]:
			var defense:int=1-side
			var middle:int=g.first_on(defense)+g.lineup_roles[defense].find(2)
			var line:=-1
			for i in g.slots_for(defense):
				g.players[i].position=g.formation_home(i,true)
				if g.Formation.zone(g.lineup_role(i),g.setter_zones[defense]) in [1,5,6]:
					if line<0 or wing*g.players[i].position.x>wing*g.players[line].position.x: line=i
			var driver=g.attackers[side]
			driver.rally_set_target=Vector3(-wing*3.7,.065,3.2)
			g.flight_kind="set"
			g.expected_hitter=g.first_on(side)+g.lineup_roles[side].find(1)
			g.serve.contact_clock=0.
			g.serve.swing_time=g.serve.recovery_end()+1.
			g.serve.moved_after_contact=true
			g.court_velocities.clear()
			var start:Vector3=g.players[line].position
			for tick in 90:
				g.match_clock+=1./60.
				driver.approach_expected_hit_at=driver.clock+maxf(.24,1.55-tick/60.)
				g.position_defense(1./60.)
				if g.blocks.size()==2: break
			var pin:int=g.defender_assignment[defense]
			assert(pin!=middle and g.blocks.has(pin) and g.blocks.has(middle))
			assert(wing*(g.players[pin].position.x-g.players[middle].position.x)>.45)
			assert(g.blocks[pin].square_block and g.blocks[middle].square_block)
			assert(is_equal_approx(g.blocks[pin].tempo,g.blocks[middle].tempo) and is_equal_approx(g.blocks[pin].age,g.blocks[middle].age))
			for i in [pin,middle]:
				g.blocks[i].read_air_lane(g.players[i].global_position+Vector3(1.,3.,1.),g.players)
				assert(g.blocks[i].reach_input==Vector2.ZERO and g.blocks[i].lean_input==0.)
			assert(g.players[line].position.z<start.z-.65 and wing*(g.players[line].position.x-start.x)>.2)
			g.blocks.clear()
			if defense==0 and wing>0:
				var saved_roles=g.lineup_roles[0].duplicate()
				var pin_position:Vector3=g.players[pin].position
				g.lineup_roles[0][pin]=g.lineup_roles[0][0]
				g.lineup_roles[0][0]=saved_roles[pin]
				g.players[0].position=pin_position
				g.spectator=false
				driver.approach_expected_hit_at=driver.clock+.25
				g.position_defense(1./60.)
				assert(g.defender_assignment[0]==0 and not g.blocks.has(middle))
				var leader=g.Block.new()
				leader.begin(g.players[0],1.)
				g.blocks[0]=leader
				g.position_defense(1./60.)
				assert(g.blocks.has(middle))
				var follower=g.blocks[middle]
				var lifts:=[-1,-1]
				for tick in 24:
					for pair in [[leader,0],[follower,1]]:
						pair[0].step(1./60.,g.ball.global_position)
						if lifts[pair[1]]<0 and pair[0].actor.position.y>pair[0].base.y+.01: lifts[pair[1]]=tick
				assert(lifts[0]>=0 and lifts[0]==lifts[1])
				print("Human pin / CPU middle first airborne frames: ",lifts)
				g.blocks.clear()
				g.spectator=true
				g.lineup_roles[0]=saved_roles
	# Recorded sharp cut toward 503. Both the mapped animation and real limb contact must fire.
	g.blocks.clear()
	g.recoveries.clear()
	g.phase=g.Phase.LIVE
	g.possession_team=1
	g.touches=3
	var defense_positions:=[Vector2(2.73,3.42),Vector2(-3.07,-.23),Vector2(.15,-2.87),Vector2(1.69,3.42),Vector2(3.42,-1.1),Vector2(-2.31,3.43)]
	for i in 6:
		g.players[i].position=Vector3(defense_positions[i].x,.04,defense_positions[i].y)
	g.players[1].rotation.y=.91
	g.players[7].global_position=Vector3(4.,.04,5.23)
	g.launch(Vector3(4.,2.526,5.234),Vector3(-8.612,3.674,-4.885),"spike",7,6.596,-1,Vector3.ZERO,Vector3.INF,Vector3.INF,true)
	var mapped:=false
	for tick in 90:
		var previous:float=g.elapsed
		g.elapsed+=1./60.
		g.ball.global_position=g.path_point(minf(g.elapsed,g.flight_end()))
		g.tick_receive(1./60.,previous)
		mapped=mapped or not g.cpu_reception.motion.is_empty()
		if g.flight_kind!="spike": break
	print("Recorded cut: mapped=",mapped," last contact=",g.last_player," flight=",g.flight_kind)
	assert(mapped and g.last_player==1 and g.flight_kind=="pass")
	# Orange 508 landed deep after setting. Recreate his release and the cover pass.
	var setter:int=g.first_on(1)+g.lineup_roles[1].find(0)
	g.players[setter].global_position=Vector3(2.675,.04,8.858)
	g.players[setter].rotation.y=.726
	g.recoveries.clear()
	g.court_velocities.clear()
	g.possession_team=1
	g.flight_kind="set"
	g.last_player=setter
	g.expected_hitter=11
	var start:Vector3=g.players[setter].global_position
	for tick in 64:
		g.match_clock+=1./60.
		g.position_attack(1./60.)
	var release_distance:float=start.distance_to(g.players[setter].global_position)
	assert(release_distance>1.)
	g.touches=1
	g.launch(Vector3(-.836,1.491,4.9),Vector3(1.375,8.167,.185),"pass",9)
	assert(g.rally_setter==setter)
	for tick in 120:
		var previous:float=g.elapsed
		g.elapsed+=1./60.
		g.match_clock+=1./60.
		g.ball.global_position=g.path_point(minf(g.elapsed,g.flight_end()))
		g.advance_set_jumps(1./60.)
		g.position_attack(1./60.)
		g.tick_receive(1./60.,previous)
		if g.flight_kind!="pass": break
	print("Orange cover: setter released ",release_distance," m; next contact ",g.last_player," / ",g.flight_kind)
	assert(g.last_player==setter and g.flight_kind=="set")
	# In the setter lane, a free approach yields early; a shoulder bump costs the current set.
	g.recoveries.clear()
	g.rally_setter=setter
	g.receiving_team=1
	g.flight_kind="pass"
	g.players[setter].position=Vector3(-1.,.04,-1.)
	g.origin=g.frames[1].to_global(Vector3(-1.,2.,2.))
	g.velocity=Vector3.UP*4.
	g.elapsed=0.
	g.duration=1.
	g.net_hit.clear()
	var runner:int=g.first_on(1)+g.lineup_roles[1].find(1)
	g.players[runner].position=Vector3(-.9,.04,.3)
	g.rally_hitter=runner
	g.clear_setter_lane(1,.05)
	assert(g.yielding.has(runner) and not g.interrupted_hitters.has(runner))
	g.players[runner].position=Vector3(-.9,.04,-.58)
	var shoulder:Vector3=g.players[runner].position
	g.clear_setter_lane(1,.05)
	assert(g.interrupted_hitters.has(runner) and g.hitter_for_set(setter)!=runner and g.players[runner].position.x>shoulder.x)
	print("Pipe tempo, approach, front-row closure and setter right of way verified")
	g.replay.record(g)
	g.match_clock+=1.
	g.replay.record(g)
	match_scene.toggle_match_replay()
	assert(g.replay.active and not g.replay.playing and is_equal_approx(g.replay.clock,g.replay.duration()))
	var controls=load("res://scripts/replay_controls.gd")
	var bindings=load("res://scripts/xbox_controls.gd")
	for left in [true,false]:
		var trigger:=InputEventJoypadMotion.new()
		trigger.device=0
		trigger.axis=bindings.trigger(left)
		trigger.axis_value=.75
		Input.parse_input_event(trigger)
		Input.flush_buffered_events()
		var scrub:float=controls.scrub(0)
		assert(scrub<0 if left else scrub>0)
		g.replay.seek(g,g.replay.clock+scrub*.15)
		if left: assert(g.replay.clock<g.replay.duration()-.4)
		else: assert(is_equal_approx(g.replay.clock,g.replay.duration()))
		trigger=trigger.duplicate()
		trigger.axis_value=0.
		Input.parse_input_event(trigger)
		Input.flush_buffered_events()
	match_scene.toggle_match_replay()
	assert(not g.replay.active)
	print("PASS both sides transition, middle tempo distribution, LT/RT seek and exit")
	quit()
