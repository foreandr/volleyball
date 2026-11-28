extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	change_scene_to_file("res://scenes/block_defense_scenario.tscn")
	await scene_changed
	var page=current_scene
	page.set_process(false)
	var game=page.game
	page.setup={"defense":3,"offense":1,"attacks":{"left":2},"in_system":true,"repeat":false}
	page.show_settings(false)
	page.run_feed(false)
	game.phase=game.Phase.LIVE
	game.launch(Vector3(1.,1.8,3.),Vector3.BACK*14.,"spike",0,0.)
	var alert_while_live:=false
	for frame in 15:
		page._process(1./60.)
		if game.phase==game.Phase.LIVE and game.net_alert_flight==game.flight_number:
			alert_while_live=true
			break
	game.begin_ball_bounce()
	game.award(1,"Into the net")
	var count:=0
	for event:Dictionary in game.trace.recent_events:
		if event.event=="net_attack_alert": count+=1
	var peak:=0.
	var ground_height:float=game.Flight.FLOOR
	for frame in 180:
		page._process(1./60.)
		if game.phase==game.Phase.DEAD:
			peak=maxf(peak,game.ball.global_position.y)
	var elapsed:float=game.dead_age-game.bounce_start
	print("LAB END alerts ",count," during live play ",alert_while_live," bounce height ",peak-ground_height," hold ",elapsed)
	quit(0 if count==1 and alert_while_live and peak-ground_height>.12 and elapsed>=1.5 and elapsed<1.54 else 1)
