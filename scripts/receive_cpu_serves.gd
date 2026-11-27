extends "res://scripts/serve_reception_test.gd"

var control_digger := false
var moving_passer := false
var role_button := Button.new()

func dig_defender() -> Node3D:
	return wall[1]

func cpu_dig() -> bool:
	return not control_digger

func manually_moving(actor: Node3D) -> bool:
	return moving_passer and actor==passers[1]

func switch_role() -> void:
	control_digger=not control_digger
	role_button.text="Control receiver" if control_digger else "Control digger"
	prompt_phase=""
	next_serve()
	apply_camera()

var serve_bag: Array[int]=[]
const CPU_SERVES := [[0,0],[1,3],[0,3],[1,0]]
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
	var motion := super.bind_contact_motion(mapper,root,actor,home,source,best)
	if mapper!=map or control_digger: return motion
	mapper.sample_receiver(motion,motion.contact,true,mapper.legs)
	var shot=serves[flight_style()]
	var velocity: Vector3=(shot.flight_point(receive_at+.005)-shot.flight_point(receive_at))/.005
	var horizontal := velocity.slide(Vector3.UP)
	incoming_speed=maxf(.1,horizontal.length())
	incoming_axis=horizontal.normalized()
	var platform: Vector3=mapper.HandPass.contact_center(actor) if motion.kind=="overhead" else (Contact.joint(actor,"hand_l")+Contact.joint(actor,"hand_r"))*.5
	if motion.kind!="overhead":
		platform=platform.lerp((Contact.joint(actor,"lowerarm_l")+Contact.joint(actor,"lowerarm_r"))*.5,.3)
	var body_depth := Contact.joint(actor,"Head").dot(incoming_axis)-.09
	platform_depth=minf(platform.dot(incoming_axis),body_depth)
	receive_at=clampf(receive_at+(platform_depth-mapper.set_intercept.dot(incoming_axis))/incoming_speed,0.,shot.planned_duration)
	pass_timing_ready=true
	return motion

func pass_meter(point := Vector3.INF) -> Dictionary:
	if not reception_release.is_empty(): return reception_release
	if not point.is_finite(): point=ball.global_position
	var depth := point.dot(incoming_axis)
	var face_depth := Contact.joint(passers[1],"Head").dot(incoming_axis)-.09
	var behind := depth-face_depth
	var platform_gap := depth-minf(platform_depth,face_depth-.13)
	var distance := platform_gap+incoming_speed*PASS_RELEASE_LEAD
	var offset := distance/incoming_speed
	var green := .12
	var late_distance := maxf(.001,BODY_CUSHION-behind+distance)
	var green_end := minf(green,late_distance*.5)
	var cursor: float
	if distance< -green:
		cursor=remap(offset,-RECEIVE_EARLY,-green/incoming_speed,.08,.33)
	elif distance<=green_end:
		cursor=remap(distance,-green,green_end,.33,.67)
	else:
		cursor=remap(distance,green_end,late_distance,.67,.90)
	var expired := behind>BODY_CUSHION or (platform_gap>.12 and not is_finite(touched_at) and not mapped_touch(map,recipe,point-incoming_axis*.001))
	if expired: cursor=1.
	var grade := ("Past receiver" if behind>BODY_CUSHION else "Out of reach") if expired else ("Early" if distance< -green else ("Perfect" if distance<=green_end else "Late"))
	return {"value":clampf(cursor,0.,1.),"offset":offset,"grade":grade,"playable":not expired and offset>=-RECEIVE_EARLY}

const RECEIVE_EARLY := .21

func can_chase_reception() -> bool:
	return control_digger

func receiver_candidates() -> Array:
	return [1]

func start_drill() -> void:
	super.start_drill()
	dig_defender().show()
	role_button.text="Control digger"
	controls_row.get_parent().add_child(role_button)
	role_button.pressed.connect(switch_role)
	title.text="PASSING  /  RECEIVE CPU SERVES"

func build_rally_sliders() -> void:
	add_rally_sliders("serving",[["Serve speed","serve_kmh",0,300,0," km/h"]])

func next_serve() -> void:
	super.next_serve()
	dig_defender().position=Vector3(0.,.04,BallNet.NET_Z-7.5)
	receiver=1
	receive_committed=false
	cpu_wait=1.25
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

func update_prompts(_next: String) -> void:
	if prompt_phase=="receive": return
	prompt_phase="receive"
	Xbox.prompts(controls_row,[["LS","Move"],["LT","Shuffle"],["RT","Sprint"],["A","Release to dig" if control_digger else "Release to pass"]])

func apply_camera() -> void:
	if control_digger:
		super.apply_camera()
		return
	yaw+=PI
	place_practice_camera(Vector3(0,1.5,BallNet.NET_Z+6.),distance*.48+2.)
	yaw-=PI

func walk_server(_delta: float,_defending := false) -> void:
	if phase=="serve_ready": ball.position=Contact.palm(hitter,"l")+Vector3.UP*.10

func update_serve_aim(_delta: float) -> void:
	super.update_serve_aim(0.)
	for driver in serves: driver.path_preview.hide()

func _process(delta: float) -> void:
	moving_passer=false
	if not settings.visible and not get_tree().paused and not replay_inspector.active:
		if (control_digger and defense_map.player==null) or (not control_digger and phase in ["serve_ready","serve_toss","serve_flight"] and not receive_committed and not receive_held):
			var actor := dig_defender() if control_digger else passers[1]
			var stick := Vector2(axis(JOY_AXIS_LEFT_X),axis(JOY_AXIS_LEFT_Y))
			if stick.length()<.22: stick=Vector2.ZERO
			stick+=Input.get_vector("ui_left","ui_right","ui_up","ui_down",.22)
			var right := camera.global_basis.x.slide(Vector3.UP).normalized()
			var travel := (right*stick.x+right.cross(Vector3.UP)*stick.y).limit_length(1.)
			var pace := GroundControls.speed(GroundControls.focus(axis),GroundControls.sprint(axis))
			var goal := actor.position+travel*pace*delta
			goal.x=clampf(goal.x,-5.,5.)
			goal.z=clampf(goal.z,BallNet.NET_Z+.4,BallNet.NET_Z+10.)
			if control_digger: goal.z=clampf(actor.position.z+travel.z*pace*delta,BallNet.NET_Z-10.,BallNet.NET_Z-.4)
			if travel.is_zero_approx(): goal=actor.position
			var focused := GroundControls.focus(axis)
			var source := pin_hitter.global_position if control_digger else serve_station
			move_receiver(actor,goal,delta,source-actor.position if focused else travel,pace,focused)
			if not control_digger:
				moving_passer=travel.length_squared()>.001
				active_stances[1]=actor.position
		if phase=="serve_ready":
			cpu_wait-=delta
			if cpu_wait<=0. and pending_serve<0:
				destination=active_stances[1]+Vector3(randf_range(-.45,.45),0.,1.)
				destination.y=.145
				handle_serve_button(cpu_style,true)
		elif phase=="serve_toss" and not is_finite(release_time) and serve_meter_error()>=-.01:
			handle_serve_button(cpu_style,false)
	super._process(delta)

func _input(event: InputEvent) -> void:
	if not settings.visible and not get_tree().paused and not replay_inspector.active:
		if event is InputEventJoypadButton and event.button_index==Xbox.physical(JOY_BUTTON_A) or event is InputEventKey and event.keycode==KEY_Q and not event.echo:
			if control_digger:
				if not event.pressed and receive_held and phase=="serve_return": dig_platforms[dig_defender()].queue_bump(dig_clock)
				receive_held=event.pressed
				get_viewport().set_input_as_handled()
				return
			if event.pressed:
				receive_held=true
				if phase=="serve_flight" and not receive_committed:
					receive_committed=true
					plan_remaining_reception(serves[flight_style()],flight_age)
			elif receive_held:
				receive_held=false
				if phase=="serve_flight" and not is_finite(released_at):
					released_at=flight_age
					record_receive_release()
			get_viewport().set_input_as_handled()
			return
		if event is InputEventJoypadButton and event.button_index!=Xbox.physical(JOY_BUTTON_START): return
	super._input(event)

func plan_serve_reception(shot) -> void:
	if control_digger or receive_held:
		receive_committed=true
		plan_remaining_reception(shot,0.)

func step_serve_reception(shot,previous: Vector3,delta: float) -> void:
	if not receive_committed:
		if not receive_held: return
		receive_committed=true
		plan_remaining_reception(shot,maxf(0.,flight_age-delta))
	super.step_serve_reception(shot,previous,delta)

func record_receive_release() -> void:
	if not reception_release.is_empty() or not is_finite(released_at) or not pass_timing_ready: return
	reception_release=pass_meter(ball.global_position)
	reception_release.point=ball.global_position
	reception_release.buffered_touch=is_finite(touched_at) or (not recipe.is_empty() and mapped_touch(map,recipe,ball.position-incoming_axis*.001))
	var offset: float=reception_release.offset
	var grade: String=reception_release.grade
	var ms := roundi(offset*1000.)
	var label := "Pass release  /  %s  (%+d ms)" % [grade,ms]
	reception_release.label=label
	show_release_feedback(offset,true)
	dig_feedback.add_theme_color_override("font_color",Color("78e1ad") if grade=="Perfect" else (Color("ffd36b") if grade=="Early" else Color("ff9086")))
	dig_feedback.text=label
	trace("pass_release",{"zone":routed_zone,"release_s":released_at,"target_s":receive_at,"offset_ms":ms,"grade":grade})

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
	if control_digger: return super.accept_reception(previous)
	if not pass_timing_ready: return false
	var face_depth := Contact.joint(passers[1],"Head").dot(incoming_axis)-.09
	var within := ball.position.dot(incoming_axis)-face_depth<=BODY_CUSHION
	var touch := within and mapped_touch(map,recipe,previous)
	if touch: touched_at=flight_age
	if not is_finite(released_at): return false
	record_receive_release()
	if not reception_release.get("playable",false): return false
	var late: bool=reception_release.grade=="Late"
	if touch or (late and reception_release.buffered_touch):
		if late and reception_release.buffered_touch: ball.position=reception_release.point
		reception_result="Pass"
		return true
	return false

func reception_pass_target() -> Vector3:
	var target := super.reception_pass_target()
	if control_digger or reception_release.get("grade","Perfect")=="Perfect": return target
	var error := clampf(absf(float(reception_release.offset))/RECEIVE_EARLY,.12,1.)
	return target+Vector3(randf_range(-.8,.8),0.,randf_range(-.65,.65))*error
