extends SceneTree

const STEP := 1.0/60.0
const TICKS_PER_TARGET_POINT := 3000
const CAPTURE_FRAMES := 24
const REVIEW_STEP := 1.0/12.0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		push_error("Expected output path, first seed, and match count")
		quit(2)
		return
	var first_seed := int(args[1])
	var count := int(args[2])
	var review_point := int(args[3]) if args.size() > 3 else 0
	var results := []
	var timed_out := false
	var series := args.size() > 4 and args[4] == "series"
	var page: Node
	for number in count:
		var match_seed := first_seed+number
		seed(match_seed)
		if page == null:
			page = await prepare_match()
		else:
			page.demo_match.reset_match()
		var result := await run_match(page,match_seed,review_point,args[0].get_base_dir())
		results.append(result)
		var finished := bool(result.review_rendered if review_point > 0 else result.finished)
		timed_out = timed_out or not finished
		if not series or not finished or number == count-1:
			unload_current_scene()
			await process_frame
			page = null
	var output := FileAccess.open(args[0],FileAccess.WRITE)
	if output == null:
		push_error("Could not write " + args[0])
		quit(2)
		return
	output.store_string(JSON.stringify({"matches":results},"  ",true,true))
	output.close()
	quit(1 if timed_out else 0)

func prepare_match() -> Node:
	change_scene_to_file("res://scenes/story_animations.tscn")
	await process_frame
	await process_frame
	var page := current_scene
	page.set_process(false)
	page.start_demo_match(2,false)
	var game: Node3D = page.demo_match
	game.set_spectator(true)
	game.set_attack_vertical(40)
	game.block_vertical = 25
	game.set_serve_vertical(30)
	game.set_spike_strength(75)
	game.passing_skill = 55
	game.setting_skill = 65
	return page

func pause_match(_game: Node3D) -> bool:
	return false

func keep_observation(_point: int, _event: Dictionary, _frames: Array) -> void:
	pass

func run_match(page: Node, match_seed: int, review_point: int, output_dir: String) -> Dictionary:
	var game: Node3D = page.demo_match
	var prior_matches: int = int(game.completed_read_matches) if game.has_method("remember_opponent_reads") else 0
	var counts := {}
	var rallies := []
	var review_frames := []
	var review_deadline := INF
	var review_rendered := false
	var previous_flight := -1
	var previous_rally := 0
	var rally_started: float = game.match_clock
	var closest_attempt := {}
	var closest_unattempted := {}
	var deflection := {}
	var evidence_frames := []
	var watching: bool = game.has_method("set_cpu_swing_power") and bool(game.cpu_policy.training)
	var stuck_frames := 0
	var last_ball := Vector3.INF
	var flags := []
	for tick in range(game.WIN_SCORE*TICKS_PER_TARGET_POINT):
		if watching and tick%120 == 0 and await pause_match(game): break
		game.step_match(STEP,page.player_controls)
		if game.phase == game.Phase.LIVE:
			if review_point == game.rallies+1 and DisplayServer.get_name() != "headless":
				review_frames.append(game.replay.capture(game))
			if game.flight_number != previous_flight:
				if game.stroke == "Body deflection" and (not closest_attempt.is_empty() or not closest_unattempted.is_empty()):
					deflection = closest_attempt if not closest_attempt.is_empty() else closest_unattempted
				else:
					deflection = {}
					evidence_frames.clear()
				closest_attempt = {}
				closest_unattempted = {}
				previous_flight = game.flight_number
				var kind: String = game.flight_kind
				counts[kind] = int(counts.get(kind,0))+1
				if game.stroke == "Body deflection":
					counts.body_deflections = int(counts.get("body_deflections",0))+1
			if game.ball.global_position.is_equal_approx(last_ball) and not game.held_ball:
				stuck_frames += 1
				if stuck_frames == 60: flags.append({"point":game.rallies+1,"type":"ball stayed still for one second"})
			else:
				stuck_frames = 0
			last_ball = game.ball.global_position
			if watching and not deflection.is_empty() and tick%3 == 0:
				evidence_frames.append(game.replay.capture(game))
				if evidence_frames.size() > 24: evidence_frames.pop_front()
			if game.flight_kind in ["spike","dump","block"]:
				var side: int = game.receiving_team
				var ball: Vector3 = game.ball.global_position
				if game.frames[side].to_local(ball).z <= game.Net.NET_Z+0.07:
					for index in range(side*2,side*2+2):
						if index == game.last_player: continue
						var platform: Node3D = game.platforms[index]
						if watching and tick%3 == 0 and game.players[index].global_position.distance_to(ball) < 2.65:
							evidence_frames.append(game.replay.capture(game))
							if evidence_frames.size() > 24: evidence_frames.pop_front()
						var check: Dictionary = platform.contact_check
						if not check.is_empty() and not bool(check.accepted):
							var margin := float(check.margin)
							if margin > 0.0 and margin <= 0.16 and margin < float(closest_attempt.get("margin_m",INF)):
								closest_attempt = {"type":"close attempted dig","player":index,"time":game.match_clock,
									"surface":check.surface,"margin_m":margin}
						elif not is_finite(platform.pressed_at) and not game.owns_action(index) and ball.y >= 0.35 and ball.y <= 1.75:
							var ready: Vector3 = platform.to_global(platform.ready_contact())
							var distance := ball.distance_to(ready)
							if distance <= 0.80 and distance < float(closest_unattempted.get("distance_m",INF)):
								closest_unattempted = {"type":"ball near a defender without an attempt","player":index,
									"time":game.match_clock,"distance_m":distance}
		if game.rallies != previous_rally:
			previous_rally = game.rallies
			var reason: String = game.last_point.reason
			rallies.append({"point":previous_rally,"score":game.score.duplicate(),"reason":reason,
				"seconds":snappedf(game.match_clock-rally_started,0.001),
				"floor_rebound_m":snappedf(game.bounce_velocity.y**2/(2.0*game.Flight.GRAVITY),0.0001) if game.bounce_end > 0.0 else null})
			if reason == "Ball down":
				var opportunity := closest_attempt if not closest_attempt.is_empty() else closest_unattempted
				if opportunity.is_empty(): opportunity = deflection
				if not opportunity.is_empty():
					opportunity["point"] = previous_rally
					opportunity["outcome"] = "body deflection" if opportunity == deflection else "untouched ball down"
					if watching: keep_observation(previous_rally,opportunity,evidence_frames)
					flags.append(opportunity)
			evidence_frames.clear()
			closest_attempt = {}
			closest_unattempted = {}
			deflection = {}
			rally_started = game.match_clock
			if review_point == game.rallies and not review_frames.is_empty():
				review_deadline = game.match_clock+clampf(game.bounce_end+0.12,0.45,1.60)
		if is_finite(review_deadline):
			review_frames.append(game.replay.capture(game))
			if game.match_clock >= review_deadline or game.phase == game.Phase.READY:
				review_rendered = await render_review(page,game,review_frames,output_dir,match_seed,review_point)
				break
		if game.phase == game.Phase.FINISHED and not is_finite(review_deadline): break
	return {"seed":match_seed,"score":game.score.duplicate(),"finished":game.phase == game.Phase.FINISHED,
		"counts":counts,"rallies":rallies,"review_flags":flags,"review_rendered":review_rendered,"learned_from_matches":prior_matches}

func render_review(page: Node, game: Node3D, frames: Array, output_dir: String, match_seed: int, point: int) -> bool:
	var camera: Camera3D = page.preview_camera
	var viewport := camera.get_viewport()
	var focus := Vector3(0.0,1.05,4.0)
	var anchors := [Vector3(0.0,6.5,-11.0),Vector3(12.5,6.0,4.0)]
	var saved: Dictionary = game.replay.capture(game)
	var camera_transform := camera.global_transform
	var tiles := Image.create_empty(320*CAPTURE_FRAMES,180*anchors.size(),false,Image.FORMAT_RGB8)
	var point_end: float = game.last_point.time
	for view in anchors.size():
		camera.global_position = anchors[view]
		camera.look_at(focus)
		var index := 0
		for column in CAPTURE_FRAMES:
			var time := point_end+(column-18)*REVIEW_STEP
			while index+1 < frames.size() and float(frames[index+1].time) <= time: index += 1
			var first: Dictionary = frames[index]
			var second: Dictionary = frames[mini(index+1,frames.size()-1)]
			var blend := clampf((time-float(first.time))/maxf(0.0001,float(second.time)-float(first.time)),0.0,1.0)
			game.replay.apply(game,first,second,blend)
			await process_frame
			await RenderingServer.frame_post_draw
			var image := viewport.get_texture().get_image()
			image.resize(320,180,Image.INTERPOLATE_LANCZOS)
			image.convert(Image.FORMAT_RGB8)
			tiles.blit_rect(image,Rect2i(0,0,320,180),Vector2i(column*320,view*180))
	var written := tiles.save_png(output_dir.path_join("seed-%d-point-%d.png" % [match_seed,point]))
	camera.global_transform = camera_transform
	game.replay.apply(game,saved,saved,0.0)
	game.ball.global_transform = saved.match_ball
	game.ball.visible = saved.match_visible
	game.serve.ball.visible = saved.serve_visible
	return written == OK
