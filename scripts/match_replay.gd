extends RefCounted

const SAVED_DIRECTORY := "user://saved-replays"

var current: Array[Dictionary] = []
var previous: Array[Dictionary] = []
var frames: Array[Dictionary] = []
var restore := {}
var active := false
var playing := false
var clock := 0.0
var speed := 0.5
var index := 0
var ball_offset := Vector3.ZERO
var actor_offsets := {}
var saved_evidence := {}
var suspended_modifiers: Array[SkeletonModifier3D] = []

func capture(match_: Node3D) -> Dictionary:
	var actors := []
	for actor in match_.players:
		var bones: Array[Transform3D] = []
		for bone in actor.skeleton.get_bone_count(): bones.append(actor.skeleton.get_bone_pose(bone))
		actors.append({"root":actor.transform,"model":actor.model.transform,"bones":bones,"mirrored":actor.mirror_animation})
	var shown: Node3D = match_.ball if match_.ball.visible else match_.serve.ball
	var keys := []
	for i in match_.key_labels.size():
		var key: Label3D = match_.key_labels[i]
		var animation_label: Label3D = match_.animation_labels[i]
		keys.append([key.text,key.visible,animation_label.text,animation_label.visible])
	return {"meter":match_.manual.timing() if match_.manual else {},"held_buttons":match_.held_input.read_buttons(),"time":match_.match_clock,"actors":actors,"ball":shown.global_transform,"visible":shown.visible,
		"match_ball":match_.ball.global_transform,"match_visible":match_.ball.visible,"serve_visible":match_.serve.ball.visible,
		"score":match_.score_label.text,"info":match_.info.text,"keys":keys,"aim":match_.aim_ring.visible,"guide":match_.trajectory_node.visible}

func record(match_: Node3D) -> void:
	var sample := capture(match_)
	sample["trace"] = match_.trace_snapshot()
	current.append(sample)

func finish_point() -> void:
	if not current.is_empty(): previous = current
	current = []

func reset() -> void:
	current = []
	previous = []

func duration() -> float:
	return frames.back().time-frames.front().time if frames.size() > 1 else 0.0

func toggle(match_: Node3D, current_finished: bool, rep_frames: Array[Dictionary] = []) -> void:
	if active:
		active = false
		playing = false
		ball_offset = Vector3.ZERO
		actor_offsets.clear()
		saved_evidence.clear()
		apply(match_,restore,restore,0.0)
		for modifier in suspended_modifiers:
			if is_instance_valid(modifier): modifier.active=true
		suspended_modifiers.clear()
		match_.ball.global_transform = restore.match_ball
		match_.ball.visible = restore.match_visible
		match_.serve.ball.visible = restore.serve_visible
		match_.aim_ring.visible = restore.aim
		match_.trajectory_node.visible = restore.guide
		match_.update_flight_guide()
		restore.clear()
		frames = []
		return
	frames = rep_frames if not rep_frames.is_empty() else (current if (current_finished or previous.is_empty()) and not current.is_empty() else previous)
	if frames.size() < 2: return
	restore = capture(match_)
	for actor in match_.players:
		for modifier in actor.skeleton.get_children():
			if modifier is SkeletonModifier3D and modifier.active:
				suspended_modifiers.append(modifier)
				modifier.active=false
	index = 0
	active = true
	match_.flight_guide.hide()
	playing = true
	match_.serve.ball.hide()
	match_.aim_ring.hide()
	match_.trajectory_node.hide()
	seek(match_,0.0)

func freeze_here(match_:Node3D) -> void:
	if active:
		toggle(match_,false)
		return
	var recent:Array[Dictionary]=previous.duplicate()
	recent.append_array(current)
	var now:=capture(match_)
	now["trace"]=match_.trace_snapshot()
	if not recent.is_empty() and recent.back().time>=now.time:
		recent.pop_back()
	recent.append(now)
	if recent.size()<2: return
	toggle(match_,true,recent)
	playing=false
	seek(match_,duration())

func seek(match_: Node3D, value: float) -> void:
	if not active: return
	clock = clampf(value,0.0,duration())
	var sample: float = frames.front().time+clock
	if frames[index].time > sample: index = 0
	while index+1 < frames.size() and float(frames[index+1].time) <= sample+0.000001: index += 1
	var first := frames[index]
	var second := frames[mini(index+1,frames.size()-1)]
	var blend := clampf((sample-float(first.time))/maxf(0.00001,float(second.time)-float(first.time)),0.0,1.0)
	apply(match_,first,second,blend)

func seek_frame(match_: Node3D, frame: int) -> void:
	if not active: return
	seek(match_,float(frames[clampi(frame,0,frames.size()-1)].time)-float(frames.front().time))

func step_frame(match_: Node3D, direction: int) -> void:
	if not active: return
	playing = false
	var sample: float = frames.front().time+clock
	var next := index+direction
	# Between captures, stepping back lands on the earlier capture first.
	if direction < 0 and sample > float(frames[index].time)+0.000001: next = index
	seek_frame(match_,next)

func step(match_: Node3D, delta: float) -> void:
	if playing:
		seek(match_,clock+delta*speed)
		if clock >= duration(): playing = false

func apply(match_: Node3D, first: Dictionary, second: Dictionary, blend: float) -> void:
	match_.replay_meter=first.get("meter",{})
	match_.held_input.reviewing=active
	match_.held_input.display(first.get("held_buttons",-1))
	for i in match_.players.size():
		var actor: Node3D = match_.players[i]
		var a: Dictionary = first.actors[i]
		var b: Dictionary = second.actors[i]
		actor.transform = a.root.interpolate_with(b.root,blend)
		actor.global_position += Vector3(actor_offsets.get(i,Vector3.ZERO))
		actor.model.transform = a.model.interpolate_with(b.model,blend)
		for bone in actor.skeleton.get_bone_count():
			var pose: Transform3D = a.bones[bone].interpolate_with(b.bones[bone],blend)
			actor.skeleton.set_bone_pose(bone,pose)
		var key: Label3D = match_.key_labels[i]
		key.text = first.keys[i][0]
		key.visible = first.keys[i][1]
		key.global_position = actor.global_position+Vector3.UP*2.18
		var animation_label: Label3D = match_.animation_labels[i]
		animation_label.text = first.keys[i][2] if first.keys[i].size() > 2 else ""
		animation_label.visible = first.keys[i].size() > 3 and first.keys[i][3]
		animation_label.global_position = key.global_position+Vector3.UP*0.32
	match_.ball.global_transform = first.ball.interpolate_with(second.ball,blend)
	match_.ball.global_position += ball_offset
	match_.ball.visible = first.visible
	match_.score_label.text = first.score
	match_.info.text = first.info
	match_.player_label.global_position = match_.human.global_position+Vector3.UP*2.17

static func saved_directory(title: String) -> String:
	return SAVED_DIRECTORY.path_join(title.to_snake_case())

static func latest_saved(title: String) -> Dictionary:
	var directory := saved_directory(title)
	if not DirAccess.dir_exists_absolute(directory): return {}
	var names := DirAccess.get_files_at(directory)
	names.sort()
	for i in range(names.size()-1,-1,-1):
		if not names[i].ends_with(".vreplay"): continue
		var file := FileAccess.open(directory.path_join(names[i]),FileAccess.READ)
		if file == null: continue
		var record: Variant = file.get_var()
		if record is Dictionary and record.get("schema") == 1 and record.get("evidence",{}).get("drill") == title:
			return record
	return {}

func open_saved(match_: Node3D, record: Dictionary, camera: Camera3D) -> bool:
	var selected: Array[Dictionary] = []
	selected.assign(record.get("frames",[]))
	if selected.size() < 2: return false
	if active: toggle(match_,true)
	toggle(match_,true,selected)
	restore_saved_view(match_,record.evidence,camera)
	return true

func restore_saved_view(match_: Node3D, evidence: Dictionary, camera: Camera3D) -> void:
	saved_evidence = evidence.duplicate()
	playing = false
	ball_offset = evidence.get("ball_offset",Vector3.ZERO)
	actor_offsets = evidence.get("actor_offsets",{}).duplicate()
	speed = float(evidence.get("speed",speed))
	camera.global_transform = evidence.get("camera",camera.global_transform)
	camera.fov = float(evidence.get("fov",camera.fov))
	seek(match_,float(evidence.get("clock",0.0)))

func drill_rep_count(history: Array) -> int:
	return history.size()+int(current.size() >= 2)

func open_drill_rep(match_: Node3D, history: Array, rep: int, autoplay: bool) -> bool:
	if rep < 0 or rep >= drill_rep_count(history): return false
	var selected: Array[Dictionary] = history[rep] if rep < history.size() else current
	if active: toggle(match_,true)
	toggle(match_,true,selected)
	if not active: return false
	playing = autoplay
	if not autoplay: seek(match_,duration())
	return true

func bake_actor(match_: Node3D, actor_index: int, title: String, contact_frame := -1, include_ball := false) -> Animation:
	return bake_recorded_actor(match_.players[actor_index],actor_index,title,contact_frame,include_ball)

func bake_recorded_actor(actor: Node3D, actor_index: int, title: String, contact_frame: int, include_ball: bool) -> Animation:
	var start: Transform3D = frames[0].actors[actor_index].root
	var rig_to_actor: Transform3D = actor.global_transform.affine_inverse()*actor.skeleton.global_transform
	var root_bone: int = actor.skeleton.find_bone("root")
	var sample := func(time: float) -> Array[Transform3D]:
		var capture: Dictionary = frames[mini(roundi(time*60.0),frames.size()-1)].actors[actor_index]
		var pose: Array[Transform3D] = []
		pose.assign(capture.bones)
		pose[root_bone] = rig_to_actor.affine_inverse()*start.affine_inverse()*capture.root*rig_to_actor*pose[root_bone]
		return pose
	var clip: Animation = actor.get_pose_author().bake({"name":title,"duration":duration(),
		"contact_time":float(frames[index if contact_frame < 0 else contact_frame].time)-float(frames[0].time)},sample)
	clip.loop_mode = Animation.LOOP_NONE
	clip.set_meta("editor_group","Both Arms")
	clip.set_meta("editor_start",actor.get_parent().to_global(start.origin))
	clip.set_meta("editor_initial_frame",index)
	if include_ball:
		var world_start: Transform3D = actor.get_parent().global_transform*start
		clip.set_meta("editor_rig_world",world_start*rig_to_actor)
		clip.set_meta("editor_yaw",world_start.basis.get_euler().y)
		clip.set_meta("editor_height_cm",actor.height_cm)
		var samples: Array[Transform3D] = []
		for frame in frames: samples.append(frame.ball)
		clip.set_meta("editor_ball_frames",samples)
	return clip
