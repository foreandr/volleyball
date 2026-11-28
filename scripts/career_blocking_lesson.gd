extends "res://scripts/blocking_camp.gd"

func next_attack_route() -> int:
	return 0 # The opposing left pin, position four.

func camp_title() -> String:
	return "BLOCKING   /   POSITION 4"

func start_drill() -> void:
	super.start_drill()
	var profile:=CareerSession.profile()
	if not profile.is_empty():
		blockers[MANUAL_SLOT].apply_profile(profile)
		block_vertical=float(profile.get("vertical_in",block_vertical))
		height_control.set_value_no_signal(block_vertical)
		height_label.text="Block vertical    %d in"%block_vertical

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
