extends "res://tools/iterate_matches.gd"

const Policy = preload("res://scripts/cpu_policy.gd")
const Review = preload("res://scripts/match_review.gd")
const IterationRun = preload("res://scripts/iteration_run.gd")
const PATTERN_PATH := Policy.DIRECTORY+"/training-patterns.json"
const SAMPLE_INTERVAL := 86400
const SAMPLE_RETENTION := 14*86400
var worker_lock := TCPServer.new()
var run_dir := ""
var started := 0
var limit_ms := 0
var completed := 0
var observations := 0
var saved_findings := 0
var latest_finding := {}
var latest_score: Array = []
var active_seed := 0
var demo_findings := {}
var player_markers := {}
var next_demo_scan := 0
var reported_demo_findings := -1
var batch_started := 0
var next_status_at := 0
var saved_matches := 0
var faster := false
var build := ""
var patterns := {}
var duplicate_findings := 0
var next_pattern_save := 0
var next_prune := 0
var pattern_changes := false
var simulated_seconds := 0.0

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
	update_status("running")
	await process_frame
	if should_stop():
		update_status("stopped")
		quit()
		return
	var page := await prepare_match()
	build = page.build_label
	patterns = Policy.read_json(PATTERN_PATH)
	if patterns.is_empty(): patterns = Policy.read_json(PATTERN_PATH+".bak")
	prune_duplicate_replays()
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
	save_patterns()
	unload_current_scene()
	await process_frame
	quit()

func should_stop() -> bool:
	return FileAccess.file_exists(run_dir+"/stop") or (limit_ms > 0 and Time.get_ticks_msec()-started >= limit_ms)

func observation_batch_ticks() -> int:
	return 120 if faster else 30

func pause_match(game: Node3D) -> bool:
	latest_score = game.score.duplicate()
	simulated_seconds = game.match_clock
	var now := Time.get_ticks_msec()
	if now >= next_demo_scan: scan_demo_findings()
	if now >= next_status_at: update_status("running")
	if now >= next_pattern_save: save_patterns()
	if now >= next_prune: prune_duplicate_replays()
	if should_stop(): return true
	if faster:
		await process_frame
	else:
		await create_timer(IterationRun.training_rest(now-batch_started,false)).timeout
	batch_started = Time.get_ticks_msec()
	return should_stop()

func scan_demo_findings() -> void:
	next_demo_scan = Time.get_ticks_msec()+3000
	Review.collect_findings(demo_findings,70)
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
	var sample_frame: Dictionary = frames.back()
	for frame in frames:
		if float(frame.time) >= event_time:
			sample_frame = frame
			break
	var action_label := ""
	var player := int(event.get("player",-1))
	var keys: Array = sample_frame.get("keys",[])
	if player >= 0 and player < keys.size() and keys[player][1]:
		action_label = str(keys[player][0])
	var signature := JSON.stringify([build,event.get("category",""),event.get("type",""),
		event.get("action",""),event.get("surface",""),event.get("reason",""),
		str(sample_frame.get("info","")).get_slice(" | ",0),action_label])
	var pattern: Dictionary = patterns.get_or_add(signature,{"count":0,"last_saved":0,"samples":[]})
	pattern.count += 1
	pattern_changes = true
	event["pattern_count"] = pattern.count
	var now := int(Time.get_unix_time_from_system())
	var samples: Array = pattern.samples
	if samples.size() >= 3 and now-int(pattern.last_saved) < SAMPLE_INTERVAL:
		duplicate_findings += 1
		return
	var lookback := 2.65 if event.get("category","") == "setting" else 1.35
	var nearby := frames.filter(func(frame: Dictionary): return float(frame.time) >= event_time-lookback and float(frame.time) <= event_time+0.40)
	var path := run_dir+"/seed-%d-point-%d-%d.vreplay" % [active_seed,point,Time.get_ticks_usec()]
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null: return
	file.store_var({"schema":1,"seed":active_seed,"point":point,"evidence":event,"frames":frames if nearby.size() < 2 else nearby})
	file.close()
	event["replay"] = path
	if append_row(run_dir+"/observations.jsonl",{"seed":active_seed,"point":point,"evidence":event}):
		samples.append({"path":path,"saved":now})
		pattern.last_saved = now
		saved_findings += 1
		latest_finding = {"number":saved_findings,"type":event.get("type","Finding saved"),"action":event.get("action",""),"replay":path}
	else:
		DirAccess.remove_absolute(path)

func save_patterns() -> void:
	next_pattern_save = Time.get_ticks_msec()+10000
	if not pattern_changes: return
	if Policy.write_json(PATTERN_PATH,patterns) == OK:
		pattern_changes = false
	else:
		push_warning("Could not save training pattern counts")

func prune_duplicate_replays() -> void:
	next_prune = Time.get_ticks_msec()+3600000
	var cutoff := int(Time.get_unix_time_from_system())-SAMPLE_RETENTION
	for pattern in patterns.values():
		var samples: Array = pattern.samples
		# Preserve the first example and the two newest examples for each pattern.
		for index in range(samples.size()-3,0,-1):
			var sample: Dictionary = samples[index]
			var path := str(sample.path).simplify_path()
			if int(sample.saved) >= cutoff or not path.begins_with(Policy.DIRECTORY+"/runs/"):
				continue
			if not path.get_file().begins_with("seed-") or not path.ends_with(".vreplay"):
				continue
			if not FileAccess.file_exists(path) or DirAccess.remove_absolute(path) == OK:
				samples.remove_at(index)
				pattern_changes = true

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
	faster = IterationRun.faster_training()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(run_dir))
	Policy.write_json(Policy.DIRECTORY+"/status.json",{"state":state,"pid":OS.get_process_id(),
		"run":run_dir,"matches":completed,"saved_matches":saved_matches,"observations":observations,
		"heartbeat":Time.get_unix_time_from_system(),"faster":faster,
		"unique_patterns":patterns.size(),"duplicate_findings":duplicate_findings,
		"simulated_seconds":simulated_seconds,
		"latest_finding":latest_finding,"demo_observations":demo_findings.size(),"player_markers":player_markers.size(),"score":latest_score})
