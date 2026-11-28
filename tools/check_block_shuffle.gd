extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	change_scene_to_file("res://scenes/block_defense_scenario.tscn")
	await scene_changed
	var page=current_scene
	page.set_process(false)
	var game=page.game
	game.start_feed(1,1,1,true)
	var middle:int=game.front_middle(0)
	var actor=game.players[middle]
	var number:int=actor.get_meta("school_jersey_number")
	game.setter_zones[0]=4
	game.begin_point()
	assert(actor.get_meta("school_jersey_number")==96)
	game.setter_zones[0]=1
	game.begin_point()
	assert(actor.get_meta("school_jersey_number")==number and number!=96)
	game.flight_kind="set"
	game.receiving_team=1
	var distances:=[]
	for rating in [0,50,100]:
		actor.attributes.Blocking=rating
		actor.position=Vector3(0,.04,3.42)
		game.court_velocities.erase(middle)
		for tick in 18:
			game.match_clock+=1./60.
			game.move_cpu(middle,game.frames[0].to_global(Vector3(2.8,.04,3.42)),1./60.,7.6,Vector3.BACK,false,false,9.,false,0.,4.7)
		distances.append(absf(actor.position.x))
	assert(distances[2]>distances[1] and distances[1]>distances[0])
	print("PASS middle jersey ",number," restored after libero 96; 0/50/100 Blocking lateral travel in 0.30 s (m): ",distances)
	game.start_feed(4,1,1,true)
	middle=game.front_middle(0)
	actor=game.players[middle]
	assert(actor.get_meta("school_jersey_number")==506 and actor.attributes.Blocking==100)
	var peaks:=[]
	var reactions:=[]
	for rating in [61,100]:
		actor.attributes.Blocking=rating
		actor.position=Vector3(0,.04,3.42)
		var jump=game.Block.new()
		jump.jump_height=1.
		jump.begin(actor)
		jump.lean_input=.5
		jump.reach_input=Vector2(.8,0.)
		jump.age=game.Block.START
		jump.step(1./60.,actor.global_position+Vector3(0,2.8,.5))
		reactions.append(Vector2(jump.lean,jump.reach.x))
		jump.age=game.Block.START+game.Block.AIR*.5
		jump.step(0.,actor.global_position+Vector3(0,2.8,.5))
		peaks.append(actor.position.y-jump.base.y)
	assert(is_equal_approx(peaks[1]-peaks[0],8.*.39*.0254*4./3.))
	assert(reactions[1].x>reactions[0].x and reactions[1].y>reactions[0].y)
	print("PASS blue 506 at 100; same-athlete 61/100 apex (m) ",peaks,"; first-frame torso and hand response ",reactions)
	quit()
