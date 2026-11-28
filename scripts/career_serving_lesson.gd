extends "res://scripts/serving_camp.gd"

var demo_wait:=0.
var serves_in:=0

var watching:=true
var entry_widget:Control
var join_time:=0.

func update_prompts(next:String) -> void:
	if watching:
		if not is_instance_valid(entry_widget):
			entry_widget=preload("res://scripts/drill_entry_prompt.gd").mount(controls_row,"Enter")
	else: super.update_prompts(next)

func _process(delta:float) -> void:
	if watching and not changing_turn and not settings.visible and not get_tree().paused and not replay_inspector.active:
		var down:=Input.is_key_pressed(KEY_ENTER) or (pad()>=0 and Input.is_joy_button_pressed(pad(),Xbox.physical(JOY_BUTTON_A)))
		join_time=join_time+delta if down else 0.
		if is_instance_valid(entry_widget): entry_widget.set_fraction(join_time)
		if join_time>=1.: fade_into_drill(enter_turn)
		if phase=="serve_ready":
			demo_wait+=delta
			if pending_serve<0 and demo_wait>=.8:
				demo_wait=0.
				handle_serve_button(2,true)
		elif phase=="serve_toss" and not is_finite(release_time) and serve_meter_error()>=-.01: handle_serve_button(2,false)
	super._process(delta)

func _input(event:InputEvent) -> void:
	if watching and not settings.visible and not get_tree().paused:
		if event is InputEventJoypadButton and event.button_index in [Xbox.physical(JOY_BUTTON_A),Xbox.physical(JOY_BUTTON_X),Xbox.physical(JOY_BUTTON_Y),Xbox.physical(JOY_BUTTON_B)]: return
		if event is InputEventKey and event.keycode in [KEY_ENTER,KEY_SPACE,KEY_Q,KEY_W,KEY_E,KEY_R]: return
	super._input(event)

func enter_turn() -> void:
	watching=false
	prompt_phase=""
	next_serve()
	if not CareerSession.profile().is_empty(): hitter.apply_profile(CareerSession.profile())
	coach_motion.whistle_cue.signal_drill(coach)

func start_drill() -> void:
	serves_in=clampi(CareerSession.progress(),0,4) if CareerSession.stage()=="serving_lesson" else 0
	super.start_drill()
	register_student(hitter,1)
	for actor in passers+wall+[receiving_setter,receiving_middle,pin_hitter]:
		actor.hide()
	title.text="SERVING   /   %d of 5 in"%serves_in

func build_rally_sliders() -> void:
	pass

func step_serve_reception(_shot,_previous:Vector3,_delta:float) -> void:
	pass

func show_service_ace() -> void:
	if watching or serves_in>=5: return
	serves_in+=1
	message.text="Serve in"
	title.text="SERVING   /   %d of 5 in"%serves_in
	if serves_in==5:
		if CareerSession.checkpoint("scrimmage",0):
			get_tree().create_timer(.9,false).timeout.connect(finish_lesson,CONNECT_ONE_SHOT)
	else: CareerSession.checkpoint("serving_lesson",serves_in)

func finish_lesson() -> void:
	CareerSession.open_scrimmage()

func serve_out() -> void:
	message.text="Serve out"

func save_and_leave_drill() -> void:
	if serves_in==5 or CareerSession.checkpoint("serving_lesson",serves_in):
		MenuPresentation.load_scene("res://scenes/story.tscn")

func reset_drill() -> void:
	if CareerSession.checkpoint("serving_lesson",0): MenuPresentation.load_scene(scene_file_path)
