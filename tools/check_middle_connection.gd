extends SceneTree
func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	seed(29017)
	var session=root.get_node("StorySession")
	session.offline_controller=-1
	session.offline_size=6
	session.offline_away_size=6
	change_scene_to_file("res://scenes/offline_match.tscn")
	await scene_changed
	var page=current_scene
	page.set_process(false)
	var game=page.game
	var attempts:=0
	var hits:=0
	var pending:=-1
	var seen:=-1
	for tick in 16000:
		game.step_match(1./60.,page.ground)
		if game.flight_kind=="pass" and game.touches==1 and game.setter_can_run_middle[game.receiving_team]:
			var middle:int=game.front_middle(game.receiving_team)
			if game.rally_setter!=middle: game.rally_hitter=middle
		if game.flight_number!=seen:
			seen=game.flight_number
			if pending>=0 and game.flight_kind=="spike" and game.last_player==pending: hits+=1
			pending=-1
			if game.flight_kind=="set" and game.expected_hitter>=0 and game.expected_hitter==game.front_middle(game.receiving_team) and game.attackers[game.receiving_team].jump.active:
				pending=game.expected_hitter
				attempts+=1
				print("Quick ",attempts," completed ",hits," arrival ",game.attackers[game.receiving_team].pin_arrival)
		if game.phase==game.Phase.FINISHED: game.reset_match()
		if attempts>=9 and pending<0: break
		if tick%180==0: await process_frame
	print("QUICK RESULT ",hits,"/",attempts)
	quit(0 if attempts==9 and hits>=8 else 1)
