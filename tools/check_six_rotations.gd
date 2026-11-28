extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var formations=load("res://scripts/six_rotations.gd")
	var session=root.get_node("StorySession")
	var options:=ConfigFile.new()
	change_scene_to_file("res://scenes/formation_editor.tscn")
	await scene_changed
	var editor=current_scene
	for rotation in range(1,7):
		for defense in [false,true]:
			editor.setter_zone=rotation
			editor.defense=defense
			editor.refresh()
			assert(editor.marks.size()==6)
			editor.selected=0
			editor.move_mark(Vector2(.1+rotation*.08,.62 if defense else .25))
			options.set_value("six_rotations",formations.key(rotation,defense),editor.marks.duplicate())
	editor.dirty=false
	assert(options.save("res://work/qa-rotation-layouts.cfg")==OK)
	session.game_options=ConfigFile.new()
	assert(session.game_options.load("res://work/qa-rotation-layouts.cfg")==OK)
	session.offline_size=6
	session.offline_away_size=6
	session.offline_roster.clear()
	for i in 12:
		var profile=load("res://scripts/player_profile.gd").generate()
		profile.position=formations.ROLES[(i+3)%6]
		session.offline_roster.append(profile)
	for career in [false,true]:
		session.career_scrimmage=career
		if career:
			session.offline_roster[2].position="Opposite"
			session.offline_roster[0].position="Libero"
		change_scene_to_file("res://scenes/offline_match.tscn")
		await scene_changed
		var g=current_scene.game
		for rally in 12:
			var receiving:int=1-g.service_team
			var rot:int=g.setter_zones[receiving]
			for i in g.slots_for(receiving):
				var role:int=g.lineup_role(i)
				if not career or receiving!=0: assert(role==(i+3)%6)
				if formations.receive_libero(role,rot): assert(g.players[i].attributes.position=="Libero")
				elif role in [2,5]: assert(g.players[i].attributes.position==formations.ROLES[role])
				var expected=formations.layout(session.game_options,rot,false)[role]
				assert(g.players[i].position.is_equal_approx(formations.on_court(expected)))
				assert(g.formation_home(i,true).is_equal_approx(formations.on_court(formations.layout(session.game_options,rot,true)[role])))
			assert(formations.zone(g.lineup_role(g.server_index()),g.setter_zones[g.service_team])==1)
			g.phase=g.Phase.LIVE
			g.award(receiving,"Side out")
			assert(g.setter_zones[receiving]==posmod(rot-2,6)+1)
			g.begin_point()
		assert(g.setter_zones==[1,1])
		if career:
			assert(g.players[0].attributes.position=="Libero")
			assert(g.players[0].display_name==session.offline_roster[0].name)
	print("PASS: 12 editable layouts persisted, both team frames, 12 side-outs in each of regular and career 6v6")
	quit()
