extends Control

const ReplayControls=preload("res://scripts/replay_controls.gd")
var live_camera:=Transform3D.IDENTITY
var live_fov:=55.
var timeline:=HSlider.new()
const Xbox = preload("res://scripts/xbox_controls.gd")
const Player = preload("res://scripts/volleyball_player.gd")
const Venue = preload("res://scripts/match_venue.gd")
const Kit = preload("res://scripts/practice_kit.gd")
var world := Node3D.new()
var preview := Control.new()
var preview_player: Node3D
var camera := Camera3D.new()
var game := preload("res://scripts/volleyball_match.gd").new()
var ground: RefCounted
var board := Label.new()
var status := Label.new()
var footer := HBoxContainer.new()
var ref: Node3D
var whistle := preload("res://scripts/official_whistle.gd").new()
var authorized := false
var replay_notice := ""
var replay_notice_until := 0
var signaled_rally := -1
var last_prompt := ""
var banner := Label.new()
var rally_end_menu := HBoxContainer.new()

func _ready() -> void:
	MenuPresentation.set_music(false)
	var config:Dictionary=StorySession.match_preference("exhibition",{})
	add_child(world)
	var where:=clampi(config.get("venue",0),0,2)
	if StorySession.career_scrimmage: where=0
	var court=Venue.build(world,where,clampi(config.get("crowd",16),0,96))
	build_officials(court)
	world.add_child(camera)
	camera.current=true
	camera.position=Vector3(0,6.0,-15.3)
	camera.fov=StorySession.game_options.get_value("tryout_camera","Field of view",55.)
	camera.look_at(Vector3(0,.90,.4))
	add_child(preview)
	preview.mouse_filter=Control.MOUSE_FILTER_IGNORE
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview_player=Player.new()
	world.add_child(preview_player)
	ground=preload("res://scripts/preview_player_control.gd").new(self,true)
	var away:=StorySession.offline_controller==1
	game.exhibition=true
	game.spectator=StorySession.offline_controller==-1
	game.side_names=["Away","Home"] if away else ["Home","Away"]
	game.win_score=5 if StorySession.career_scrimmage else clampi(config.get("points",21),1,99)
	world.add_child(game)
	build_hud()
	game.configure(preview_player,board,status,"Offline",StorySession.offline_away_size if away else StorySession.offline_size,false,false,StorySession.offline_size if away else StorySession.offline_away_size)
	game.replay.speed=.25
	game.set_ball_sound(true)
	game.update_score()
	game.held_input.row.offset_top=16
	game.serve_style=3
	game.set_serve_style(3)
	refresh_prompts()

func build_officials(court:Node3D) -> void:
	var stand:=StandardMaterial3D.new()
	stand.albedo_color=Color("395565")
	court.box("Referee platform",Vector3(1.1,.14,1.05),Vector3(5.66,1.28,4),stand)
	for x in [5.24,6.08]:
		for z in [3.62,4.38]:
			court.box("Platform leg",Vector3(.06,1.26,.06),Vector3(x,.64,z),stand)
	ref=official(Vector3(5.66,1.36,4),-PI/2)
	whistle.fit_whistle(ref.skeleton)
	whistle.sound.volume_db=0.
	official(Vector3(-5.7,.045,4),PI/2)
	for pos in [Vector3(-4.95,.045,-5.6),Vector3(4.95,.045,13.6)]:
		var judge=official(pos,atan2(-pos.x,4-pos.z))
		var grip:=BoneAttachment3D.new()
		judge.skeleton.add_child(grip)
		grip.bone_name="hand_r"
		var flag:=MeshInstance3D.new()
		var cloth:=BoxMesh.new()
		cloth.size=Vector3(.26,.24,.012)
		flag.mesh=cloth
		var red:=StandardMaterial3D.new()
		red.albedo_color=Color("e54336")
		flag.material_override=red
		grip.add_child(flag)
		flag.position=Vector3(.10,-.14,0)

func official(pos:Vector3,yaw:float) -> Node3D:
	var person:=Player.new()
	world.add_child(person)
	person.position=pos
	person.rotation.y=yaw
	Kit.apply(person,true)
	person.shirt_fabric.set_shader_parameter("fabric",Color("e8ece9"))
	person.get_node("DirectionArrows").hide()
	person.play_action("base/Idle",0)
	person.animator.advance(0)
	person.animator.pause()
	return person

func build_hud() -> void:
	var plate:=PanelContainer.new()
	plate.position=Vector2(22,48)
	plate.mouse_filter=Control.MOUSE_FILTER_IGNORE
	plate.add_theme_stylebox_override("panel",MenuPresentation.box(Color("0d1c2cec"),Color("68d7bd"),4))
	add_child(plate)
	var box:=VBoxContainer.new()
	plate.add_child(box)
	MenuPresentation.section_label(box,"%dv%d   /   First to %d   /   Win by two"%[StorySession.offline_size,StorySession.offline_away_size,game.win_score])
	box.add_child(board)
	board.add_theme_font_size_override("font_size",24)
	box.add_child(status)
	status.add_theme_font_size_override("font_size",15)
	var rail:=PanelContainer.new()
	add_child(rail)
	rail.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	rail.grow_horizontal=Control.GROW_DIRECTION_BOTH
	rail.grow_vertical=Control.GROW_DIRECTION_BEGIN
	rail.offset_top=-55
	rail.offset_bottom=-14
	rail.add_theme_stylebox_override("panel",MenuPresentation.box(Color("091927e8"),Color("61cfb6"),2))
	var replay_layout:=VBoxContainer.new()
	rail.add_child(replay_layout)
	replay_layout.add_child(footer)
	replay_layout.add_child(timeline)
	timeline.focus_mode=Control.FOCUS_NONE
	timeline.step=.001
	timeline.hide()
	timeline.value_changed.connect(func(value:float):
		if game.replay.active:
			game.replay.playing=false
			game.replay.seek(game,value))
	footer.add_theme_constant_override("separation",13)
	add_child(banner)
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	banner.grow_horizontal=Control.GROW_DIRECTION_BOTH
	banner.offset_top=65
	banner.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size",28)
	banner.add_theme_constant_override("outline_size",6)
	banner.text=("Your position / "+str(StorySession.offline_roster[0].position)) if StorySession.career_scrimmage else "Waiting for the whistle"
	add_child(rally_end_menu)
	rally_end_menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	rally_end_menu.grow_horizontal=Control.GROW_DIRECTION_BOTH
	rally_end_menu.hide()
	for title in ["Rematch","My Career" if StorySession.career_scrimmage else "Match setup"]:
		var b:=Button.new()
		b.text=title
		rally_end_menu.add_child(b)
		if title=="Rematch": b.pressed.connect(restart_activity)
		else: b.pressed.connect(leave_match)

func restart_activity() -> void:
	MenuPresentation.load_scene(scene_file_path)

var timeouts_left:=2

func can_take_timeout() -> bool:
	return authorized and timeouts_left>0 and game.phase in [game.Phase.READY,game.Phase.DEAD] and not game.replay.active

func take_timeout() -> void:
	if not can_take_timeout(): return
	timeouts_left-=1
	for athlete in game.players: athlete.stamina.recover(30.)

func leave_match() -> void:
	if StorySession.career_scrimmage:
		CareerSession.tournament=""
		StorySession.career_scrimmage=false
		MenuPresentation.load_scene("res://scenes/story.tscn")
		return
	MenuPresentation.return_page="Match setup"
	MenuPresentation.load_scene("res://scenes/main.tscn")

func refresh_prompts() -> void:
	var entries:Array
	var keys:String
	if game.replay.active:
		entries=[["LT","Rewind"],["RT","Advance"],[JOY_BUTTON_A,"Play / pause"],["D-pad Left/Right","Frame"],["LS","Move"],["RS","Look"],[JOY_BUTTON_LEFT_STICK,"Save"],[JOY_BUTTON_RIGHT_STICK,"Speed"],["View","Return"]]
		keys="Space  Play / pause      ← / →  Frame      F5  Save      Tab  Speed      R  Return"
	elif game.spectator:
		entries=[["View","Replay"],[JOY_BUTTON_START,"Pause"]]
		keys="R  Replay      Esc  Pause"
	else:
		match game.manual.context():
			"serve":
				if game.serve_pending:
					entries=[["Move","Aim"],[game.manual.service.Camp.FACE[3-game.serve_style],"Release to serve"]]
					keys="Mouse  Aim     Release toss button to serve"
				else:
					entries=[["Move","Walk"],[JOY_BUTTON_A,"Spin"],[JOY_BUTTON_B,"Jump float"],[JOY_BUTTON_X,"Standing float"],[JOY_BUTTON_Y,"Underhand"],["Aim","Aim"],["D-pad Left/Right","Spin"]]
					keys="WASD  Walk     Space  Spin     L  Jump float     J  Standing float     I  Underhand     Mouse  Aim     Arrows  Spin"
			"set":
				entries=[[JOY_BUTTON_X,"Left"],[JOY_BUTTON_Y,"Middle"],[JOY_BUTTON_B,"Back"],[JOY_BUTTON_LEFT_SHOULDER,"Jump set"],[JOY_BUTTON_RIGHT_SHOULDER,"Height"],["Aim","Bump set"],[JOY_BUTTON_LEFT_STICK,"Arc"]]
				keys="Hold J / I / L  Set left / middle / back     Z  Jump set     C  Height     V  Arc"
			"attack":
				entries=[[JOY_BUTTON_X,"Left"],[JOY_BUTTON_Y,"Middle"],[JOY_BUTTON_B,"Right"],["Move","Aim"],[JOY_BUTTON_LEFT_SHOULDER,"Roll"],[JOY_BUTTON_RIGHT_SHOULDER,"Tip"]]
				if game.flight_kind=="pass": entries.push_front([JOY_BUTTON_A,"Call for set"])
				keys="Q  Call for set     Hold Space / Y / B  Attack left / middle / right     Release to time     Z  Roll     C  Tip"
			"block":
				entries=[[JOY_BUTTON_A,"Load / release to jump"],["Move","Move / air lean"],["LT","Left reach"],["RT","Right reach"]]
				keys="Space  Load / release to block     WASD  Move"
			"receive":
				entries=[["Move","Move"],["LT","Shuffle"],["RT","Sprint"],[JOY_BUTTON_A,"Hold / release to pass or dig"],["View","Replay"]]
				keys="WASD  Move     Ctrl  Shuffle     Shift  Sprint     Hold Space / release at contact     R  Replay"
			_:
				entries=[["View","Replay"],[JOY_BUTTON_START,"Pause"]]
				keys="R  Replay     Esc  Pause"
	if not game.replay.active and not game.spectator:
		if game.manual.context()=="serve":
			var spins:Array=[[JOY_BUTTON_DPAD_UP,"Topspin"],[JOY_BUTTON_DPAD_LEFT,"Left spin"],[JOY_BUTTON_DPAD_RIGHT,"Right spin"],[JOY_BUTTON_DPAD_DOWN,"Float"]]
			entries=spins
			keys="↑  Topspin     ←  Left spin     →  Right spin     ↓  Float"
		elif game.manual.context()=="attack":
			var tempo_label:="Set tempo %d"%game.manual.requested_tempo
			entries=[[JOY_BUTTON_DPAD_UP,"Higher"],[JOY_BUTTON_DPAD_DOWN,tempo_label+" · Lower"]]
			keys="↑ / ↓   "+tempo_label
		else:
			entries=[]
			keys=""
	elif game.spectator and not game.replay.active:
		entries=[]
		keys=""
	footer.get_parent().get_parent().visible=not keys.is_empty()
	var token:=keys+str(game.serve_style)+str(Xbox.keyboard_prompts())
	if token==last_prompt: return
	last_prompt=token
	Xbox.prompts(footer,[] if Xbox.keyboard_prompts() else entries)
	if Xbox.keyboard_prompts():
		var label:=Label.new()
		label.text=keys
		footer.add_child(label)

var greeting_rally := -1
var greeting_age := 0.
var skip_age := 0.
var formation_spots: Array[Vector3] = []
var point_end_spots: Array[Vector3] = []

func greet_between_points(delta:float) -> bool:
	if not game.six_on_six() or game.replay.active: return false
	if game.phase not in [game.Phase.READY,game.Phase.FINISHED]: return false
	if greeting_rally!=game.rallies:
		greeting_rally=game.rallies
		greeting_age=0.
		skip_age=0.
		formation_spots.clear()
		for i in game.players.size():
			formation_spots.append(game.players[i].position)
			if game.phase==game.Phase.READY and point_end_spots.size()==game.players.size():
				game.players[i].position=point_end_spots[i]
	if formation_spots.is_empty(): return false
	greeting_age+=delta
	var pads:=Input.get_connected_joypads()
	var held:=Input.is_key_pressed(KEY_SPACE) or (pads.size()>0 and Input.is_joy_button_pressed(pads[0],Xbox.physical(JOY_BUTTON_A)))
	skip_age=skip_age+delta if held else 0.
	var returning:=greeting_age>=3.6
	var settled:=true
	for i in game.players.size():
		var actor=game.players[i]
		var partner=game.players[i^1]
		var angle:=TAU*floori((i%6)/2.)/3.
		var radial:=Vector3(sin(angle),0.,cos(angle))
		var spot:=Vector3(0,.04,-.9)+radial*1.05+Vector3(radial.z,0.,-radial.x)*(.42 if i%2==0 else -.42)
		var destination:=formation_spots[i] if returning else spot
		var travel:Vector3=destination-actor.position
		var moving:=travel.length()>.035
		settled=settled and not moving
		var face:Vector3=travel if moving else (Vector3.BACK if returning else partner.position-actor.position)
		if not face.slide(Vector3.UP).is_zero_approx():
			actor.rotation.y=rotate_toward(actor.rotation.y,atan2(face.x,face.z),delta*5.)
		var pace:=minf(4.1,sqrt(8.*travel.length())) if moving else 0.
		var before:Vector3=actor.position
		actor.position=actor.position.move_toward(destination,delta*pace)
		actor.animator.speed_scale=1.
		actor.play_ground_gait(actor.position.distance_to(before)/maxf(delta,.0001))
		actor.animator.advance(delta)
		if not moving and not returning and greeting_age>2.0 and actor.position.distance_to(partner.position)<1.1:
			var weight:=smoothstep(2.,2.6,greeting_age)*(1.-smoothstep(3.,3.55,greeting_age))
			var palm:Vector3=actor.global_position.lerp(partner.global_position,.5)
			palm.y=minf(actor.height_cm,partner.height_cm)*.009
			actor.pose_high_five(palm,weight)
	if skip_age>=.55 or (returning and settled):
		for i in game.players.size():
			game.players[i].position=formation_spots[i]
			game.players[i].rotation.y=0.
		formation_spots.clear()
		banner.hide()
		return false
	banner.text="Team huddle"
	banner.show()
	return true

func _process(delta:float) -> void:
	if not is_instance_valid(ground) or is_instance_valid(MenuPresentation.loading_screen): return
	if greet_between_points(delta): return
	if not game.replay.active and game.phase==game.Phase.READY and signaled_rally!=game.rallies:
		signaled_rally=game.rallies
		authorized=false
		whistle.signal_drill(ref)
		banner.text=("Your position / "+str(StorySession.offline_roster[0].position)) if StorySession.career_scrimmage else "Waiting for the whistle"
		banner.show()
	if whistle.signal_time>=0 and not game.replay.active:
		whistle.step_whistle(ref,delta)
		if not authorized and whistle.signal_time>=.74:
			authorized=true
			banner.text="Your serve" if game.is_human(game.server_index()) else str(game.side_names[game.service_team])+" to serve"
	if not authorized and game.manual and game.phase==game.Phase.READY and not game.replay.active:
		game.manual_ready_movement(delta,ground,false)
	if authorized or game.replay.active:
		if not game.spectator and not game.replay.active and game.manual.context()=="receive": aim_stick(delta)
		if game.replay.active:
			var pads:=Input.get_connected_joypads()
			var pad:int=pads[0] if not pads.is_empty() else -1
			ReplayControls.move_camera(camera,pad,delta)
			var scrub:=ReplayControls.scrub(pad)
			if scrub!=0.:
				game.replay.playing=false
				game.replay.seek(game,game.replay.clock+delta*scrub)
		if game.phase==game.Phase.DEAD and game.six_on_six():
			point_end_spots.resize(game.players.size())
			for i in game.players.size(): point_end_spots[i]=game.players[i].position
		game.tick_match(delta,ground)
	if game.replay.active:
		timeline.max_value=game.replay.duration()
		timeline.set_value_no_signal(game.replay.clock)
		banner.text=replay_notice if Time.get_ticks_msec()<replay_notice_until else "Replay   ·   "+str(game.replay.speed)+"x"
		if Time.get_ticks_msec()>=replay_notice_until and game.replay_meter.has("label"):
			banner.text=game.replay_meter.label
		banner.show()
	elif game.manual and game.match_clock<game.manual.feedback_until:
		banner.text=game.manual.feedback_text
		banner.show()
	elif game.manual and game.match_clock<game.manual.call_until:
		banner.text=game.manual.call_notice
		banner.show()
	elif game.phase!=game.Phase.READY or game.serve_pending: banner.hide()
	if game.manual and authorized and game.phase==game.Phase.READY and not game.serve_pending and game.is_human(game.server_index()) and not game.replay.active:
		status.text="%s  /  %s"%[game.manual.service.Camp.LABELS[3-game.serve_style],game.manual.service.Camp.SPIN_LABELS[game.manual.service.spin]]
	status.visible=game.replay.active or (authorized and (game.phase!=game.Phase.LIVE))
	if game.phase==game.Phase.FINISHED and not game.replay.active and not rally_end_menu.visible:
		rally_end_menu.show()
		rally_end_menu.get_child(0).grab_focus()
	refresh_prompts()

func aim_stick(delta:float) -> void:
	var pads:=Input.get_connected_joypads()
	if pads.is_empty(): return
	var dir:=Vector2(Input.get_joy_axis(pads[0],JOY_AXIS_RIGHT_X),-Input.get_joy_axis(pads[0],JOY_AXIS_RIGHT_Y))
	if dir.length()<.18: return
	var target:Vector3=game.aim_point if game.aim_point.is_finite() else Vector3(0,.055,8)
	game.set_aim(Vector3(clampf(target.x-dir.x*9.*delta,-6.,6.),.055,clampf(target.z+dir.y*12.*delta,-4.,14.5)))

func _notification(what:int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_PAUSED] and is_instance_valid(game) and game.manual:
		game.manual.clear_input()

func toggle_match_replay() -> void:
	if game.replay.active:
		camera.global_transform=live_camera
		camera.fov=live_fov
	else:
		live_camera=camera.global_transform
		live_fov=camera.fov
	if game.manual: game.manual.clear_input()
	game.replay.freeze_here(game)
	timeline.visible=game.replay.active
	refresh_prompts()

func _input(event:InputEvent) -> void:
	if not formation_spots.is_empty() and not game.replay.active: return
	if game.replay.active and ReplayControls.mouse_camera(camera,event):
		get_viewport().set_input_as_handled()
		return
	if game.manual==null or game.replay.active or get_tree().paused or is_instance_valid(MenuPresentation.loading_screen): return
	if game.phase in [game.Phase.READY,game.Phase.LIVE] and game.manual.handle(event):
		get_viewport().set_input_as_handled()

func _unhandled_input(event:InputEvent) -> void:
	if not is_instance_valid(ground) or is_instance_valid(MenuPresentation.loading_screen): return
	if event is InputEventMouseMotion and not game.spectator and not game.replay.active:
		var src:=camera.project_ray_origin(event.position)
		var dir:=camera.project_ray_normal(event.position)
		var hit=Plane(Vector3.UP,.055).intersects_ray(src,dir)
		if hit is Vector3: game.set_aim(hit)
		return
	var down:bool
	var action:String
	if event is InputEventJoypadButton:
		var devices:=Input.get_connected_joypads()
		if devices.size() and event.device!=devices[0]: return
		down=event.pressed
		if event.button_index==JOY_BUTTON_BACK: action="replay"
		elif game.replay.active and event.button_index==Xbox.physical(JOY_BUTTON_LEFT_STICK): action="save"
		elif event.button_index==Xbox.physical(JOY_BUTTON_RIGHT_STICK): action="speed"
		elif event.button_index==JOY_BUTTON_DPAD_LEFT: action="previous"
		elif event.button_index==JOY_BUTTON_DPAD_RIGHT: action="next"
		elif event.button_index==Xbox.physical(JOY_BUTTON_A): action="jump"
		elif event.button_index==Xbox.physical(JOY_BUTTON_X): action="forearm"
		elif event.button_index==Xbox.physical(JOY_BUTTON_Y): action="hands"
	elif event is InputEventKey and not event.echo:
		down=event.pressed
		action={KEY_SPACE:"jump",KEY_Q:"forearm",KEY_E:"hands",KEY_R:"replay",KEY_F5:"save",KEY_TAB:"speed",KEY_LEFT:"previous",KEY_RIGHT:"next"}.get(event.keycode,"")
	if action.is_empty(): return
	if not formation_spots.is_empty() and action!="replay": return
	if action=="replay" and down: toggle_match_replay()
	elif game.replay.active:
		if down and action=="jump":
			if game.replay.clock>=game.replay.duration(): game.replay.seek(game,0.)
			game.replay.playing=not game.replay.playing
		if down and action=="save":
			var path:String=game.save_reviewed_rep("Match",game.rallies,camera,Vector3(0,.9,.4))
			replay_notice="Replay saved" if not path.is_empty() else "Could not save replay"
			replay_notice_until=Time.get_ticks_msec()+1500
		if down and action=="speed":
			var speeds:=[.25,.125,.0625,1.,.5]
			game.replay.speed=speeds[(speeds.find(game.replay.speed)+1)%speeds.size()]
		if down and action in ["previous","next"]: game.replay.step_frame(game,-1 if action=="previous" else 1)
	else: return
	get_viewport().set_input_as_handled()
