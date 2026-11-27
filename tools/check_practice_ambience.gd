extends SceneTree

func _initialize() -> void:
	check.call_deferred()

func check() -> void:
	change_scene_to_file("res://scenes/career_hitting_lesson.tscn")
	await scene_changed
	var room
	for child in current_scene.get_children():
		if child.get_script()==preload("res://scripts/practice_ambience.gd"): room=child
	if room==null:
		quit(1)
		return
	var other=room.get_child(0)
	var count:int=other.partners.size()+room.participants.size()+room.seats.size()+room.coaches.size()+room.partners.size()
	var intruder:Node3D=current_scene.hitter
	var home:=intruder.position
	room.set_process(false)
	for i in 80: room._process(1./60.)
	var launched:bool=room.flight_time>=0.
	intruder.position=room.partners[0].position
	for i in 150: room._process(1./60.)
	var waited:bool=room.flight_time<0. and room.hold_time>1.
	intruder.position=home
	for i in 75: room._process(1./60.)
	var resumed:bool=room.flight_time>=0.
	print("Population %d; background rally launched %s, caught and waited %s, resumed %s."%[count,launched,waited,resumed])
	current_scene.enter_hitting_turn()
	var handed_off:bool=current_scene.hitter.position.distance_to(Vector3(-2.6,.04,-2.8))<.1 and current_scene.sideline_actor.position.distance_to(Vector3(0.,.04,-2.8))<.1
	print("Handoff to one and six: ",handed_off)
	quit(0 if handed_off and count>=15 and count<=20 and launched and waited and resumed else 1)
