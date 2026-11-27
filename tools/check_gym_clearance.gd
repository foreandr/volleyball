extends SceneTree

func _initialize() -> void:
	check.call_deferred()

func check() -> void:
	change_scene_to_file("res://scenes/career_hitting_lesson.tscn")
	await scene_changed
	await physics_frame
	await physics_frame
	var roof=current_scene.gym.get_node("Ceiling")
	var query:=PhysicsRayQueryParameters3D.create(Vector3(0,8,1),Vector3(0,14,1),16)
	var hit=current_scene.world.get_world_3d().direct_space_state.intersect_ray(query)
	print("Roof center ",roof.global_position.y," physical underside ",hit.get("position",Vector3.INF))
	quit(0 if is_equal_approx(roof.global_position.y,12.) and not hit.is_empty() and absf(hit.position.y-11.9)<.01 else 1)
