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

var cpu_wait := 0.
var receive_held := false
var released_at := INF
var touched_at := INF
var receive_committed := false
const RECEIVE_EARLY := .21
const RECEIVE_LATE := .15

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
	released_at=INF
	touched_at=INF
	spin_selection=3
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
			stick+=Vector2(Input.get_axis("ui_left","ui_right"),Input.get_axis("ui_up","ui_down"))
			var right := camera.global_basis.x.slide(Vector3.UP).normalized()
			var travel := (right*stick.x+right.cross(Vector3.UP)*stick.y).limit_length(1.)
			var pace := GroundControls.speed(GroundControls.focus(axis),GroundControls.sprint(axis))
			var goal := actor.position+travel*pace*delta
			goal.x=clampf(goal.x,-5.,5.)
			goal.z=clampf(goal.z,BallNet.NET_Z+.4,BallNet.NET_Z+10.)
			if control_digger: goal.z=clampf(actor.position.z+travel.z*pace*delta,BallNet.NET_Z-10.,BallNet.NET_Z-.4)
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
				handle_serve_button(2,true)
		elif phase=="serve_toss" and not is_finite(release_time) and serve_meter_error()>=-.01:
			handle_serve_button(2,false)
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
				if phase=="serve_flight":
					released_at=flight_age
					if not recipe.is_empty(): show_release_feedback(released_at-receive_at,true,.085)
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

func accept_reception(previous: Vector3) -> bool:
	if control_digger: return super.accept_reception(previous)
	if mapped_touch(map,recipe,previous) and not is_finite(touched_at): touched_at=flight_age
	if not is_finite(touched_at) or not is_finite(released_at): return false
	return released_at>=receive_at-RECEIVE_EARLY and released_at<=receive_at+RECEIVE_LATE
