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
	var failures:=0
	# Original replay sample, 54 ms after release. The ball would cross the tape
	# after the middle's contact, which used to send 507 after a phantom overpass.
	g.start_feed(3,1,2,true,1)
	var hitter:int=g.front_middle(1)
	var setter:int=g.first_on(1)+g.lineup_roles[1].find(0)
	g.phase=g.Phase.LIVE
	g.last_was_block=false
	g.launch(Vector3(.8811,3.4012,5.4297),Vector3(-6.2301,1.9643,-2.2398),"set",setter,0.,hitter,Vector3(-1.355,3.347,4.626))
	g.attackers[1].approach_expected_hit_at=g.attackers[1].clock+.341
	var stole_attack:bool=g.position_overpass(1./60.)
	g.launch(Vector3(0,3.25,4.55),Vector3(0,0,-2.25),"pass",setter)
	var played_overpass:bool=g.position_overpass(1./60.)
	print("31 preserved ",not stole_attack," unclaimed crossing recognized ",played_overpass)
	if stole_attack or not played_overpass: failures+=1
	for test_seed:int in [185,24,81,143]:
		seed(test_seed)
		g.start_feed(3,1,2,true,1)
		g.middle_31[1]=true
		var middle:int=g.front_middle(0)
		var pin:int=g.first_on(0)+g.lineup_roles[0].find(0)
		var actual:=false
		var reached:=false
		var upright:=[false,false]
		var displaced:=false
		var late:=[false,false]
		var observed:=[false,false]
		for tick in 540:
			if test_seed==143 and not displaced and g.flight_kind=="set" and g.expected_hitter==g.front_middle(1):
				# A missed first shuffle leaves the middle more than one arm-width outside.
				g.players[middle].position.x=.64
				g.court_velocities.erase(middle)
				displaced=true
			g.step_match(1./60.,page.ground)
			if g.flight_kind=="set" and g.expected_hitter==g.front_middle(1): actual=true
			if actual and g.flight_kind in ["set","spike"] and g.phase==g.Phase.LIVE:
				for j in 2:
					var i:int=[middle,pin][j]
					if not g.blocks.has(i): continue
					var block=g.blocks[i]
					if block.wrists.size()!=2 or g.players[i].position.y<.4: continue
					observed[j]=true
					var good:bool=block.square_block
					var extended:=false
					for hand in 2:
						var lift:Vector3=block.wrists[hand]-block.shoulders[hand]
						good=good and lift.y>.38 and absf(lift.x)<.20
						extended=extended or (lift.y>.34 and absf(lift.x)>.16 and lift.x*(block.late_quick_x-g.players[i].global_position.x)>0.)
					if good: upright[j]=true
					if extended and is_finite(block.late_quick_x): late[j]=true
			if actual and g.flight_kind=="spike":
				reached=g.players[middle].position.y>.25
				break
			if g.phase==g.Phase.DEAD: break
		print("Tempo-one 31 seed ",test_seed," attacked ",actual," 506 up at spike ",reached," square ",upright," one arm ",late," airborne ",observed)
		if (displaced and not late[0]) or not reached or not (upright[0] or late[0]) or not (upright[1] or late[1]): failures+=1
	quit(1 if failures else 0)
