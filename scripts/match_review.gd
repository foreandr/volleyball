extends RefCounted

const Trace = preload("res://scripts/setting_trace.gd")
const DIRECTORY := "user://iteration_lab/demo-findings"
const REVIEW_FOCUS := "Animation smoothing and cleanup"
var flight := -1
var dig := {}
var motion_samples := {}
var pending_motion: Array[Dictionary] = []
var motion_flags := {}
var bone_indices := PackedInt32Array()
const MOTION_BONES := ["pelvis","neck_01","lowerarm_l","hand_l","lowerarm_r","hand_r"]

func reset() -> void:
	flight = -1
	dig = {}
	motion_samples.clear()
	pending_motion.clear()
	motion_flags.clear()

func observe(game: Node3D, delta: float) -> void:
	if game.flight_number != flight:
		flight = game.flight_number
		if game.stroke != "Body deflection": dig = {}
	if game.flight_kind in ["spike","dump","block"]: observe_dig(game)
	observe_motion(game,delta)

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

func observe_motion(game: Node3D, delta: float) -> void:
	for index in game.players.size():
		var actor: Node3D = game.players[index]
		var rig: Skeleton3D = actor.skeleton
		if bone_indices.is_empty():
			for name_ in MOTION_BONES: bone_indices.append(rig.find_bone(name_))
		var points := PackedVector3Array()
		for bone in bone_indices: points.append(rig.get_bone_global_pose(bone).origin)
		var rotation := PackedVector4Array()
		for bone in range(2,6):
			var joint := rig.get_bone_pose_rotation(bone_indices[bone])
			rotation.append(Vector4(joint.x,joint.y,joint.z,joint.w))
		var last: Dictionary = motion_samples.get(index,{})
		var scale_ := rig.global_basis.y.length()
		var hip := points[0].lerp(points[1],0.30)
		var chest := points[0].lerp(points[1],0.78)
		var inside := 0.0
		for joint in [2,4]:
			for hand_point in [points[joint+1],points[joint].lerp(points[joint+1],0.68)]:
				var center := Geometry3D.get_closest_point_to_segment(hand_point,hip,chest)
				inside = maxf(inside,0.105-center.distance_to(hand_point)*scale_)
		var clip_time := float(last.get("clip_time",0.0))+delta if inside >= 0.028 else 0.0
		motion_samples[index] = {"points":points,"rotation":rotation,"root":actor.global_position,"yaw":actor.rotation.y,"clip_time":clip_time}
		if last.is_empty() or delta <= 0.0 or delta > 0.06: continue
		var previous_root: Vector3 = last.root
		var travel := actor.global_position-previous_root
		var degrees := absf(rad_to_deg(angle_difference(last.yaw,actor.rotation.y)))
		if degrees >= maxf(39.0,delta*1080.0):
			flag_motion(game,index,"Possible body rotation snap",{"degrees":degrees,"seconds":delta},
				"Compare body facing on the two frames and smooth the turn or action handoff.")
		if travel.slide(Vector3.UP).length() >= maxf(0.32,delta*12.5) or absf(travel.y) >= maxf(0.27,delta*10.5):
			flag_motion(game,index,"Possible body position snap",{"travel_m":travel.length(),"seconds":delta},
				"Check root motion and ground alignment across the transition.")
		if clip_time >= 0.035:
			flag_motion(game,index,"Possible arm clipping",{"inside_m":inside,"seconds":clip_time},
				"Check whether the wrist or forearm passes through the torso during this action.")
		for joint in [2,4]:
			var hand_travel := points[joint+1].distance_to(last.points[joint+1])*scale_
			if hand_travel < maxf(0.32,delta*18.0): continue
			var turn := 0.0
			for sample in [joint-2,joint-1]:
				var current: Vector4 = rotation[sample]
				var previous: Vector4 = last.rotation[sample]
				turn = maxf(turn,rad_to_deg(Quaternion(current.x,current.y,current.z,current.w).angle_to(Quaternion(previous.x,previous.y,previous.z,previous.w))))
			if turn < maxf(64.0,delta*1520.0): continue
			var action := motion_action(game,index)
			flag_motion(game,index,"Possible swing snap" if action == "attack" else "Possible arm snap",
				{"degrees":turn,"travel_m":hand_travel,"arm":actor.animation_side("l" if joint == 2 else "r"),"seconds":delta},
				"Compare the elbow and wrist on both sides of the action transition.")

func motion_action(game: Node3D, index: int) -> String:
	var actor: Node3D = game.players[index]
	if game.serve.player == actor and game.serve_pending and not game.serve.moved_after_contact and game.serve.swing_time <= game.serve.recovery_end():
		return "serve"
	var driver: Node3D = game.attackers[game.team(index)]
	if driver.enabled and driver.setter == actor and (driver.jump.active or driver.stage == driver.Stage.HIT): return "attack"
	if game.blocks.has(index): return "block"
	if game.set_jumps[index].active: return "jump set"
	if is_finite(game.platforms[index].pressed_at): return "receive"
	return str(actor.animator.current_animation)

func flag_motion(game: Node3D, index: int, type: String, measures: Dictionary, instruction: String) -> void:
	var action := motion_action(game,index)
	var key := "%d:%s:%s" % [index,action,type]
	if motion_flags.has(key): return
	motion_flags[key] = true
	measures.merge({"type":type,"category":"animation","player":index,"action":action,"time":game.match_clock,"review":instruction})
	pending_motion.append(measures)

func take_motion(time: float, flush: bool) -> Array[Dictionary]:
	var ready: Array[Dictionary] = []
	while not pending_motion.is_empty() and (flush or time-float(pending_motion.front().time) >= 0.24):
		ready.append(pending_motion.pop_front())
	return ready

func finding(point: Dictionary) -> Dictionary:
	if point.get("reason") == "Ball down" and not dig.is_empty(): return dig
	return {}

func unplayed_set(game: Node3D) -> Dictionary:
	if game.touches != 2 or game.last_player < 0 or game.flight_kind not in ["set","pass"]: return {}
	var side: int = game.team(game.last_player)
	var reason: String = game.last_point.get("reason","")
	if game.possession_team != side or game.last_point.get("winner",-1) != 1-side or reason not in ["Ball down","Into the net","Out"]: return {}
	var set_pin := Vector3.INF
	if game.expected_hitter >= 0: set_pin = game.attackers[side].rally_set_target
	return {"type":"No third touch after set","category":"setting","time":game.match_clock,"setter":game.last_player,
		"hitter":game.expected_hitter,"reason":reason,"set_pin":Trace.json_value(set_pin),"apex":game.last_set_apex,
		"review":"Check whether the set gives the hitter a reachable contact and enough time for an approach."}

func save_finding(game: Node3D, evidence: Dictionary, samples := [], directory := DIRECTORY) -> String:
	var frames: Array = []
	var lookback := 2.1 if directory == Trace.MARKER_REPLAYS else 1.35
	if evidence.get("category","") == "setting": lookback = 2.65
	for sample in (game.replay.current if samples.is_empty() else samples):
		if float(sample.time) >= float(evidence.time)-lookback and float(sample.time) <= float(evidence.time)+0.85:
			frames.append(sample)
	if frames.size() < 2 or DirAccess.make_dir_recursive_absolute(directory) != OK: return ""
	var path := directory.path_join("%d-%d.vreplay" % [int(Time.get_unix_time_from_system()*1000000),OS.get_process_id()])
	var file := FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file == null: return ""
	file.store_var({"schema":1,"team_size":game.team_size,"point":evidence.get("point",game.rallies),"evidence":evidence,"frames":frames,
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
		var priority := 1 if evidence.get("category","") == "animation" or evidence.get("type","") == "Possible swing snap" else 2
		known[name_] = {"source":"demo_match","priority":priority,"type":evidence.get("type",""),"time":evidence.get("time",0.0),
			"point":record.get("point",0),"team_size":record.get("team_size",2),"match_id":record.get("match_id",""),
			"score":record.get("score",[]),"evidence":Trace.json_value(evidence),"contact_frame":Trace.json_value(nearest)}

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
