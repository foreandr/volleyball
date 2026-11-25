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

func reset_feed() -> void:
	var last_position := hitter.position
	var last_heading := hitter.rotation.y
	super.reset_feed()
	if spikes>0:
		hitter.position=Vector3(last_position.x,START.y,last_position.z)
		hitter.rotation.y=last_heading
	var shot := spikes%3
	# Zone six sits in the middle third. Line targets stay on the attacker's sideline.
	var targets_x := [-1.1,3.9,3.85]
	var targets_z := [12.3,12.4,8.0]
	review_setup.x=-float(targets_x[shot])
	review_setup.z=targets_z[shot]
	cross_court=shot==0
	bounce_line=shot==2