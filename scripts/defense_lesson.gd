extends "res://scripts/defense_tryout.gd"

const FEEDS:=[Vector2(.10,.99),Vector2(-.86,.57),Vector2(.18,1.95),Vector2(.94,.76),Vector2(-.32,1.45)]
var feed_slot:=0
var balls:=0
var digs:=0

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
	super._process(delta)

func _input(event:InputEvent) -> void:
	if watching and not settings.visible and not get_tree().paused:
		if event is InputEventJoypadButton and event.button_index in [Xbox.physical(JOY_BUTTON_A),Xbox.physical(JOY_BUTTON_X),Xbox.physical(JOY_BUTTON_Y),Xbox.physical(JOY_BUTTON_B)]: return
		if event is InputEventKey and event.keycode in [KEY_ENTER,KEY_SPACE,KEY_Q,KEY_W,KEY_E,KEY_R]: return
	super._input(event)

func enter_turn() -> void:
	watching=false
	prompt_phase=""
	attack_in_play=false
	next_serve()
	if not CareerSession.profile().is_empty(): hitter.apply_profile(CareerSession.profile())
	coach_motion.whistle_cue.signal_drill(coach)

func start_drill() -> void:
	balls=clampi(CareerSession.progress(),0,4) if CareerSession.stage()=="defense_lesson" else 0
	super.start_drill()
	register_student(hitter,1)
	for blocker in wall: blocker.hide()
	cpu_defense=watching
	title.text="DEFENSE   /   %d of 5 attacks"%balls

func next_serve() -> void:
	if leaving_court: return
	if attack_in_play and not watching:
		attack_in_play=false
		balls+=1
		digs+=int(last_digger==hitter)
		if balls==5:
			if CareerSession.checkpoint("serving_lesson",0):
				leaving_court=true
				if StorySession.game_options.get_value("presentation","coach_feedback",true):
					say(coach,"Good work. Baseline next. Serve to one.",1.65)
				title.text="Defense complete"
				get_tree().create_timer(1.7,false).timeout.connect(func(): MenuPresentation.load_scene("res://scenes/career_serving_lesson.tscn"))
			return
		CareerSession.checkpoint("defense_lesson",balls)
	feed_slot=replay_rally%5 if watching else balls
	prepare_defense_feed(feed_slot,digs)
	floor_target=FIVE+Vector3(FEEDS[feed_slot].x,.105,.55)
	attack_landing=floor_target
	cpu_defense=watching
	title.text="DEFENSE   /   %d of 5 attacks"%balls

func step_serve_wall(_delta:float) -> void:
	pass

func dig_chases_feed() -> bool:
	return false

func dig_defender() -> Node3D:
	return hitter

func feed_height(_offset:Vector3) -> float:
	return FEEDS[feed_slot].y*hitter.height_cm/185.

func save_and_leave_drill() -> void:
	if CareerSession.checkpoint("defense_lesson",balls): MenuPresentation.load_scene("res://scenes/story.tscn")

func reset_drill() -> void:
	if CareerSession.checkpoint("defense_lesson",0): MenuPresentation.load_scene(scene_file_path)
