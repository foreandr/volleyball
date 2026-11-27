extends "res://scripts/serving_camp.gd"

const Map = preload("res://scripts/mapped_reception.gd")
var map := Map.new()
var defense_map := Map.new()
var defense_anchor := Node3D.new()
var defense_recipe := {}
var defense_at := INF
var defense_contact := -INF
var first_dig_touch := -INF
var dig_feedback := Label.new()
var feedback_tween: Tween
var feedback_rally := -1
const DIG_WINDOW := .125
const DIG_PERFECT := .055
var dig_reach := .12
var stance_points: Array[Vector3]=[]
var chase_box := {}
var chase_goal := Vector3.ZERO
var active_stances: Array[Vector3]=[]
var routed_zone := ""
var boxes: Array[Dictionary]=[]
var recipe := {}
var anchor := Node3D.new()
var dragged := -1
var boundary := Node3D.new()
var boundary_ink := StandardMaterial3D.new()
var boundary_timer := Timer.new()

func across(point: Vector3) -> Vector3:
	return Vector3(-point.x,point.y,2.*BallNet.NET_Z-point.z)

func start_drill() -> void:
	AudioServer.set_bus_mute(0,StorySession.game_options.get_value("audio","muted",false))
	build_boundary()
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
	for x in 3:
		for y in 3:
			for z in 3:
				var cell := Vector3i(x,y,z)
				for part in map.region_parts(cell):
					var id := map.assigned_action(cell,part)
					if id<=0: continue
					var size := map.region_size(cell,part)
					boxes.append({"cell":cell,"part":part,"id":id,"bounds":AABB(map.region_center(cell,part)-size*.5,size)})
	super.start_drill()
	title.text="SERVING  /  RECEPTION TEST"
	add_child(dig_feedback)
	dig_feedback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dig_feedback.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	dig_feedback.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	dig_feedback.mouse_filter=Control.MOUSE_FILTER_IGNORE
	dig_feedback.add_theme_font_size_override("font_size",34)
	dig_feedback.add_theme_constant_override("outline_size",7)
	dig_feedback.add_theme_color_override("font_outline_color",Color("192029"))
	dig_feedback.hide()
	for actor in wall+[receiving_middle]: actor.hide()

func build_rally_sliders() -> void:
	add_rally_sliders("serving",[["Serve speed","serve_kmh",0,300,0," km/h"],["Dig reach assist","dig_reach_cm",0,25,12," cm"]])

func apply_drill_slider(key: String,value: float) -> void:
	if key=="dig_reach_cm": dig_reach=value*.01

func next_serve() -> void:
	if defense_map.player!=null:
		defense_map.player.reparent(world,true)
		defense_map.player.basis=Basis.IDENTITY
		for modifier in defense_map.player.skeleton.get_children():
			if modifier is SkeletonModifier3D: modifier.active=true
		defense_map.player=null
	defense_recipe={}
	defense_at=INF
	defense_contact=-INF
	first_dig_touch=-INF
	if map.player!=null:
		map.player.reparent(world,true)
		map.player.basis=Basis.IDENTITY
		for modifier in map.player.skeleton.get_children():
			if modifier is SkeletonModifier3D: modifier.active=true
		map.player=null
	recipe={}
	super.next_serve()
	active_stances.clear()
	for i in passers.size():
		active_stances.append(receive_read.position_for(stance_points[i],i==1))
		passers[i].position=active_stances[i]
	receiving_setter.position=Vector3(map.pass_goal.x,.04,maxf(map.pass_goal.z,BallNet.NET_Z+.25))

func stage_attacker(actor: Node3D,slot: int,delta: float) -> void:
	if actor==pin_hitter: super.stage_attacker(actor,slot,delta)

func step_serve_wall(_delta: float) -> void:
	pass

func move_libero_to_cover(_delta: float) -> void:
	pass

func receiver_candidates() -> Array:
	return [0,1,2]

func plan_serve_reception(shot) -> void:
	plan_remaining_reception(shot,0.)

func plan_remaining_reception(shot,from_time: float) -> void:
	chase_box={}
	routed_zone=""
	received_spin_rps=shot.reception_spin_rps()
	var finish: float=shot.planned_duration
	leave_serve=reads_serve_out(shot.flight_point(finish),passers[0].effective_rating("Forearm reception"),randf_range(-1.,1.))
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
	mapper.index=int(best.id)-1
	mapper.legs=mapper.index
	var recipe := mapper.reception_recipe(mapper.clips[mapper.index],best.cell,best.part)
	var key := mapper.assignment_key(best.cell,best.part)
	if recipe.kind=="overhead":
		var audition: int=StorySession.game_options.get_value("studio_hand_legs",key,-2)
		if audition>=-1 and audition<mapper.clips.size():
			recipe=recipe.duplicate()
			mapper.legs=audition
			recipe.step_legs=0 if audition<0 else mapper.clips[audition].id
			recipe.audition=true
	mapper.posed_lead_foot=mapper.lead_foot(best.cell,best.part)
	root.position=home
	root.basis=Basis(Vector3.UP,atan2(source.x-root.position.x,source.z-root.position.z))
	var flipped: bool=StorySession.game_options.get_value("studio_mirror",key,mapper.default_mirror(best.cell,best.part,recipe))
	root.scale=Vector3(-1. if flipped else 1.,1.,1.)
	if flipped and mapper.posed_lead_foot!="Auto": mapper.posed_lead_foot="Left" if mapper.posed_lead_foot=="Right" else "Right"
	mapper.player=actor
	mapper.player.reparent(root,false)
	mapper.player.transform=Transform3D.IDENTITY
	mapper.player.animator.pause()
	for modifier in mapper.player.skeleton.get_children():
		if modifier is SkeletonModifier3D: modifier.active=false
	mapper.bind_receiver(mapper.player)
	mapper.intercept_shift=Vector3.ZERO
	mapper.shift_frame=recipe.contact
	mapper.sample_receiver(recipe,recipe.contact,true,mapper.legs)
	var center: Vector3=mapper.HandPass.contact_center(mapper.player) if recipe.kind=="overhead" else mapper.player.skeleton.to_global(mapper.player.skeleton.get_bone_global_pose(mapper.player.skeleton.find_bone("hand_l")).origin)
	var offset := mapper.set_intercept-center
	mapper.intercept_shift=offset.slide(Vector3.UP).limit_length(.75)
	if mapper==defense_map: mapper.intercept_shift+=(offset-mapper.intercept_shift).limit_length(dig_reach)
	return recipe

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
	map.sample_receiver(recipe,clampf(recipe.contact+(flight_age-receive_at)*60.,0.,recipe.frames),true,map.legs)
	if absf(flight_age-receive_at)>.24: return
	if not accept_reception(previous): return
	receive_read.covered()
	pass_start=ball.position
	pass_end=reception_pass_target()
	pass_end.y=receiving_setter.height_cm*.0118
	pass_duration=sqrt(2.*map.pass_rise/9.81)+sqrt(2.*maxf(.05,pass_start.y+map.pass_rise-pass_end.y)/9.81)
	pass_clock=0.
	attack_slot=2
	set_at=pass_duration
	pass_in_system=false
	phase="serve_pass"
	if recipe.kind!="overhead": dig_sound.play()
	message.text="Pass"

func reception_pass_target() -> Vector3:
	return map.pass_goal

func accept_reception(previous: Vector3) -> bool:
	return mapped_touch(map,recipe,previous)

func mapped_touch(mapper: Map,motion: Dictionary,previous: Vector3) -> bool:
	var touched := false
	if motion.kind=="overhead":
		var hands := mapper.HandPass.contact_center(mapper.player)
		touched=hands.distance_to(Geometry3D.get_closest_point_to_segment(hands,previous,ball.position))<=mapper.HAND_RADIUS
	else:
		for shape in mapper.RECEPTION_CAPSULES:
			var seg := mapper.reception_segment(mapper.player.skeleton,shape)
			var points := Geometry3D.get_closest_points_between_segments(previous,ball.position,seg[0],seg[1])
			if points[0].distance_to(points[1])<=mapper.BALL_RADIUS+float(shape[2])+mapper.FOREARM_CONTACT_GRACE:
				touched=true
				break
	return touched

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
		var ahead := minf(.32,preload("res://scripts/pass_flight.gd").landing_time(ball.position,drop_velocity))
		var source := pin_hitter.global_position
		var yaw := atan2(source.x-dig_defender().position.x,source.z-dig_defender().position.z)
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
		if best.is_empty(): return false
		var lead := maxf(0.,(ahead+dt)*first-dt)
		defense_at=dig_clock+lead
		defense_map.set_intercept=ball.position+drop_velocity*lead+Vector3.DOWN*4.905*lead*lead
		defense_map.incoming_lead_seconds=lead
		defense_map.feed_kmh=drop_velocity.length()*3.6
		defense_recipe=bind_contact_motion(defense_map,defense_anchor,dig_defender(),dig_defender().position,source,best)
	sample_attack_dig()
	if mapped_touch(defense_map,defense_recipe,previous):
		defense_contact=dig_clock
		if not is_finite(first_dig_touch): first_dig_touch=dig_clock
	if cpu_dig():
		if is_finite(defense_contact): dig_platforms[dig_defender()].queue_bump(dig_clock)
	else: update_dig_feedback()
	var release: float=dig_platforms[dig_defender()].pressed_at
	if not is_finite(defense_contact) or not is_finite(release) or minf(absf(release-defense_at),absf(release-defense_contact))>DIG_WINDOW or absf(defense_contact-dig_clock)>DIG_WINDOW: return false
	last_digger=dig_defender()
	dig_incoming=drop_velocity
	var apex := ball.position.y+3.4
	var flight := sqrt(2.*(apex-ball.position.y)/9.81)+sqrt(2.*(apex-defense_map.pass_goal.y)/9.81)
	drop_velocity=(defense_map.pass_goal-ball.position)/flight+Vector3.UP*4.905*flight
	drop_net_hit.clear()
	hard_spike_floor_pending=false
	floor_linger=0.
	phase="server_dig"
	dig_sound.play()
	message.text="Dig"
	trace("mapped_dig",{"contact":defense_contact,"prediction":defense_at,"release":release,"apex":apex})
	return true

func update_dig_feedback() -> void:
	var release: float=dig_platforms[dig_defender()].pressed_at
	if not is_finite(release) or not is_finite(defense_at): return
	var measured := is_finite(first_dig_touch)
	var reference := first_dig_touch if measured else defense_at
	show_release_feedback(release-reference,measured)

func show_release_feedback(offset: float,measured: bool,perfect_window := 0.) -> void:
	var ms := roundi(offset*1000.)
	var direction := "Early" if ms<0 else ("Late" if ms>0 else "On time")
	if perfect_window>0. and absf(offset)<=perfect_window: direction="Perfect"
	var label := "%s  %d ms" % [direction,absi(ms)]
	if not measured: label+=" (estimated)"
	dig_feedback.text=label
	dig_feedback.add_theme_color_override("font_color",Color("78e1ad") if direction=="Perfect" else Color("ffd36b") if ms<0 else (Color("ff9086") if ms>0 else Color("78e1ad")))
	if feedback_rally==replay_rally: return
	feedback_rally=replay_rally
	if feedback_tween: feedback_tween.kill()
	dig_feedback.modulate.a=0.
	dig_feedback.show()
	feedback_tween=create_tween()
	feedback_tween.tween_property(dig_feedback,"modulate:a",1.,.16)
	feedback_tween.tween_interval(1.05)
	feedback_tween.tween_property(dig_feedback,"modulate:a",0.,.38)
	feedback_tween.tween_callback(dig_feedback.hide)


func attack_surface_contact(point: Vector3,floor_hit: bool) -> void:
	if phase=="serve_return" and attack_floor_pending and floor_hit:
		trace("mapped_dig_miss",{"assigned":not defense_recipe.is_empty(),"pose_contact":str(defense_contact),"prediction":str(defense_at),"release":str(dig_platforms[dig_defender()].pressed_at),"floor":str(point)})
	super.attack_surface_contact(point,floor_hit)

func step_reception_rally(delta: float) -> void:
	super.step_reception_rally(delta)
	if phase=="serve_pass":
		map.sample_receiver(recipe,minf(recipe.frames,recipe.contact+60.*(flight_age-receive_at+pass_clock)),true,map.legs)

func scoring_target(_origin: Vector3) -> Vector3:
	return Vector3(0.,BallNet.RADIUS,BallNet.NET_Z-8.)

func choose_rally_attack(origin: Vector3) -> void:
	pin_attack.rally_shot="spike"
	pin_attack.swing_aim=pin_frame.to_local(scoring_target(origin))

func build_boundary() -> void:
	world.add_child(boundary)
	boundary_ink.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in 4:
		var edge := MeshInstance3D.new()
		var strip := BoxMesh.new()
		var sign_side := -1. if i%2==0 else 1.
		strip.size=Vector3(.065,.004,9.) if i<2 else Vector3(9.,.004,.065)
		edge.mesh=strip
		edge.material_override=boundary_ink
		edge.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		boundary.add_child(edge)
		edge.position=Vector3(sign_side*4.475,.063,BallNet.NET_Z+4.5) if i<2 else Vector3(0,.063,BallNet.NET_Z+4.5+sign_side*4.475)
	boundary.hide()
	add_child(boundary_timer)
	boundary_timer.one_shot=true
	boundary_timer.timeout.connect(display_boundary.bind(0))

func flash_boundary(ace: bool) -> void:
	display_boundary(1 if ace else -1)
	boundary_timer.start(1.)

func display_boundary(call_value: int) -> void:
	set_meta("serve_boundary",call_value)
	boundary_ink.albedo_color=Color("#30ee76") if call_value==1 else Color("#ff394b")
	boundary.visible=call_value!=0

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
