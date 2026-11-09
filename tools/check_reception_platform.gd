extends SceneTree

# Run with Godot --headless --path . --script tools/check_reception_platform.gd.
func _initialize() -> void:
	call_deferred("check")

func check() -> void:
	change_scene_to_file("res://scenes/story_animations.tscn")
	await process_frame
	await process_frame
	var page = current_scene
	page.select_category("Forearm reception")
	page.set_process(false)
	page.angle_control.set_process(false)
	var review = page.reception_review
	review.toggle_play()
	var rig: Skeleton3D = page.preview_player.skeleton
	for index in [8,10,14]:
		review.load_case(index)
		for frame in range(26): review.step(1.0/60)
		var ready_wrist := bone_position(rig,"hand_l")
		review.step(1.0/60)
		if ready_wrist.distance_to(bone_position(rig,"hand_l")) > 0.10:
			push_error("Clip %d snapped into the receive." % (index+1))
			quit(1)
			return
		for frame in range(15): review.step(1.0/60)
		for frame in range(3):
			review.step(1.0/60)
			if not check_platform(rig,index):
				quit(1)
				return
		for frame in range(13): review.step(1.0/60)
		var contact_wrist := bone_position(rig,"hand_l")
		review.step(1.0/60)
		if contact_wrist.distance_to(bone_position(rig,"hand_l")) > 0.10:
			push_error("Clip %d snapped out of the receive." % (index+1))
			quit(1)
			return
	print("Lunge platform check passed for forward, left and right.")
	quit()

func check_platform(rig: Skeleton3D, index: int) -> bool:
	var left_elbow := bone_position(rig,"lowerarm_l")
	var right_elbow := bone_position(rig,"lowerarm_r")
	var left_wrist := bone_position(rig,"hand_l")
	var right_wrist := bone_position(rig,"hand_r")
	var left_shoulder := bone_position(rig,"upperarm_l")
	var right_shoulder := bone_position(rig,"upperarm_r")
	var elbow_gap := left_elbow.distance_to(right_elbow)
	var wrist_gap := left_wrist.distance_to(right_wrist)
	var left_angle := rad_to_deg((left_shoulder-left_elbow).angle_to(left_wrist-left_elbow))
	var right_angle := rad_to_deg((right_shoulder-right_elbow).angle_to(right_wrist-right_elbow))
	var tilt := left_shoulder.y-right_shoulder.y
	var correct_tilt := index == 8 or (tilt > 0.02 if index == 14 else tilt < -0.02)
	if elbow_gap <= 0.24 and wrist_gap <= 0.075 and minf(left_angle,right_angle) >= 156.0 and correct_tilt:
		return true
	push_error("Clip %d: elbow gap %.3f m, wrist gap %.3f m, elbows %.1f / %.1f degrees, tilt %.3f m." %
		[index+1,elbow_gap,wrist_gap,left_angle,right_angle,tilt])
	return false

func bone_position(rig: Skeleton3D, bone_name: String) -> Vector3:
	return rig.get_bone_global_pose(rig.find_bone(bone_name)).origin
