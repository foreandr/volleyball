extends "res://scripts/indoor_practice.gd"

const LANES := ["Left side (4)","Middle","Right side"]
const METHODS := ["Standing hand set","Jump hand set","Bump set"]
var credit:=0
var performed:=-1
var watching:=true
var join_hold:=0.
var human:Node3D
var demo_actor:Node3D
var closing:=false
var clearing_demo:=false

func start_drill() -> void:
	credit=clampi(CareerSession.progress() if CareerSession.stage()=="setting_lesson" else 0,0,17)
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
	return clampi(credit/6,0,2)

func method() -> int:
	return (credit%6)/2

func choose_camp_toss() -> Vector3:
	return BASE

func middle_available() -> bool:
	return true

func camp_title() -> String:
	return "%s   /   %s   /   %d of 2"%[LANES[called()],METHODS[method()],credit%2+1]

func jump_rep() -> bool:
	if watching: return method()==1
	return super.jump_rep()

func start_set_flight() -> void:
	performed=2 if bump_touched else (1 if jump.active and setter.position.y>BASE.y+.04 else 0)
	super.start_set_flight()

func reset_feed() -> void:
	if not watching and phase=="between" and success and target==called() and performed==method():
		credit+=1
		if credit==18:
			closing=true
			CareerSession.checkpoint("setting_lesson_complete",18)
			MenuPresentation.load_scene("res://scenes/story.tscn")
			return
		CareerSession.checkpoint("setting_lesson",credit)
	performed=-1
	cpu_bump=watching and method()==2
	super.reset_feed()
	camp_call=called()
	prompt_phase=""
	update_prompts(phase)
	title.text=camp_title()
	for i in targets.size(): targets[i].beacon.visible=i==called()

func update_prompts(next:String) -> void:
	var key:="%s/%d/%s/%s"%[watching,credit,next=="ground",Xbox.keyboard_prompts()]
	if key==prompt_phase: return
	prompt_phase=key
	var entries:Array=[]
	if watching: entries=[[JOY_BUTTON_A,"Hold to enter the drill"]]
	elif next=="ground": entries=[[JOY_BUTTON_LEFT_SHOULDER,"Next toss"]]
	elif method()==2:
		entries=[["RS","Hold "+["left","up","right"][called()]+"; let go as the ball meets your forearms"]]
	else:
		if method()==1: entries.append([JOY_BUTTON_LEFT_SHOULDER,"Hold to jump"])
		entries.append([BUTTONS[called()],"Hold to prepare; release as the ball meets your hands"])
	Xbox.prompts(controls_row,entries)
	if Xbox.keyboard_prompts():
		hint.show()
		hint.text="Hold Space to enter" if watching else ("Enter: next toss" if next=="ground" else ("Hold %s; release at forearm contact"%["U","O","P"][called()] if method()==2 else "%sHold %s; release at hand contact"%["Hold Space to jump. " if method()==1 else "",["J","I","L"][called()]]))

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
	cpu_setting=false
	cpu_bump=false
	coach_motion.whistle_cue.signal_drill(coach)
	reset_feed()

func _input(event:InputEvent) -> void:
	if watching and event is InputEventJoypadButton and event.button_index in [Xbox.physical(JOY_BUTTON_BACK),Xbox.physical(JOY_BUTTON_RIGHT_STICK)]:
		return
	if watching and event is InputEventKey and event.physical_keycode==KEY_TAB: return
	super._input(event)

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
