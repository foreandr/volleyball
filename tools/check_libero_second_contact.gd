extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	seed(2951)
	change_scene_to_file("res://scenes/block_defense_scenario.tscn")
	await scene_changed
	var page=current_scene
	page.set_process(false)
	var game=page.game
	var failures:=0
	var pins:={}
	for side:int in [0,1]:
		for sample:Array in [[-.9,-.4,2],[.05,1.30,2],[1.6,1.8,0],[-.1,2.6,0]]:
			seed(185)
			game.start_feed(1,1,1,true,2)
			game.feed_number=-100
			game.phase=game.Phase.LIVE
			game.serve_pending=false
			game.possession_team=side
			game.receiving_team=side
			game.touches=1
			var passer:int=game.first_on(side)+game.lineup_roles[side].find(0)
			var libero:int=game.choose_setter(side,passer)
			var actor=game.players[libero]
			actor.position=Vector3(0,game.PLAYER_GROUND_Y,sample[0])
			var frame:Node3D=game.frames[side]
			# Alternate the open pin using the real set-distribution history.
			for i in game.slots_for(side):
				game.last_set_to[i]=4 if game.attack_lane_for(i).x*(1. if sample[1]>1. else -1.)>0. else 0
			var start:=Vector3(0,1.3,sample[1]-1.)
			var end:=Vector3(0,2.55,sample[1])
			var seconds:=1.2
			var velocity:Vector3=(end-start)/seconds+Vector3.UP*.5*game.Flight.GRAVITY*seconds
			game.launch(frame.to_global(start),frame.global_basis*velocity,"pass",passer)
			var takeoff:=INF
			var correct:=false
			var feet_clear:=true
			for tick in 120:
				var jump=game.set_jumps[libero]
				if jump.active and jump.elapsed<=jump.load_duration() and jump.elapsed+1./60.>jump.load_duration():
					feet_clear=game.libero_feet_behind_line(libero)
				game.step_match(1./60.,page.ground)
				if game.set_jumps[libero].active and not is_finite(takeoff):
					takeoff=game.set_jumps[libero].start.z
				if game.flight_kind!="pass" or game.phase!=game.Phase.LIVE: break
			if game.flight_kind=="set" and game.last_player==libero and game.expected_hitter>=0:
				var pin:Vector3=game.attack_lane_for(game.expected_hitter)
				correct=absf(pin.x)>3. and game.stroke==("Jump set" if sample[2]==2 else "Forearm")
				if sample[2]==2:
					correct=correct and feet_clear and takeoff<game.Net.NET_Z-3.
					if sample[1]>1.: correct=correct and frame.to_local(game.origin).z>1. and game.set_jumps[libero].carry_velocity.z>0.
					pins[signf(pin.x)]=true
				else: correct=correct and not is_finite(takeoff)
			print("side ",side," ball z ",sample[1]," plant z ",takeoff," ",game.stroke," ",game.flight_kind," contact ",frame.to_local(game.origin)," ok ",correct)
			if not correct: failures+=1
	print("pin directions ",pins.keys())
	quit(1 if failures or pins.size()!=2 else 0)
