extends "res://scripts/serving_camp.gd"

const Map = preload("res://scripts/mapped_reception.gd")
var map := Map.new()
var stance_points: Array[Vector3]=[]
var boxes: Array[Dictionary]=[]
var recipe := {}
var anchor := Node3D.new()
var dragged := -1
var set_start := Vector3.ZERO
var set_end := Vector3.ZERO

func across(point: Vector3) -> Vector3:
	return Vector3(-point.x,point.y,2.*BallNet.NET_Z-point.z)

func start_drill() -> void:
	world.add_child(map)
	world.add_child(anchor)
	map.defenders.append(anchor)
	map.clips=JSON.parse_string(FileAccess.get_file_as_string("res://assets/reception_studio.json"))
	map.pass_rise=StorySession.game_options.get_value("reception_studio","pass_arc",3.05)
	map.pass_goal=across(StorySession.game_options.get_value("reception_studio","pass_target",Vector3(.022,.08,3.699)))
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
	for actor in wall+[pin_hitter,receiving_middle]: actor.hide()

func build_rally_sliders() -> void:
	add_rally_sliders("serving",[["Serve speed","serve_kmh",0,300,0," km/h"]])

func next_serve() -> void:
	if map.player!=null:
		map.player.reparent(world,true)
		map.player.basis=Basis.IDENTITY
		for modifier in map.player.skeleton.get_children():
			if modifier is SkeletonModifier3D: modifier.active=true
		map.player=null
	recipe={}
	super.next_serve()
	for i in passers.size(): passers[i].position=stance_points[i]
	receiving_setter.position=Vector3(map.pass_goal.x,.04,maxf(map.pass_goal.z,BallNet.NET_Z+.25))

func stage_attacker(_actor: Node3D,_slot: int,_delta: float) -> void:
	pass

func step_serve_wall(_delta: float) -> void:
	pass

func move_libero_to_cover(_delta: float) -> void:
	pass

func plan_serve_reception(shot) -> void:
	received_spin_rps=shot.reception_spin_rps()
	var finish: float=shot.planned_duration
	leave_serve=reads_serve_out(shot.flight_point(finish),passers[0].effective_rating("Forearm reception"),randf_range(-1.,1.))
	if leave_serve or not shot.net_hit.is_empty(): return
	var previous: Vector3=shot.origin
	var steps := maxi(1,ceili(finish*90.))
	for tick in range(1,steps+1):
		var point: Vector3=shot.flight_point(finish*tick/steps)
		if point.z>BallNet.NET_Z:
			var earliest := INF
			var best := {}
			var nearest := INF
			for i in 3:
				var local_start := (previous-stance_points[i]).rotated(Vector3.UP,PI)
				var local_end := (point-stance_points[i]).rotated(Vector3.UP,PI)
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
				receive_at=finish*(tick-1+earliest)/steps
				if map.early_platform(best.cell): receive_at=maxf(0.,receive_at-.55/maxf(1.,shot.velocity.slide(Vector3.UP).length()))
				map.set_intercept=shot.flight_point(receive_at)
				map.incoming_lead_seconds=receive_at
				map.feed_kmh=shot.velocity.length()*3.6
				map.index=int(best.id)-1
				map.legs=map.index
				recipe=map.reception_recipe(map.clips[map.index],best.cell,best.part)
				var key := map.assignment_key(best.cell,best.part)
				if recipe.kind=="overhead":
					var audition: int=StorySession.game_options.get_value("studio_hand_legs",key,-2)
					if audition>=-1 and audition<map.clips.size():
						recipe=recipe.duplicate()
						map.legs=audition
						recipe.step_legs=0 if audition<0 else map.clips[audition].id
						recipe.audition=true
				map.posed_lead_foot=map.lead_foot(best.cell,best.part)
				anchor.position=stance_points[receiver]
				anchor.basis=Basis(Vector3.UP,atan2(serve_station.x-anchor.position.x,serve_station.z-anchor.position.z))
				var flipped: bool=StorySession.game_options.get_value("studio_mirror",key,map.default_mirror(best.cell,best.part,recipe))
				anchor.scale=Vector3(-1. if flipped else 1.,1.,1.)
				if flipped and map.posed_lead_foot!="Auto": map.posed_lead_foot="Left" if map.posed_lead_foot=="Right" else "Right"
				map.player=passers[receiver]
				map.player.reparent(anchor,false)
				map.player.transform=Transform3D.IDENTITY
				map.player.animator.pause()
				for modifier in map.player.skeleton.get_children():
					if modifier is SkeletonModifier3D: modifier.active=false
				map.bind_receiver(map.player)
				map.intercept_shift=Vector3.ZERO
				map.shift_frame=recipe.contact
				map.sample_receiver(recipe,recipe.contact,true,map.legs)
				var center: Vector3=map.HandPass.contact_center(map.player) if recipe.kind=="overhead" else map.player.skeleton.to_global(map.player.skeleton.get_bone_global_pose(map.player.skeleton.find_bone("hand_l")).origin)
				map.intercept_shift=(map.set_intercept-center).slide(Vector3.UP).limit_length(.75)
				return
		previous=point

func step_serve_reception(_shot,previous: Vector3,_delta: float) -> void:
	if recipe.is_empty(): return
	map.sample_receiver(recipe,clampf(recipe.contact+(flight_age-receive_at)*60.,0.,recipe.frames),true,map.legs)
	if absf(flight_age-receive_at)>.24: return
	var touched := false
	if recipe.kind=="overhead":
		var hands := map.HandPass.contact_center(map.player)
		touched=hands.distance_to(Geometry3D.get_closest_point_to_segment(hands,previous,ball.position))<=map.HAND_RADIUS
	else:
		for shape in map.RECEPTION_CAPSULES:
			var seg := map.reception_segment(map.player.skeleton,shape)
			var points := Geometry3D.get_closest_points_between_segments(previous,ball.position,seg[0],seg[1])
			if points[0].distance_to(points[1])<=map.BALL_RADIUS+float(shape[2])+map.FOREARM_CONTACT_GRACE:
				touched=true
				break
	if not touched: return
	pass_start=ball.position
	pass_end=map.pass_goal
	pass_end.y=receiving_setter.height_cm*.0118
	pass_duration=sqrt(2.*map.pass_rise/9.81)+sqrt(2.*maxf(.05,pass_start.y+map.pass_rise-pass_end.y)/9.81)
	pass_clock=0.
	phase="serve_pass"
	if recipe.kind!="overhead": dig_sound.play()
	message.text="Pass"

func step_reception_rally(delta: float) -> void:
	pass_clock+=delta
	var target := Vector3(-3.5,.145,BallNet.NET_Z+1.1)
	if phase=="serve_pass":
		map.sample_receiver(recipe,minf(recipe.frames,recipe.contact+60.*(flight_age-receive_at+pass_clock)),true,map.legs)
		ball.position=arc(pass_start,pass_end,minf(1.,pass_clock/pass_duration),4.905*pass_duration*pass_duration*.25)
		move_receiver(receiving_setter,Vector3(pass_end.x,.04,pass_end.z+.20),delta,target-pass_end)
		var remaining := pass_duration-pass_clock
		if remaining<.35: SetHands.standing_set(receiving_setter,ball.position,target-pass_end,Vector3.ZERO,-1.,smoothstep(.35,0.,remaining),Vector3.ZERO)
		if remaining>0.: return
		set_start=ball.position
		set_end=target
		pass_clock=0.
		phase="test_set"
		message.text="Set"
	else:
		var duration := 1.35
		ball.position=arc(set_start,set_end,minf(1.,pass_clock/duration),4.905*duration*duration*.25)
		if pass_clock<.32:
			var push := ((set_end-set_start)/duration+Vector3.UP*4.905*duration).normalized()
			SetHands.standing_set(receiving_setter,set_start,set_end-set_start,push,pass_clock,1.,Vector3.ZERO)
		else: receiving_setter.animator.advance(delta)
		if pass_clock>=duration:
			floor_impact.stream=preload("res://assets/audio/ball_floor.wav")
			floor_impact.play()
			next_serve()

func _process(delta: float) -> void:
	if phase=="test_set":
		if not settings.visible and not get_tree().paused and not replay_inspector.active: step_reception_rally(delta)
	else: super(delta)

func _input(event: InputEvent) -> void:
	if phase=="serve_ready" and not settings.visible and not get_tree().paused and not replay_inspector.active:
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
			if event.pressed:
				var closest := 24.
				for i in passers.size():
					var foot := camera.unproject_position(stance_points[i])
					var head := camera.unproject_position(stance_points[i]+Vector3.UP*1.8)
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
				passers[dragged].position=stance_points[dragged]
		if dragged>=0: return
	super(event)
