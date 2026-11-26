extends "res://scripts/serving_camp.gd"

const FIVE := Vector3(2.65,.04,-2.2)
var homes := [FIVE,Vector3(-1.6,.04,-2.2)]
var floor_target := Vector3(2.35,.145,-1.60)
var target_marker := MeshInstance3D.new()
var dragged := -1
var orbit_offset := Vector2.ZERO
var dig_contact_grip := Vector3.INF
var release_window := 0.
var set_tempo := 1
var cpu_defense := true

var feed_age := 0.
var attack_landing := Vector3.ZERO

func start_drill() -> void:
	cpu_defense=true
	for i in homes.size():
		homes[i]=StorySession.game_options.get_value("digging","defender_home_"+str(i),homes[i])
	floor_target=StorySession.game_options.get_value("digging","floor_target",floor_target)
	super.start_drill()
	title.text="DIGGING  /  DIG FROM FIVE"
	for actor in passers+[receiving_middle,wall[2]]:
		actor.hide()
	target_marker.mesh=ball.mesh
	target_marker.material_override=ball.material_override
	target_marker.scale=ball.scale
	add_child(target_marker)
	target_marker.position=floor_target
	coach.show()
	coach.position=Vector3(-.5,.04,10.3)
	GroundControls.face(coach,SETTER_BASE-coach.position,1.,10.)
	update_prompts("ready")

func build_rally_sliders() -> void:
	add_rally_sliders("digging",[
		["Attack speed","attack_kmh",15,180,105," km/h"],
		["Attack vertical","attack_vertical",1,60,46," in"],
		["Set tempo","set_tempo",0,3,1,""],
		["Block vertical","block_vertical",1,60,34," in"],
	])

func apply_drill_slider(key: String, value: float) -> void:
	if key=="set_tempo": set_tempo=int(value)

func pin_flight_time(_slot: int) -> float:
	return [ZERO_FLIGHT,ONE_FLIGHT,1.10,1.60][set_tempo]

func paced_set_duration(origin: Vector3,target: Vector3,_tempo: float) -> float:
	return super.paced_set_duration(origin,target,pin_flight_time(attack_slot))

func update_prompts(_next: String) -> void:
	var mode := "cpu_dig" if cpu_defense else "player_dig"
	if prompt_phase==mode: return
	prompt_phase=mode
	if cpu_defense:
		Xbox.prompts(controls_row,[["View","Control defender"]])
	else:
		Xbox.prompts(controls_row,[["View","Watch CPU"],["A","Release to dig"]])

func apply_camera() -> void:
	var default_yaw := yaw
	var default_elevation := elevation
	yaw+=orbit_offset.x
	elevation=clampf(elevation+orbit_offset.y,3.,85.)
	super.apply_camera()
	yaw=default_yaw
	elevation=default_elevation

func _input(event: InputEvent) -> void:
	if not settings.visible and not replay_inspector.active and not get_tree().paused:
		if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_MIDDLE and dragged<0:
			orbit_offset.x=wrapf(orbit_offset.x+event.relative.x*.006,-PI,PI)
			orbit_offset.y=clampf(orbit_offset.y+event.relative.y*.25,3.-elevation,85.-elevation)
			apply_camera()
			get_viewport().set_input_as_handled()
			return
		if handle_drag(event):
			get_viewport().set_input_as_handled()
			return
		if event is InputEventJoypadButton and event.button_index==Xbox.physical(JOY_BUTTON_A):
			active_pad=event.device
			cpu_defense=false
			if not event.pressed and phase=="serve_return": release_window=.18
			update_prompts("")
			get_viewport().set_input_as_handled()
			return
		if event is InputEventJoypadButton and event.pressed and event.button_index==Xbox.physical(JOY_BUTTON_BACK):
			cpu_defense=not cpu_defense
			release_window=0.
			update_prompts("")
			get_viewport().set_input_as_handled()
			return
	super._input(event)

func next_serve() -> void:
	super.next_serve()
	release_window=0.
	hitter.position=homes[0]
	wall[1].position=homes[1]
	hitter.rotation.y=0.
	receiving_setter.position=SETTER_BASE
	receiver=0
	attack_slot=2
	called_slot=2
	off_blocker=1
	wall[0].position=Vector3(-4.,.04,BallNet.NET_Z-.85)
	serve_clock=10.
	toss_style=2
	feed_age=0.
	phase="coach_feed"
	attack_landing=floor_target
	message.text="Coach toss"

func _process(delta: float) -> void:
	if settings.visible or get_tree().paused or replay_inspector.active: return
	if phase=="coach_feed" and ball.position.z>hitter.position.z+.18:
		GroundControls.face(hitter,ball.global_position-hitter.global_position,delta,8.)
	if phase=="coach_feed":
		feed_age+=delta
		ball.position=coach_motion.toss(coach,clampf((feed_age-.45)/.33,0.,1.))
		if feed_age>=.78:
			pass_start=ball.position
			pass_end=SETTER_BASE+Vector3.UP*2.
			pass_duration=1.35
			set_at=pass_duration
			pass_clock=0.
			pass_in_system=true
			phase="serve_pass"
			message.text="Set to four"
		return
	if phase=="serve_return":
		release_window=maxf(0.,release_window-delta)
		dig_platforms[hitter].queue_bump(dig_clock)
		off_blocker=1
	super._process(delta)
	if phase=="server_dig" and last_digger!=null:
		var platform: Reception=dig_platforms[last_digger]
		var age := dig_clock-platform.touch_time
		if age>0. and age<platform.Drive.FAST_DIG_ELBOW_DURATION:
			var degrees := lerpf(6.,27.,smoothstep(10.,25.,dig_incoming.length()))
			platform.Drive.absorb_with_joined_platform(last_digger,age,degrees,dig_contact_grip)

func handle_drag(event: InputEvent) -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera==null: return false
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if not event.pressed:
			var handled := dragged>=0
			if handled:
				if dragged==2:
					StorySession.game_options.set_value("digging","floor_target",floor_target)
				else:
					StorySession.game_options.set_value("digging","defender_home_"+str(dragged),homes[dragged])
				StorySession.save_options()
			dragged=-1
			return handled
		var closest := 22.
		for i in 3:
			var point: Vector3=floor_target if i==2 else homes[i]
			var foot := camera.unproject_position(point)
			var top := camera.unproject_position(point+Vector3.UP*(.01 if i==2 else 1.65))
			var distance: float=event.position.distance_to(Geometry2D.get_closest_point_to_segment(event.position,foot,top))
			if distance<closest:
				dragged=i
				closest=distance
		return dragged>=0
	if event is InputEventMouseMotion and dragged>=0:
		var hit=Plane(Vector3.UP,0.).intersects_ray(camera.project_ray_origin(event.position),camera.project_ray_normal(event.position))
		if hit!=null:
			var point := Vector3(clampf(hit.x,-4.48,4.48),.04,clampf(hit.z,BallNet.NET_Z-8.98,BallNet.NET_Z-.15))
			if dragged==2:
				point.y=.145
				floor_target=point
				attack_landing=point
				target_marker.position=point
			else:
				homes[dragged]=point
				var actor=hitter if dragged==0 else wall[1]
				actor.position=point
				dig_platforms[actor].low_save.active=false
		return true
	return false

func walk_server(delta: float,_defending := false) -> void:
	for actor in [hitter,wall[1]]:
		if phase=="server_dig" and actor==last_digger and dig_platforms[actor].low_save.active: continue
		actor.play_ground_gait(0.)
		actor.animator.advance(delta)
		GroundControls.face(actor,ball.global_position-actor.global_position,delta,8.)

func return_struck(actor: Node3D,point: Vector3,velocity: Vector3,spin: float) -> void:
	var nearest: Node3D=hitter if hitter.position.distance_squared_to(floor_target)<=wall[1].position.distance_squared_to(floor_target) else wall[1]
	var offset := floor_target-nearest.position
	var contact := floor_target
	contact.y=lerpf(1.04,.46,smoothstep(.80,1.65,offset.slide(Vector3.UP).length()))
	var travel := maxf(.30,point.distance_to(contact)/maxf(1.,velocity.length()))
	var launch := (contact-point)/travel+Vector3.UP*4.905*travel
	var flight := preload("res://scripts/pass_flight.gd").landing_time(point,launch)
	var landing := point+launch*flight+Vector3.DOWN*4.905*flight*flight
	pin_attack.swing_aim=pin_frame.to_local(landing)
	super.return_struck(actor,point,launch,spin)

func sample_defensive_contact(platform: Reception,start: float,dt: float,_until_floor: float,path: Callable) -> void:
	var actor=platform.setter
	var automatic: bool=actor!=hitter or cpu_defense
	var home: Vector3=homes[0 if actor==hitter else 1]
	var now: Vector3=path.call(start)
	var ahead := clampf((actor.to_global(Vector3(0,1.04,.62))-now).slide(Vector3.UP).dot(drop_velocity.slide(Vector3.UP))/maxf(.01,drop_velocity.slide(Vector3.UP).length_squared()),0.,_until_floor)
	if ahead>.42: return
	var intercept: Vector3=path.call(start+ahead)
	var base: Vector3=home+actor.basis*Vector3(0,1.04,.62)
	var offset := intercept-base
	var save=platform.low_save
	if platform.reach.is_empty() and not save.active and (offset.slide(Vector3.UP).length()>1.15 or intercept.y<.58):
		if save.plan(actor,path,start,start+_until_floor,platform.clip,true,false):
			save.travel_scale=0.
			save.wide_arm=""
			save.heading=(save.aim-save.start).slide(Vector3.UP).normalized()
	if save.active:
		save.sample(actor,start+dt,save.contact_time+.07)
	else:
		var progress := smoothstep(0.,.39,.42-ahead)
		var close := 1.-smoothstep(.09,.20,ahead)
		if not automatic: close*=smoothstep(0.,.035,.18-release_window+dt) if release_window>0. else 0.
		platform.sample_pose(platform.clip,platform.tracks,platform.contact_frame*close,1.,true)
		var lateral: float=absf((actor.basis.inverse()*offset).x)
		if platform.reach.is_empty() and lateral>.18 and offset.slide(Vector3.UP).length()<1.65:
			platform.plan_reach(offset.normalized()*maxf(.36,offset.length()),true)
		if not platform.reach.is_empty():
			platform.reach_progress=progress
			var step: Vector3=actor.basis.inverse()*platform.reach_step
			var travel: Vector3=step*.68*progress
			actor.position=home+actor.basis*travel
			platform.reach.lead="l" if step.x>0. else "r"
			platform.reach.tier=2 if lateral>.55 else 1
			preload("res://scripts/forearm_reach_pose.gd").sample(actor.skeleton,actor.get_pose_author(),step,travel,progress,progress,platform.ready_pose,platform.reach,false,0,intercept,false)
		platform.deep_squat=true
		platform.knee_bend_depth=progress*lerpf(.07,.24,smoothstep(10.,25.,drop_velocity.length()))
		platform.apply_knee_bend()
		if close>.01: platform.reach_platform(intercept-platform.platform_center(),close,.72,true,true)
	var grip_target := Vector3.INF
	if save.active or not platform.reach.is_empty(): grip_target=intercept+actor.basis.z*.10
	platform.Drive.pose_joined_platform(actor,1.,174.,grip_target)
	if not automatic and release_window<=0.: return
	var contact := platform.dig_contact_segment(path.call(start),path.call(start+dt))
	if contact[0].distance_to(contact[1])>platform.PLATFORM_RADIUS: return
	platform.touch=contact[0]
	platform.touch_time=start+dt
	platform.outgoing=platform.aim_velocity(platform.touch)
	platform.capture_bump_contact()
	dig_contact_grip=Vector3.INF
	if not save.active and not platform.reach.is_empty():
		var rig: Skeleton3D=actor.skeleton
		var left := rig.get_bone_global_pose(rig.find_bone("hand_l")).origin
		var right := rig.get_bone_global_pose(rig.find_bone("hand_r")).origin
		dig_contact_grip=rig.to_global((left+right)*.5)

func scoring_target(_origin: Vector3) -> Vector3:
	return attack_landing

func choose_rally_attack(_origin: Vector3) -> void:
	pin_attack.swing_aim=pin_frame.to_local(attack_landing)

func try_cover(_previous: Vector3,_delta: float) -> void:
	pass

func step_serve_wall(delta: float) -> void:
	var actor := wall[0]
	var block: RefCounted=wall_jumps[0]
	if block!=null:
		if not block.step(delta,ball.global_position): wall_jumps[0]=null
		return
	if phase=="server_dig":
		move_receiver(actor,Vector3(-4.,.04,BallNet.NET_Z-.85),delta,ball.global_position-actor.global_position,GroundControls.speed(true,false),true)
		return
	if phase!="serve_attack": return
	var six := Vector3(0.,.145,-3.)
	var at_net := (actor.position.z-pass_end.z)/(six.z-pass_end.z)
	var goal := actor.position
	goal.x=lerpf(pass_end.x,six.x,at_net)-.48
	move_receiver(actor,goal,delta,Vector3.BACK,GroundControls.speed(true,false),true)
	if not wall_committed[0] and set_duration-pass_clock<=.46:
		block=PracticeBlock.new()
		block.aggressive_press=true
		block.net_heading=0.
		block.jump_height=wall_vertical_inches*.0254*actor.stamina.effectiveness()
		block.begin(actor)
		wall_committed[0]=true
		wall_jumps[0]=block
		actor.stamina.spend(5,"Block")
