extends "res://scripts/serving_camp.gd"

const PassAccuracy = preload("res://scripts/reception_accuracy.gd")
const Map = preload("res://scripts/mapped_reception.gd")
var map := Map.new()
var defense_map := Map.new()
var defense_anchor := Node3D.new()
var defense_recipe := {}
var defense_at := INF
var defense_contact := -INF
var first_dig_touch := -INF
var feedback_rally := -1
const PASS_RELEASE_LEAD := .050
const DIG_WINDOW := .125
const DIG_PERFECT := .055
var dig_reach := .12
var stance_points: Array[Vector3]=[]
var chase_box := {}
var line_read_noise := 0.
var chase_goal := Vector3.ZERO
var active_stances: Array[Vector3]=[]
var routed_zone := ""
var boxes: Array[Dictionary]=[]
var recipe := {}
var anchor := Node3D.new()
var dragged := -1
func across(point: Vector3) -> Vector3:
	return Vector3(-point.x,point.y,2.*BallNet.NET_Z-point.z)

func start_drill() -> void:
	AudioServer.set_bus_mute(0,StorySession.game_options.get_value("audio","muted",false))
	world.add_child(map)
	world.add_child(anchor)
	world.add_child(defense_map)
	world.add_child(defense_anchor)
	defense_map.defenders.append(defense_anchor)
	map.defenders.append(anchor)
	map.clips=JSON.parse_string(FileAccess.get_file_as_string("res://assets/reception_studio.json"))
	map.pass_rise=StorySession.game_options.get_value("reception_studio","pass_arc",3.05)
	defense_map.clips=map.clips
	defense_map.pass_goal=Vector3(0.,.15,BallNet.NET_Z-1.5)
	map.pass_goal=SETTER_BASE
	for i in 3:
		stance_points.append(across(StorySession.game_options.get_value("reception_studio",Map.HOME_KEYS[i],Map.DEFAULT_STANCES[i])))
	boxes=map.assigned_boxes()
	super.start_drill()
	title.text="SERVING  /  RECEPTION TEST"
	for actor in wall+[receiving_middle]: actor.hide()

func build_rally_sliders() -> void:
	add_rally_sliders("serving",[["Serve speed","serve_kmh",0,300,0," km/h"],["Dig reach assist","dig_reach_cm",0,25,12," cm"]])

func apply_drill_slider(key: String,value: float) -> void:
	if key=="dig_reach_cm": dig_reach=value*.01

var dig_recovery_age := 0.

func release_dig_pose() -> void:
	var actor=defense_map.player
	if actor==null: return
	var facing := defense_anchor.rotation.y
	actor.reparent(world,true)
	actor.global_basis=Basis(Vector3.UP,facing)*Basis.from_scale(defense_map.athlete_scale)
	actor.position.y=.04
	for bone in defense_map.ready_pose.size():
		actor.skeleton.set_bone_pose(bone,defense_map.ready_pose[bone])
	for modifier in actor.skeleton.get_children():
		if modifier is SkeletonModifier3D: modifier.active=true
	actor.play_action("idle",0.)
	actor.animator.seek(0.,true)
	defense_map.player=null

func recover_digger(delta: float) -> bool:
	if defense_recipe.is_empty(): return super.recover_digger(delta)
	if defense_map.player==null:
		last_digger.animator.advance(delta)
		return false
	dig_recovery_age+=delta
	sample_attack_dig()
	var blend := smoothstep(.12,.85,dig_recovery_age)
	var rig: Skeleton3D=last_digger.skeleton
	for bone in defense_map.ready_pose.size():
		rig.set_bone_pose(bone,rig.get_bone_pose(bone).interpolate_with(defense_map.ready_pose[bone],blend))
	last_digger.position.y=lerpf(last_digger.position.y,0.,blend)
	if dig_recovery_age>=.85: release_dig_pose()
	return false

func next_serve() -> void:
	line_read_noise=randf_range(-1.,1.)
	release_dig_pose()
	dig_recovery_age=0.
	defense_recipe={}
	defense_at=INF
	defense_contact=-INF
	first_dig_touch=-INF
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


func bind_contact_motion(mapper: Map,root: Node3D,actor: Node3D,home: Vector3,source: Vector3,best: Dictionary) -> Dictionary:
	return mapper.begin_mapped_motion(root,actor,home,source,best,dig_reach if mapper==defense_map else 0.)

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
	if recipe.kind!="overhead": dig_sound.play()
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

func mapped_touch(mapper: Map,motion: Dictionary,previous: Vector3) -> bool:
	return mapped_segment_touch(mapper,motion,previous,ball.position)

func mapped_segment_touch(mapper: Map,motion: Dictionary,previous: Vector3,end: Vector3) -> bool:
	return mapper.segment_touch(motion,previous,end)

func sample_attack_dig() -> void:
	var offset := dig_clock-defense_at
	var frame := float(defense_recipe.contact)+offset*60.
	if offset<0.:
		var pace := smoothstep(40.,110.,defense_map.feed_kmh)
		var lead := defense_map.incoming_lead_seconds
		var elapsed := maxf(0.,lead+offset)
		# Start at the usual entry pose, then form the platform early and hold it through contact.
		frame=float(defense_recipe.contact)+minf(0.,elapsed*(1.+.8*pace)-lead)*60.
	defense_map.sample_receiver(defense_recipe,clampf(frame,0.,defense_recipe.frames),true,defense_map.legs)

func walk_server(delta: float,defending := false) -> void:
	if defending and defense_map.player!=null:
		sample_attack_dig()
		return
	super.walk_server(delta,defending)

func dig_defender() -> Node3D:
	return hitter

func cpu_dig() -> bool:
	return false

func block_on_flight_segment(previous: Vector3) -> bool:
	if phase!="serve_return" or not attack_floor_pending: return false
	var dt := previous.distance_to(ball.position)/maxf(.01,drop_velocity.length())
	dig_clock+=dt
	if defense_recipe.is_empty():
		if not dig_armed(): return false
		var ahead := minf(.32,preload("res://scripts/pass_flight.gd").landing_time(ball.position,drop_velocity))
		var source := pin_hitter.global_position
		var actor := dig_defender()
		var fall := preload("res://scripts/pass_flight.gd").landing_time(ball.position-Vector3.UP*.72,drop_velocity)
		var intercept := ball.position+drop_velocity*fall+Vector3.DOWN*4.905*fall*fall
		if cpu_dig():
			var facing := (source-actor.position).slide(Vector3.UP).normalized()
			var stance := intercept.slide(Vector3.UP)-facing*.52+Vector3.UP*actor.position.y
			if stance.distance_to(actor.position)>.22:
				move_receiver(actor,stance,dt,source-actor.position,GroundControls.speed(true,true),true)
		var yaw := atan2(source.x-actor.position.x,source.z-actor.position.z)
		var start := (previous-dig_defender().position).rotated(Vector3.UP,-yaw)
		var predicted := ball.position+drop_velocity*ahead+Vector3.DOWN*4.905*ahead*ahead
		var end := (predicted-dig_defender().position).rotated(Vector3.UP,-yaw)
		var first := INF
		var best := {}
		for box in boxes:
			var span := map.zone_interval(start,end,box.bounds)
			if span.y>span.x and span.x<first:
				first=span.x
				best=box
		var lead := maxf(0.,(ahead+dt)*first-dt)
		if best.is_empty():
			var gap := (intercept-actor.position).slide(Vector3.UP).length()
			if not cpu_dig() or fall>.20 or gap>1.75: return false
			var local := (intercept-actor.position).rotated(Vector3.UP,-yaw)
			best={"id":11 if gap>1. else 21,"cell":Vector3i(0 if local.x<0. else 2,0,2),"part":0}
			lead=fall
		defense_at=dig_clock+lead
		defense_map.set_intercept=ball.position+drop_velocity*lead+Vector3.DOWN*4.905*lead*lead
		defense_map.incoming_lead_seconds=lead
		defense_map.feed_kmh=drop_velocity.length()*3.6
		defense_recipe=bind_contact_motion(defense_map,defense_anchor,dig_defender(),dig_defender().position,source,best)
	sample_attack_dig()
	var timing_error := dig_contact_error(previous)
	if timing_error<0.: return false
	last_digger=dig_defender()
	dig_incoming=drop_velocity
	var bounds: Vector2=PassAccuracy.spread(timing_error,drop_velocity.length(),received_spin_rps,last_digger.effective_rating("Forearm reception"),false)
	var miss: Vector3=PassAccuracy.sample_offset(bounds)
	var goal := defense_map.pass_goal+miss.slide(Vector3.UP)
	var apex := ball.position.y+maxf(1.,3.4+miss.y)
	var flight := sqrt(2.*(apex-ball.position.y)/9.81)+sqrt(2.*(apex-goal.y)/9.81)
	drop_velocity=(goal-ball.position)/flight+Vector3.UP*4.905*flight
	drop_net_hit.clear()
	hard_spike_floor_pending=false
	floor_linger=0.
	phase="server_dig"
	dig_sound.play()
	message.text="Dig"
	trace("mapped_dig",{"contact":defense_contact,"prediction":defense_at,"release":str(dig_platforms[last_digger].pressed_at),"apex":apex,"landing_target":str(goal)})
	return true

func dig_armed() -> bool:
	return true

func dig_contact_error(previous: Vector3) -> float:
	if mapped_touch(defense_map,defense_recipe,previous):
		defense_contact=dig_clock
		if not is_finite(first_dig_touch): first_dig_touch=dig_clock
	if cpu_dig():
		if is_finite(defense_contact): dig_platforms[dig_defender()].queue_bump(dig_clock)
	else: update_dig_feedback()
	var release: float=dig_platforms[dig_defender()].pressed_at
	if not is_finite(defense_contact) or not is_finite(release) or minf(absf(release-defense_at+PASS_RELEASE_LEAD),absf(release-defense_contact+PASS_RELEASE_LEAD))>DIG_WINDOW or absf(defense_contact-dig_clock)>DIG_WINDOW: return -1.
	return clampf(absf(release-defense_at+PASS_RELEASE_LEAD)/DIG_WINDOW,0.,1.)

func update_dig_feedback() -> void:
	var release: float=dig_platforms[dig_defender()].pressed_at
	if not is_finite(release) or not is_finite(defense_at): return
	var measured := is_finite(first_dig_touch)
	var reference := first_dig_touch if measured else defense_at
	if feedback_rally!=replay_rally:
		feedback_rally=replay_rally
		ContactTiming.window("Dig",release-reference+PASS_RELEASE_LEAD,-DIG_WINDOW,DIG_WINDOW,-DIG_PERFECT,DIG_PERFECT,not measured)

func attack_surface_contact(point: Vector3,floor_hit: bool) -> void:
	if phase=="serve_return" and attack_floor_pending and floor_hit:
		trace("mapped_dig_miss",{"assigned":not defense_recipe.is_empty(),"pose_contact":str(defense_contact),"prediction":str(defense_at),"release":str(dig_platforms[dig_defender()].pressed_at),"floor":str(point)})
	super.attack_surface_contact(point,floor_hit)

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
