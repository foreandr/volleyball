extends Control

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
var serve_types := ["Underhand","Standing float","Jump float","Spin serve"]
var last_prompt := ""
var banner := Label.new()
var rally_end_menu := HBoxContainer.new()

func _ready() -> void:
	MenuPresentation.set_music(false)
	var config:Dictionary=StorySession.match_preference("exhibition",{})
	add_child(world)
	var where:=clampi(config.get("venue",0),0,2)
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
	game.win_score=clampi(config.get("points",21),1,99)
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
	whistle.sound.unit_size=22.
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
	rail.add_child(footer)
	footer.add_theme_constant_override("separation",13)
	add_child(banner)
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	banner.grow_horizontal=Control.GROW_DIRECTION_BOTH
	banner.offset_top=65
	banner.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size",28)
	banner.add_theme_constant_override("outline_size",6)
	banner.text="Waiting for the whistle"
	add_child(rally_end_menu)
	rally_end_menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	rally_end_menu.grow_horizontal=Control.GROW_DIRECTION_BOTH
	rally_end_menu.hide()
	for title in ["Rematch","Match setup"]:
		var b:=Button.new()
		b.text=title
		rally_end_menu.add_child(b)
		if title=="Rematch": b.pressed.connect(restart_activity)
		else: b.pressed.connect(leave_match)

func restart_activity() -> void:
	MenuPresentation.load_scene(scene_file_path)

func leave_match() -> void:
	MenuPresentation.return_page="Match setup"
	MenuPresentation.load_scene("res://scenes/main.tscn")

func refresh_prompts() -> void:
	var entries:Array
	var keys:String
	if game.replay.active:
		entries=[[JOY_BUTTON_A,"Play / pause"],["D-pad Left/Right","Frame"],[JOY_BUTTON_X,"Save"],[JOY_BUTTON_RIGHT_STICK,"Speed"],["View","Return"]]
		keys="Space  Play / pause      ← / →  Frame      F5  Save      Tab  Speed      R  Return"
	elif game.spectator:
		entries=[["View","Replay"],[JOY_BUTTON_START,"Pause"]]
		keys="R  Replay      Esc  Pause"
	elif game.phase==game.Phase.READY and game.is_human(game.server_index()) and not game.serve_pending and authorized:
		entries=[[JOY_BUTTON_A,"Serve"],["D-pad Left/Right",serve_types[game.serve_style]],["Aim","Aim"],[JOY_BUTTON_START,"Pause"]]
		keys="Space  Serve      ← / →  "+str(serve_types[game.serve_style])+"      Mouse  Aim      Esc  Pause"
	else:
		entries=[["Move","Move"],["LT","Shuffle"],["RT","Sprint"],[JOY_BUTTON_A,"Jump"],[JOY_BUTTON_X,"Forearm"],[JOY_BUTTON_Y,"Hands"],["View","Replay"],[JOY_BUTTON_START,"Pause"]]
		keys="WASD  Move      Ctrl  Shuffle      Shift  Sprint      Space  Jump      Q / E  Receive      R  Replay      Esc  Pause"
	var token:=keys+str(Xbox.keyboard_prompts())
	if token==last_prompt: return
	last_prompt=token
	Xbox.prompts(footer,[] if Xbox.keyboard_prompts() else entries)
	if Xbox.keyboard_prompts():
		var label:=Label.new()
		label.text=keys
		footer.add_child(label)

func _process(delta:float) -> void:
	if not is_instance_valid(ground) or is_instance_valid(MenuPresentation.loading_screen): return
	if not game.replay.active and game.phase==game.Phase.READY and signaled_rally!=game.rallies:
		signaled_rally=game.rallies
		authorized=false
		whistle.signal_drill(ref)
		banner.text="Waiting for the whistle"
		banner.show()
	if whistle.signal_time>=0 and not game.replay.active:
		whistle.step_whistle(ref,delta)
		if not authorized and whistle.signal_time>=.74:
			authorized=true
			banner.text="Your serve" if game.is_human(game.server_index()) else str(game.side_names[game.service_team])+" to serve"
	if authorized or game.replay.active:
		if not game.spectator and not game.replay.active: aim_stick(delta)
		game.tick_match(delta,ground)
	if game.replay.active:
		banner.text=replay_notice if Time.get_ticks_msec()<replay_notice_until else "Replay   ·   "+str(game.replay.speed)+"x"
		banner.show()
	elif game.phase!=game.Phase.READY or game.serve_pending: banner.hide()
	status.visible=game.replay.active or game.phase!=game.Phase.READY or game.serve_pending
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

func toggle_match_replay() -> void:
	game.toggle_replay()
	refresh_prompts()

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
	if action=="replay" and down: toggle_match_replay()
	elif game.replay.active:
		if down and action=="jump": game.replay.playing=not game.replay.playing
		if down and action in ["forearm","save"]:
			var path:String=game.save_reviewed_rep("Match",game.rallies,camera,Vector3(0,.9,.4))
			replay_notice="Replay saved" if not path.is_empty() else "Could not save replay"
			replay_notice_until=Time.get_ticks_msec()+1500
		if down and action=="speed":
			var speeds:=[.25,.125,.0625,1.,.5]
			game.replay.speed=speeds[(speeds.find(game.replay.speed)+1)%speeds.size()]
		if down and action in ["previous","next"]: game.replay.step_frame(game,-1 if action=="previous" else 1)
	elif authorized and not game.spectator:
		if action=="jump": game.input_space(down)
		if action in ["forearm","hands"]:
			game.receive_prepared=down
			if not down: game.input_receive(0 if action=="forearm" else 1)
		if down and action in ["previous","next"] and game.phase==game.Phase.READY:
			game.set_serve_style(posmod(game.serve_style+(-1 if action=="previous" else 1),4))
	get_viewport().set_input_as_handled()
