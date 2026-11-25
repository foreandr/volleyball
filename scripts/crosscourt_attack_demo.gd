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
	# Each demonstration feed starts with a rested jump setter.
	setter.stamina.rested_capacity=setter.stamina.capacity()
	setter.stamina.value=setter.stamina.rested_capacity
	setter.stamina.exhausted=false
	super.reset_feed()
	if spikes>0:
		hitter.position=Vector3(last_position.x,START.y,last_position.z)
		hitter.rotation.y=last_heading
	# Court coordinates for sharp cross, six, one, and the line bounce.
	var targets := [Vector2(-3.65,8.45),Vector2(-.35,11.4),Vector2(3.75,11.55),Vector2(3.85,8.65)]
	var shot := spikes%targets.size()
	var aim: Vector2=targets[shot]
	review_setup.x=-aim.x
	review_setup.z=aim.y
	cross_court=shot<2
	bounce_line=shot==3