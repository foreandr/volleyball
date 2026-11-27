extends SceneTree

func _initialize() -> void:
	verify.call_deferred()

func verify() -> void:
	var host := VBoxContainer.new()
	root.add_child(host)
	root.get_node("MenuPresentation").audio_options(host)
	paused=true
	for control in host.get_children():
		if control is Button and control.text=="Test spike sound":
			control.pressed.emit()
	var speaker=root.get_node("StorySession").impact_player
	if not speaker.playing or not speaker.can_process():
		push_error("Paused settings did not start the shared spike sound")
		quit(1)
		return
	print("AUDIO_EVENT preview ",Time.get_unix_time_from_system())
	await create_timer(.9).timeout
	paused=false
	host.queue_free()
	change_scene_to_file("res://scenes/career_hitting_lesson.tscn")
	await scene_changed
	var game=current_scene
	var spike:=false
	var floor_hit:=false
	for frame in 2000:
		await process_frame
		if not spike and game.spike_sound_count>0:
			print("AUDIO_EVENT spike ",Time.get_unix_time_from_system())
			spike=true
		if spike and game.floor_sound_count>0:
			print("AUDIO_EVENT floor ",Time.get_unix_time_from_system())
			floor_hit=true
			break
	if not floor_hit:
		quit(1)
		return
	await create_timer(1.25).timeout
	game.enter_hitting_turn()
	for frame in 300:
		await process_frame
		if game.coach_motion.whistle_cue.play_count>0:
			print("AUDIO_EVENT whistle ",Time.get_unix_time_from_system())
			await create_timer(.65).timeout
			quit()
			return
	quit(1)
