extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	change_scene_to_file("res://scenes/block_defense_scenario.tscn")
	await scene_changed
	var page=current_scene
	page.set_process(false)
	var g=page.game
	var failures:=0
	for side in 2:
		g.start_feed(1,1,1,true)
		var setter:int=g.first_on(side)+g.lineup_roles[side].find(0)
		var libero:int=g.choose_setter(side,setter)
		var pin:int=g.first_on(side)+g.lineup_roles[side].find(g.role_for_route("left",1))
		var attacker:int=g.front_middle(1-side)
		g.phase=g.Phase.LIVE
		g.previous_attacker=attacker
		g.last_player=attacker
		g.possession_team=1-side
		g.touches=3
		if not g.can_touch(pin,true) or g.touches!=0: failures+=1
		g.last_player=pin
		if g.can_touch(attacker) or g.touches!=0: failures+=1
		g.flight_kind="block"
		var contact:Vector3=g.frames[side].to_global(Vector3(0.,1.2,0.))
		var goal:Vector3=g.frames[side].to_global(Vector3(0.,2.,2.))
		var motion:Vector3=(goal-contact)+Vector3.UP*.5*g.Flight.GRAVITY
		g.receive_contact(libero,contact,motion,0)
		if g.touches!=1 or g.flight_kind!="pass" or g.rally_setter!=setter or g.first_ball_source!="block": failures+=1
		g.players[pin].position=g.attack_lane_for(pin)-Vector3.BACK*1.7
		g.players[pin].rotation.y=0.
		for source:String in ["serve","free","block","spike"]:
			g.first_ball_source=source
			for tempo in [0,1]:
				var expected:int=tempo if source in ["serve","free"] else 2
				if g.pin_tempo(setter,pin,g.SETTER_BASE,tempo)!=expected or g.pin_tempo(libero,pin,g.SETTER_BASE,tempo)!=2: failures+=1
		g.first_ball_source="serve"
		g.players[pin].position=g.attack_lane_for(pin)
		if g.pin_tempo(setter,pin,g.SETTER_BASE,0)!=2: failures+=1
		if absf(g.pin_staging(pin,g.attack_lane_for(pin)).x)<=4.5: failures+=1
	print("CONTACT RULES failures ",failures)
	for lane:String in ["left","middle","right"]:
		var hits:=0
		var clears:=0
		var hard:=0
		var worst_turn:=0.
		var speeds:=[]
		for rep in 8:
			seed(1820+rep)
			g.start_attack_plan(3,1,{lane:1 if lane=="middle" else 2},true)
			var id:int=g.feed_hitter
			var last_yaw:float=g.players[id].rotation.y
			var turn:=0.
			var started:=false
			var contacted:=false
			for tick in 580:
				var flight:int=g.flight_number
				g.tick_match(1./60.,page.ground)
				var y:float=g.players[id].rotation.y
				if g.players[id].position.y>g.PLAYER_GROUND_Y+.10:
					if started: turn+=absf(angle_difference(last_yaw,y))
					started=true
				elif started:
					worst_turn=maxf(worst_turn,rad_to_deg(turn))
					if contacted: break
					started=false
					turn=0.
				last_yaw=y
				if not contacted and flight!=g.flight_number and g.flight_kind=="spike" and g.last_player==id:
					contacted=true
					var local:Vector3=g.frames[1].global_basis.inverse()*g.velocity
					hits+=1
					if local.z>0. and g.net_hit.is_empty(): clears+=1
					if local.length()*3.6>=60.: hard+=1
					speeds.append(roundi(local.length()*3.6))
					var trace:Dictionary=g.replay.current.back().trace
					if trace.attack_decision.is_empty() or trace.set_decision.is_empty(): failures+=1
					if rep==0:
						var recorded:Dictionary=g.replay.current.back()
						g.replay.toggle(g,true,[recorded,recorded] as Array[Dictionary])
						var live:String=g.attack_decision
						g.attack_decision="later rally"
						page.running=true
						page.decision_toggle.set_pressed_no_signal(true)
						page.update_decision_label()
						if not page.decision_label.text.contains(trace.attack_decision) or page.decision_label.text.contains("later rally"): failures+=1
						g.attack_decision=live
						g.replay.toggle(g,false)
					print("SWING ",lane," ",rep," ",trace.attack_decision.replace("\n"," "), " yaw ",rad_to_deg(turn))
				if g.phase==g.Phase.DEAD and not started: break
			worst_turn=maxf(worst_turn,rad_to_deg(turn))
			await process_frame
		print("RALLY CHECK ",lane," hits ",hits,"/8 clean crossings ",clears," hard ",hard," speeds ",speeds," max air turn ",snappedf(worst_turn,.1))
		var minimum_crossings:=8 if lane=="left" else 5
		if hits!=8 or clears<minimum_crossings or hard<1 or worst_turn>(90. if lane=="middle" else 165.): failures+=1
	print("TRANSITION CHECK failures ",failures)
	quit(1 if failures else 0)
