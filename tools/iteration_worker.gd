extends "res://tools/iterate_matches.gd"

const Policy = preload("res://scripts/cpu_policy.gd")
const Review = preload("res://scripts/match_review.gd")
var run_dir := ""
var started := 0
var limit_ms := 0
var completed := 0
var observations := 0
var latest_score: Array = []
var active_seed := 0
var demo_findings := {}
var next_demo_scan := 0
var reported_demo_findings := -1

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2 or args.size() > 3:
		quit(2)
		return
	var existing := Policy.read_json(Policy.DIRECTORY+"/status.json")
	var worker := int(existing.get("pid",0))
	if existing.get("state","") == "running" and worker > 0 and OS.is_process_running(worker):
		quit(3)
		return
	run_dir = Policy.DIRECTORY+"/runs/"+args[0]
	limit_ms = maxi(0,int(args[1]))*60000
	started = Time.get_ticks_msec()
	scan_demo_findings()
	update_status("running")
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
		var result := await run_match(page,active_seed,0,"")
		latest_score = result.score
		result["build"] = page.build_label
		result["starting_policy"] = starting_policy
		if result.finished:
			completed += 1
			if game.cpu_policy.save_match(game.carried_shot_reads) != OK:
				update_status("Could not save the learning profile")
				break
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
	if Time.get_ticks_msec() >= next_demo_scan: scan_demo_findings()
	update_status("running")
	await process_frame
	return should_stop()

func scan_demo_findings() -> void:
	next_demo_scan = Time.get_ticks_msec()+3000
	Review.collect_findings(demo_findings)
	var path := run_dir+"/demo-findings.json"
	if reported_demo_findings != demo_findings.size() or not FileAccess.file_exists(path):
		if Policy.write_json(path,{"findings":demo_findings.values()}) == OK:
			reported_demo_findings = demo_findings.size()
		else:
			push_warning("Could not write Demo Match review findings")

func keep_observation(point: int, event: Dictionary, frames: Array) -> void:
	if frames.is_empty(): return
	var path := run_dir+"/seed-%d-point-%d.vreplay" % [active_seed,point]
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null: return
	file.store_var({"schema":1,"seed":active_seed,"point":point,"evidence":event,"frames":frames})
	file.close()
	event["replay"] = path

func append_summary(result: Dictionary) -> bool:
	var path := run_dir+"/matches.jsonl"
	var file := FileAccess.open(path,FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file == null: return false
	file.seek_end()
	file.store_line(JSON.stringify(result))
	file.close()
	return true

func update_status(state: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(run_dir))
	Policy.write_json(Policy.DIRECTORY+"/status.json",{"state":state,"pid":OS.get_process_id(),
		"run":run_dir,"matches":completed,"observations":observations,
		"demo_observations":demo_findings.size(),"score":latest_score})
