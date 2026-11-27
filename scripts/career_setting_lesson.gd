extends "res://scripts/indoor_practice.gd"

const LANES := ["Left side (4)","Middle","Right side (2)"]
const METHODS := ["Standing hand set","Jump hand set"]
var credit:=0
var performed:=-1
var watching:=true
var join_hold:=0.
var human:Node3D
var demo_actor:Node3D
var closing:=false
var clearing_demo:=false

func start_drill() -> void:
	if CareerSession.stage()=="setting_lesson":
		credit=CareerSession.progress()
		if not CareerSession.data.get_value(CareerSession.key(),"twelve_set_lesson",false):
			credit=4*(credit/6)+mini(credit%6,4)
	credit=clampi(credit,0,12)
	CareerSession.data.set_value(CareerSession.key(),"twelve_set_lesson",true)
	if credit==12:
		enter_hitting()
		return
	human=setter
	seat_teammates()
	demo_actor=athlete(BASE,"e97937")
	register_student(demo_actor,1)
	preload("res://scripts/practice_kit.gd").apply(demo_actor,false,1)
	energy[demo_actor]=demo_actor.stamina
	setter=demo_actor
	rotation_drill.key_upright_idle(demo_actor)
	rings.participants=[human]
	start_practice()
	human.position=BASE+Vector3(1.7,0,-1.4)
	say(coach,"Good passing. Now you set. Watch the release, then take a turn.",4.)

func called() -> int:
	return clampi(credit/4,0,2)

func method() -> int:
	return (credit%4)/2

func choose_camp_toss() -> Vector3:
	return Vector3(setter.position.x,BASE.y,setter.position.z) if not watching else BASE

func set_destination(origin:Vector3,aim:Vector3,height_index:int) -> Vector3:
	var end:=super.set_destination(origin,aim,height_index)
	if watching or target!=called() or not bump_aim.is_zero_approx(): return end
	# Guide playable releases toward the called target. Keep the actual flight,
	# rim collision and any mistimed release in the ordinary scoring path.
	var assist:=1.-smoothstep(0.,timing_window(),absf(set_error))
	return end.lerp(PINS[target],assist*.90)

func middle_available() -> bool:
	return true

func camp_title() -> String:
	return "%s   /   %s   /   %d / 2 correct"%[LANES[called()],METHODS[method()],credit%2]

func jump_rep() -> bool:
	if watching: return method()==1
	return super.jump_rep()

func start_set_flight() -> void:
	performed=2 if bump_touched else (1 if jump.active and setter.position.y>BASE.y+.04 else 0)
	super.start_set_flight()

func enter_hitting() -> void:
	closing=true
	if CareerSession.checkpoint("hitting_lesson",0):
		MenuPresentation.load_scene("res://scenes/career_hitting_lesson.tscn")

func finish_set() -> void:
	super.finish_set()
	if watching or not success: return
	if performed!=method():
		message.text="Target hit. Use the called technique."
		return
	credit+=1
	CareerSession.checkpoint("setting_lesson",credit)
	title.text=camp_title() if credit<12 else "Setting complete   /   12 of 12"
	if credit==12: enter_hitting()

func reset_feed() -> void:
	performed=-1
	cpu_bump=false
	super.reset_feed()
	camp_call=called()
	prompt_phase=""
	update_prompts(phase)
	title.text=camp_title()
	panel.show()
	for i in targets.size(): targets[i].beacon.visible=i==called()

func update_prompts(next:String) -> void:
	var key:="%s/%d/%s/%s"%[watching,credit,next=="ground",Xbox.keyboard_prompts()]
	if key==prompt_phase: return
	prompt_phase=key
	var entries:Array=[]
	if watching: entries=[[JOY_BUTTON_A,"Hold to enter the drill"]]
	elif next=="ground": entries=[[JOY_BUTTON_LEFT_SHOULDER,"Next toss"]]
	else:
		entries.append(["LT","Square up to the selected target"])
		if method()==1: entries.append([JOY_BUTTON_LEFT_SHOULDER,"Hold to jump"])
		entries.append([BUTTONS[called()],"Hold to prepare; release as the ball meets your hands"])
	Xbox.prompts(controls_row,entries)
	if Xbox.keyboard_prompts():
		hint.show()
		hint.text="Hold Space to enter" if watching else ("Enter: next toss" if next=="ground" else "%sHold %s; release at hand contact"%["Hold Space to jump. " if method()==1 else "",["J","I","L"][called()]])

func aim_bump(stick:Vector2) -> void:
	if Input.is_key_pressed(KEY_U): stick=Vector2.LEFT
	elif Input.is_key_pressed(KEY_O): stick=Vector2.UP
	elif Input.is_key_pressed(KEY_P): stick=Vector2.RIGHT
	super.aim_bump(stick)

func switch_camp_control() -> void:
	if not watching: return
	watching=false
	performed=-1
	if rotation_drill.issued: rotation_drill.free_ball(Vector3.ZERO)
	clearing_demo=true
	setter=human
	human.position=BASE
	cpu_setting=false
	cpu_bump=false
	coach_motion.whistle_cue.signal_drill(coach)
	reset_feed()

func _input(event:InputEvent) -> void:
	if watching and event is InputEventJoypadButton and event.button_index in [Xbox.physical(JOY_BUTTON_BACK),Xbox.physical(JOY_BUTTON_RIGHT_STICK)]:
		return
	if watching and event is InputEventKey and event.physical_keycode==KEY_TAB: return
	super._input(event)
	if not watching and is_instance_valid(panel):
		for i in targets.size(): targets[i].beacon.visible=i==called()

func _process(dt:float) -> void:
	if closing: return
	if clearing_demo:
		var goal:=Vector3(5.5,BASE.y,1.)
		var travel:=goal-demo_actor.position
		if travel.length()>.06:
			GroundControls.face(demo_actor,travel,dt)
			demo_actor.play_travel_gait(travel.normalized()*3.)
			demo_actor.position=demo_actor.position.move_toward(goal,3.*dt)
		else:
			demo_actor.play_action("idle",.2)
			clearing_demo=false
		demo_actor.animator.advance(dt)
	if watching:
		move_setter(dt,human,true)
		human.animator.advance(dt)
		var down:=Input.is_key_pressed(KEY_SPACE) or (pad()>=0 and Input.is_joy_button_pressed(pad(),Xbox.physical(JOY_BUTTON_A)))
		join_hold=join_hold+dt if down else 0.
		if join_hold>=1.: switch_camp_control()
	super._process(dt)
	if Xbox.keyboard_prompts(): hint.show()

func reset_drill() -> void:
	if CareerSession.checkpoint("setting_lesson",0): MenuPresentation.load_scene(scene_file_path)

func save_and_leave_drill() -> void:
	if CareerSession.checkpoint("setting_lesson",credit): MenuPresentation.load_scene("res://scenes/main.tscn")
