extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var page=load("res://scenes/block_defense_scenario.tscn").instantiate()
	page.roster_path="user://block-shuffle-test-%d-%d.cfg"%[OS.get_process_id(),Time.get_ticks_usec()]
	root.add_child(page)
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
	game.start_feed(4,1,1,true)
	middle=game.front_middle(0)
	actor=game.players[middle]
	assert(actor.get_meta("school_jersey_number")==506 and actor.attributes.Blocking==100)
	game.phase=game.Phase.LIVE
	game.flight_kind="set"
	game.receiving_team=1
	var distances:=[]
	for rating in [0,61,100]:
		actor.attributes.Blocking=rating
		actor.position=Vector3(0,.04,3.42)
		game.court_velocities.erase(middle)
		for tick in 18:
			game.match_clock+=1./60.
			game.move_cpu(middle,game.frames[0].to_global(Vector3(2.8,.04,3.42)),1./60.,7.6,Vector3.BACK,false,false,9.,false,0.,4.7)
		distances.append(absf(actor.position.x))
	assert(distances[2]>distances[1] and distances[1]>distances[0])
	assert(absf(distances[2]/distances[1]-1.30)<.005)
	print("PASS blue #506: 0/61/100 Blocking lateral travel in 0.30 s (m): ",distances)
	actor.rotation.y=.7
	for tick in 30:
		game.match_clock+=1./60.
		game.move_cpu(middle,game.frames[0].to_global(Vector3(-2.8,.04,3.42)),1./60.,7.6,Vector3.RIGHT,true,true)
		assert(actor.animator.current_animation!=actor.animation_slots["run"])
	assert(absf(actor.rotation.y)<.001 and game.footwork[middle].weight>.5)
	game.animated.fill(false)
	game.advance_idle_players(1./60.)
	assert(absf(actor.rotation.y)<.001)
	for inches in [30.,40.,50.]:
		for rating in [0,90,100]:
			actor.attributes.Blocking=rating
			assert(is_equal_approx(game.Block.bonus_height(actor,inches*.0254)/.0254,inches*rating*.001))
	print("PASS net-facing shuffle, idle and percentage bonus for 30/40/50 inches at 0/90/100 Blocking")
	var peaks:=[]
	var reactions:=[]
	actor.position.y=.04
	var ceiling:float=game.Block.maximum_block_lift(actor)
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
	for i in 2:
		var rated_lift:float=(1.+.1*[.61,1.][i])*game.Block.Jump.COURT_VERTICAL_SCALE
		assert(is_equal_approx(peaks[i],minf(ceiling,rated_lift)))
	assert(reactions[1].x>reactions[0].x and reactions[1].y>reactions[0].y)
	print("PASS blue 506 at 100; same-athlete 61/100 apex (m) ",peaks,"; first-frame torso and hand response ",reactions)
	for side in 2:
		actor=game.players[game.front_middle(side)]
		for requested in [.36,2.5]:
			actor.position=Vector3(0,.04,3.42)
			actor.rotation.y=0.
			var jump=game.Block.new()
			jump.square_block=true
			jump.jump_height=requested
			jump.begin(actor)
			var ahead:Vector3=actor.global_basis.z.normalized()
			var ball_at:=Vector3(0,3.1,game.Net.NET_Z)
			jump.age=jump.START+jump.AIR*.17
			jump.step(0.,ball_at)
			assert((jump.wrists[0]-jump.shoulders[0]).y>.34)
			jump.age=jump.START+jump.AIR*.5
			jump.step(0.,ball_at)
			var rig:Skeleton3D=actor.skeleton
			var chest:=rig.to_global(rig.get_bone_global_pose(rig.find_bone("spine_03")).origin)
			var waist:=rig.to_global(rig.get_bone_global_pose(rig.find_bone("spine_01")).origin)
			assert(chest.y<=game.Net.NET_TOP+jump.MAX_CHEST_ABOVE_TAPE+.01)
			assert(waist.y<game.Net.NET_TOP-.10)
			if requested<1.:
				assert(actor.position.y-jump.base.y<.60)
				continue
			assert(chest.y>=game.Net.NET_TOP-.16)
			for i in 2:
				assert((jump.wrists[i]-jump.shoulders[i]).dot(ahead)>.30)
				assert((jump.hands[i]-ball_at).dot(ahead)>.07)
				assert(jump.hands[i].y-jump.wrists[i].y<.025)
			print("PASS side ",side," apex chest/tape ",chest.y-game.Net.NET_TOP," m, fingertips over tape ",(jump.hands[0]-ball_at).dot(ahead)," m")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(page.roster_path))
	quit()
