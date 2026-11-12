extends RefCounted

const Trace = preload("res://scripts/setting_trace.gd")
const DIRECTORY := "user://iteration_lab/demo-findings"
const REVIEW_FOCUS := "Animation smoothing and cleanup"
var flight := -1
var dig := {}
var pose := {}
var swing_samples := {}

func reset() -> void:
	flight = -1
	dig = {}
	pose = {}
	swing_samples.clear()

func observe(game: Node3D, delta: float) -> void:
	if game.flight_number != flight:
		flight = game.flight_number
		if game.stroke != "Body deflection": dig = {}
	if game.flight_kind in ["spike","dump","block"]: observe_dig(game)
	observe_swing(game,delta)

func observe_dig(game: Node3D) -> void:
	var side: int = game.receiving_team
	var ball: Vector3 = game.ball.global_position
	if game.frames[side].to_local(ball).z > game.Net.NET_Z+0.07: return
	for index in range(side*game.team_size,(side+1)*game.team_size):
		if index == game.last_player: continue
		var platform: Node3D = game.platforms[index]
		var check: Dictionary = platform.contact_check
		if not check.is_empty() and not check.accepted and is_finite(platform.pressed_at):
			var margin: float = check.margin
			if margin > 0.0 and margin <= 0.16 and margin < float(dig.get("margin_m",INF)):
				dig = {"type":"Close dig missed","player":index,"time":game.match_clock,
					"surface":check.surface,"margin_m":margin,
					"review":"Compare the platform contact window with the frame of closest approach."}
		elif not game.is_human(index) and not is_finite(platform.pressed_at) and not game.owns_action(index) and ball.y >= 0.35 and ball.y <= 1.75:
			var ready: Vector3 = platform.to_global(platform.ready_contact())
			var distance := ball.distance_to(ready)
			if not dig.has("margin_m") and distance <= 0.64 and distance < float(dig.get("distance_m",INF)):
				dig = {"type":"Ball dropped near platform","player":index,"time":game.match_clock,"distance_m":distance,
					"review":"Check receiver assignment and whether the defender could commit earlier."}

func observe_swing(game: Node3D, delta: float) -> void:
	for side in game.attackers.size():
		var driver: Node3D = game.attackers[side]
		if not driver.enabled or not driver.jump.active or not is_finite(driver.swing_drive_started):
			swing_samples.erase(side)
			continue
		var actor: Node3D = driver.setter
		var rig: Skeleton3D = actor.skeleton
		var hand := rig.get_bone_global_pose(rig.find_bone("hand_r")).origin
		var elbow := rig.get_bone_pose_rotation(rig.find_bone("lowerarm_r"))
		var last: Dictionary = swing_samples.get(side,{})
		swing_samples[side] = {"actor":actor,"hand":hand,"elbow":elbow}
		if last.get("actor") != actor or delta <= 0.0 or delta > 0.042: continue
		var degrees := rad_to_deg(elbow.angle_to(last.elbow))
		var travel := rig.to_global(hand).distance_to(rig.to_global(last.hand))
		if degrees >= 68.0 and travel >= maxf(0.35,delta*22.0) and degrees > float(pose.get("degrees",0.0)):
			pose = {"type":"Possible swing snap","player":game.players.find(actor),"time":game.match_clock,
				"degrees":degrees,"travel_m":travel,
				"review":"Compare elbow rotation and wrist travel across the two poses before adjusting the blend."}

func finding(point: Dictionary) -> Dictionary:
	if point.get("reason") == "Ball down" and not dig.is_empty(): return dig
	return pose

func save_finding(game: Node3D, evidence: Dictionary, samples := [], directory := DIRECTORY) -> String:
	var frames: Array = []
	var lookback := 2.1 if directory == Trace.MARKER_REPLAYS else 1.35
	for sample in (game.replay.current if samples.is_empty() else samples):
		if float(sample.time) >= float(evidence.time)-lookback and float(sample.time) <= float(evidence.time)+0.85:
			frames.append(sample)
	if frames.size() < 2 or DirAccess.make_dir_recursive_absolute(directory) != OK: return ""
	var path := directory.path_join("%d-%d.vreplay" % [int(Time.get_unix_time_from_system()*1000000),OS.get_process_id()])
	var file := FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file == null: return ""
	file.store_var({"schema":1,"team_size":game.team_size,"point":game.rallies,"evidence":evidence,"frames":frames,
		"match_id":"%s:%d" % [game.trace.path,game.trace.feed-game.rallies],"score":game.score.duplicate()})
	file.close()
	return path if DirAccess.rename_absolute(path+".tmp",path) == OK else ""

static func collect_findings(known: Dictionary) -> void:
	if not DirAccess.dir_exists_absolute(DIRECTORY): return
	for name_ in DirAccess.get_files_at(DIRECTORY):
		if not name_.ends_with(".vreplay") or known.has(name_): continue
		var path := DIRECTORY.path_join(name_)
		var file := FileAccess.open(path,FileAccess.READ)
		if file == null: continue
		var record: Variant = file.get_var()
		if not record is Dictionary or not record.get("evidence") is Dictionary: continue
		var evidence: Dictionary = record.evidence.duplicate(true)
		evidence["replay"] = ProjectSettings.globalize_path(path)
		var nearest := {}
		var distance := INF
		for sample in record.get("frames",[]):
			var gap := absf(float(sample.get("time",0.0))-float(evidence.get("time",0.0)))
			if gap < distance and sample.get("trace") is Dictionary:
				distance = gap
				nearest = sample.trace
		var priority := 1 if evidence.get("type","") == "Possible swing snap" else 2
		known[name_] = {"source":"demo_match","priority":priority,"type":evidence.get("type",""),"time":evidence.get("time",0.0),
			"point":record.get("point",0),"team_size":record.get("team_size",2),"match_id":record.get("match_id",""),
			"score":record.get("score",[]),"evidence":evidence,"contact_frame":Trace.json_value(nearest)}

static func collect_player_markers(known: Dictionary) -> void:
	if not DirAccess.dir_exists_absolute(Trace.MARKER_DIRECTORY): return
	for name_ in DirAccess.get_files_at(Trace.MARKER_DIRECTORY):
		if not name_.ends_with(".json") or known.has(name_): continue
		var file := FileAccess.open(Trace.MARKER_DIRECTORY.path_join(name_),FileAccess.READ)
		if file == null: continue
		var json := JSON.new()
		if json.parse(file.get_as_text()) != OK or not json.data is Dictionary: continue
		var archived: Dictionary = json.data
		var event: Dictionary = archived.marker
		var evidence: Dictionary = event.data
		evidence["review"] = "Review the marked action, including the transition into it and the recovery out of it."
		if evidence.has("replay"): evidence.replay = ProjectSettings.globalize_path(str(evidence.replay))
		known[name_] = {"source":"player_marker","priority":0,"type":"Player debug marker",
			"time":evidence.get("recorded_at",event.time),"point":evidence.get("point",event.feed),
			"match_id":archived.trace,"trace":archived.trace,"feed":event.feed,"session_ms":event.session_ms,
			"evidence":evidence,"context":archived.get("context",[])}

static func ordered_findings(known: Dictionary) -> Array:
	var names := known.keys()
	names.sort_custom(func(a: String,b: String):
		var left: int = known[a].priority
		var right: int = known[b].priority
		return a > b if left == right else left < right)
	return names.map(func(name_: String): return known[name_])
