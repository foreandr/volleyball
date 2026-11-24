extends Node3D

const Flight = preload("res://scripts/pass_flight.gd")
const Match = preload("res://scripts/volleyball_match.gd")
const Player = preload("res://scripts/volleyball_player.gd")
const SOURCE := Vector3(0,2.85,3.5)
const RECEIVE_START := Vector3(0,0.04,-2.7)
const SETTER_START := Vector3(-1.45,0.04,0.4)
const PASS_TARGET := Vector3(0.55,3.35,1.50)
const LEFT_PIN := Vector3(3.55,0.065,3.28)
const NET_TARGET_COUNT := 7
const STEP := 1.0/60.0
const SETUP_KEY := "SetToTarget"

var game: Node3D
var trail: MultiMeshInstance3D
var running := false
var live_speed := 1.0
var rep_history: Array = []
var review_index := -1
const HISTORY_LIMIT := 10
var budget := 0.0
var passer_start := RECEIVE_START
var setter_start := SETTER_START
var feed_landing := Vector3(0,Flight.FLOOR,-4.0)
var pass_target := PASS_TARGET
var set_target := LEFT_PIN
var set_apex := 4.1
var feed_duration := 0.95
var selected := ""
var dragging := false
var grab := Vector3.ZERO
var markers := {}
var remaining := 0
var batch_rep := 0
var batch_size := 0
var net_sweep := false
var successful_reps := 0
var completed_reps := 0
var replay_drag := -2
var replay_drag_plane: Plane
var repeating := false
var next_rep := -1.0
var pass_preview: MultiMeshInstance3D
var feed_preview: MultiMeshInstance3D
var contact_frames: Dictionary

func configure(status: Label) -> void:
	var setup := StorySession.load_drill_setup(setup_key())
	passer_start = setup.get("passer",passer_start)
	setter_start = setup.get("setter",setter_start)
	feed_landing = setup.get("feed",feed_landing)
	pass_target = setup.get("pass",pass_target)
	set_target = setup.get("set",set_target)
	set_apex = setup.get("set_apex",set_apex)
	feed_duration = setup.get("feed_duration",feed_duration)
	live_speed = setup.get("live_speed",live_speed)
	var setter := Player.new()
	add_child(setter)
	game = Match.new()
	game.spectator = true
	add_child(game)
	var score := Label.new()
	add_child(score)
	score.hide()
	game.configure(setter,score,status,drill_title(),2,false,false)
	game.set_ball_sound(false)
	game.passing_skill = 100.0
	game.setting_skill = 100.0
	game.drill_set_pin = LEFT_PIN
	trail = make_dots(Color("3bafff"))
	pass_preview = make_dots(Color("68dfbb"))
	feed_preview = make_dots(Color("ffa95b"))
	var colors := target_colors()
	for key in colors:
		var marker := make_dots(colors[key])
		marker.multimesh.instance_count = 16
		markers[key] = marker
	reset_players()
	game.ball.global_position = SOURCE
	game.ball.show()
	status.text = "Ready"
	refresh_setup()

func setup_key() -> String:
	return SETUP_KEY

func drill_title() -> String:
	return "Set to Target"

func target_colors() -> Dictionary:
	return {"feed":Color("ffa95b"),"pass":Color("68dfbb"),"set":Color("3bafff")}

func player_slots() -> Dictionary:
	return {"setter":0,"passer":1}

func setup_snapshot() -> Dictionary:
	return {"passer":passer_start,"setter":setter_start,"feed":feed_landing,"pass":pass_target,
		"set":set_target,"set_apex":set_apex,"feed_duration":feed_duration,"live_speed":live_speed}

func save_setup() -> void:
	StorySession.save_drill_setup(setup_key(),setup_snapshot())

func reset_players() -> void:
	game.begin_point()
	game.phase = game.Phase.FINISHED
	game.serve.ball.hide()
	game.aim_ring.hide()
	game.trajectory_node.hide()
	game.score_label.hide()
	for index in game.players.size():
		game.players[index].visible = index < 2
	game.players[0].position = setter_start
	game.players[1].position = passer_start

func launch_single() -> void:
	net_sweep = false
	batch_rep = 0
	batch_size = 0
	repeating = false
	remaining = 1
	launch_rep()

func launch_ten() -> void:
	start_batch(10,false)

func launch_net_sweep() -> void:
	start_batch(NET_TARGET_COUNT,true)

func start_batch(count: int, sweep: bool) -> void:
	repeating = false
	net_sweep = sweep
	batch_size = count
	remaining = count
	batch_rep = 1
	completed_reps = 0
	successful_reps = 0
	launch_rep()

func toggle_repeat() -> void:
	net_sweep = false
	batch_rep = 0
	batch_size = 0
	repeating = not repeating
	remaining = 0
	if repeating and not running: launch_rep()
	elif not repeating: next_rep = -1.0

func feed_origin() -> Vector3:
	return Vector3(feed_landing.x, SOURCE.y, SOURCE.z)

func feed_motion() -> Vector3:
	return (feed_landing-feed_origin())/feed_duration+Vector3.UP*Flight.GRAVITY*feed_duration*0.5

func begin_rep() -> void:
	if game.replay.active: game.replay.toggle(game,true)
	if game.replay.current.size() >= 2:
		rep_history.append(game.replay.current)
		if rep_history.size() >= HISTORY_LIMIT: rep_history.pop_front()
	next_rep = -1.0
	if remaining > 0: remaining -= 1
	pass_preview.hide()
	feed_preview.hide()
	reset_players()
	trail.hide()
	budget = 0.0

func launch_rep() -> void:
	begin_rep()
	game.phase = game.Phase.LIVE
	game.drill_pass_target = pass_target
	var target := set_target
	if net_sweep:
		target = Vector3(lerpf(LEFT_PIN.x,-LEFT_PIN.x,float(batch_rep-1)/(NET_TARGET_COUNT-1)),LEFT_PIN.y,LEFT_PIN.z)
	game.drill_set_pin = target
	markers.set.position = Vector3(target.x,0.055,target.z)
	game.drill_set_apex = set_apex
	start_feed()
	running = true
	var feed := setup_snapshot()
	feed["set"] = target
	game.trace.write("setting_drill_feed",game.match_clock,feed,true)
	game.replay.record(game)
	game.replay.current[0]["set_pin"] = target
	contact_frames = {}
	game.replay.current[0]["contacts"] = contact_frames

func start_feed() -> void:
	game.launch(feed_origin(),feed_motion(),"serve",2,0.0,-1,Vector3.ZERO,Vector3.DOWN*Flight.GRAVITY)
	game.receiving_team = 0
	game.cpu_choice = 1
	game.cpu_technique = 0
	set_status("Float feed")

func step_serve() -> bool:
	return false

func step_attack(_kind: String) -> void:
	pass

func _physics_process(delta: float) -> void:
	if game.replay.active:
		game.replay.step(game,delta)
		return
	delta *= live_speed
	if not running:
		if next_rep >= 0.0:
			next_rep -= delta
			if next_rep <= 0.0:
				if batch_rep > 0: batch_rep += 1
				launch_rep()
		return
	budget += delta
	while running and budget+0.000001 >= STEP:
		budget -= STEP
		step_rep()

func step_rep() -> void:
	game.match_clock += STEP
	game.animated.fill(false)
	if step_serve():
		game.replay.record(game)
		return
	var previous: float = game.elapsed
	var kind: String = game.flight_kind
	game.elapsed = minf(previous+STEP,game.flight_end())
	game.ball.global_position = game.path_point(game.elapsed)
	game.advance_set_jumps(STEP)
	game.advance_recoveries(STEP)
	game.advance_ball_spin(STEP)
	step_attack(kind)
	if kind in ["serve","pass"]:
		game.tick_receive(STEP,previous)
		if game.flight_kind == "pass" and kind == "serve":
			game.cpu_choice = 0
			game.cpu_technique = 1
			contact_frames["passer"] = game.replay.current.size()
			set_status("Pass to setter")
		elif game.flight_kind == "set":
			contact_frames["setter"] = game.replay.current.size()
			show_set_path()
			set_status("Set to target")
	game.advance_idle_players(STEP)
	if game.elapsed >= game.flight_end() and finish_rep():
		if game.flight_kind == "serve": set_status("Missed feed")
		elif game.flight_kind == "pass": set_status("Missed set")
		complete_rep(rep_success(game.flight_kind))
	game.replay.record(game)

func complete_rep(success: bool) -> void:
	running = false
	game.phase = game.Phase.FINISHED
	if repeating or remaining > 0: next_rep = 0.7
	if batch_rep > 0:
		completed_reps += 1
		successful_reps += int(success)
		game.info.text += "\n%d/%d %s completed" % [successful_reps,completed_reps,result_label()]
	game.trace.write("setting_drill_result",game.match_clock,{"rep":batch_rep,"set_completed":success,"result":game.info.text},true)

func finish_rep() -> bool:
	return true

func rep_success(kind: String) -> bool:
	return kind == "set" and game.net_hit.is_empty()

func result_label() -> String:
	return "sets"

func set_status(message: String) -> void:
	game.info.text = "%d/%d · %s" % [batch_rep,batch_size,message] if batch_rep > 0 else message

func make_dots(color: Color) -> MultiMeshInstance3D:
	var node := MultiMeshInstance3D.new()
	node.multimesh = MultiMesh.new()
	node.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var dot := SphereMesh.new()
	dot.radius = 0.035
	dot.height = 0.07
	var style := StandardMaterial3D.new()
	style.albedo_color = color
	style.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot.material = style
	node.multimesh.mesh = dot
	add_child(node)
	return node

func draw_path(node: MultiMeshInstance3D, path: Callable, duration: float) -> void:
	node.multimesh.instance_count = 32
	for index in 32:
		var point: Vector3 = path.call(duration*index/31.0)
		node.multimesh.set_instance_transform(index,Transform3D(Basis.IDENTITY,point))
	node.show()

func show_set_path() -> void:
	record_path(trail,"set_path")

func record_path(node: MultiMeshInstance3D, key: String) -> void:
	draw_path(node,game.path_point,game.flight_end())
	var points := PackedVector3Array()
	for index in node.multimesh.instance_count:
		points.append(node.multimesh.get_instance_transform(index).origin)
	game.replay.current[0][key] = points

func show_rep_target(frames: Array[Dictionary]) -> void:
	if frames.is_empty(): return
	var pin: Vector3 = frames[0].get("set_pin",set_target)
	markers.set.position = Vector3(pin.x,0.055,pin.z)
	restore_path(trail,frames[0],"set_path")

func restore_path(node: MultiMeshInstance3D, metadata: Dictionary, key: String) -> void:
	var points: PackedVector3Array = metadata.get(key,PackedVector3Array())
	node.visible = not points.is_empty()
	if points.is_empty(): return
	node.multimesh.instance_count = points.size()
	for index in points.size():
		node.multimesh.set_instance_transform(index,Transform3D(Basis.IDENTITY,points[index]))

func close_review() -> void:
	game.replay.toggle(game,true)
	show_rep_target(game.replay.current)

func show_preview(node: MultiMeshInstance3D, origin: Vector3, velocity: Vector3, duration: float) -> void:
	draw_path(node,func(t: float): return origin+velocity*t+Vector3.DOWN*Flight.GRAVITY*0.5*t*t,duration)

func refresh_setup() -> void:
	if running: return
	game.players[0].position = setter_start
	game.players[1].position = passer_start
	game.ball.global_position = feed_origin()
	for key in markers:
		var marker: MultiMeshInstance3D = markers[key]
		var point := setup_position(key)
		marker.position = Vector3(point.x,0.055,point.z)
		for index in 16:
			var angle := TAU*index/16.0
			marker.multimesh.set_instance_transform(index,Transform3D(Basis.IDENTITY,Vector3(cos(angle),0,sin(angle))*0.22))
	var launch := passer_start+Vector3(0,1,0.48)
	var vertical := sqrt(2.0*Flight.GRAVITY*maxf(0.28,pass_target.y+0.28-launch.y))
	var arrival := (vertical+sqrt(maxf(0.0,vertical*vertical+2.0*Flight.GRAVITY*(launch.y-pass_target.y))))/Flight.GRAVITY
	var motion := (pass_target-launch).slide(Vector3.UP)/arrival+Vector3.UP*vertical
	show_preview(pass_preview,launch,motion,Flight.landing_time(launch,motion))
	show_feed_preview()
	var contact := Vector3(pass_target.x,2.0,pass_target.z)
	var set_motion: Vector3 = game.attackers[0].set_toward_pin(contact,set_target,set_apex,game.attackers[0].set_contact_height(set_apex))
	show_preview(trail,contact,set_motion,Flight.landing_time(contact,set_motion))

func show_feed_preview() -> void:
	show_preview(feed_preview,feed_origin(),feed_motion(),feed_duration)

func handle_setup_input(event: InputEvent, camera: Camera3D) -> bool:
	if not event is InputEventMouse: return false
	if game.replay.active: return handle_replay_drag(event,camera)
	if running or next_rep >= 0.0: return false
	var mouse: Vector2 = event.position
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		dragging = event.pressed
		if not dragging:
			if not selected.is_empty(): save_setup()
			return not selected.is_empty()
		selected = ""
		var distance := 28.0
		for key in player_slots().keys()+markers.keys():
			var point := setup_position(key)
			if player_slots().has(key): point.y += 0.78
			if camera.is_position_behind(point): continue
			var gap := camera.unproject_position(point).distance_to(mouse)
			if gap < distance:
				distance = gap
				selected = key
		var hit: Variant = court_hit(camera,mouse)
		grab = setup_position(selected)-hit if hit is Vector3 and not selected.is_empty() else Vector3.ZERO
		return true
	if selected.is_empty(): return false
	var arc := 0.0
	if event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_MIDDLE: arc = -event.relative.y*0.018
		elif dragging and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			var hit: Variant = court_hit(camera,mouse)
			if hit is Vector3: move_selection(hit+grab)
			return true
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: arc = 0.15
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: arc = -0.15
	if is_zero_approx(arc): return false
	adjust_arc(arc)
	refresh_setup()
	save_setup()
	return true

func adjust_arc(arc: float) -> void:
	if selected in ["setter","set"]: set_apex = clampf(set_apex+arc,3.35,7.0)
	elif selected == "feed":
		feed_duration = clampf(feed_duration+arc*0.12,0.70,1.35)
	else: pass_target.y = clampf(pass_target.y+arc,2.3,6.0)

func court_hit(camera: Camera3D, mouse: Vector2) -> Variant:
	return Plane(Vector3.UP,0.055).intersects_ray(camera.project_ray_origin(mouse),camera.project_ray_normal(mouse))

func setup_position(key: String) -> Vector3:
	match key:
		"passer": return passer_start
		"setter": return setter_start
		"feed": return Vector3(feed_landing.x,0.055,feed_landing.z)
		"pass": return Vector3(pass_target.x,0.055,pass_target.z)
		"set": return Vector3(set_target.x,0.055,set_target.z)
	return Vector3.ZERO

func move_selection(point: Vector3) -> void:
	var x := clampf(point.x,-4.4,4.4)
	var z := clampf(point.z,-4.85,3.72)
	match selected:
		"passer": passer_start = Vector3(x,passer_start.y,z)
		"setter": setter_start = Vector3(x,setter_start.y,z)
		"feed": feed_landing = Vector3(x,Flight.FLOOR,z)
		"pass": pass_target = Vector3(x,pass_target.y,z)
		"set": set_target = Vector3(x,set_target.y,z)
	refresh_setup()

func handle_replay_drag(event: InputEvent, camera: Camera3D) -> bool:
	var replay = game.replay
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var was_dragging := replay_drag != -2
		replay_drag = -2
		if not event.pressed: return was_dragging
		var closest := 30.0
		for index in [-1]+player_slots().values():
			if index == -1 and not game.ball.visible: continue
			var point: Vector3 = game.ball.global_position if index == -1 else game.players[index].global_position+Vector3.UP*0.78
			if camera.is_position_behind(point): continue
			var distance := camera.unproject_position(point).distance_to(event.position)
			if distance >= closest: continue
			var plane := Plane(Vector3.UP,point.y)
			var hit: Variant = plane.intersects_ray(camera.project_ray_origin(event.position),camera.project_ray_normal(event.position))
			if not hit is Vector3: continue
			var offset: Vector3 = replay.ball_offset if index == -1 else replay.actor_offsets.get(index,Vector3.ZERO)
			closest = distance
			replay_drag = index
			replay_drag_plane = plane
			grab = offset-hit
		return replay_drag != -2
	if event is InputEventMouseMotion and replay_drag != -2 and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		var hit: Variant = replay_drag_plane.intersects_ray(camera.project_ray_origin(event.position),camera.project_ray_normal(event.position))
		if hit is Vector3:
			var offset := (Vector3(hit)+grab).slide(Vector3.UP)
			if replay_drag == -1: replay.ball_offset = offset
			else: replay.actor_offsets[replay_drag] = offset
			replay.seek(game,replay.clock)
		return true
	return false

func review_count() -> int:
	return game.replay.drill_rep_count(rep_history)

func open_review(index: int, autoplay := false) -> void:
	if game.replay.open_drill_rep(game,rep_history,index,autoplay):
		review_index = index
		replay_drag = -2
		show_rep_target(game.replay.frames)

func edit_setter() -> void:
	edit_role(0,"Setting replay","Setting","Overhead","setter")

func edit_role(actor: int, title: String, category: String, type: String, role: String, include_ball := false) -> void:
	var replay = game.replay
	if not replay.active: return
	replay.playing = false
	save_setup()
	StorySession.return_to_drill = drill_title()
	var contacts: Dictionary = replay.frames[0].get("contacts",{})
	StorySession.edit_animation = replay.bake_actor(game,actor,title,contacts.get(role,replay.index),include_ball or setup_key() == "Butterfly")
	StorySession.edit_entry = {"id":setup_key()+"_"+title,"name":title,"category":category,"type":type}
	StorySession.animation_draft.clear()
	MenuPresentation.load_scene("res://scenes/animation_editor.tscn")
