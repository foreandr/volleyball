extends "res://scripts/blocking_camp.gd"

func next_attack_route() -> int:
	return 0 # The opposing left pin, position four.

func camp_title() -> String:
	return "BLOCKING   /   POSITION 4"

func start_drill() -> void:
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
	if route<0:
		register_student(hitter,1)
		camp_jump_height=float(setter.attributes.vertical_in)*.0254
	super.reset_feed()

func attack_speed() -> float:
	return preload("res://scripts/swing_speed.gd").kmh(hitter)/3.6

func update_prompts(_next:String) -> void:
	Xbox.prompts(controls_row,[["LS","Move"],[JOY_BUTTON_A,"Hold and release to block"],["LT","Left reach"],["RT","Right reach"]])

func build_settings() -> void:
	super.build_settings()
	var finish:=settings.bar(settings.home,"Finish blocking practice",finish_practice)
	settings.home.move_child(finish,2)

func finish_practice() -> void:
	if CareerSession.checkpoint("position",0):
		settings.hide()
		MenuPresentation.load_scene("res://scenes/story.tscn")

func save_and_leave_drill() -> void:
	if CareerSession.checkpoint("blocking_lesson",0):
		MenuPresentation.load_scene("res://scenes/story.tscn")
