extends "res://scripts/serve_reception_test.gd"

var cpu_wait := 0.
var receive_held := false
var released_at := INF
var touched_at := INF

func receiver_candidates() -> Array:
	return [1]

func start_drill() -> void:
	super.start_drill()
	title.text="PASSING  /  RECEIVE CPU SERVES"

func build_rally_sliders() -> void:
	add_rally_sliders("serving",[["Serve speed","serve_kmh",0,300,0," km/h"]])

func next_serve() -> void:
	super.next_serve()
	cpu_wait=1.25
	receive_held=false
	released_at=INF
	touched_at=INF
	spin_selection=3
	message.text="Ready"

func update_prompts(_next: String) -> void:
	if prompt_phase=="receive": return
	prompt_phase="receive"
	Xbox.prompts(controls_row,[["LS","Move"],["LT","Shuffle"],["RT","Sprint"],["A","Release to pass"]])

func apply_camera() -> void:
	yaw+=PI
	place_practice_camera(Vector3(0,1.5,BallNet.NET_Z+6.),distance*.48+2.)
	yaw-=PI

func walk_server(_delta: float,_defending := false) -> void:
	if phase=="serve_ready": ball.position=Contact.palm(hitter,"l")+Vector3.UP*.10

func update_serve_aim(_delta: float) -> void:
	super.update_serve_aim(0.)

func _process(delta: float) -> void:
	if not settings.visible and not get_tree().paused and not replay_inspector.active:
		if phase in ["serve_ready","serve_toss"]:
			var actor := passers[1]
			var stick := Vector2(axis(JOY_AXIS_LEFT_X),axis(JOY_AXIS_LEFT_Y))
			stick+=Vector2(Input.get_axis("ui_left","ui_right"),Input.get_axis("ui_up","ui_down"))
			var right := camera.global_basis.x.slide(Vector3.UP).normalized()
			var travel := (right*stick.x+right.cross(Vector3.UP)*stick.y).limit_length(1.)
			var pace := GroundControls.speed(GroundControls.focus(axis),GroundControls.sprint(axis))
			var goal := actor.position+travel*pace*delta
			goal.x=clampf(goal.x,-5.,5.)
			goal.z=clampf(goal.z,BallNet.NET_Z+.4,BallNet.NET_Z+10.)
			move_receiver(actor,goal,delta,serve_station-actor.position,pace,true)
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
			if event.pressed: receive_held=true
			elif receive_held:
				receive_held=false
				if phase=="serve_flight":
					released_at=flight_age
					if not recipe.is_empty(): show_release_feedback(released_at-receive_at,false)
			get_viewport().set_input_as_handled()
			return
		if event is InputEventJoypadButton and event.button_index!=Xbox.physical(JOY_BUTTON_START): return
	super._input(event)

func accept_reception(previous: Vector3) -> bool:
	if mapped_touch(map,recipe,previous) and not is_finite(touched_at): touched_at=flight_age
	if not is_finite(touched_at) or not is_finite(released_at): return false
	show_release_feedback(released_at-touched_at,true)
	return absf(released_at-touched_at)<=.15

func step_reception_rally(delta: float) -> void:
	pass_clock+=delta
	var u := minf(1.,pass_clock/pass_duration)
	ball.position=arc(pass_start,pass_end,u,4.905*pass_duration*pass_duration*.25)
	map.sample_receiver(recipe,minf(recipe.frames,recipe.contact+pass_clock*60.),true,map.legs)
	if u>=1.:
		drop_velocity=(pass_end-pass_start)/pass_duration+Vector3.DOWN*4.905*pass_duration
		drop_net_hit.clear()
		roll_time=-1.
		flight_age=0.
		phase="serve_miss"
