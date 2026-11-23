extends Control

const Court = preload("res://scripts/preview_court.gd")
const Player = preload("res://scripts/volleyball_player.gd")
const Hands = preload("res://scripts/hand_setting_pose.gd")
const TARGETS := ["Left side","Middle","Pipe","Right side"]
const TEMPOS := ["Normal","High","Fast"]
const BUTTONS := [JOY_BUTTON_X,JOY_BUTTON_Y,JOY_BUTTON_A,JOY_BUTTON_B]
const KEYS := [KEY_J,KEY_I,KEY_K,KEY_L]
const PINS := [Vector3(3.65,2.9,3.1),Vector3(0.55,3.0,3.2),Vector3(0,2.9,1.3),Vector3(-3.65,2.9,3.1)]
const STARTS := [Vector3(4.15,0.04,0),Vector3(1.6,0.04,1),Vector3(0,0.04,-1.9),Vector3(-4.15,0.04,0)]
const DURATION := [1.05,1.65,0.68]
const APEX := [1.1,2.5,0.32]
const LINES := ["Welcome to the team, %s. I’m Coach Ellis.","You’re trying out at setter. Get under the first pass and show me where you want your hitters.","We’ll start at the left pin. Give me two at each tempo. Then we’ll work across the net."]
var phase := ""
var elapsed := 0.0
var clock := 0.0
var skip_time := 0.0
var camera := Camera3D.new()
var world := Node3D.new()
var setter: Node3D
var passer: Node3D
var coach: Node3D
var hitters: Array[Node3D] = []
var landing := MeshInstance3D.new()
var ball := MeshInstance3D.new()
var panel := PanelContainer.new()
var title := Label.new()
var message := Label.new()
var hint := Label.new()
var skip := TextureProgressBar.new()
var finish := Button.new()
var rep := 0
var held := -1
var last_flick := 0
var flick_at := -10.0
var source := Vector3.ZERO
var catch_point := Vector3.ZERO
var target := 0
var tempo := 0
var success := false
var feedback := ""
var flight_time := 1.0
var contact_sound := AudioStreamPlayer.new()

func athlete(at: Vector3,color: String) -> Node3D:
	var actor := Player.new()
	actor.team_color = Color(color)
	actor.position = at
	world.add_child(actor)
	actor.get_node("DirectionArrows").hide()
	return actor

func _ready() -> void:
	MenuPresentation.set_music(false)
	add_child(world)
	world.add_child(Court.new())
	Court.add_preview_lighting(world)
	world.add_child(camera)
	camera.current = true
	setter = athlete(Vector3(-0.8,0.04,1.1),"e97937")
	setter.apply_profile(CareerSession.profile())
	setter.play_action("idle")
	passer = athlete(Vector3(2,0.04,-3.6),"236b80")
	for start in STARTS: hitters.append(athlete(start,"236b80"))
	coach = athlete(Vector3(-2.4,0.04,1.8),"242c3a")
	var mesh := SphereMesh.new()
	mesh.radius = 0.105
	mesh.height = 0.21
	ball.mesh = mesh
	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color("ffeaa9")
	ball.material_override = leather
	world.add_child(ball)
	contact_sound.stream = preload("res://assets/audio/set_touch.wav")
	add_child(contact_sound)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.53
	ring.outer_radius = 0.58
	landing.mesh = ring
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color("7effdf")
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	landing.material_override = paint
	world.add_child(landing)
	landing.hide()
	build_hud()
	rep = CareerSession.progress()
	match CareerSession.stage():
		"intro": begin("intro")
		"complete": complete()
		_: reset_feed()

func build_hud() -> void:
	panel.anchor_top = 1
	panel.anchor_bottom = 1
	panel.offset_left = 26
	panel.offset_bottom = -22
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.add_theme_stylebox_override("panel",MenuPresentation.box(Color("112534ed"),Color("6de4d1"),4))
	add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	title.add_theme_color_override("font_color",Color("7be3d3"))
	column.add_child(title)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size.x = 620
	message.add_theme_font_size_override("font_size",22)
	column.add_child(message)
	column.add_child(hint)
	finish.text = "Return to My Career"
	finish.pressed.connect(leave)
	column.add_child(finish)
	finish.hide()
	var img := Image.create(54,54,false,Image.FORMAT_RGBA8)
	for y in 54:
		for x in 54:
			var r := Vector2(x-26.5,y-26.5).length()
			img.set_pixel(x,y,Color(1,1,1,clampf(minf(r-19,25-r),0,1)))
	var ring := ImageTexture.create_from_image(img)
	skip.texture_under = ring
	skip.tint_under = Color("445a68")
	skip.texture_progress = ring
	skip.fill_mode = TextureProgressBar.FILL_CLOCKWISE
	skip.tint_progress = Color("72e2cf")
	skip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	skip.offset_left = -86
	skip.offset_top = -88
	skip.offset_right = -32
	skip.offset_bottom = -34
	add_child(skip)
	skip.hide()

func begin(next: String) -> void:
	phase = next
	elapsed = 0
	held = -1

func leave() -> void:
	get_tree().change_scene_to_file("res://scenes/story.tscn")

func reset_feed() -> void:
	begin("feed")
	last_flick = 0
	flick_at = -10
	coach.hide()
	ball.show()
	setter.position = Vector3(-0.8,0.04,1.1)
	catch_point = Vector3(-0.5+0.72*sin(rep*2.3),1.93*setter.height_cm/180.0,2.45)
	for i in 4:
		hitters[i].position = STARTS[i]
		hitters[i].play_action("idle")
	if back_row_right(): hitters[3].position.z = -1.8
	landing.position = Vector3(catch_point.x,0.075,catch_point.z)
	landing.show()
	camera.position = Vector3(0,7.4,-10.6)
	camera.look_at(Vector3(0,1.25,2.2))
	title.text = "SETTER TRYOUT    /    %02d OF 24" % (rep+1)
	message.text = "%s   ·   %s tempo" % [route_label(rep/6),TEMPOS[(rep%6)/2]]
	hint.text = "RT sprint   LT face ball   •   X left   Y middle   A pipe   B right/C   •   RS ↓ fast   ↑ high"

func route_label(index: int) -> String:
	return "C ball" if index == 3 and back_row_right() else TARGETS[index]

func back_row_right() -> bool:
	return rep%2 == 1

func pin(index: int) -> Vector3:
	var point: Vector3 = PINS[index]
	if index == 3 and back_row_right(): point.z = 0.85
	return point

func arc(a: Vector3,b: Vector3,t: float,height: float) -> Vector3:
	var u := clampf(t,0,1)
	return a.lerp(b,u)+Vector3.UP*4.0*height*u*(1.0-u)

func pad() -> int:
	var pads := Input.get_connected_joypads()
	return -1 if pads.is_empty() else pads[0]

func axis(which: JoyAxis) -> float:
	var id := pad()
	return Input.get_joy_axis(id,which) if id >= 0 else 0.0

func move_setter(delta: float) -> void:
	var motion := Vector2(axis(JOY_AXIS_LEFT_X),axis(JOY_AXIS_LEFT_Y))
	motion += Vector2(int(Input.is_key_pressed(KEY_D))-int(Input.is_key_pressed(KEY_A)),int(Input.is_key_pressed(KEY_S))-int(Input.is_key_pressed(KEY_W)))
	if motion.length()<0.16: motion = Vector2.ZERO
	var direction := Vector3(-motion.x,0,-motion.y).limit_length(1)
	var focus := axis(JOY_AXIS_TRIGGER_LEFT)>0.25 or Input.is_key_pressed(KEY_CTRL)
	var sprint := axis(JOY_AXIS_TRIGGER_RIGHT)>0.25 or Input.is_key_pressed(KEY_SHIFT)
	var speed := 2.35 if focus else (6.2 if sprint else 4.3)
	setter.position = Court.clamp_setter(setter.position+direction*delta*speed,3.65,-4.85)
	var facing := ball.position-setter.position if focus else direction
	if Vector2(facing.x,facing.z).length()>0.05:
		setter.rotation.y = lerp_angle(setter.rotation.y,atan2(facing.x,facing.z),minf(1,delta*14))
	setter.play_action("idle" if direction.is_zero_approx() or focus else "run")

func _process(delta: float) -> void:
	clock += delta
	elapsed += delta
	if phase == "intro":
		play_intro(delta)
		return
	if phase == "complete": return
	if phase in ["feed","pass"]: move_setter(delta)
	var stick := axis(JOY_AXIS_RIGHT_Y)
	if absf(stick)>0.45 or Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_DOWN):
		last_flick = 1 if stick < -0.45 or Input.is_key_pressed(KEY_UP) else 2
		flick_at = clock
	match phase:
		"feed":
			ball.position = arc(Vector3(-1,2.5,5.8),passer.position+Vector3.UP*1.15,elapsed/1.15,0.75)
			if elapsed >= 1.15:
				passer.play_action("forearm")
				contact_sound.play()
				source = ball.position
				begin("pass")
		"pass":
			ball.position = arc(source,catch_point,elapsed/1.85,1.35)
			var callout := "%s · %s" % [route_label(rep/6),TEMPOS[(rep%6)/2]]
			var timing := "Move to the ring" if elapsed<1.15 else ("Hold the target" if elapsed<1.66 else "Release")
			message.text = "%s    /    %s" % [callout,timing]
			if held >= 0: Hands.apply(setter,ball.position,clampf((elapsed-1.3)*2,0,1))
			if elapsed>1.85: ball.position.y -= (elapsed-1.85)*4.0
			if elapsed > 2.13: miss("The pass landed. Move under it and release at contact.")
		"set":
			var t := clampf(elapsed/flight_time,0,1)
			ball.position = arc(source,pin(target),t,APEX[tempo])
			var hitter := hitters[target]
			var approach := pin(target)
			approach.y = 0.04
			var runup: Vector3 = STARTS[target]
			if target == 3 and back_row_right(): runup.z = -1.8
			hitter.position = runup.lerp(approach,smoothstep(0.0,0.92,t))
			hitter.position.y += sin(clampf((t-0.68)/0.60,0,1)*PI)*0.66
			if t>=1:
				if success:
					if not CareerSession.credit(rep): return
					rep += 1
				begin("result")
				message.text = feedback
		"result":
			if elapsed>1.15:
				if rep>=24: complete()
				else: reset_feed()

func play_intro(delta: float) -> void:
	ball.hide()
	var line := mini(2,int(elapsed/4.2))
	camera.position = [Vector3(4.2,2.9,-3),Vector3(-0.3,1.85,3.8),Vector3(3.2,4.2,-4.5)][line]+Vector3.RIGHT*0.12*fmod(elapsed,4.2)
	camera.look_at(coach.position+Vector3.UP*1.5 if line==1 else setter.position+Vector3.UP*1.4)
	coach.rotation.y = atan2(setter.position.x-coach.position.x,setter.position.z-coach.position.z)
	title.text = "INDOOR  /  DAY ONE     •     COACH ELLIS"
	message.text = LINES[0] % CareerSession.profile().name if line==0 else LINES[line]
	hint.text = "Hold A or Space to skip"
	var holding := Input.is_key_pressed(KEY_SPACE) or (pad()>=0 and Input.is_joy_button_pressed(pad(),JOY_BUTTON_A))
	skip_time = minf(1,skip_time+delta) if holding else 0.0
	skip.visible = true
	skip.value = skip_time*100
	if skip_time>=1 or elapsed>=12.6:
		if CareerSession.checkpoint("tutorial",0):
			skip.hide()
			reset_feed()

func miss(reason: String) -> void:
	begin("result")
	message.text = reason

func release(index: int) -> void:
	if phase!="pass" or held!=index: return
	held = -1
	var skill := float(CareerSession.profile().get("Hand setting",40))/100
	var gap := Vector2(setter.position.x-catch_point.x,setter.position.z-catch_point.z).length()
	if absf(elapsed-1.85)>0.16+0.12*skill or gap>0.72+0.36*skill:
		miss("Missed contact. Move under the pass, then release.")
		return
	target = index
	tempo = last_flick if clock-flick_at<0.35 else 0
	source = ball.position
	flight_time = DURATION[tempo]
	success = target==rep/6 and tempo==(rep%6)/2
	feedback = "On target.  %s · %s" % [route_label(target),TEMPOS[tempo]] if success else "You set %s · %s. Try the called ball again." % [route_label(target),TEMPOS[tempo]]
	contact_sound.play()
	Hands.apply(setter,source,1.0,pin(target)-source)
	hitters[target].play_action("run")
	begin("set")

func complete() -> void:
	landing.hide()
	begin("complete")
	camera.position = Vector3(0,6,-9)
	camera.look_at(Vector3(0,1.4,2))
	ball.hide()
	coach.hide()
	title.text = "MY CAREER   /   INDOOR SETTER"
	message.text = "Setter tryout complete"
	var badges: Array = CareerSession.data.get_value("badges",CareerSession.athlete_id,[])
	hint.text = "Badges   •   "+"   /   ".join(badges) if not badges.is_empty() else ""
	finish.show()
	finish.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo: return
	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed:
		leave()
		return
	var index := -1
	if event is InputEventJoypadButton: index = BUTTONS.find(event.button_index)
	elif event is InputEventKey: index = KEYS.find(event.keycode)
	if index < 0 or phase != "pass": return
	if event.is_pressed(): held = index
	else: release(index)
	get_viewport().set_input_as_handled()
