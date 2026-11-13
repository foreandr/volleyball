extends RefCounted

const Flight = preload("res://scripts/pass_flight.gd")
const Net = preload("res://scripts/net_collision.gd")
const RECEIVER := 1
const FEEDER := 2
const TARGET_RADIUS := 0.90
const BATCH_REPS := 10
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
var planned_reps := 0
var completed_reps := 0
var successful_reps := 0
var batch_active := false
var rep_readout: Label
var batch_button: Button
var launch_button: Button
var running := false
var finish_delay := -1.0
var incoming_flight := -1
var feed_spin_axis := Vector3.ZERO
var feed_spin_speed := 0.0
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
var trajectory: MeshInstance3D

func _init(match_: Node3D) -> void:
	game = match_
	var saved_source: Variant = StorySession.match_preference(PREFERENCE_PREFIX+"source_position",Vector2(source.x,source.z))
	if saved_source is Vector2 and saved_source.is_finite():
		source.x = clampf(saved_source.x,-6.5,6.5)
		source.z = clampf(saved_source.y,-6.5,15.0)
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
	rep_readout = host.label("",18)
	rep_readout.hide()
	host.content.add_child(rep_readout)
	var left: VBoxContainer = host.content
	add_slider(host,left,"speed_scale","Slow motion","%",10,100,5,100,func(v): playback_speed = v*0.01)
	add_slider(host,parent,"target_height","Target height","m",0.15,4.5,0.05,target.y,func(v): target.y = v)
	add_slider(host,parent,"skill","Passing skill","%",0,100,1,game.passing_skill,func(v): game.passing_skill = v)
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
				"receiver": start = Vector3(clampf(point.x,-4.4,4.4),start.y,clampf(point.z,-4.9,3.4))
				"source":
					source = Vector3(clampf(point.x,-6.5,6.5),source.y,clampf(point.z,-6.5,15.0))
					StorySession.save_match_preference(PREFERENCE_PREFIX+"source_position",Vector2(source.x,source.z))
				"target": target = Vector3(clampf(point.x,-4.4,4.4),target.y,clampf(point.z,-4.9,3.8))
			update_setup()
		return true
	return false

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

func start_single() -> void:
	if batch_active: return
	start_reps(1)

func toggle_batch() -> void:
	if batch_active:
		batch_active = false
		batch_button.text = "Run 10 reps"
		launch_button.disabled = false
		planned_reps = completed_reps+int(running)
		update_rep_readout()
		return
	start_reps(BATCH_REPS)

func start_reps(count: int) -> void:
	planned_reps = count
	completed_reps = 0
	successful_reps = 0
	batch_active = count > 1
	launch_button.disabled = batch_active
	batch_button.text = "Stop after this rep" if batch_active else "Run 10 reps"
	update_rep_readout()
	launch_ball()

func update_rep_readout() -> void:
	rep_readout.show()
	rep_readout.text = "%d/%d successful · %d/%d completed" % [successful_reps,completed_reps,completed_reps,planned_reps] if completed_reps > 0 else "0/%d completed" % planned_reps

func launch_ball() -> void:
	if game.replay.active: game.toggle_replay()
	game.begin_point()
	game.phase = game.Phase.LIVE
	game.serve.ball.hide()
	game.players[RECEIVER].global_position = start
	game.drill_pass_target = target
	target_marker.global_position = target
	origin_marker.global_position = source
	trajectory.hide()
	game.update_player_guide()
	game.score_label.hide()
	game.info.text = "Ball in flight"
	var plan := feed()
	feed_spin_axis = plan.spin_axis
	feed_spin_speed = plan.spin_rate
	game.launch(source,plan.incoming,"spike",FEEDER,spin_rate if spin != "No spin" else 0.0,-1,Vector3.ZERO,plan.acceleration)
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
		"rep":completed_reps+1,"receiver":start,"source":source,"target":target,
		"direction":heading,"angle":angle,"speed":speed,"spin":spin,
		"spin_rate":spin_rate if spin != "No spin" else 0.0,"passing_skill":game.passing_skill
	},true)
	game.replay.record(game)

func tick(delta: float) -> void:
	if game.replay.active:
		game.replay.step(game,delta)
		return
	if not running:
		if finish_delay >= 0.0:
			delta *= playback_speed
			game.match_clock += delta
			game.animated.fill(false)
			game.advance_recoveries(delta)
			game.advance_idle_players(delta)
			game.replay.record(game)
			finish_delay = maxf(0.0,finish_delay-delta)
			if finish_delay <= 0.0 and not game.recoveries.get(RECEIVER,{}).has("save"):
				finish_delay = -1.0
				if batch_active: launch_ball()
				else: reset_receiver()
		return
	delta *= playback_speed
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
	if game.flight_number == incoming_flight:
		if not feed_spin_axis.is_zero_approx(): game.ball.rotate(feed_spin_axis,feed_spin_speed*delta)
		var platform: Node3D = game.platforms[RECEIVER]
		game.tick_receive(delta,previous)
		var check: Dictionary = platform.contact_check
		if check.has("gap") and float(check.gap) < float(closest_check.get("gap",INF)):
			closest_check = check.duplicate()
		if platform.low_save.active:
			technique_label = "Pancake" if platform.low_save.pancake else ("One-arm dive" if not platform.low_save.wide_arm.is_empty() else "Dive")
		if game.flight_number != incoming_flight:
			contact_label = technique_label if not technique_label.is_empty() else game.stroke
			game.info.text = contact_label
	game.advance_idle_players(delta)
	if game.elapsed >= game.flight_end():
		finish()
	game.replay.record(game)

func reset_receiver() -> void:
	var receiver: Node3D = game.players[RECEIVER]
	game.recoveries.erase(RECEIVER)
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
			batch_active = false
			batch_button.text = "Run 10 reps"
			launch_button.disabled = false
		update_rep_readout()
	game.trace.write("passing_drill_result",game.match_clock,{
		"rep":completed_reps,"successful":success,"result":game.info.text,
		"technique":contact_label if not contact_label.is_empty() else technique_label,
		"target_crossing":target_crossing,"ball_end":game.ball.global_position,"closest_contact":closest_check
	},true)
	finish_delay = 1.0
