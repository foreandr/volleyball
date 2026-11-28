extends "res://scripts/offline_match.gd"

const ScenarioMatch=preload("res://scripts/block_scenario_match.gd")
var notes_path:="user://block_defense_positions.jsonl"
var defense:=OptionButton.new()
var offense:=OptionButton.new()
var quality:=OptionButton.new()
var settings:=VBoxContainer.new()
var actions:=HBoxContainer.new()
var run_button:=Button.new()
var reset_button:=Button.new()
var player_panel:=preload("res://scripts/scenario_player_panel.gd").new()
var roster_path:="user://block_defense_roster.cfg"
var options_button:=Button.new()
var resume_button:=Button.new()
var repeat_option:=CheckBox.new()
var selected_tempos:Dictionary={}
var result_label:=Label.new()
var decision_label:=Label.new()
var decision_toggle:=CheckButton.new()
var panel:=PanelContainer.new()
var between_feeds:=0.
var replay_button:=Button.new()
var edit_button:=Button.new()
var note:=Label.new()
var running:=false
var editing:=false
var dragged:=-1
var drag_start:=Vector2.ZERO
var moved_player:=false
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
	game.free()
	game=ScenarioMatch.new()
	game.roster.path=roster_path
	StorySession.offline_roster=game.roster.load_starters(CareerSession.profile())
	super._ready()
	game.instructions.load(game.rules_path)
	add_child(panel)
	panel.position=Vector2(18,112)
	panel.add_theme_stylebox_override("panel",MenuPresentation.box(Color("101c29ee"),Color("61cfb6"),2))
	var column:=VBoxContainer.new()
	column.add_theme_constant_override("separation",6)
	panel.add_child(column)
	var header:=HBoxContainer.new()
	column.add_child(header)
	var title:=Label.new()
	title.text="Block defense"
	title.add_theme_font_size_override("font_size",23)
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(reset_button)
	reset_button.text="Reset"
	reset_button.tooltip_text="Restart this scenario from the serve"
	reset_button.pressed.connect(reset_scenario)
	reset_button.hide()
	column.add_child(settings)
	settings.add_theme_constant_override("separation",6)
	for zone in range(1,7):
		defense.add_item("Defense · S%d"%zone,zone)
		offense.add_item("Offense · S%d"%zone,zone)
	quality.add_item("In-system pass")
	quality.add_item("Out-of-system pass")
	var rotations:=HBoxContainer.new()
	settings.add_child(rotations)
	for control:OptionButton in [defense,offense]:
		control.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		rotations.add_child(control)
	settings.add_child(quality)
	var saved:Dictionary=StorySession.game_options.get_value("block_defense","setup",{})
	defense.select(clampi(saved.get("defense",3),1,6)-1)
	offense.select(clampi(saved.get("offense",1),1,6)-1)
	quality.select(0 if saved.get("in_system",true) else 1)
	selected_tempos=restore_tempos(saved)
	MenuPresentation.section_label(settings,"Attack tempo   /   X = Off")
	var choices:=GridContainer.new()
	choices.columns=6
	choices.add_theme_constant_override("h_separation",5)
	choices.add_theme_constant_override("v_separation",5)
	settings.add_child(choices)
	for route:String in ScenarioMatch.ROUTES:
		var label:=Label.new()
		label.text=route_label(route)
		label.custom_minimum_size.x=87
		choices.add_child(label)
		var group:=ButtonGroup.new()
		for value:int in [0,1,2,3,-1]:
			var cell:=Button.new()
			cell.name=route+("_off" if value<0 else "_"+str(value))
			cell.text="X" if value<0 else str(value)
			cell.tooltip_text=label.text+(" off" if value<0 else " · Tempo %d"%value)
			cell.custom_minimum_size=Vector2(42,32)
			cell.toggle_mode=true
			cell.button_group=group
			cell.button_pressed=selected_tempos[route]==value
			var selected:=StyleBoxFlat.new()
			selected.bg_color=Color("32685f") if value>=0 else Color("774741")
			selected.set_corner_radius_all(4)
			cell.add_theme_stylebox_override("pressed",selected)
			cell.add_theme_stylebox_override("hover_pressed",selected)
			cell.pressed.connect(select_tempo.bind(route,value))
			choices.add_child(cell)
	settings.add_child(repeat_option)
	repeat_option.text="Repeat scenario"
	repeat_option.button_pressed=saved.get("repeat",true)
	settings.add_child(run_button)
	run_button.text="Run scenario"
	run_button.pressed.connect(start_scenario)
	run_button.disabled=not has_enabled_route()
	settings.add_child(resume_button)
	resume_button.text="Back to rally"
	resume_button.hide()
	resume_button.pressed.connect(show_settings.bind(false))
	run_button.grab_focus()
	column.add_child(result_label)
	result_label.hide()
	column.add_child(actions)
	actions.hide()
	actions.add_child(options_button)
	options_button.text="Attack options"
	options_button.pressed.connect(show_settings.bind(true))
	actions.add_child(replay_button)
	replay_button.text="Replay"
	replay_button.disabled=true
	replay_button.pressed.connect(toggle_match_replay)
	actions.add_child(edit_button)
	edit_button.text="Pause & place · F2"
	edit_button.disabled=true
	edit_button.pressed.connect(toggle_edit)
	column.add_child(decision_toggle)
	decision_toggle.text="Show decisions"
	decision_toggle.button_pressed=StorySession.game_options.get_value("block_defense","show_decisions",true)
	decision_toggle.toggled.connect(func(on:bool):
		StorySession.game_options.set_value("block_defense","show_decisions",on)
		StorySession.save_options()
		decision_label.visible=on and running)
	column.add_child(decision_label)
	decision_label.custom_minimum_size.x=300
	decision_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	decision_label.hide()
	column.add_child(note)
	note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x=230
	note.hide()
	banner.hide()
	board.hide()
	status.hide()
	add_child(player_panel)
	player_panel.changed.connect(change_player_stat)

static func route_label(route:String) -> String:
	return route.capitalize()+" side" if route in ["left","right"] else route.capitalize()

static func restore_tempos(saved:Dictionary) -> Dictionary:
	var choices:={"left":2,"middle":0,"pipe":1,"right":2}
	if saved.get("attacks") is Dictionary:
		for lane:String in choices:
			choices[lane]=clampi(int(saved.attacks.get(lane,-1)),-1,3)
	elif saved.has("role"):
		var lane:=ScenarioMatch.Formation.attack_route(int(saved.role),clampi(int(saved.get("offense",1)),1,6))
		if choices.has(lane): choices[lane]=clampi(int(saved.get("tempo",2)),0,3)
	return choices

func has_enabled_route() -> bool:
	for value:int in selected_tempos.values():
		if value>=0: return true
	return false

func select_tempo(route:String,value:int) -> void:
	selected_tempos[route]=value
	run_button.disabled=not has_enabled_route()
	note.text="" if not run_button.disabled else "Choose at least one attack."

func show_settings(open:bool) -> void:
	settings.visible=open
	actions.visible=not open
	result_label.visible=not open
	resume_button.visible=open and running
	panel.reset_size.call_deferred()
	if open: run_button.grab_focus()
	else: options_button.grab_focus()

func selected_setup() -> Dictionary:
	return {"defense":defense.get_selected_id(),"offense":offense.get_selected_id(),"attacks":selected_tempos.duplicate(),"in_system":quality.selected==0,"repeat":repeat_option.button_pressed}

func start_scenario() -> void:
	if not has_enabled_route(): return
	if editing: toggle_edit()
	if game.replay.active: toggle_match_replay()
	setup=selected_setup()
	StorySession.game_options.set_value("block_defense","setup",setup.duplicate())
	StorySession.save_options()
	show_settings(false)
	run_feed(false)

func run_feed(repeating:bool) -> void:
	formation_spots.clear()
	game.start_attack_plan(setup.defense,setup.offense,setup.attacks,setup.in_system,repeating)
	between_feeds=0.
	result_label.text="Waiting for set"
	greeting_rally=game.rallies
	signaled_rally=game.rallies
	authorized=true
	running=true
	reset_button.show()
	replay_button.disabled=false
	edit_button.disabled=false
	rally_end_menu.hide()
	note.text=""

func reset_scenario() -> void:
	if not running: return
	if editing: toggle_edit()
	if game.replay.active: toggle_match_replay()
	if settings.visible: show_settings(false)
	run_feed(false)

func pick_player(mouse:Vector2) -> int:
	var picked:=-1
	var best:=INF
	var front:=INF
	for i in game.players.size():
		var actor=game.players[i]
		var feet:Vector3=actor.global_position
		if camera.is_position_behind(feet): continue
		var base:=camera.unproject_position(feet)
		var head:=camera.unproject_position(feet+Vector3.UP*actor.height_cm*.01)
		var radius:=clampf(head.distance_to(base)*.19,10.,36.)
		var gap:=Geometry2D.get_closest_point_to_segment(mouse,base,head).distance_to(mouse)/radius
		var depth:=camera.global_position.distance_to(feet)
		if gap<=1. and (gap<best-.08 or (absf(gap-best)<=.08 and depth<front)):
			picked=i
			best=gap
			front=depth
	return picked

func inspect_player(i:int) -> void:
	var side:int=game.team(i)
	var identity:int=game.player_identity(i)
	player_panel.display(side,identity,game.players[i].get_meta("school_jersey_number"),game.roster.profile(side,identity))

func change_player_stat(side:int,identity:int,field:String,value:Variant) -> void:
	var result:Error=game.edit_player(side,identity,field,value)
	var profile:Dictionary=game.roster.profile(side,identity)
	var jersey:int=profile.get("jersey_number",502+side*6+posmod(identity-1,6))
	player_panel.display(side,identity,jersey,profile)
	if result!=OK:
		player_panel.message.text="Could not save · "+error_string(result)
		player_panel.message.show()

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
	if note.visible==note.text.is_empty():
		note.visible=not note.text.is_empty()
		panel.reset_size.call_deferred()
	if (editing or not game.replay.active) and not get_viewport().gui_get_focus_owner() is LineEdit:
		ReplayControls.move_camera(camera,-1,delta)
	if not running or editing or settings.visible: return
	if not game.replay.active and game.phase in [game.Phase.DEAD,game.Phase.FINISHED]:
		if not str(game.last_point.get("net_attack_alert","")).is_empty(): note.text="Net attack alert · recording queued"
		if setup.get("repeat",false):
			between_feeds+=delta
			if between_feeds>=3.: run_feed(true)
		elif note.text.is_empty(): note.text="Point complete"
		update_decision_label()
		return
	super._process(delta)
	var route:String=game.released_route
	var set_tempo:int=game.released_tempo
	if game.replay.active:
		var trace:Dictionary=game.replay.frames[game.replay.index].get("trace",{})
		route=trace.get("lab_route","")
		set_tempo=trace.get("lab_tempo",-1)
	update_decision_label()
	result_label.text="Waiting for set" if route.is_empty() else "%s  ·  Tempo %d"%[route_label(route),set_tempo]

func update_decision_label() -> void:
	decision_label.visible=running and decision_toggle.button_pressed
	if not decision_label.visible:
		result_label.visible=running and not settings.visible
		return
	var set_read:String=game.set_decision
	var swing_read:String=game.attack_decision
	if game.replay.active:
		var sample:Dictionary=game.replay.frames[game.replay.index].get("trace",{})
		set_read=sample.get("set_decision","")
		swing_read=sample.get("attack_decision","")
	decision_label.text="\n".join(PackedStringArray([set_read,swing_read])).strip_edges()
	result_label.visible=not settings.visible and set_read.is_empty()

func _input(event:InputEvent) -> void:
	if get_tree().paused: return
	if event is InputEventMouse and player_panel.visible and player_panel.get_global_rect().has_point(event.position): return
	if event is InputEventKey and get_viewport().gui_get_focus_owner() is LineEdit: return
	if (editing or not game.replay.active) and ReplayControls.mouse_camera(camera,event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.keycode==KEY_F2 and event.pressed and not event.echo:
		toggle_edit()
		get_viewport().set_input_as_handled()
		return
	if not running or editing or settings.visible: return
	super._input(event)

func toggle_match_replay() -> void:
	if editing: toggle_edit()
	if not running: return
	super.toggle_match_replay()
	if not game.replay.active: game.apply_replay_edits()
	replay_button.text="Return to rally" if game.replay.active else "Replay"
	if game.replay.active: get_viewport().gui_release_focus()
	elif not settings.visible: options_button.grab_focus()

func _unhandled_input(event:InputEvent) -> void:
	if event is InputEventKey and get_viewport().gui_get_focus_owner() is LineEdit: return
	if not editing and event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		var i:=pick_player(event.position)
		if i>=0:
			inspect_player(i)
			get_viewport().set_input_as_handled()
			return
	if settings.visible: return
	if editing and ((event is InputEventKey and event.keycode==KEY_R and event.pressed and not event.echo) or (event is InputEventJoypadButton and event.button_index==JOY_BUTTON_BACK and event.pressed)):
		toggle_match_replay()
		get_viewport().set_input_as_handled()
		return
	if not editing:
		if running: super._unhandled_input(event)
		return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			dragged=pick_player(event.position)
			drag_start=event.position
			moved_player=false
			if dragged>=0:
				var actor=game.players[dragged]
				var role:String="Libero" if game.active_identities.get(dragged,-1)==6 else ScenarioMatch.Formation.ROLES[game.lineup_role(dragged)]
				note.text="#%d %s · %s · Blocking %d"%[actor.get_meta("school_jersey_number",-1),actor.display_name,role,actor.attributes.Blocking]
		elif dragged>=0:
			if moved_player: save_placement(dragged)
			else: inspect_player(dragged)
			dragged=-1
	elif dragged>=0 and event is InputEventMouseMotion:
		if not moved_player and event.position.distance_to(drag_start)<4.: return
		var point=Plane(Vector3.UP,.04).intersects_ray(camera.project_ray_origin(event.position),camera.project_ray_normal(event.position))
		if point!=null:
			moved_player=true
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
