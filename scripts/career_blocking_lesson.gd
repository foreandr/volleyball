extends "res://scripts/blocking_camp.gd"

const REQUIRED_TOUCHES := 5
var touches := 0
var pending_player_touch := false

func next_attack_route() -> int:
	return 0 # The opposing left pin, position four.

func camp_title() -> String:
	return "BLOCKING   /   POSITION 4   /   %d of %d touches"%[touches,REQUIRED_TOUCHES]

func start_drill() -> void:
	touches=clampi(CareerSession.progress(),0,REQUIRED_TOUCHES-1) if CareerSession.stage()=="blocking_lesson" else 0
	manual_slot=0
	blocker_homes=[3.65]
	coach_only_feeds=true
	random_heights=false
	attack_tempo=2
	aim_mode=AimMode.INTO_BLOCK
	super.start_drill()
	var profile:=CareerSession.profile()
	if profile.is_empty(): profile=preload("res://scripts/player_profile.gd").load_profile()
	blockers[manual_slot].apply_profile(profile)
	block_vertical=float(blockers[manual_slot].attributes.vertical_in)

func reset_feed() -> void:
	pending_player_touch=false
	if route<0:
		register_student(hitter,1)
		camp_jump_height=float(setter.attributes.vertical_in)*.0254
	super.reset_feed()

func attack_speed() -> float:
	return preload("res://scripts/swing_speed.gd").kmh(hitter)/3.6

func update_prompts(_next:String) -> void:
	Xbox.prompts(controls_row,[["LS","Move"],[JOY_BUTTON_A,"Hold and release to block"],["LT","Left reach"],["RT","Right reach"]])

func choose_block_target() -> void:
	aim_committed=true
	var landing:=strike_landing(endpoint)
	review_setup.x=-landing.x
	review_setup.z=landing.z

func strike_landing(origin:Vector3) -> Vector3:
	# Aim along the blocker's lane. Shorten the landing depth until the
	# descending ball just clears the tape at its current swing speed.
	var blocker:=blockers[manual_slot]
	var aim_x:=blocker.position.x
	var jump=jumps[manual_slot]
	if jump!=null and jump.hands.size()==2:
		aim_x=(jump.hands[0].x+jump.hands[1].x)*.5
	var slope:=(aim_x-origin.x)/maxf(.2,blocker.position.z-origin.z)
	var near_depth:=BallNet.NET_Z
	var far_depth:=BallNet.NET_Z+8.9
	var landing:=Vector3.ZERO
	for i in 10:
		var z:=far_depth if i==0 else (near_depth+far_depth)*.5
		var candidate:=Vector3(clampf(origin.x+slope*(z-origin.z),-4.4,4.4),Contact.BALL_RADIUS,z)
		var duration:=attack_flight_time(origin,candidate)
		var spin:=shot_spin_force(origin,candidate,duration)
		var velocity:=launch_velocity(origin,candidate,duration,spin)
		var t:=(BallNet.NET_Z+.055-origin.z)/maxf(.01,velocity.z)
		var y:=origin.y+velocity.y*t+.5*(spin.y-9.81)*t*t
		if i==0: landing=candidate
		if y>=BallNet.NET_TOP+Contact.BALL_RADIUS+.085:
			far_depth=z
			landing=candidate
		else:
			near_depth=z
	return landing

func resolve_block_contact(previous:Vector3,block_jumps:Array,attack_direction:=1.) -> bool:
	if deflected or not super.resolve_block_contact(previous,block_jumps,attack_direction): return false
	pending_player_touch=not automatic_block
	return true

func attack_surface_contact(point:Vector3,floor_hit:bool) -> void:
	var already_decided:=attack_decided
	super.attack_surface_contact(point,floor_hit)
	if already_decided or not attack_decided or not pending_player_touch: return
	pending_player_touch=false
	if not floor_hit or absf(point.x)>4.5 or absf(point.z-BallNet.NET_Z)>9.: return
	if touches>=REQUIRED_TOUCHES: return
	touches+=1
	title.text=camp_title()
	trace("tutorial_block_touch",{"touches":touches,"rep":rep})
	if touches==REQUIRED_TOUCHES:
		if CareerSession.checkpoint("position",0):
			get_tree().create_timer(1.,false).timeout.connect(finish_practice)
	else:
		CareerSession.checkpoint("blocking_lesson",touches)

func finish_practice() -> void:
	MenuPresentation.load_scene("res://scenes/story.tscn")

func reset_drill() -> void:
	if CareerSession.checkpoint("blocking_lesson",0): super.reset_drill()

func save_and_leave_drill() -> void:
	if touches==REQUIRED_TOUCHES: finish_practice()
	elif CareerSession.checkpoint("blocking_lesson",touches):
		MenuPresentation.load_scene("res://scenes/story.tscn")
