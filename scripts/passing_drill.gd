extends RefCounted

const Flight = preload("res://scripts/pass_flight.gd")
const Net = preload("res://scripts/net_collision.gd")
const RECEIVER := 1
const FEEDER := 2
const TARGET_RADIUS := 0.90
const BATCH_REPS := 10
const ZONES := [1,6,5]
const ZONE_X := {1:2.8,6:0.0,5:-2.8}
const SEQUENCE_TYPES := ["Attack","Spin serve","Float serve"]
const SIM_STEP := 1.0/60.0
const SOURCE_MIN_Z := -8.5
const SOURCE_MAX_Z := 17.0
const PREFERENCE_PREFIX := "PassingDrill_"
const SPINS := ["No spin","Topspin","Backspin","Sidespin left","Sidespin right"]

var game: Node3D
var start := Vector3(0,0.04,-2.25)
var source := Vector3(0,3.95,10.8)
var target := Vector3(1.7,2.2,1.7)
var heading := 0.0
var angle := 2.0
var speed := 18.0
var spin_rate := 6.0
var spin := "Topspin"
var playback_speed := 1.0
var pending_sim_time := 0.0
var batch_replays: Array = []
var review_rep := -1
var planned_reps := 0
var completed_reps := 0
var successful_reps := 0
var batch_active := false
var sequence_feeds: Array[Dictionary] = []
var sequence_button: Button
var rep_readout: Label
var batch_button: Button
var launch_button: Button
var running := false
var finish_delay := -1.0
var incoming_flight := -1
var contact_label := ""
var closest_check := {}
var target_crossing := Vector3.INF
var technique_label := ""
var drag_handle := ""
var drag_plane: Plane
var grab_offset := Vector3.ZERO
var sliders := {}
var origin_marker: MeshInstance3D
var target_marker: MeshInstance3D
var landing_marker: MeshInstance3D
var trajectory: MeshInstance3D

func _init(match_: Node3D) -> void:
	game = match_
	var saved_source: Variant = StorySession.match_preference(PREFERENCE_PREFIX+"source_position",Vector2(source.x,source.z))
	if saved_source is Vector2 and saved_source.is_finite():
		source.x = clampf(saved_source.x,-6.5,6.5)
		source.z = clampf(saved_source.y,SOURCE_MIN_Z,SOURCE_MAX_Z)
	var saved_receiver: Variant = StorySession.match_preference(PREFERENCE_PREFIX+"receiver_position",Vector2(start.x,start.z))
	if saved_receiver is Vector2 and saved_receiver.is_finite():
		set_receiver_start(Vector3(saved_receiver.x,start.y,saved_receiver.y))
	game.phase = game.Phase.FINISHED
	game.update_player_guide()
	game.score_label.hide()
	game.info.text = "Set up the feed, then launch."
	game.serve.ball.hide()
	game.ball.hide()
	for index in game.players.size():
		game.players[index].visible = index == RECEIVER
	for label in game.key_labels:
		label.hide()
	game.players[RECEIVER].global_position = start
	origin_marker = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.16
	sphere.height = 0.32
	origin_marker.mesh = sphere
	origin_marker.material_override = material(Color("#ffa95b"))
	game.add_child(origin_marker)
	target_marker = marker(TARGET_RADIUS,TARGET_RADIUS-0.06,Color("#54d9e3"))
	landing_marker = marker(0.28,0.20,Color("#ff9750"))
	trajectory = MeshInstance3D.new()
	game.add_child(trajectory)
	update_setup()

func material(color: Color) -> StandardMaterial3D:
	var paint := StandardMaterial3D.new()
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paint.albedo_color = color
	return paint

func marker(radius: float, inner: float, color: Color) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = radius
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material(color)
	game.add_child(node)
	return node

func build_controls(host: Control, parent: VBoxContainer) -> void:
	launch_button = host.button("Launch ball",start_single)
	launch_button.name = "LaunchPassingFeed"
	host.content.add_child(launch_button)
	batch_button = host.button("Run 10 reps",toggle_batch)
	batch_button.name = "RunPassingBatch"
	host.content.add_child(batch_button)
	sequence_button = host.button("Run 27 reps",toggle_batch.bind(true))
	host.content.add_child(sequence_button)
	rep_readout = host.label("",18)
	rep_readout.hide()
	host.content.add_child(rep_readout)
	var left: VBoxContainer = host.content
	add_slider(host,left,"speed_scale","Slow motion","%",10,100,5,100,func(v): playback_speed = v*0.01)
	add_slider(host,parent,"target_height","Target height","m",0.15,4.5,0.05,target.y,func(v): target.y = v)
	add_slider(host,parent,"skill","Passing skill","%",0,100,1,game.passing_skill,func(v): game.passing_skill = v)
	add_slider(host,parent,"squat_rise","Squat rise time","s",0.10,3.0,0.05,game.squat_rise_duration,func(v): game.squat_rise_duration = v)
	left.add_child(host.label("Ball feed",19))
	add_slider(host,left,"source_y","Source height","m",0.3,7.0,0.05,source.y,func(v): source.y = v)
	add_slider(host,left,"heading","Direction","°",-180,180,1,heading,func(v): heading = v)
	add_slider(host,left,"angle","Downward angle","°",-65,75,1,angle,func(v): angle = v)
	add_slider(host,left,"speed","Ball speed","m/s",2,40,0.5,speed,func(v): speed = v)
	var selector := OptionButton.new()
	selector.name = "PassingSpinType"
	for style in SPINS: selector.add_item(style)
	var saved_spin: String = StorySession.match_preference(PREFERENCE_PREFIX+"spin_type",spin)
	if SPINS.has(saved_spin): spin = saved_spin
	selector.select(SPINS.find(spin))
	selector.item_selected.connect(func(index: int):
		spin = SPINS[index]
		StorySession.save_match_preference(PREFERENCE_PREFIX+"spin_type",spin)
		update_spin_controls()
		update_setup())
	left.add_child(selector)
	add_slider(host,left,"spin","Spin rate","rps",0,18,0.5,spin_rate,func(v): spin_rate = v)
	update_spin_controls()

func add_slider(host: Control, parent: VBoxContainer, id: String, caption: String, unit: String, lower: float, upper: float, step: float, initial: float, apply: Callable) -> void:
	var label: Label = host.label("",16)
	parent.add_child(label)
	var slider := HSlider.new()
	slider.name = id
	slider.min_value = lower
	slider.max_value = upper
	slider.step = step
	var preference := PREFERENCE_PREFIX+id
	slider.value = StorySession.match_preference(preference,initial)
	slider.custom_minimum_size.y = 19
	parent.add_child(slider)
	sliders[id] = slider
	var update := func(value: float):
		label.text = "%s  %.2f %s" % [caption,value,unit]
		apply.call(value)
		update_setup()
	slider.value_changed.connect(func(value: float):
		update.call(value)
		StorySession.save_match_preference(preference,value))
	update.call(slider.value)

func update_spin_controls() -> void:
	var slider: HSlider = sliders.spin
	slider.editable = spin != "No spin"
	slider.focus_mode = Control.FOCUS_ALL if slider.editable else Control.FOCUS_NONE
	slider.modulate.a = 1.0 if slider.editable else 0.40

func handle_drag(event: InputEvent, camera: Camera3D, screen: Vector2) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var was_dragging := not drag_handle.is_empty()
		if drag_handle == "receiver":
			StorySession.save_match_preference(PREFERENCE_PREFIX+"receiver_position",Vector2(start.x,start.z))
		drag_handle = ""
		return was_dragging
	if game.replay.active: return handle_replay_drag(event,camera,screen)
	if running or finish_delay >= 0.0: return false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var handle := pick_handle(camera,screen)
		if handle.is_empty(): return false
		var point: Vector3 = {"receiver":start,"source":source,"target":target}[handle]
		drag_plane = Plane(Vector3.UP,point.y)
		var hit: Variant = drag_point(camera,screen)
		if hit == null: return false
		drag_handle = handle
		grab_offset = point-hit
		return true
	if event is InputEventMouseMotion and not drag_handle.is_empty():
		if not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
			drag_handle = ""
			return false
		var hit: Variant = drag_point(camera,screen)
		if hit is Vector3:
			var point: Vector3 = hit+grab_offset
			match drag_handle:
				"receiver": set_receiver_start(point)
				"source":
					source = Vector3(clampf(point.x,-6.5,6.5),source.y,clampf(point.z,SOURCE_MIN_Z,SOURCE_MAX_Z))
					StorySession.save_match_preference(PREFERENCE_PREFIX+"source_position",Vector2(source.x,source.z))
				"target": target = Vector3(clampf(point.x,-4.4,4.4),target.y,clampf(point.z,-4.9,3.8))
			update_setup()
		return true
	return false

func set_receiver_start(point: Vector3) -> void:
	start = Vector3(clampf(point.x,-4.4,4.4),start.y,clampf(point.z,-4.9,3.4))

func handle_replay_drag(event: InputEvent, camera: Camera3D, screen: Vector2) -> bool:
	var replay: RefCounted = game.replay
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var rig: Skeleton3D = game.players[RECEIVER].skeleton
		var hips := rig.to_global(rig.get_bone_global_pose(rig.find_bone("pelvis")).origin)
		var head := rig.to_global(rig.get_bone_global_pose(rig.find_bone("Head")).origin)
		var ball: Vector3 = game.ball.global_position
		var handle := ""
		var point := hips
		if game.ball.visible and not camera.is_position_behind(ball) and camera.unproject_position(ball).distance_to(screen) <= 22.0:
			handle = "replay_ball"
			point = ball
		elif not camera.is_position_behind(hips) and not camera.is_position_behind(head):
			var body := Geometry2D.get_closest_point_to_segment(screen,camera.unproject_position(hips),camera.unproject_position(head))
			if body.distance_to(screen) <= 32.0: handle = "replay_receiver"
		if handle.is_empty(): return false
		drag_plane = Plane(Vector3.UP,point.y)
		var hit: Variant = drag_point(camera,screen)
		if hit == null: return false
		var offset: Vector3 = replay.ball_offset if handle == "replay_ball" else replay.actor_offsets.get(RECEIVER,Vector3.ZERO)
		grab_offset = offset-hit
		drag_handle = handle
		return true
	if event is InputEventMouseMotion and drag_handle in ["replay_ball","replay_receiver"]:
		if not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
			drag_handle = ""
			return false
		var hit: Variant = drag_point(camera,screen)
		if hit is Vector3:
			var offset: Vector3 = (hit+grab_offset).slide(Vector3.UP)
			if drag_handle == "replay_ball": replay.ball_offset = offset
			else: replay.actor_offsets[RECEIVER] = offset
			replay.seek(game,replay.clock)
		return true
	return false

func pick_handle(camera: Camera3D, screen: Vector2) -> String:
	for handle in ["source","target"]:
		var point := source if handle == "source" else target
		var radius := 24.0
		if handle == "target":
			radius = maxf(radius,camera.unproject_position(point).distance_to(camera.unproject_position(point+Vector3.RIGHT*TARGET_RADIUS)))
		if not camera.is_position_behind(point) and camera.unproject_position(point).distance_to(screen) <= radius:
			return handle
	if not camera.is_position_behind(start):
		var foot := camera.unproject_position(start)
		var head := camera.unproject_position(start+Vector3.UP*1.85)
		var closest := Geometry2D.get_closest_point_to_segment(screen,foot,head)
		if closest.distance_to(screen) <= maxf(18.0,foot.distance_to(head)*0.22):
			return "receiver"
	return ""

func drag_point(camera: Camera3D, screen: Vector2) -> Variant:
	return drag_plane.intersects_ray(camera.project_ray_origin(screen),camera.project_ray_normal(screen))

func feed() -> Dictionary:
	var radians := deg_to_rad(heading)
	return Flight.air(Vector3(sin(radians),0,-cos(radians)),{"angle":angle,"speed":speed,"spin":spin,"spin_rate":spin_rate})

func update_setup() -> void:
	if running or game.replay.active: return
	game.players[RECEIVER].global_position = start
	origin_marker.global_position = source
	target_marker.global_position = target
	var plan := feed()
	var incoming: Vector3 = plan.incoming
	var acceleration: Vector3 = plan.acceleration
	var duration := Flight.landing_time(source,incoming,-acceleration.y)
	var flight := func(time: float) -> Vector3: return source+incoming*time+0.5*acceleration*time*time
	var hit := Net.first_hit(flight,0.0,duration)
	if not hit.is_empty(): duration = float(hit.end_time)
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP,material(Color("#ffc474")))
	for index in 65:
		var time := duration*index/64.0
		mesh.surface_add_vertex(Net.after_hit(hit,time) if not hit.is_empty() and time >= float(hit.time) else flight.call(time))
	mesh.surface_end()
	trajectory.mesh = mesh
	trajectory.show()
	show_landing(Net.after_hit(hit,duration) if not hit.is_empty() else flight.call(duration))

func show_landing(point: Vector3) -> void:
	landing_marker.global_position = Vector3(point.x,0.055,point.z)
	landing_marker.show()

func start_single() -> void:
	if batch_active: return
	start_reps(1)

func toggle_batch(use_sequence := false) -> void:
	if batch_active:
		planned_reps = completed_reps+int(running)
		end_batch()
		update_rep_readout()
		return
	start_reps(SEQUENCE_TYPES.size()*ZONES.size()*ZONES.size() if use_sequence else BATCH_REPS,use_sequence)

func end_batch() -> void:
	batch_active = false
	sequence_feeds.clear()
	batch_button.text = "Run 10 reps"
	sequence_button.text = "Run 27 reps"
	batch_button.disabled = false
	sequence_button.disabled = false
	launch_button.disabled = false

func start_reps(count: int, use_sequence := false) -> void:
	batch_replays.clear()
	pending_sim_time = 0.0
	planned_reps = count
	completed_reps = 0
	successful_reps = 0
	batch_active = count > 1
	if use_sequence:
		for kind in SEQUENCE_TYPES:
			for receiver_zone in ZONES:
				for source_zone in ZONES:
					sequence_feeds.append({"kind":kind,"receiver_zone":receiver_zone,"source_zone":source_zone})
	launch_button.disabled = batch_active
	batch_button.disabled = use_sequence
	sequence_button.disabled = batch_active and not use_sequence
	if batch_active:
		var stop_button := sequence_button if use_sequence else batch_button
		stop_button.text = "Stop after this rep"
	update_rep_readout()
	launch_ball()

func sequence_feed(rep: Dictionary) -> Dictionary:
	var kind: String = rep.kind
	var attack := kind == "Attack"
	var receiver := Vector3(ZONE_X[rep.receiver_zone],start.y,randf_range(-4.0,-1.4))
	# Source lanes are numbered from the other team's perspective.
	var from := Vector3(-ZONE_X[rep.source_zone],randf_range(3.15,3.75),randf_range(4.8,6.0) if attack else 12.8)
	var landing := Vector3(receiver.x+randf_range(-0.9,0.9),Flight.FLOOR,clampf(receiver.z+randf_range(-1.1,1.4),-4.7,3.3))
	var span := landing-from
	var pace := randf_range(18.0,29.0) if attack else (randf_range(13.0,21.0) if kind == "Spin serve" else randf_range(9.0,14.0))
	var spin_type := "Topspin" if kind != "Float serve" else "No spin"
	var rate := randf_range(3.0,11.0) if spin_type == "Topspin" else 0.0
	var forward := span.slide(Vector3.UP).normalized()
	var air := Flight.air(forward,{"angle":0.0,"speed":pace,"spin":spin_type,"spin_rate":rate})
	var acceleration: Vector3 = air.acceleration
	var time := span.slide(Vector3.UP).length()/pace
	# Lengthen the flight only as much as needed to clear the tape.
	while true:
		var incoming := span/time-acceleration*0.5*time
		var path := func(t: float) -> Vector3: return from+incoming*t+acceleration*0.5*t*t
		if Net.first_hit(path,0.0,time).is_empty():
			return {"receiver":receiver,"source":from,"incoming":incoming,"acceleration":acceleration,
				"spin_axis":air.spin_axis,"spin_rate":air.spin_rate,"spin_type":spin_type}
		time *= 1.1
	return {}

func update_rep_readout() -> void:
	rep_readout.show()
	rep_readout.text = "%d/%d successful · %d/%d completed" % [successful_reps,completed_reps,completed_reps,planned_reps] if completed_reps > 0 else "0/%d completed" % planned_reps

func launch_ball() -> void:
	if game.replay.active: game.toggle_replay()
	game.begin_point()
	game.phase = game.Phase.LIVE
	game.serve.ball.hide()
	var randomized := not sequence_feeds.is_empty()
	var rep: Dictionary = sequence_feeds.pop_front() if randomized else {}
	var kind: String = rep.get("kind","")
	var plan := sequence_feed(rep) if randomized else feed()
	var receiver: Vector3 = plan.receiver if randomized else start
	var ball_source: Vector3 = plan.source if randomized else source
	game.players[RECEIVER].global_position = receiver
	game.drill_pass_target = target
	target_marker.global_position = target
	origin_marker.global_position = ball_source
	trajectory.hide()
	game.update_player_guide()
	game.score_label.hide()
	game.info.text = "%s · Receive %d · From %d" % [kind,rep.receiver_zone,rep.source_zone] if randomized else "Ball in flight"
	var motion: Vector3 = plan.incoming
	var rate: float = plan.spin_rate/TAU if not plan.spin_axis.is_zero_approx() else 0.0
	var flight_kind := "serve" if kind.ends_with("serve") else "spike"
	game.launch(ball_source,motion,flight_kind,FEEDER,rate,-1,Vector3.ZERO,plan.acceleration,plan.spin_axis*rate)
	game.receiving_team = 0
	game.cpu_choice = RECEIVER
	game.cpu_technique = 1 if game.overhead_available(RECEIVER,1) else 0
	incoming_flight = game.flight_number
	technique_label = ""
	contact_label = ""
	closest_check.clear()
	target_crossing = Vector3.INF
	drag_handle = ""
	running = true
	finish_delay = -1.0
	game.trace.write("passing_drill_feed",game.match_clock,{
		"rep":completed_reps+1,"receiver":receiver,"source":ball_source,"target":target,
		"feed_type":kind,"receiver_zone":rep.get("receiver_zone"),"source_zone":rep.get("source_zone"),"direction":rad_to_deg(atan2(motion.x,-motion.z)),"angle":rad_to_deg(atan2(-motion.y,motion.slide(Vector3.UP).length())),"speed":motion.length(),"spin":plan.get("spin_type",spin),
		"spin_rate":rate,"passing_skill":game.passing_skill
	},true)
	show_landing(game.path_point(game.flight_end()))
	game.update_action_labels()
	game.replay.record(game)

func review_count() -> int:
	return game.replay.drill_rep_count(batch_replays)

func open_rep(index: int, autoplay: bool) -> void:
	if game.replay.open_drill_rep(game,batch_replays,index,autoplay):
		review_rep = index
		drag_handle = ""

func tick(delta: float) -> void:
	if game.replay.active:
		landing_marker.hide()
		game.replay.step(game,delta)
		return
	landing_marker.show()
	if not running and finish_delay < 0.0:
		pending_sim_time = 0.0
		return
	pending_sim_time += delta*playback_speed
	while pending_sim_time+0.0000001 >= SIM_STEP and (running or finish_delay >= 0.0):
		pending_sim_time = maxf(0.0,pending_sim_time-SIM_STEP)
		simulate_step(SIM_STEP)

func simulate_step(delta: float) -> void:
	if not running:
		if finish_delay >= 0.0:
			game.match_clock += delta
			game.animated.fill(false)
			game.advance_recoveries(delta)
			game.advance_idle_players(delta)
			game.update_action_labels()
			game.replay.record(game)
			finish_delay = maxf(0.0,finish_delay-delta)
			if game.recoveries.has(RECEIVER):
				finish_delay = maxf(0.15,finish_delay)
			if finish_delay <= 0.0:
				finish_delay = -1.0
				if batch_active:
					batch_replays.append(game.replay.current)
					launch_ball()
				else: reset_receiver()
		return
	game.match_clock += delta
	var previous: float = game.elapsed
	game.elapsed = minf(game.elapsed+delta,game.flight_end())
	game.ball.global_position = game.path_point(game.elapsed)
	if game.flight_number != incoming_flight and not target_crossing.is_finite():
		var before: Vector3 = game.path_point(previous)
		var after: Vector3 = game.ball.global_position
		var height: float = game.drill_pass_target.y
		if before.y >= height and after.y <= height and after.y < before.y:
			target_crossing = before.lerp(after,(before.y-height)/(before.y-after.y))
	game.animated.fill(false)
	game.advance_recoveries(delta)
	game.advance_ball_spin(delta)
	if game.flight_number == incoming_flight:
		var platform: Node3D = game.platforms[RECEIVER]
		game.tick_receive(delta,previous)
		var check: Dictionary = platform.contact_check
		if check.has("gap") and float(check.gap) < float(closest_check.get("gap",INF)):
			closest_check = check.duplicate()
		if platform.low_save.active:
			technique_label = "Pancake" if platform.low_save.pancake else ("One-arm dive" if not platform.low_save.wide_arm.is_empty() else "Dive")
		if game.flight_number != incoming_flight:
			show_landing(game.path_point(game.flight_end()))
			contact_label = technique_label if not technique_label.is_empty() else game.stroke
			game.info.text = contact_label
	game.advance_idle_players(delta)
	if game.elapsed >= game.flight_end():
		finish()
	game.update_action_labels()
	game.replay.record(game)

func reset_receiver() -> void:
	var receiver: Node3D = game.players[RECEIVER]
	game.recoveries.erase(RECEIVER)
	game.receive_animation_labels.erase(RECEIVER)
	game.update_action_labels()
	receiver.rotation.y = 0.0
	receiver.play_action("idle",0.0)
	receiver.animator.advance(0.0)
	game.ball.hide()
	update_setup()

func finish() -> void:
	running = false
	game.phase = game.Phase.FINISHED
	var success := false
	if contact_label.is_empty():
		if game.platforms[RECEIVER].low_save.active: game.begin_recovery(RECEIVER)
		game.info.text = "Missed feed" if game.net_hit.is_empty() else "Feed hit the net"
	else:
		var result_point: Vector3 = target_crossing if target_crossing.is_finite() else game.ball.global_position
		var error: float = (result_point-game.drill_pass_target).length()
		success = target_crossing.is_finite() and error <= TARGET_RADIUS
		var result := "On target" if success else "%.2f m from target" % error
		game.info.text = "%s · %s" % [contact_label,result]
	if completed_reps < planned_reps:
		completed_reps += 1
		successful_reps += int(success)
		if completed_reps >= planned_reps:
			end_batch()
		update_rep_readout()
	game.trace.write("passing_drill_result",game.match_clock,{
		"rep":completed_reps,"successful":success,"result":game.info.text,
		"technique":contact_label if not contact_label.is_empty() else technique_label,
		"target_crossing":target_crossing,"ball_end":game.ball.global_position,"closest_contact":closest_check
	},true)
	finish_delay = 1.0
