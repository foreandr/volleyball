extends "res://scripts/attacking_camp.gd"

func start_drill() -> void:
	review_setup={"power":40.,"x":3.4,"z":11.,"spin":0}
	jump_height=50.*.0254
	cross_court=true
	super.start_drill()

func jump_rep() -> bool:
	return true

func choose_camp_toss() -> Vector3:
	return BASE

func attack_speed() -> float:
	return 40.
