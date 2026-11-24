extends SceneTree

# Run with --fixed-fps 30 --resolution 1280x720 --script res://tools/review_jersey_motion.gd
const Setting := preload("res://scripts/hand_setting_pose.gd")

func _initialize() -> void:
	call_deferred("review")

func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path := OS.get_temp_dir().path_join("jersey-review-"+label+".jpg")
	var err := root.get_texture().get_image().save_jpg(path,.95)
	if err != OK:
		push_error("Cannot save "+path)
		quit(1)

func review() -> void:
	var career = root.get_node("CareerSession")
	career.store_path=OS.get_temp_dir().path_join("jersey-review-career.cfg")
	career.data.clear()
	career.create_athlete(career.base_profile())
	career.checkpoint("tutorial",0)
	change_scene_to_file(career.CHAPTER)
	await scene_changed
	var gym=current_scene
	gym.start_practice()
	gym.panel.hide()
	# Isolate animation playback from toss scheduling for repeatable comparisons.
	gym.set_physics_process(false)
	gym.set_process(false)
	var athlete=gym.rotation_drill.roster[1]
	var start: Vector3=athlete.position
	var heading: Vector3=athlete.basis.z.normalized()
	var playback=athlete.animator.callback_mode_process
	athlete.animator.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for action in ["run","set"]:
		athlete.play_action("run" if action=="run" else "base/Idle",0.)
		athlete.animator.advance(0.)
		var base_pose: Array[Transform3D]=[]
		for bone in athlete.skeleton.get_bone_count(): base_pose.append(athlete.skeleton.get_bone_pose(bone))
		for frame in (24 if action=="run" else 72):
			await process_frame
			athlete.animator.advance(1./30.)
			if action=="run":
				athlete.position+=heading*.075
			else:
				for bone in base_pose.size(): athlete.skeleton.set_bone_pose(bone,base_pose[bone])
				var contact: Vector3=athlete.to_global(Vector3(0,1.86,.23))
				Setting.apply(athlete,contact,smoothstep(0.,10.,frame),(Vector3.UP+heading*.3).normalized()*.22,0.,.3,false,Vector3.ZERO,smoothstep(32.,58.,frame),heading*4.,.5,true)
			gym.camera.position=athlete.to_global(Vector3(1.45,1.63,1.88))
			gym.camera.look_at(athlete.to_global(Vector3(0,1.38,0)))
			if action=="run" and frame in [8,15,20]:
				gym.camera.position=athlete.to_global(Vector3(1.08,.58,1.20))
				gym.camera.look_at(athlete.to_global(Vector3(0,.49,0)))
				await capture("knees"+str(frame))
			if frame in ([6,12,18] if action=="run" else [16,36,64]): await capture(action+str(frame))
	athlete.animator.callback_mode_process=playback
	athlete.position=start
	gym.set_process(true)
	gym.set_physics_process(true)
	gym.complete()
	for frame in 150:
		await process_frame
		if frame>=120:
			gym.camera.position=Vector3(-1.75,1.96,-3.65)
			gym.camera.look_at(gym.rotation_drill.HUDDLE_CENTER+Vector3.UP*1.23)
		if frame in [125,140]: await capture("huddle"+str(frame))
		if frame in [128,134,144]:
			var head: Vector3=athlete.skeleton.to_global(athlete.skeleton.get_bone_global_pose(athlete.skeleton.find_bone("Head")).origin)
			gym.camera.position=head+athlete.global_basis.orthonormalized()*Vector3(.56,.27,.67)
			gym.camera.look_at(head+Vector3.UP*.09)
			await capture("hair"+str(frame))
	gym.set_process(false)
	gym.set_physics_process(false)
	var coach=gym.coach
	var cart=gym.rotation_drill.basket
	coach.animator.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	coach.global_basis=cart.global_basis.orthonormalized().scaled(Vector3.ONE*(coach.height_cm/180.))
	coach.position=cart.to_global(Vector3(0,0,-.87))
	var stride := 0.
	for frame in 48:
		await process_frame
		if frame<24:
			gym.ball.position=gym.coach_motion.toss(coach,float(frame)/23.)
		else:
			var step: Vector3=cart.global_basis.z.normalized()*.028
			cart.position+=step
			coach.position+=step
			stride=gym.rotation_drill.push_pose(coach,cart,stride,.028)
		gym.camera.position=coach.to_global(Vector3(1.9,1.70,2.15))
		gym.camera.look_at(coach.to_global(Vector3(0,1.19,0)))
		if frame in [6,20,32,44]: await capture("coach"+str(frame))
	print("Completed running, overhead setting and huddle captures")
	quit()
