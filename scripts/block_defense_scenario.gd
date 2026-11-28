extends "res://scripts/offline_match.gd"

const ScenarioMatch=preload("res://scripts/block_scenario_match.gd")
var notes_path:="user://block_defense_positions.jsonl"
var defense:=OptionButton.new()
var offense:=OptionButton.new()
var hitter:=OptionButton.new()
var tempo:=OptionButton.new()
var quality:=OptionButton.new()
var replay_button:=Button.new()
var edit_button:=Button.new()
var note:=Label.new()
var running:=false
var editing:=false
var dragged:=-1
var originals:Array[Vector3]=[]
var setup:Dictionary={}
var session_before:Dictionary={}

func _ready() -> void:
	for key in ["offline_controller","offline_size","offline_away_size","career_scrimmage","offline_roster"]:
		session_before[key]=StorySession.get(key)
	StorySession.offline_controller=-1
	StorySession.offline_size=6
	StorySession.offline_away_size=6
	StorySession.career_scrimmage=false
	var roster:Array[Dictionary]=[]
	for i in 12:
		var member:Dictionary=CareerSession.profile().duplicate(true) if i==0 else {}
		if member.is_empty(): member=preload("res://scripts/player_profile.gd").generate()
		member.position=ScenarioMatch.Formation.ROLES[(i+1)%6]
		roster.append(member)
	StorySession.offline_roster=roster
	game.free()
	game=ScenarioMatch.new()
	super._ready()
	game.instructions.load(game.rules_path)
	var panel:=PanelContainer.new()
	add_child(panel)
	panel.position=Vector2(18,145)
	panel.add_theme_stylebox_override("panel",MenuPresentation.box(Color("101c29ee"),Color("61cfb6"),2))
	var column:=VBoxContainer.new()
	panel.add_child(column)
	MenuPresentation.section_label(column,"Block defense")
	for zone in range(1,7):
		defense.add_item("Defense · setter in %d"%zone,zone)
		offense.add_item("Offense · setter in %d"%zone,zone)
	quality.add_item("In-system pass")
	quality.add_item("Out-of-system pass")
	for value in range(4): tempo.add_item("Set tempo · %d"%value,value)
	for control in [defense,offense,quality,hitter,tempo]: column.add_child(control)
	var saved:Dictionary=StorySession.game_options.get_value("block_defense","setup",{})
	defense.select(clampi(saved.get("defense",3),1,6)-1)
	offense.select(clampi(saved.get("offense",1),1,6)-1)
	tempo.select(clampi(saved.get("tempo",2),0,3))
	quality.select(0 if saved.get("in_system",true) else 1)
	populate_hitters(saved.get("role",1))
	offense.item_selected.connect(func(_i): populate_hitters(hitter.get_selected_id()))
	var run:=Button.new()
	run.text="Run scenario"
	column.add_child(run)
	run.pressed.connect(start_scenario)
	run.grab_focus()
	column.add_child(replay_button)
	replay_button.text="Replay"
	replay_button.disabled=true
	replay_button.pressed.connect(toggle_match_replay)
	column.add_child(edit_button)
	edit_button.text="Pause & place · F2"
	edit_button.disabled=true
	edit_button.pressed.connect(toggle_edit)
	column.add_child(note)
	note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x=190
	banner.hide()
	board.hide()
	status.hide()

func populate_hitters(preferred:int) -> void:
	hitter.clear()
	for role in [1,2,3,4,5]:
		var zone:=ScenarioMatch.Formation.zone(role,offense.get_selected_id())
		var front:=zone in [2,3,4]
		if role in [2,5] and not front: continue
		var route:="Middle" if role in [2,5] else ("Pin" if front else ("Pipe" if role in [1,4] else "Back right"))
		hitter.add_item("%s · %s"%[ScenarioMatch.Formation.ROLES[role],route],role)
	hitter.select(maxi(0,hitter.get_item_index(preferred)))

func start_scenario() -> void:
	if editing: toggle_edit()
	if game.replay.active: toggle_match_replay()
	setup={"defense":defense.get_selected_id(),"offense":offense.get_selected_id(),"role":hitter.get_selected_id(),"in_system":quality.selected==0,"tempo":tempo.get_selected_id()}
	StorySession.game_options.set_value("block_defense","setup",setup.duplicate())
	StorySession.save_options()
	formation_spots.clear()
	game.start_feed(setup.defense,setup.offense,setup.role,setup.in_system,setup.tempo)
	greeting_rally=game.rallies
	signaled_rally=game.rallies
	authorized=true
	running=true
	replay_button.disabled=false
	edit_button.disabled=false
	rally_end_menu.hide()
	note.text=""
	if get_viewport().gui_get_focus_owner(): get_viewport().gui_release_focus()

func toggle_edit() -> void:
	if not running: return
	editing=not editing
	timeline.editable=not editing
	dragged=-1
	if editing:
		if game.replay.active: game.replay.playing=false
		originals.clear()
		for actor in game.players: originals.append(actor.position)
		note.text="Drag a player to teach a position for this phase."
	else:
		for i in originals.size(): game.players[i].position=originals[i]
		note.text=""
	edit_button.text="Finish placement · F2" if editing else "Pause & place · F2"

func _process(delta:float) -> void:
	if editing or not game.replay.active: ReplayControls.move_camera(camera,-1,delta)
	if not running or editing: return
	if not game.replay.active and game.phase in [game.Phase.DEAD,game.Phase.FINISHED]:
		if note.text.is_empty(): note.text="Point complete · run again or review."
		return
	super._process(delta)

func _input(event:InputEvent) -> void:
	if get_tree().paused: return
	if (editing or not game.replay.active) and ReplayControls.mouse_camera(camera,event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.keycode==KEY_F2 and event.pressed and not event.echo:
		toggle_edit()
		get_viewport().set_input_as_handled()
		return
	if not running or editing: return
	super._input(event)

func toggle_match_replay() -> void:
	if editing: toggle_edit()
	if not running: return
	super.toggle_match_replay()
	replay_button.text="Return to rally" if game.replay.active else "Replay"
	if get_viewport().gui_get_focus_owner(): get_viewport().gui_release_focus()

func _unhandled_input(event:InputEvent) -> void:
	if editing and ((event is InputEventKey and event.keycode==KEY_R and event.pressed and not event.echo) or (event is InputEventJoypadButton and event.button_index==JOY_BUTTON_BACK and event.pressed)):
		toggle_match_replay()
		get_viewport().set_input_as_handled()
		return
	if not editing:
		if running: super._unhandled_input(event)
		return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			var nearest:=42.
			for i in game.players.size():
				var at:Vector3=game.players[i].global_position
				var gap:=Geometry2D.get_closest_point_to_segment(event.position,camera.unproject_position(at),camera.unproject_position(at+Vector3.UP*1.6)).distance_to(event.position)
				if gap<nearest:
					nearest=gap
					dragged=i
			if dragged>=0:
				var actor=game.players[dragged]
				var role:String="Libero" if game.active_identities.get(dragged,-1)==6 else ScenarioMatch.Formation.ROLES[game.lineup_role(dragged)]
				note.text="#%d %s · %s · Blocking %d"%[actor.get_meta("school_jersey_number",-1),actor.display_name,role,actor.attributes.Blocking]
		elif dragged>=0:
			if game.players[dragged].position.distance_to(originals[dragged])>.01: save_placement(dragged)
			dragged=-1
	elif dragged>=0 and event is InputEventMouseMotion:
		var point=Plane(Vector3.UP,.04).intersects_ray(camera.project_ray_origin(event.position),camera.project_ray_normal(event.position))
		if point!=null:
			var actor=game.players[dragged]
			var local:Vector3=game.frames[game.team(dragged)].to_local(point)
			actor.position=Vector3(clampf(local.x,-6.,6.),originals[dragged].y,clampf(local.z,-7.,3.9))

func save_placement(index:int) -> void:
	var record:=setup.duplicate()
	var section:String=game.phase_key()
	var clock:float=game.match_clock
	var flight:String=game.flight_kind
	if game.replay.active:
		var frame:Dictionary=game.replay.frames[game.replay.index]
		clock=game.replay.frames.front().time+game.replay.clock
		var trace:Dictionary=frame.get("trace",{})
		section=trace.get("scenario_phase","")
		flight=trace.get("flight",flight)
	record.merge({"time":Time.get_datetime_string_from_system(),"match_seconds":clock,"scenario_phase":section,"edited_slot":index,"flight":flight,"ball_world":[game.ball.global_position.x,game.ball.global_position.y,game.ball.global_position.z],"players":[]})
	for i in game.players.size():
		var actor=game.players[i]
		var at:Vector3=actor.position
		var was:=originals[i]
		record.players.append({"team":game.team(i),"role":("Libero" if game.active_identities.get(i,-1)==6 else ScenarioMatch.Formation.ROLES[game.lineup_role(i)]),"name":actor.display_name,"actual":[was.x,was.y,was.z],"intended":[at.x,at.y,at.z]})
	var file:=FileAccess.open(notes_path,FileAccess.READ_WRITE if FileAccess.file_exists(notes_path) else FileAccess.WRITE)
	if not file:
		note.text="Could not open position notes."
		return
	file.seek_end()
	file.store_line(JSON.stringify(record))
	file.flush()
	if section.is_empty():
		note.text="Saved position note for "+game.players[index].display_name
	elif game.teach(section,index,game.players[index].position)==OK:
		note.text="Taught %s · %s"%[game.players[index].display_name,flight]
	else:
		note.text="Position note saved. AI instruction could not be saved."

func leave_match() -> void:
	MenuPresentation.return_page="Play"
	MenuPresentation.load_scene("res://scenes/main.tscn")

func _exit_tree() -> void:
	for key in session_before: StorySession.set(key,session_before[key])
