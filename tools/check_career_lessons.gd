extends SceneTree

func _initialize(): run.call_deferred()

func wait_loaded(path:String):
	for i in 3000:
		await process_frame
		if current_scene and current_scene.scene_file_path==path and not is_instance_valid(root.get_node("MenuPresentation").loading_screen): return true
	return false

func run():
	var c=root.get_node("CareerSession")
	c.store_path="res://work/qa-career-route.cfg"
	c.data=ConfigFile.new()
	var athlete=c.base_profile()
	athlete.name="Test Defender"
	assert(c.create_athlete(athlete))
	c.checkpoint("defense_lesson",2)
	change_scene_to_file("res://scenes/story.tscn")
	await scene_changed
	var menu=current_scene
	menu.controls_tutorial()
	assert(menu.column.get_children().filter(func(n):return n is Button).size()==6)
	var back:=InputEventJoypadButton.new()
	back.button_index=JOY_BUTTON_B
	back.pressed=true
	assert(back.is_action_pressed("ui_cancel") and not back.is_action_pressed("ui_accept"))
	root.push_input(back)
	assert(menu.screen=="MY CAREER")
	root.push_input(back)
	assert(await wait_loaded("res://scenes/main.tscn"))
	change_scene_to_file("res://scenes/story.tscn")
	await scene_changed
	current_scene.resume()
	assert(await wait_loaded("res://scenes/defense_lesson.tscn"))
	var d=current_scene
	assert(d.balls==2 and d.watching and d.cpu_defense)
	d.settings.show()
	d.settings.quit_gameplay()
	assert(await wait_loaded("res://scenes/story.tscn"))
	assert(c.progress()==2)
	current_scene.controls_tutorial()
	c.practice_lesson("serving_lesson")
	assert(await wait_loaded("res://scenes/career_serving_lesson.tscn"))
	current_scene.settings.show()
	current_scene.settings.quit_gameplay()
	assert(await wait_loaded("res://scenes/story.tscn"))
	assert(current_scene.screen=="CONTROLS TUTORIAL" and c.stage()=="defense_lesson" and c.progress()==2)
	current_scene.resume()
	assert(await wait_loaded("res://scenes/defense_lesson.tscn"))
	d=current_scene
	d.enter_turn()
	assert(not d.cpu_defense)
	var press:=InputEventJoypadButton.new()
	press.button_index=d.Xbox.physical(JOY_BUTTON_A)
	var released:=false
	var saw_pose:=false
	var success:=false
	var saw_hold:=false
	for tick in 700:
		await process_frame
		if d.phase=="serve_attack" and not d.dig_held and not released:
			press.pressed=true
			root.push_input(press)
		if d.phase=="serve_return" and not d.defense_recipe.is_empty():
			d.rings.position_floor_ring(d.hitter)
			d.rings.draw_defense_timing(d.hitter,d.hitter==d.setter)
			saw_hold=saw_hold or (d.dig_held and d.rings.displayed_timing.has(d.hitter) and d.rings.floor_rings[d.hitter].visible)
			saw_pose=d.defense_map.player==d.hitter and int(d.defense_recipe.id) in d.boxes.map(func(b):return b.id)
			if not released and d.dig_clock>=d.defense_at-d.PASS_RELEASE_LEAD:
				press.pressed=false
				root.push_input(press)
				released=true
		if d.phase=="server_dig" and d.last_digger==d.hitter:
			success=true
			break
	print("Manual A / observed pose: ",saw_pose," release: ",released," returned: ",success)
	assert(saw_pose and released and success and saw_hold,"Human mapped dig must connect on timed A release")
	print("Human dig used Studio clip ",d.defense_recipe.id," / ",d.defense_recipe.kind)
	var caption=root.get_node("ContactTiming").caption
	assert(caption.visible and caption.text.begins_with("Dig") and "ms" in caption.text)
	var bright:=false
	var faded:=false
	for tick in 104:
		await process_frame
		bright=bright or (caption.visible and caption.modulate.a>.9)
		if bright and not caption.visible:
			faded=true
			break
	assert(bright and faded)
	print("Defense HUD: stamina ring, hold timing and millisecond fade passed")
	for i in range(5-d.balls):
		d.attack_in_play=true
		d.next_serve()
	assert(await wait_loaded("res://scenes/career_serving_lesson.tscn"))
	var s=current_scene
	var served:=false
	for tick in 360:
		await process_frame
		if s.phase=="serve_flight":
			served=true
			break
	assert(served and s.serves_in==0)
	s.enter_turn()
	s.serve_out()
	assert(s.serves_in==0)
	for i in 5: s.show_service_ace()
	assert(await wait_loaded("res://scenes/offline_match.tscn"))
	var g=current_scene.game
	assert(g.players.size()==12 and g.team_size==6 and g.away_size==6 and g.win_score==5)
	for side in 2:
		var passer:int=g.first_on(side)+4
		var designated:int=g.choose_setter(side,passer)
		assert(root.get_node("StorySession").offline_roster[designated].position=="Setter")
		assert(g.choose_setter(side,designated)!=designated)
	print("PASS: B back, six lessons, save/leave/resume, isolated practice, five feeds, five serves, 6v6 with setters and backups")
	quit()
