extends "res://scripts/set_to_target.gd"

signal trajectory_changed

const SERVER := 0
const SERVE_STYLE := 3
const Net = preload("res://scripts/net_collision.gd")

var server_start := Vector3(0.0,0.04,-8.15)
var serve_target := Vector3(0.0,Flight.FLOOR,10.7)
var serve_apex := 3.70
var serve_speed := 1.55
var serve_jump_height := 1.12
var serve_lean := -15.0
var sidespin := 0.0
var jump_carry := true

func configure(status: Label) -> void:
	var setup := StorySession.load_drill_setup(setup_key())
	server_start = setup.get("server",server_start)
	serve_target = setup.get("target",serve_target)
	serve_apex = setup.get("apex",serve_apex)
	serve_speed = setup.get("speed",serve_speed)
	serve_jump_height = setup.get("jump_height",serve_jump_height)
	serve_lean = setup.get("lean",serve_lean)
	sidespin = setup.get("sidespin",sidespin)
	jump_carry = setup.get("carry",jump_carry)
	super.configure(status)
	game.ball.hide()

func setup_key() -> String:
	return "SpinServe"

func drill_title() -> String:
	return "Spin Serve"

func target_colors() -> Dictionary:
	return {"target":Color("64cfff")}

func player_slots() -> Dictionary:
	return {"server":SERVER}

func setup_snapshot() -> Dictionary:
	return {"server":server_start,"target":serve_target,"apex":serve_apex,"speed":serve_speed,
		"jump_height":serve_jump_height,"lean":serve_lean,"sidespin":sidespin,"carry":jump_carry,"live_speed":live_speed}

func reset_players() -> void:
	game.phase = game.Phase.FINISHED
	game.replay.finish_point()
	game.ball.hide()
	for index in game.players.size(): game.players[index].visible = index == SERVER
	if game.serve.get_script() != Match.SERVES[SERVE_STYLE]: game.prepare_serve(SERVE_STYLE)
	game.aim_ring.hide()
	game.trajectory_node.hide()
	game.score_label.hide()
	refresh_setup()

func refresh_setup() -> void:
	if running: return
	var serve = game.serve
	serve.serve_start = server_start
	serve.apex = serve_apex
	serve.serve_speed = serve_speed
	serve.jump_height = serve_jump_height
	serve.forward_lean_degrees = serve_lean
	serve.sidespin = sidespin/100.0
	serve.jump_carry_enabled = jump_carry
	serve.target = serve_target
	serve.reset()
	serve.aim(serve_target)
	serve.aim_ring.hide()
	serve.path_preview.hide()
	serve.ball.show()
	show_target(serve_target)
	var duration: float = serve.flight_duration(serve.preview_origin)
	var launch: Vector3 = serve.launch_velocity(serve.preview_origin,duration)
	draw_path(trail,func(time: float):
		return serve.to_global(serve.preview_origin+launch*time+Vector3.DOWN*0.5*Flight.GRAVITY*time*time
			+serve.preview_lane_offset(0,time/duration,launch)),duration)

func show_target(point: Vector3) -> void:
	var marker: MultiMeshInstance3D = markers.target
	marker.position = Vector3(point.x,0.055,point.z)
	for index in 16:
		var angle := TAU*index/16.0
		marker.multimesh.set_instance_transform(index,Transform3D(Basis.IDENTITY,Vector3(cos(angle),0,sin(angle))*0.22))

func launch_rep() -> void:
	begin_rep()
	game.serve.serve()
	game.serve.external_rally = true
	running = true
	set_status("Toss")
	game.trace.begin_feed({"mode":"spin_serve_drill","setup":setup_snapshot()})
	contact_frames = {}
	game.replay.record(game)
	game.replay.current[0]["contacts"] = contact_frames
	game.replay.current[0]["target"] = serve_target
	var points := PackedVector3Array()
	for index in trail.multimesh.instance_count:
		points.append(trail.multimesh.get_instance_transform(index).origin)
	game.replay.current[0]["serve_path"] = points
	trail.show()

func step_rep() -> void:
	var serve = game.serve
	game.match_clock += STEP
	serve.step(STEP)
	if is_finite(serve.contact_clock):
		if not contact_frames.has("server"):
			contact_frames["server"] = game.replay.current.size()
			ContactTiming.launch_speed("Topspin serve",serve.velocity,"Horizontal %.1f  ·  Vertical %.1f km/h"%[serve.velocity.slide(Vector3.UP).length()*3.6,serve.velocity.y*3.6])
			set_status("Topspin serve")
		var flight_age: float = serve.elapsed-serve.contact_clock
		if serve.swing_time >= serve.recovery_end() and flight_age >= serve.landing_time+0.25:
			var landed: Vector3 = serve.ball.position
			var success: bool = serve.net_hit.is_empty() and absf(landed.x) <= 4.5 and landed.z >= Net.NET_Z and landed.z <= 13.0
			set_status("In" if success else ("Out" if serve.net_hit.is_empty() else "Net"))
			complete_rep(success)
	game.replay.record(game)

func result_label() -> String:
	return "serves in"

func show_rep_target(frames: Array[Dictionary]) -> void:
	if frames.is_empty(): return
	show_target(frames[0].get("target",serve_target))
	restore_path(trail,frames[0],"serve_path")

func setup_position(key: String) -> Vector3:
	return server_start if key == "server" else serve_target

func move_selection(point: Vector3) -> void:
	var x := clampf(point.x,-4.45,4.45)
	if selected == "server":
		server_start = Vector3(x,server_start.y,clampf(point.z,-10.5,-7.7))
	else:
		serve_target = Vector3(x,Flight.FLOOR,clampf(point.z,Net.NET_Z+0.5,12.95))
	refresh_setup()

func adjust_arc(arc: float) -> void:
	serve_apex = clampf(serve_apex+arc,3.5,9.0)
	trajectory_changed.emit()

func trajectory_value(key: String) -> float:
	match key:
		"apex": return serve_apex
		"speed": return serve_speed
		"jump_height": return serve_jump_height
		"lean": return serve_lean
		_: return sidespin

func set_trajectory_value(key: String, value: float) -> void:
	match key:
		"apex": serve_apex = value
		"speed": serve_speed = value
		"jump_height": serve_jump_height = value
		"lean": serve_lean = value
		"sidespin": sidespin = value
	if not game.replay.active and next_rep < 0.0: refresh_setup()
	save_setup()
	trajectory_changed.emit()

func set_jump_carry(enabled: bool) -> void:
	jump_carry = enabled
	if not game.replay.active and next_rep < 0.0: refresh_setup()
	save_setup()

func edit_server() -> void:
	edit_role(SERVER,"Spin serve replay","Serving","Spin","server",true)
