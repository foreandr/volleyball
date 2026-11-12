extends RefCounted

const Flight = preload("res://scripts/pass_flight.gd")
const Net = preload("res://scripts/net_collision.gd")
const RECEIVER := 1
const FEEDER := 2
const TARGET_RADIUS := 0.90
const SPINS := ["No spin","Topspin","Backspin","Sidespin left","Sidespin right"]

var game: Node3D
var start := Vector3(0,0.04,-2.25)
var source := Vector3(0,3.95,10.8)
var target := Vector3(1.7,0.04,1.7)
var heading := 0.0
var angle := 2.0
var speed := 18.0
var spin_rate := 6.0
var spin := "Topspin"
var playback_speed := 1.0
var repeat := false
var running := false
var finish_delay := -1.0
var incoming_flight := -1
var feed_spin_axis := Vector3.ZERO
var feed_spin_speed := 0.0
var contact_label := ""
var technique_label := ""
var placement: OptionButton
var sliders := {}
var origin_marker: MeshInstance3D
var target_marker: MeshInstance3D
var trajectory: MeshInstance3D

func _init(match_: Node3D) -> void:
	game = match_
	game.phase = game.Phase.FINISHED
	game.score_label.hide()
	game.info.text = "Set up the feed, then launch."
	game.serve.ball.hide()
	game.ball.hide()
	for index in game.players.size():
		game.players[index].visible = index == RECEIVER
	for label in game.key_labels:
		label.hide()
	game.players[RECEIVER].global_position = start
	origin_marker = marker(0.18,0.12,Color("#ffa95b"))
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
	var launch: Button = host.button("Launch ball",launch_ball)
	launch.name = "LaunchPassingFeed"
	parent.add_child(launch)
	var loop := CheckButton.new()
	loop.text = "Repeat feed"
	loop.toggled.connect(func(value: bool): repeat = value)
	parent.add_child(loop)
	placement = OptionButton.new()
	for text in ["Click court to place receiver","Click court to place ball source","Click court to place target"]:
		placement.add_item(text)
	parent.add_child(placement)
	parent.add_child(host.label("Receiver and target",19))
	add_slider(host,parent,"receiver_x","Receiver X","m",-4.4,4.4,0.1,start.x,func(v): start.x = v)
	add_slider(host,parent,"receiver_z","Receiver depth","m",-4.9,3.4,0.1,start.z,func(v): start.z = v)
	add_slider(host,parent,"target_x","Target X","m",-4.4,4.4,0.1,target.x,func(v): target.x = v)
	add_slider(host,parent,"target_z","Target depth","m",-4.9,3.8,0.1,target.z,func(v): target.z = v)
	add_slider(host,parent,"skill","Passing skill","%",0,100,1,game.passing_skill,func(v): game.passing_skill = v)
	parent.add_child(host.label("Ball feed",19))
	add_slider(host,parent,"source_x","Source X","m",-6.5,6.5,0.1,source.x,func(v): source.x = v)
	add_slider(host,parent,"source_y","Source height","m",0.3,7.0,0.05,source.y,func(v): source.y = v)
	add_slider(host,parent,"source_z","Source depth","m",-6.5,15.0,0.1,source.z,func(v): source.z = v)
	add_slider(host,parent,"heading","Direction","°",-180,180,1,heading,func(v): heading = v)
	add_slider(host,parent,"angle","Downward angle","°",-65,75,1,angle,func(v): angle = v)
	add_slider(host,parent,"speed","Ball speed","m/s",2,40,0.5,speed,func(v): speed = v)
	var selector := OptionButton.new()
	for style in SPINS: selector.add_item(style)
	selector.select(SPINS.find(spin))
	selector.item_selected.connect(func(index: int): spin = SPINS[index]; update_setup())
	parent.add_child(selector)
	add_slider(host,parent,"spin","Spin rate","rps",0,18,0.5,spin_rate,func(v): spin_rate = v)
	add_slider(host,parent,"speed_scale","Drill speed","%",10,100,5,100,func(v): playback_speed = v*0.01)

func add_slider(host: Control, parent: VBoxContainer, id: String, caption: String, unit: String, lower: float, upper: float, step: float, initial: float, apply: Callable) -> void:
	var label: Label = host.label("",16)
	parent.add_child(label)
	var slider := HSlider.new()
	slider.name = id
	slider.min_value = lower
	slider.max_value = upper
	slider.step = step
	slider.value = initial
	slider.custom_minimum_size.y = 19
	parent.add_child(slider)
	sliders[id] = slider
	var update := func(value: float):
		label.text = "%s  %.2f %s" % [caption,value,unit]
		apply.call(value)
		update_setup()
	slider.value_changed.connect(update)
	update.call(slider.value)

func place(point: Vector3) -> void:
	if running or game.replay.active: return
	match placement.selected:
		0:
			sliders.receiver_x.value = point.x
			sliders.receiver_z.value = point.z
		1:
			sliders.source_x.value = point.x
			sliders.source_z.value = point.z
		2:
			sliders.target_x.value = point.x
			sliders.target_z.value = point.z

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
	running = true
	finish_delay = -1.0
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
			finish_delay -= delta
			if finish_delay <= 0.0:
				finish_delay = -1.0
				if repeat: launch_ball()
		return
	delta *= playback_speed
	game.match_clock += delta
	var previous: float = game.elapsed
	game.elapsed = minf(game.elapsed+delta,game.flight_end())
	game.ball.global_position = game.path_point(game.elapsed)
	game.animated.fill(false)
	game.advance_recoveries(delta)
	if game.flight_number == incoming_flight:
		if not feed_spin_axis.is_zero_approx(): game.ball.rotate(feed_spin_axis,feed_spin_speed*delta)
		var platform: Node3D = game.platforms[RECEIVER]
		game.tick_receive(delta,previous)
		if platform.low_save.active:
			technique_label = "Pancake" if platform.low_save.pancake else ("One-arm dive" if not platform.low_save.wide_arm.is_empty() else "Dive")
		if game.flight_number != incoming_flight:
			contact_label = technique_label if not technique_label.is_empty() else game.stroke
			game.info.text = contact_label
	game.advance_idle_players(delta)
	if game.elapsed >= game.flight_end():
		finish()
	game.replay.record(game)

func finish() -> void:
	running = false
	game.phase = game.Phase.FINISHED
	var point: Vector3 = game.ball.global_position
	if contact_label.is_empty():
		if game.platforms[RECEIVER].low_save.active: game.begin_recovery(RECEIVER)
		game.info.text = "Missed feed" if game.net_hit.is_empty() else "Feed hit the net"
	else:
		var error: float = (point-game.drill_pass_target).slide(Vector3.UP).length()
		var result := "On target" if error <= TARGET_RADIUS else "%.2f m from target" % error
		game.info.text = "%s · %s" % [contact_label,result]
	finish_delay = 1.0
