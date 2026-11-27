extends "res://scripts/serve_reception_test.gd"

var control_digger := false
var other_map := Map.new()
var other_anchor := Node3D.new()
var other_motion := {}
var other_time := 0.
var other_slot := -1

func exchange_passers() -> void:
	var mapper := map
	map=other_map
	other_map=mapper
	var root := anchor
	anchor=other_anchor
	other_anchor=root
	var motion := recipe
	recipe=other_motion
	other_motion=motion
	var when := receive_at
	receive_at=other_time
	other_time=when
	var slot := receiver
	receiver=other_slot
	other_slot=slot

func release_passer(mapper: Map) -> void:
	var actor=mapper.player
	if actor==null: return
	var yaw: float=actor.get_parent_node_3d().rotation.y
	actor.reparent(world,true)
	actor.basis=Basis(Vector3.UP,yaw)
	actor.position.y=.04
	for bone in mapper.ready_pose.size(): actor.skeleton.set_bone_pose(bone,mapper.ready_pose[bone])
	for modifier in actor.skeleton.get_children():
		if modifier is SkeletonModifier3D: modifier.active=true
	actor.play_action("idle",.12)
	mapper.player=null

var prepare_weight := 0.
var moving_last_tick := false
var moving_passer := false
var checking_human_lane := false
var next_route_check := 0.
var role_button := Button.new()

func dig_defender() -> Node3D:
	return wall[1]

func cpu_dig() -> bool:
	return not control_digger

func manually_moving(actor: Node3D) -> bool:
	return (moving_passer and actor==passers[1]) or super.manually_moving(actor)

func cpu_positions_passer(slot: int) -> bool:
	return control_digger or slot!=1

func switch_role() -> void:
	control_digger=not control_digger
	StorySession.game_options.set_value("receive_cpu_serves","control_digger",control_digger)
	StorySession.save_options()
	role_button.text="Control receiver" if control_digger else "Control digger"
	prompt_phase=""
	next_serve()
	apply_camera()

var serve_bag: Array[int]=[]
const CPU_SERVES := [[0,0],[1,3],[0,3],[1,0]]
var spike_target := Vector3.ZERO
var cpu_serve := -1
var cpu_style := -1
var cpu_wait := 0.
var receive_held := false
var released_at := INF
var touched_at := INF
var receive_committed := false
var reception_release := {}
var reception_result := ""
const BODY_CUSHION := .20
var incoming_axis := Vector3.FORWARD
var incoming_speed := 1.
var platform_depth := 0.
var pass_timing_ready := false

func bind_contact_motion(mapper: Map,root: Node3D,actor: Node3D,home: Vector3,source: Vector3,best: Dictionary) -> Dictionary:
	if mapper==map and not control_digger and mapper.incoming_lead_seconds>.65:
		return {}
	var motion := super.bind_contact_motion(mapper,root,actor,home,source,best)
	var digging := control_digger and mapper==defense_map
	if not digging and (mapper!=map or control_digger or actor!=passers[1]): return motion
	var shot=serves[flight_style()]
	var route_time := defense_at if digging else receive_at
	var path: Callable=shot.flight_point
	var floor_time: float=shot.planned_duration
	if digging:
		var origin := ball.position
		var velocity := drop_velocity
		var now := dig_clock
		path=func(t: float) -> Vector3:
			var dt := t-now
			return origin+velocity*dt+Vector3.DOWN*4.905*dt*dt
		floor_time=now+preload("res://scripts/pass_flight.gd").landing_time(origin,velocity)
	var bind_time:=maxf(0.,route_time-mapper.incoming_lead_seconds)
	var contact_time:=mapper.align_contact(motion,path,route_time,bind_time,floor_time)
	if digging: defense_at=contact_time
	else: receive_at=contact_time
	var velocity_at_contact: Vector3=(path.call(contact_time+.005)-path.call(contact_time))/.005
	var horizontal := velocity_at_contact.slide(Vector3.UP)
	incoming_speed=maxf(.1,horizontal.length())
	incoming_axis=horizontal.normalized()
	platform_depth=mapper.set_intercept.dot(incoming_axis)
	pass_timing_ready=true
	initial_reach_shift=mapper.intercept_shift
	steering_shift=Vector3.ZERO
	pass_entry_time=bind_time
	mapper.entry_frame=clampf(motion.contact-(contact_time-bind_time)*60.,minf(6.,motion.contact),motion.contact)
	mapper.entry_duration=clampf(motion.contact-mapper.entry_frame,.01,12.)
	mapper.sample_receiver(motion,mapper.entry_frame,true,mapper.legs)
	return motion

var initial_reach_shift := Vector3.ZERO
var steering_shift := Vector3.ZERO
var pass_entry_time := 0.

func reception_frame() -> float:
	if not control_digger and receiver==1 and pass_timing_ready and flight_age<receive_at:
		var progress := clampf((flight_age-pass_entry_time)/maxf(.001,receive_at-pass_entry_time),0.,1.)
		return lerpf(map.entry_frame,recipe.contact,progress)
	return super.reception_frame()

func controlled_passer() -> Node3D:
	return dig_defender() if control_digger else passers[1]

func dig_armed() -> bool:
	return not control_digger or receive_held

func dig_contact_error(previous: Vector3) -> float:
	if not control_digger: return super.dig_contact_error(previous)
	if not accept_manual_contact(previous,defense_map,defense_recipe,dig_clock): return -1.
	defense_contact=dig_clock
	return manual_timing_penalty()

func pass_meter(point := Vector3.INF) -> Dictionary:
	if not reception_release.is_empty(): return reception_release
	if not point.is_finite(): point=ball.global_position
	var depth := point.dot(incoming_axis)
	var face_depth := Contact.joint(controlled_passer(),"Head").dot(incoming_axis)-.09
	var touching := is_finite(touched_at) or mapped_touch(defense_map if control_digger else map,defense_recipe if control_digger else recipe,point-incoming_axis*.001)
	return Map.release_grade(depth,face_depth,platform_depth,incoming_speed,touching,controlled_passer().effective_rating("Hand reception" if (defense_recipe if control_digger else recipe).get("kind","")=="overhead" else "Forearm reception"))

const RECEIVE_EARLY := .21

func can_chase_reception() -> bool:
	return not checking_human_lane

func receiver_candidates() -> Array:
	return super.receiver_candidates() if control_digger else ([1] if checking_human_lane else [0,2])

func start_drill() -> void:
	control_digger=StorySession.game_options.get_value("receive_cpu_serves","control_digger",false) or "--defender" in OS.get_cmdline_user_args()
	super.start_drill()
	world.add_child(other_map)
	world.add_child(other_anchor)
	other_map.defenders.append(other_anchor)
	other_map.clips=map.clips
	other_map.pass_goal=map.pass_goal
	other_map.pass_rise=map.pass_rise
	dig_defender().show()
	role_button.text="Control receiver" if control_digger else "Control digger"
	controls_row.get_parent().add_child(role_button)
	role_button.pressed.connect(switch_role)
	title.text="PASSING  /  RECEIVE CPU SERVES"

func build_rally_sliders() -> void:
	add_rally_sliders("serving",[["Serve speed","serve_kmh",0,300,0," km/h"]])

func reception_home(slot: int) -> Vector3:
	if slot==1 and not control_digger: return HOMES[slot]
	return super.reception_home(slot)

func next_serve() -> void:
	release_passer(other_map)
	other_motion={}
	other_slot=-1
	super.next_serve()
	dig_defender().position=Vector3(0.,.04,BallNet.NET_Z-6.)
	receiver=1
	receive_committed=false
	checking_human_lane=false
	prepare_weight=0.
	next_route_check=0.
	cpu_wait=1.25
	spike_target=Vector3(randf_range(-1.5,1.5),BallNet.RADIUS,BallNet.NET_Z-randf_range(7.25,8.9))
	receive_held=false
	pass_timing_ready=false
	reception_release={}
	reception_result=""
	released_at=INF
	touched_at=INF
	if serve_bag.is_empty():
		serve_bag.assign(range(CPU_SERVES.size()))
		serve_bag.shuffle()
		if serve_bag.back()==cpu_serve: serve_bag.reverse()
	cpu_serve=serve_bag.pop_back()
	cpu_style=CPU_SERVES[cpu_serve][0]
	spin_selection=CPU_SERVES[cpu_serve][1]
	message.text="Ready"

func scoring_target(_origin: Vector3) -> Vector3:
	return spike_target

func cpu_serve_target() -> Vector3:
	var best := Vector3.ZERO
	var best_space := -1.
	# Spin serves and hybrids compare several landing lanes for open court.
	var candidates := 1 if cpu_serve==1 else 4
	for i in candidates:
		var target := Vector3(randf_range(-4.45,4.45),.145,BallNet.NET_Z+randf_range(3.05,8.95))
		var space := INF
		for passer in passers:
			space=minf(space,(target-passer.global_position).slide(Vector3.UP).length_squared())
		if space>best_space:
			best=target
			best_space=space
	return best

func update_prompts(_next: String) -> void:
	if prompt_phase=="receive": return
	prompt_phase="receive"
	Xbox.prompts(controls_row,[["LS","Move"],["LT","Shuffle"],["RT","Sprint"],["A","Release to dig" if control_digger else "Release to pass"],["Y","Switch role"]])

func apply_camera() -> void:
	if control_digger:
		super.apply_camera()
		return
	yaw+=PI
	place_practice_camera(Vector3(0,1.5,BallNet.NET_Z+6.),distance*.48+2.)
	yaw-=PI

func walk_server(_delta: float,_defending := false) -> void:
	if phase=="serve_ready": ball.position=Contact.palm(hitter,"l")+Vector3.UP*.10

func configure_flight(shot,origin: Vector3) -> void:
	super.configure_flight(shot,origin)
	if shot!=serves[0] or destination.z<=BallNet.NET_Z or origin.z>=BallNet.NET_Z: return
	var displacement := Vector3(destination.x-origin.x,BallNet.RADIUS-origin.y,destination.z-origin.z)
	var fraction := (BallNet.NET_Z-origin.z)/displacement.z
	var rise := BallNet.NET_TOP+BallNet.RADIUS+.12-(origin.y+fraction*displacement.y)
	if rise<=0. or fraction>=1.: return
	var duration := sqrt(2.*rise/(9.81*fraction*(1.-fraction)))
	var feasible := displacement/duration+Vector3.UP*4.905*duration
	shot.test_speed_mps=minf(shot.test_speed_mps,feasible.length())

func update_serve_aim(_delta: float) -> void:
	super.update_serve_aim(0.)
	for driver in serves: driver.path_preview.hide()

func _process(delta: float) -> void:
	moving_passer=false
	if not settings.visible and not get_tree().paused and not replay_inspector.active:
		if not control_digger or defense_map.player==null or phase=="serve_return":
			var actor := dig_defender() if control_digger else passers[1]
			var stick := Vector2(axis(JOY_AXIS_LEFT_X),axis(JOY_AXIS_LEFT_Y))
			if stick.length()<.22: stick=Vector2.ZERO
			stick+=Input.get_vector("ui_left","ui_right","ui_up","ui_down",.22)
			var right := camera.global_basis.x.slide(Vector3.UP).normalized()
			var travel := (right*stick.x+right.cross(Vector3.UP)*stick.y).limit_length(1.)
			var pace := GroundControls.speed(GroundControls.focus(axis),GroundControls.sprint(axis))
			if not control_digger and map.player==actor and phase!="serve_flight" and (not travel.is_zero_approx() or phase!="serve_pass" or pass_clock>.4):
				release_passer(map)
			var goal := actor.global_position+travel*pace*delta
			goal.x=clampf(goal.x,-5.,5.)
			goal.z=clampf(goal.z,BallNet.NET_Z+.4,BallNet.NET_Z+10.)
			if control_digger: goal.z=clampf(actor.global_position.z+travel.z*pace*delta,BallNet.NET_Z-10.,BallNet.NET_Z-.4)
			if travel.is_zero_approx(): goal=actor.global_position
			var preparing := receive_held and phase==("serve_return" if control_digger else "serve_flight")
			prepare_weight=move_toward(prepare_weight,1. if preparing else 0.,delta*5.)
			var focused := GroundControls.focus(axis)
			var source := pin_hitter.global_position if control_digger else serve_station
			if (control_digger and defense_map.player==actor) or (not control_digger and map.player==actor):
				var shift := (goal-actor.global_position).slide(Vector3.UP)
				var root := defense_anchor if control_digger else anchor
				var active_map := defense_map if control_digger else map
				root.position+=shift
				steering_shift+=shift
				active_map.intercept_shift=initial_reach_shift-steering_shift.limit_length(.45)
			elif not travel.is_zero_approx() or moving_last_tick or prepare_weight>0.:
				move_receiver(actor,goal,delta,source-actor.position if focused else travel,pace,focused)
				if prepare_weight>0.:
					var platform=receptions[1] if not control_digger else dig_platforms[actor]
					platform.knee_bend_depth=.12*prepare_weight
					platform.apply_knee_bend()
					platform.knee_bend_depth=0.
			moving_last_tick=not travel.is_zero_approx()
			if not control_digger:
				moving_passer=travel.length_squared()>.001
				active_stances[1]=actor.global_position
		if phase=="serve_ready":
			cpu_wait-=delta
			if cpu_wait<=0. and pending_serve<0:
				destination=cpu_serve_target()
				handle_serve_button(cpu_style,true)
		elif phase=="serve_toss" and not is_finite(release_time) and serve_meter_error()>=-.01:
			handle_serve_button(cpu_style,false)
	super._process(delta)

func _input(event: InputEvent) -> void:
	if not settings.visible and not get_tree().paused and not replay_inspector.active:
		if event is InputEventJoypadButton and event.button_index==Xbox.physical(JOY_BUTTON_Y) and event.pressed:
			switch_role()
			get_viewport().set_input_as_handled()
			return
		if event is InputEventJoypadButton and event.button_index==Xbox.physical(JOY_BUTTON_A) or event is InputEventKey and event.keycode==KEY_Q and not event.echo:
			if control_digger:
				if not event.pressed and receive_held and phase=="serve_return" and pass_timing_ready and not is_finite(released_at):
					released_at=dig_clock
					dig_platforms[dig_defender()].queue_bump(dig_clock)
					record_receive_release()
				receive_held=event.pressed
				get_viewport().set_input_as_handled()
				return
			if event.pressed:
				receive_held=true
				next_route_check=0.
			elif receive_held:
				receive_held=false
				if phase=="serve_flight" and not is_finite(released_at):
					released_at=flight_age
					record_receive_release()
			get_viewport().set_input_as_handled()
			return
		if event is InputEventJoypadButton and event.button_index!=Xbox.physical(JOY_BUTTON_START): return
	super._input(event)

func route_reception(shot,age: float) -> void:
	if not control_digger and receive_held:
		checking_human_lane=true
		plan_remaining_reception(shot,age)
		if not routed_zone.is_empty():
			receive_committed=not recipe.is_empty()
			return
	checking_human_lane=false
	plan_remaining_reception(shot,age)
	receive_committed=not recipe.is_empty()

func plan_serve_reception(shot) -> void:
	route_reception(shot,0.)
	next_route_check=.06

func step_serve_reception(shot,previous: Vector3,delta: float) -> void:
	if not control_digger and receive_held and map.player!=null and map.player!=passers[1] and flight_age>=next_route_check:
		next_route_check=flight_age+.04
		var cpu_zone := routed_zone
		exchange_passers()
		checking_human_lane=true
		plan_remaining_reception(shot,maxf(0.,flight_age-delta))
		if map.player==null:
			exchange_passers()
			routed_zone=cpu_zone
			checking_human_lane=false
	if other_map.player!=null:
		other_map.sample_receiver(other_motion,clampf(other_motion.contact+(flight_age-other_time)*60.,0.,other_motion.frames),true,other_map.legs)
	if map.player==null and flight_age>=next_route_check:
		next_route_check=flight_age+.06
		if checking_human_lane or (receive_held and not control_digger) or chase_box.is_empty():
			route_reception(shot,maxf(0.,flight_age-delta))
	super.step_serve_reception(shot,previous,delta)
	if other_map.player!=null:
		if phase=="serve_flight" and absf(flight_age-other_time)<=.24 and mapped_touch(other_map,other_motion,previous):
			exchange_passers()
			pass_timing_ready=false
			complete_reception()
		if phase!="serve_flight": release_passer(other_map)

func record_receive_release() -> void:
	if not reception_release.is_empty() or not is_finite(released_at) or not pass_timing_ready: return
	reception_release=pass_meter(ball.global_position)
	reception_release.point=ball.global_position
	reception_release.buffered_touch=is_finite(touched_at)
	var offset: float=reception_release.offset
	var grade: String=reception_release.grade
	var ms := roundi(offset*1000.)
	var label := "%s release  /  %s  (%+d ms)" % ["Dig" if control_digger else "Pass",grade,ms]
	reception_release.label=label
	show_release_feedback(offset,true)
	dig_feedback.add_theme_color_override("font_color",Color("78e1ad") if grade=="Perfect" else (Color("ffd36b") if grade=="Early" else Color("ff9086")))
	dig_feedback.text=label
	trace("dig_release" if control_digger else "pass_release",{"zone":routed_zone,"release_s":released_at,"target_s":defense_at if control_digger else receive_at,"offset_ms":ms,"grade":grade})

func show_service_ace() -> void:
	super.show_service_ace()
	if control_digger: return
	if reception_release.is_empty():
		reception_result="No timed release"
	elif reception_release.grade=="Past receiver":
		reception_result="Ball past receiver"
	elif not reception_release.playable:
		reception_result="Outside timing window"
	else:
		reception_result="No platform contact"
	trace("manual_pass_miss",{"result":reception_result,"release":reception_release,"platform_contact_s":str(touched_at)})

func accept_reception(previous: Vector3) -> bool:
	if control_digger or receiver!=1: return super.accept_reception(previous)
	return accept_manual_contact(previous,map,recipe,flight_age)

func accept_manual_contact(previous: Vector3,mapper: Map,motion: Dictionary,clock: float) -> bool:
	if not pass_timing_ready: return false
	var face_depth := Contact.joint(controlled_passer(),"Head").dot(incoming_axis)-.09
	var depth_limit := face_depth+BODY_CUSHION
	var end := ball.position
	var advance := (end-previous).dot(incoming_axis)
	if advance>0. and end.dot(incoming_axis)>depth_limit:
		end=previous.lerp(end,clampf((depth_limit-previous.dot(incoming_axis))/advance,0.,1.))
	var touch := previous.dot(incoming_axis)<=depth_limit and mapped_segment_touch(mapper,motion,previous,end)
	if touch: touched_at=clock
	if not is_finite(released_at):
		if not receive_held or not touch: return false
		ball.position=first_platform_contact(previous,end,mapper,motion)
		reception_result="Held at contact"
		return true
	record_receive_release()
	if not reception_release.get("playable",false): return false
	if not touch: return false
	ball.position=first_platform_contact(previous,end,mapper,motion)
	reception_result="Dig" if control_digger else "Pass"
	return true

func first_platform_contact(start: Vector3,end: Vector3,mapper: Map,motion: Dictionary) -> Vector3:
	var low := start
	var high := end
	for step in 7:
		var mid := low.lerp(high,.5)
		if mapped_segment_touch(mapper,motion,start,mid): high=mid
		else: low=mid
	return high

func pass_timing_penalty() -> float:
	if control_digger or receiver!=1: return super.pass_timing_penalty()
	return manual_timing_penalty()

func manual_timing_penalty() -> float:
	if reception_result=="Held at contact": return .8
	return clampf(absf(float(reception_release.get("offset",0.)))/RECEIVE_EARLY,0.,1.)
