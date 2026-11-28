extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
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
				assert(is_equal_approx(rise,.47) or is_equal_approx(rise,1.12))
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
