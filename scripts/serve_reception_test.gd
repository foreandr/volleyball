extends "res://scripts/mapped_defense_camp.gd"

var map := Map.new()
var stance_points: Array[Vector3]=[]
var chase_box := {}
var line_read_noise := 0.
var chase_goal := Vector3.ZERO
var active_stances: Array[Vector3]=[]
var routed_zone := ""
var recipe := {}
var anchor := Node3D.new()
var dragged := -1
func across(point: Vector3) -> Vector3:
	return Vector3(-point.x,point.y,2.*BallNet.NET_Z-point.z)

func start_drill() -> void:
	world.add_child(map)
	world.add_child(anchor)
	map.defenders.append(anchor)
	map.clips=JSON.parse_string(FileAccess.get_file_as_string("res://assets/reception_studio.json"))
	map.pass_rise=StorySession.game_options.get_value("reception_studio","pass_arc",3.05)
	map.pass_goal=SETTER_BASE
	for i in 3:
		stance_points.append(across(StorySession.game_options.get_value("reception_studio",Map.HOME_KEYS[i],Map.DEFAULT_STANCES[i])))
	super.start_drill()
	title.text="SERVING  /  RECEPTION TEST"
	for actor in wall+[receiving_middle]: actor.hide()

func build_rally_sliders() -> void:
	add_rally_sliders("serving",[["Serve speed","serve_kmh",0,300,0," km/h"],["Dig reach assist","dig_reach_cm",0,25,12," cm"]])

func apply_drill_slider(key: String,value: float) -> void:
	if key=="dig_reach_cm": dig_reach=value*.01

func next_serve() -> void:
	line_read_noise=randf_range(-1.,1.)
	if map.player!=null:
		map.player.reparent(world,true)
		map.player.global_basis=Basis.from_scale(map.athlete_scale)
		for modifier in map.player.skeleton.get_children():
			if modifier is SkeletonModifier3D: modifier.active=true
		map.player=null
	recipe={}
	super.next_serve()
	active_stances.clear()
	for i in passers.size():
		active_stances.append(reception_home(i))
		passers[i].position=active_stances[i]
	receiving_setter.position=Vector3(map.pass_goal.x,.04,maxf(map.pass_goal.z,BallNet.NET_Z+.25))

func reception_home(slot: int) -> Vector3:
	return stance_points[slot]

func walk_to_coverage(delta: float) -> void:
	super.walk_to_coverage(delta)
	for slot in passers.size(): active_stances[slot]=passers[slot].position

func stage_attacker(actor: Node3D,slot: int,delta: float) -> void:
	if actor==pin_hitter: super.stage_attacker(actor,slot,delta)

func step_serve_wall(_delta: float) -> void:
	pass

func move_libero_to_cover(_delta: float) -> void:
	pass

func can_chase_reception() -> bool:
	return true

func receiver_candidates() -> Array:
	return [0,1,2]

func plan_serve_reception(shot) -> void:
	plan_remaining_reception(shot,0.)

func plan_remaining_reception(shot,from_time: float) -> void:
	chase_box={}
	routed_zone=""
	received_spin_rps=shot.reception_spin_rps()
	var finish: float=shot.planned_duration
	leave_serve=reads_serve_out(shot.flight_point(finish),passers[0].effective_rating("Forearm reception"),line_read_noise)
	if leave_serve or not shot.net_hit.is_empty(): return
	var previous: Vector3=shot.flight_point(from_time)
	var steps := maxi(1,ceili((finish-from_time)*90.))
	for tick in range(1,steps+1):
		var point: Vector3=shot.flight_point(lerpf(from_time,finish,float(tick)/steps))
		if point.z>BallNet.NET_Z:
			var earliest := INF
			var best := {}
			var nearest := INF
			for i in receiver_candidates():
				var local_start := (previous-active_stances[i]).rotated(Vector3.UP,PI)
				var local_end := (point-active_stances[i]).rotated(Vector3.UP,PI)
				if AABB(map.MAP_ORIGIN,map.CELL_SIZE*3.).grow(.01).intersects_segment(local_start,local_end)==null: continue
				for box in boxes:
					var span := map.zone_interval(local_start,local_end,box.bounds)
					if span.y<=span.x: continue
					var distance := local_start.lerp(local_end,span.x).slide(Vector3.UP).length_squared()
					if span.x<earliest-.0001 or (absf(span.x-earliest)<.0001 and distance<nearest):
						earliest=span.x
						nearest=distance
						receiver=i
						best=box
			if not best.is_empty():
				receive_at=lerpf(from_time,finish,(tick-1+earliest)/steps)
				if map.early_platform(best.cell): receive_at=maxf(from_time,receive_at-.55/maxf(1.,shot.velocity.slide(Vector3.UP).length()))
				map.set_intercept=shot.flight_point(receive_at)
				map.incoming_lead_seconds=receive_at-from_time
				map.feed_kmh=shot.velocity.length()*3.6
				routed_zone=map.region_number(best.cell,best.part)
				recipe=bind_contact_motion(map,anchor,passers[receiver],active_stances[receiver],serve_station,best)
				return
		previous=point

	# The flight missed every stationary platform. Find the least travel needed
	# to bring an assigned motion into the descending ball's path.
	if not can_chase_reception(): return
	var best_cost := INF
	for tick in range(1,steps+1):
		var t := lerpf(from_time,finish,float(tick)/steps)
		var point: Vector3=shot.flight_point(t)
		if point.z<=BallNet.NET_Z or point.y<.25: continue
		for i in receiver_candidates():
			var home: Vector3=passers[i].global_position
			var yaw := atan2(serve_station.x-home.x,serve_station.z-home.z)
			var local := (point-home).rotated(Vector3.UP,-yaw)
			for box in boxes:
				var bounds: AABB=box.bounds
				if local.y<bounds.position.y or local.y>bounds.end.y: continue
				var center := bounds.get_center()
				var offset := Vector3(local.x-center.x,0.,local.z-center.z)
				var goal := home+offset.rotated(Vector3.UP,yaw)
				if goal.z<BallNet.NET_Z+.20: continue
				var travel := offset.length()
				var spare: float=t-from_time-passers[i].reaction_seconds()-travel/GroundControls.speed(true,true)
				var cost := travel+.5*absf(local.y-center.y)+12.*maxf(0.,.20-spare)
				if i==1 and spare>.12: cost-=.55
				if cost>=best_cost: continue
				best_cost=cost
				chase_box=box
				chase_goal=goal
				receiver=i
				receive_at=t
	if not chase_box.is_empty():
		map.set_intercept=shot.flight_point(receive_at)
		map.feed_kmh=shot.velocity.length()*3.6


func step_serve_reception(_shot,previous: Vector3,_delta: float) -> void:
	if not chase_box.is_empty():
		var actor := passers[receiver]
		if flight_age<actor.reaction_seconds(): return
		var parent := actor.get_parent_node_3d()
		var before := actor.global_position
		move_receiver(actor,parent.to_local(chase_goal),_delta,parent.to_local(ball.position)-actor.position,GroundControls.speed(true,true),true)
		if before.distance_to(actor.global_position)>2.35*_delta: actor.stamina.spend(_delta*actor.stamina.SPRINT_DRAIN,"Sprint")
		if actor.global_position.distance_to(chase_goal)>.14 or flight_age>receive_at+.10: return
		map.incoming_lead_seconds=maxf(0.,receive_at-flight_age)
		routed_zone=map.region_number(chase_box.cell,chase_box.part)
		recipe=bind_contact_motion(map,anchor,actor,actor.global_position,serve_station,chase_box)
		chase_box={}
	if recipe.is_empty(): return
	map.sample_receiver(recipe,reception_frame(),true,map.legs)
	if not accept_reception(previous): return
	complete_reception()

func reception_frame() -> float:
	return clampf(recipe.contact+(flight_age-receive_at)*60.,0.,recipe.frames)

func complete_reception() -> void:
	receive_read.covered()
	pass_start=ball.position
	pass_end=reception_pass_target()
	pass_end.y=receiving_setter.height_cm*.0118
	var return_lift:=maxf(.15,PassAccuracy.IDEAL_APEX+return_height_error-pass_start.y)
	pass_duration=sqrt(2.*return_lift/9.81)+sqrt(2.*maxf(.05,pass_start.y+return_lift-pass_end.y)/9.81)
	pass_clock=0.
	attack_slot=2
	set_at=pass_duration
	pass_in_system=false
	phase="serve_pass"
	message.text="Pass"

func pass_timing_penalty() -> float:
	return absf(flight_age-receive_at)/.21

var return_height_error:=0.

func reception_pass_target() -> Vector3:
	var bounds := PassAccuracy.spread(pass_timing_penalty(),map.feed_kmh/3.6,received_spin_rps,passers[receiver].effective_rating("Hand reception" if recipe.get("kind","")=="overhead" else "Forearm reception"),false)
	var miss: Vector3=PassAccuracy.sample_offset(bounds)
	return_height_error=miss.y
	return receiving_setter.position+miss.slide(Vector3.UP)

func accept_reception(previous: Vector3) -> bool:
	return absf(flight_age-receive_at)<=.24 and mapped_touch(map,recipe,previous)

func step_reception_rally(delta: float) -> void:
	super.step_reception_rally(delta)
	if phase=="serve_pass" and map.player!=null:
		map.sample_receiver(recipe,minf(recipe.frames,recipe.contact+60.*(flight_age-receive_at+pass_clock)),true,map.legs)

func scoring_target(_origin: Vector3) -> Vector3:
	return Vector3(0.,BallNet.RADIUS,BallNet.NET_Z-8.)

func choose_rally_attack(origin: Vector3) -> void:
	pin_attack.rally_shot="spike"
	pin_attack.swing_aim=pin_frame.to_local(scoring_target(origin))

func flash_boundary(ace:bool) -> void:
	court_boundary.flash(Vector3(0.,0.,BallNet.NET_Z+4.5),ace)

func serve_out() -> void:
	flash_boundary(false)

func show_service_ace() -> void:
	super.show_service_ace()
	flash_boundary(true)
	var reason := "judged out" if leave_serve else ("no assigned zone crossed" if routed_zone.is_empty() else "platform missed")
	trace("reception_test_miss",{"reason":reason,"zone":routed_zone,"receiver":receiver if not routed_zone.is_empty() else -1,"landing":str(ball.position)})

func _input(event: InputEvent) -> void:
	if phase=="serve_ready" and not settings.visible and not get_tree().paused and not replay_inspector.active:
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
			if event.pressed:
				var closest := 24.
				for i in passers.size():
					var foot := camera.unproject_position(active_stances[i])
					var head := camera.unproject_position(active_stances[i]+Vector3.UP*1.8)
					var gap: float=event.position.distance_to(Geometry2D.get_closest_point_to_segment(event.position,foot,head))
					if gap<closest:
						closest=gap
						dragged=i
			elif dragged>=0:
				StorySession.game_options.set_value("reception_studio",Map.HOME_KEYS[dragged],across(stance_points[dragged]))
				StorySession.save_options()
				dragged=-1
				return
		if event is InputEventMouseMotion and dragged>=0:
			var hit=Plane(Vector3.UP,.052).intersects_ray(camera.project_ray_origin(event.position),camera.project_ray_normal(event.position))
			if hit!=null:
				stance_points[dragged]=Vector3(clampf(hit.x,-4.5,4.5),.052,clampf(hit.z,4.1,13.))
				active_stances[dragged]=stance_points[dragged]
				passers[dragged].position=active_stances[dragged]
		if dragged>=0: return
	super(event)
	if phase=="serve_return": update_dig_feedback()
