extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	change_scene_to_file("res://scenes/block_defense_scenario.tscn")
	await scene_changed
	var page=current_scene
	page.set_process(false)
	var game=page.game
	var failures:=0
	var accuracy=game.Bump.Accuracy
	var slower:Vector2=accuracy.dig_spread(95./3.6,94.)
	var harder:Vector2=accuracy.dig_spread(100./3.6,94.)
	var lower_skill:Vector2=accuracy.dig_spread(100./3.6,60.)
	if harder.x<=slower.x or harder.y<=slower.y or lower_skill.x<=harder.x or lower_skill.y<=harder.y: failures+=1
	print("DIG bounds at 95 km/h ",slower," at 100 km/h ",harder," at lower skill ",lower_skill)
	for sample:Array in [
		[1,Vector3(4.74,.04,1.294),Vector3(3.796,.065,2.990),Vector3(.94346,5.91854,2.29661),5.18308,1.25524,-.41],
		[0,Vector3(5.093,.04,1.098),Vector3(3.654,.065,3.044),Vector3(4.04966,6.05239,-.08704),5.19426,1.28826,0.]
	]:
		seed(7839)
		game.start_attack_plan(3,1,{"left":2},true)
		var side:int=sample[0]
		var frame:Node3D=game.frames[side]
		var hitter:int=8 if side==1 else 0
		var setter:int=game.choose_setter(side,8 if side==1 else 0)
		var runner=game.players[hitter]
		runner.position=sample[1]
		runner.rotation.y=sample[6]
		var target:Vector3=sample[2]
		var motion:Vector3=sample[3]
		var apex:float=sample[4]
		var origin:=target-motion.slide(Vector3.UP)*float(sample[5])
		origin.y=apex-motion.y*motion.y/(2.*game.Flight.GRAVITY)
		var adjustment:=smoothstep(4.1,5.2,target.x-origin.x)
		target=Vector3(minf(target.x+.34*adjustment,4.05),target.y,target.z-.56*adjustment)
		var seconds:float=game.zone_four_flight_time(target.x-origin.x)
		if seconds>float(sample[5]):
			game.size_attack_jump(game.attackers[side],hitter)
			var driver=game.attackers[side]
			apex=driver.apex_for_set_time(origin.y,apex,seconds)
			motion=driver.set_toward_pin(origin,target,apex,driver.set_contact_height(apex))
		game.last_set_apex=apex
		game.phase=game.Phase.LIVE
		game.possession_team=side
		game.touches=2
		game.launch(frame.to_global(origin),frame.global_basis*motion,"set",setter,1.,hitter,frame.to_global(target))
		var hit:=false
		var cleared_net:=false
		for tick in 155:
			game.tick_match(1./60.,page.ground)
			if tick==14:
				print("START ",side," ",runner.position)
				if runner.position.x>=float(sample[1].x)-.025: failures+=1
			if game.flight_kind=="spike" and game.last_player==hitter:
				hit=true
				cleared_net=game.net_hit.is_empty() and frame.to_local(game.path_point(game.flight_end())).z>game.Net.NET_Z
				print("RALLY ",side," ",game.attack_decision," cleared ",cleared_net)
				break
			if game.phase!=game.Phase.LIVE: break
		print("RESULT ",side," ",hit," ",game.last_point)
		if not hit or (side==1 and not cleared_net): failures+=1
		await process_frame
	game.start_attack_plan(3,1,{"left":2},true)
	var libero:int=game.choose_setter(0,game.first_on(0)+game.lineup_roles[0].find(0))
	var attacker:int=game.first_on(1)
	var contact:=Vector3(1.6,1.3,-2.1)
	game.phase=game.Phase.LIVE
	game.possession_team=1
	game.touches=3
	game.launch(contact,Vector3.FORWARD*(100./3.6),"spike",attacker,0.,-1,Vector3.ZERO,Vector3.INF,Vector3.INF,true)
	game.platforms[libero].touch_time=0.
	game.receive_contact(libero,contact,Vector3.UP*6.,0)
	var dig:Dictionary={}
	for event:Dictionary in game.trace.recent_events:
		if event.event=="dig_outlet": dig=event.data
	if dig.is_empty() or not is_equal_approx(float(dig.speed_kmh),100.) or dig.pot!=[0.,game.Net.NET_Z-3.]: failures+=1
	print("DIG actual ",dig)
	print("ZONE FOUR failures ",failures)
	quit(1 if failures else 0)
