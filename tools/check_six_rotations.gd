extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func check_order(marks:PackedVector2Array,rotation:int) -> void:
	var slots:=PackedVector2Array()
	for z in range(1,7): slots.append(marks[posmod(z-rotation,6)])
	assert(slots[3].x<=slots[2].x+.000001 and slots[2].x<=slots[1].x+.000001)
	assert(slots[4].x<=slots[5].x+.000001 and slots[5].x<=slots[0].x+.000001)
	for pair in [Vector2i(4,5),Vector2i(3,6),Vector2i(2,1),Vector2i(4,1),Vector2i(2,5)]:
		assert(slots[pair.x-1].y<=slots[pair.y-1].y+.000001)

func run() -> void:
	var formations=load("res://scripts/six_rotations.gd")
	var session=root.get_node("StorySession")
	var options:=ConfigFile.new()
	change_scene_to_file("res://scenes/formation_editor.tscn")
	await scene_changed
	var editor=current_scene
	for rotation in range(1,7):
		var base:PackedVector2Array=formations.layout(ConfigFile.new(),rotation,true)
		for role in 6:
			var front:bool=formations.zone(role,rotation) in [2,3,4]
			var expected_slot:int=[[3,0],[1,4],[2,5]][role%3][0 if front else 1]
			assert(base[role]==formations.BLOCK_DEFENSE[expected_slot])
		for defense in [false,true]:
			editor.setter_zone=rotation
			editor.defense=defense
			editor.refresh()
			assert(editor.marks.size()==6)
			for role in 6:
				assert(editor.libero_mark(role)==(role in [2,5] and formations.zone(role,rotation) in [1,5,6]))
			if not defense:
				check_order(editor.marks,rotation)
				for role in 6:
					editor.selected=role
					var original:PackedVector2Array=editor.marks.duplicate()
					for corner in [Vector2.ZERO,Vector2.ONE,Vector2.RIGHT,Vector2.DOWN]:
						editor.move_mark(corner)
						check_order(editor.marks,rotation)
						for other in 6:
							if other!=role: assert(editor.marks[other]==original[other])
					editor.marks=original
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
		assert(g.indicators.participants==[g.human])
		for rally in 12:
			var receiving:int=1-g.service_team
			var rot:int=g.setter_zones[receiving]
			for side in 2:
				var liberos:=0
				for i in g.slots_for(side):
					var slot:int=g.lineup_role(i)
					if slot not in [2,5]: continue
					if formations.zone(slot,g.setter_zones[side]) in [1,5,6]:
						assert(g.players[i].attributes.position=="Libero")
						liberos+=1
					else: assert(g.players[i].attributes.position==formations.ROLES[slot])
				assert(liberos==1)
			for i in g.slots_for(receiving):
				var role:int=g.lineup_role(i)
				if not career or receiving!=0: assert(role==(i+3)%6)
				var front:bool=formations.zone(role,rot) in [2,3,4]
				var lane:Vector3=g.attack_lane_for(i)
				if role==0:
					assert(g.back_row_setter(i)==(not front))
					if not front:
						assert(not g.start_second_ball_spike(i))
						g.start_block(i,.27,false,true)
						assert(not g.blocks.has(i))
				if front and role in [1,4]: assert(lane.x<0 if rot==1 else lane.x>0)
				if front and role==3: assert(lane.x>0 if rot==1 else lane.x<0)
				if not front and role in [1,4]: assert(lane.x==0. and lane.z<1.)
				if formations.back_row_libero(role,rot): assert(g.players[i].attributes.position=="Libero")
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
