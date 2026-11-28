extends SceneTree

func _initialize() -> void:
	verify.call_deferred()

func verify() -> void:
	change_scene_to_file("res://scenes/career_hitting_lesson.tscn")
	await scene_changed
	var drill=current_scene
	drill.tip_shot=false
	drill.roll_shot=false
	for grade in [0.,-.17,.38]:
		drill.contact_grade=grade
		var pace:float=drill.hard_contact_speed()
		for origin in [Vector3(1,2.15,3.8),Vector3(-2,3.6,2.)]:
			for target in [Vector3(3,.145,8),Vector3(-4,.145,12)]:
				for spin_style in 5:
					drill.review_setup.spin=spin_style
					var duration:float=drill.attack_flight_time(origin,target)
					var spin:Vector3=drill.shot_spin_force(origin,target,duration)
					var velocity:Vector3=drill.launch_velocity(origin,target,duration,spin)
					var landing:Vector3=origin+velocity*duration+(spin+Vector3.DOWN*9.81)*.5*duration*duration
					if absf(velocity.length()-pace)>.001 or landing.distance_to(target)>.01:
						push_error("Strike pace or trajectory mismatch")
						quit(1)
						return
		print("Release grade ",grade," verified ",pace*3.6," km/h across targets and spin")
	if drill.predicted_net_hit(Vector3(1,2.15,3.8),Vector3(1,.145,8)).is_empty():
		quit(1)
		return
	print("Low hard swing hits net")
	quit()
