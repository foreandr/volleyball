extends "res://tools/iterate_matches.gd"

const Policy = preload("res://scripts/cpu_policy.gd")
const Review = preload("res://scripts/match_review.gd")
const IterationRun = preload("res://scripts/iteration_run.gd")
var worker_lock := TCPServer.new()
var run_dir := ""
var started := 0
var limit_ms := 0
var completed := 0
var observations := 0
var latest_score: Array = []
var active_seed := 0
var demo_findings := {}
var player_markers := {}
var next_demo_scan := 0
var reported_demo_findings := -1
var batch_started := 0
var next_status_at := 0
var saved_matches := 0

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2 or args.size() > 3:
		quit(2)
		return
	if worker_lock.listen(IterationRun.worker_port(),"127.0.0.1") != OK:
		quit(3)
		return
	var existing := Policy.read_json(Policy.DIRECTORY+"/status.json")
	var worker := int(existing.get("pid",0))
	if not existing.has("heartbeat") and existing.get("state","") == "running" and worker > 0 and OS.is_process_running(worker):
		quit(3)
		return
	run_dir = Policy.DIRECTORY+"/runs/"+args[0]
	limit_ms = maxi(0,int(args[1]))*60000
	started = Time.get_ticks_msec()
	var previous_policy := Policy.read_json(Policy.PATH)
	if previous_policy.is_empty(): previous_policy = Policy.read_json(Policy.PATH+".bak")
	saved_matches = int(previous_policy.get("matches",0))
	scan_demo_findings()
	update_status("running")
	await process_frame
	if should_stop():
		update_status("stopped")
		quit()
		return
	var page := await prepare_match()
	var game: Node3D = page.demo_match
	game.cpu_policy.training = true
	game.cpu_policy.load_profile()
	game.completed_read_matches = game.cpu_policy.matches
	var history: Array = game.cpu_policy.shot_history
	for side in mini(2,history.size()):
		if not history[side] is Dictionary: continue
		for zone in history[side]:
			var sample: Variant = history[side][zone]
			if sample is Array and sample.size() == 2:
				game.carried_shot_reads[side][int(zone)] = Vector2(float(sample[0]),float(sample[1]))
	game.trace.close(0.0)
	while not should_stop():
		active_seed = int(args[2])+completed if args.size() == 3 else int(Time.get_unix_time_from_system()) ^ game.cpu_policy.matches
		var starting_policy := run_dir+"/seed-%d-policy.json" % active_seed
		var snapshot := {"schema":Policy.SCHEMA,"matches":game.cpu_policy.matches,
			"tactics":game.cpu_policy.table,"shot_history":game.cpu_policy.shot_history,"build":page.build_label}
		if Policy.write_json(starting_policy,snapshot) != OK:
			update_status("Could not save the match starting state")
			break
		seed(active_seed)
		game.reset_match()
		batch_started = Time.get_ticks_msec()
		var result := await run_match(page,active_seed,0,"")
		latest_score = result.score
		result["build"] = page.build_label
		result["starting_policy"] = starting_policy
		if result.finished:
			completed += 1
			if game.cpu_policy.save_match(game.carried_shot_reads) != OK:
				update_status("Could not save the learning profile")
				break
			saved_matches = game.cpu_policy.matches
		observations += result.review_flags.size()
		if not append_summary(result):
			update_status("Could not save the run log")
			break
		if not result.finished and not should_stop():
			update_status("Match exceeded its time limit")
			break
		update_status("running")
	if should_stop():
		scan_demo_findings()
		update_status("stopped")
	unload_current_scene()
	await process_frame
	quit()

func should_stop() -> bool:
	return FileAccess.file_exists(run_dir+"/stop") or (limit_ms > 0 and Time.get_ticks_msec()-started >= limit_ms)

func pause_match(game: Node3D) -> bool:
	latest_score = game.score.duplicate()
	var now := Time.get_ticks_msec()
	if now >= next_demo_scan: scan_demo_findings()
	if now >= next_status_at: update_status("running")
	if should_stop(): return true
	var rest := clampf(float(now-batch_started)*0.00055,0.008,0.10)
	await create_timer(rest).timeout
	batch_started = Time.get_ticks_msec()
	return should_stop()

func scan_demo_findings() -> void:
	next_demo_scan = Time.get_ticks_msec()+3000
	Review.collect_findings(demo_findings)
	Review.collect_player_markers(player_markers)
	var path := run_dir+"/demo-findings.json"
	var count := demo_findings.size()+player_markers.size()
	if reported_demo_findings != count or not FileAccess.file_exists(path):
		var findings := demo_findings.duplicate()
		findings.merge(player_markers)
		if Policy.write_json(path,{"review_focus":Review.REVIEW_FOCUS,"findings":Review.ordered_findings(findings)}) == OK:
			reported_demo_findings = count
		else:
			push_warning("Could not write Demo Match review findings")

func keep_observation(point: int, event: Dictionary, frames: Array) -> void:
	if frames.is_empty(): return
	var event_time := float(event.get("time",frames.back().time))
	var lookback := 2.65 if event.get("category","") == "setting" else 1.35
	var nearby := frames.filter(func(frame: Dictionary): return float(frame.time) >= event_time-lookback and float(frame.time) <= event_time+0.40)
	var path := run_dir+"/seed-%d-point-%d-%d.vreplay" % [active_seed,point,Time.get_ticks_usec()]
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null: return
	file.store_var({"schema":1,"seed":active_seed,"point":point,"evidence":event,"frames":frames if nearby.size() < 2 else nearby})
	file.close()
	event["replay"] = path
	append_row(run_dir+"/observations.jsonl",{"seed":active_seed,"point":point,"evidence":event})

func append_summary(result: Dictionary) -> bool:
	return append_row(run_dir+"/matches.jsonl",result)

func append_row(path: String, data: Dictionary) -> bool:
	var file := FileAccess.open(path,FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file == null: return false
	file.seek_end()
	file.store_line(JSON.stringify(data))
	file.close()
	return true

func update_status(state: String) -> void:
	next_status_at = Time.get_ticks_msec()+1000
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(run_dir))
	Policy.write_json(Policy.DIRECTORY+"/status.json",{"state":state,"pid":OS.get_process_id(),
		"run":run_dir,"matches":completed,"saved_matches":saved_matches,"observations":observations,
		"heartbeat":Time.get_unix_time_from_system(),
		"demo_observations":demo_findings.size(),"player_markers":player_markers.size(),"score":latest_score})
