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
	var handed_off:bool=current_scene.hitter.position.distance_to(current_scene.FEED_LANES[current_scene.active_lane])<.1 and absf(current_scene.sideline_actor.position.x)>4.5
	print("Handoff positions ",current_scene.hitter.position," and ",current_scene.sideline_actor.position,"; active lane ",current_scene.active_lane)
	var lanes_ok:=true
	var cpu_offsets:Array[Vector3]=[]
	for demo in [false,true]:
		current_scene.cpu_hitter=demo
		for i in 9:
			current_scene.makes=i
			current_scene.demo_rep=i
			current_scene.demo_hit=false
			current_scene.reset_feed()
			current_scene.phase="feed"
			current_scene.change_feed_phase("pass")
			var target:Vector3=current_scene.receive_point
			if demo:
				var hit:Vector3=current_scene.shot_landing(Vector3.ZERO)
				lanes_ok=lanes_ok and hit==current_scene.shot_landing(Vector3.ZERO)
				cpu_offsets.append(hit-current_scene.zone_center())
			var center:Vector3=current_scene.FEED_LANES[i/3]
			lanes_ok=lanes_ok and current_scene.active_lane==i/3 and (target-center).slide(Vector3.UP).length()<1.
			lanes_ok=lanes_ok and (current_scene.height_preset() in [1,2] if demo else current_scene.height_preset()==3)
	lanes_ok=lanes_ok and cpu_offsets[0].x!=cpu_offsets[1].x and cpu_offsets[0].z!=cpu_offsets[1].z
	current_scene.show_height_preview(2)
	print("Separate handoff: ",handed_off,", all nine feed assignments and heights for both roles: ",lanes_ok)
	quit(0 if lanes_ok and handed_off and count>=15 and count<=20 and launched and waited and resumed else 1)
