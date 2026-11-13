extends "res://scripts/set_to_target.gd"

signal trajectory_changed

const Net = preload("res://scripts/net_collision.gd")
const SERVER_SLOT := 2
var server_start := Vector3(0,0.04,14.0)
var spike_target := Vector3(1.5,Flight.FLOOR,11.8)
var serve_apex := 5.6
var spike_pace := 1.0
var spike_jump_height := 42.0
var spike_preview: MultiMeshInstance3D
var tape_marker: MultiMeshInstance3D
var landing_time := 0.0

func _init() -> void:
	passer_start = Vector3(2.6,0.04,-2.9)
	setter_start = Vector3(0.2,0.04,1.3)
	feed_landing = Vector3(2.6,Flight.FLOOR,-4.25)
	pass_target = Vector3(0.2,3.4,1.65)
	set_target = Vector3(3.0,0.065,3.18)
	set_apex = 5.0

func configure(status: Label) -> void:
	var setup := StorySession.load_drill_setup(setup_key())
	server_start = setup.get("server",server_start)
	spike_target = setup.get("spike",spike_target)
	serve_apex = setup.get("serve_apex",serve_apex)
	spike_pace = setup.get("spike_pace",spike_pace)
	spike_jump_height = setup.get("spike_jump_height",spike_jump_height)
	spike_preview = make_dots(Color("fa91b6"))
	tape_marker = make_dots(Color("ffc24c"))
	tape_marker.multimesh.instance_count = 16
	super.configure(status)

func setup_key() -> String:
	return "Butterfly"

func drill_title() -> String:
	return "Butterfly"

func player_slots() -> Dictionary:
	var slots := super.player_slots()
	slots["server"] = SERVER_SLOT
	return slots

func target_colors() -> Dictionary:
	var colors := super.target_colors()
	colors["spike"] = Color("fa91b6")
	return colors

func setup_snapshot() -> Dictionary:
	var setup := super.setup_snapshot()
	setup.merge({"server":server_start,"spike":spike_target,"serve_apex":serve_apex,"spike_pace":spike_pace,"spike_jump_height":spike_jump_height})
	return setup

func reset_players() -> void:
	game.service_team = 1
	super.reset_players()
	game.players[SERVER_SLOT].show()
	if game.serve.get_script() != Match.SERVES[0]: game.prepare_serve(0)
	configure_serve()

func configure_serve() -> void:
	var server_frame: Node3D = game.frames[1]
	game.serve.serve_start = server_frame.to_local(server_start)
	var aim: Vector3 = server_frame.to_local(feed_landing)
	var heading: Vector3 = aim-game.serve.serve_start
	game.serve.serve_yaw = atan2(heading.x,heading.z)
	game.serve.forward = Vector3(sin(game.serve.serve_yaw),0,cos(game.serve.serve_yaw))
	game.serve.apex = serve_apex
	game.serve.aim(aim)
	game.serve.reset()
	game.serve.aim_ring.hide()
	game.serve.path_preview.hide()

func start_feed() -> void:
	game.drill_force_forearm_serve_receive = true
	game.drill_spike_target = spike_target
	game.drill_spike_pace = spike_pace
	apply_spike_jump_height()
	landing_time = 0.0
	spike_preview.hide()
	tape_marker.hide()
	game.phase = game.Phase.READY
	game.ball.hide()
	game.serve.serve()
	set_status("Underhand serve")

func launch_rep() -> void:
	super.launch_rep()
	var metadata: Dictionary = game.replay.current[0]
	metadata["feed_target"] = feed_landing
	metadata["pass_target"] = pass_target
	metadata["spike_target"] = spike_target

func step_serve() -> bool:
	if game.phase != game.Phase.READY:
		if game.serve.swing_time < game.serve.recovery_end():
			game.serve.step(STEP)
			game.animated[SERVER_SLOT] = true
		return false
	game.serve.step(STEP)
	if is_finite(game.serve.contact_clock):
		game.serve.external_rally = true
		game.serve.ball.hide()
		game.phase = game.Phase.LIVE
		game.launch(game.serve.to_global(game.serve.origin),game.serve.global_basis*game.serve.velocity,"serve",SERVER_SLOT)
		contact_frames["server"] = game.replay.current.size()
		record_path(feed_preview,"serve_path")
		game.cpu_choice = 1
		game.cpu_technique = 0
	return true

func step_attack(kind: String) -> void:
	if kind == "pass":
		if not game.replay.current[0].has("pass_path"): record_path(pass_preview,"pass_path")
		game.position_attack(STEP)
	if kind == "set":
		var driver = game.attackers[0]
		if not game.net_hit.is_empty():
			driver.enabled = false
		elif driver.enabled:
			game.prepare_cpu_approach(1,driver,STEP)
		if game.elapsed >= game.flight_end(): set_status("Missed spike")
	game.advance_attackers(STEP)
	if kind != "spike" and game.flight_kind == "spike":
		contact_frames["hitter"] = game.replay.current.size()
		record_path(spike_preview,"spike_path")
		var tape := tape_contact(game.net_hit)
		show_tape_contact(tape)
		game.replay.current[0]["spike_tape"] = tape
		set_status("Spike hits tape" if tape.is_finite() else "Spike")

func show_rep_target(frames: Array[Dictionary]) -> void:
	super.show_rep_target(frames)
	if frames.is_empty(): return
	for key in ["feed","pass","spike"]:
		var point: Vector3 = frames[0].get(key+"_target",setup_position(key))
		markers[key].position = Vector3(point.x,0.055,point.z)
	restore_path(feed_preview,frames[0],"serve_path")
	restore_path(pass_preview,frames[0],"pass_path")
	restore_path(spike_preview,frames[0],"spike_path")
	show_tape_contact(frames[0].get("spike_tape",Vector3.INF))

func finish_rep() -> bool:
	if game.flight_kind != "spike": return true
	if landing_time == 0.0 and game.net_hit.is_empty():
		game.begin_ball_bounce()
	landing_time += STEP
	if game.bounce_end > 0.0:
		var time := minf(landing_time,game.bounce_end)
		game.ball.global_position = game.bounce_origin+game.bounce_velocity*time+Vector3.DOWN*0.5*Flight.GRAVITY*time*time
	return landing_time >= 0.70

func rep_success(kind: String) -> bool:
	var point: Vector3 = game.path_point(game.flight_end())
	return kind == "spike" and game.net_hit.is_empty() and absf(point.x) <= 4.5 and point.z >= Net.NET_Z and point.z <= 13.0

func result_label() -> String:
	return "spikes"

func apply_spike_jump_height() -> void:
	game.attackers[0].jump.max_height = spike_jump_height*0.0254+0.2032

func tape_contact(hit: Dictionary) -> Vector3:
	return hit.point if hit.get("kind","") == "tape" else Vector3.INF

func show_tape_contact(point: Vector3) -> void:
	tape_marker.visible = point.is_finite()
	if not tape_marker.visible: return
	tape_marker.position = point
	for index in tape_marker.multimesh.instance_count:
		var angle := TAU*index/tape_marker.multimesh.instance_count
		var offset := Vector3(cos(angle),sin(angle),0)*0.15
		tape_marker.multimesh.set_instance_transform(index,Transform3D(Basis.IDENTITY,offset))

func show_feed_preview() -> void:
	apply_spike_jump_height()
	configure_serve()
	game.ball.hide()
	var duration: float = game.serve.flight_duration(game.serve.preview_origin)
	var launch: Vector3 = game.serve.launch_velocity(game.serve.preview_origin,duration)
	show_preview(feed_preview,game.serve.to_global(game.serve.preview_origin),game.serve.global_basis*launch,duration)
	var start := Vector3(set_target.x,game.attackers[0].set_contact_height(set_apex),set_target.z)
	var time := (spike_target-start).slide(Vector3.UP).length()/(22.0*spike_pace)
	var gravity := Flight.spike_gravity(10.0)
	var velocity := (spike_target-start)/time+Vector3.UP*gravity*time*0.5
	var path := func(t: float): return start+velocity*t+Vector3.DOWN*gravity*t*t*0.5
	draw_path(spike_preview,path,time)
	show_tape_contact(tape_contact(Net.first_hit(path,0.0,time)))

func setup_position(key: String) -> Vector3:
	match key:
		"server": return server_start
		"spike": return spike_target
	return super.setup_position(key)

func move_selection(point: Vector3) -> void:
	match selected:
		"server":
			server_start = Vector3(clampf(point.x,-4.4,4.4),server_start.y,clampf(point.z,13.05,15.0))
			refresh_setup()
		"spike":
			spike_target = Vector3(clampf(point.x,-4.45,4.45),Flight.FLOOR,clampf(point.z,4.5,12.95))
			refresh_setup()
		_: super.move_selection(point)

func trajectory_value(key: String) -> float:
	match key:
		"serve_apex": return serve_apex
		"pass_height": return pass_target.y
		"set_apex": return set_apex
		"spike_jump_height": return spike_jump_height
		_: return spike_pace

func set_trajectory_value(key: String, value: float) -> void:
	if running or game.replay.active or next_rep >= 0.0:
		trajectory_changed.emit()
		return
	match key:
		"serve_apex": serve_apex = clampf(value,3.5,9.0)
		"pass_height": pass_target.y = clampf(value,2.3,6.0)
		"set_apex": set_apex = clampf(value,3.35,7.0)
		"spike_pace": spike_pace = clampf(value,0.5,1.4)
		"spike_jump_height": spike_jump_height = clampf(value,30.0,65.0)
	refresh_setup()
	save_setup()
	trajectory_changed.emit()

func adjust_arc(arc: float) -> void:
	match selected:
		"server","feed": serve_apex = clampf(serve_apex+arc,3.5,9.0)
		"spike": spike_pace = clampf(spike_pace+arc*0.2,0.5,1.4)
		_: super.adjust_arc(arc)
	trajectory_changed.emit()
