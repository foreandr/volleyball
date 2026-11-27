extends "res://scripts/indoor_practice.gd"

const MOMENTS := [preload("res://assets/menu/highlights/serve.ogv"),preload("res://assets/menu/highlights/dig.ogv"),preload("res://assets/menu/highlights/spike.ogv"),preload("res://assets/menu/highlights/block.ogv")]
const WELCOME := "Welcome to tryouts. Around here, the first job is keeping the ball alive for somebody else. Start on the baseline. Find the left baseline marker. Hold focus and shuffle two complete laps around the net. After that, grab a partner for pepper."
var film:=VideoStreamPlayer.new()
var shot:=0
var captions:=VBoxContainer.new()
var prompt:=HBoxContainer.new()
var curtain:=ColorRect.new()
var partner:Node3D
const ROUTE := [Vector3(5.5,.04,-4.5),Vector3(-5.5,.04,-4.5),Vector3(-5.5,.04,5.3),Vector3(5.5,.04,5.3)]
var leg:=0
var route_state:="approach"
var marker:=MeshInstance3D.new()
var pepper:=preload("res://scripts/pepper_tutorial.gd").new()
var workout_label:Label


func start_drill() -> void:
	for child in get_children():
		if child is Control: child.hide()
	for target in targets: target.hide()
	for cart in rotation_drill.bins+[rotation_drill.basket]: cart.hide()
	for stored in rotation_drill.stock: stored.hide()
	for worker in rotation_drill.workers:
		worker.actor.play_action("base/Idle",0.)
		worker.actor.animator.advance(.2)
	for student in rotation_drill.roster:
		student.play_action("idle",0.)
		student.animator.advance(.15)
	ball.hide()
	partner=rotation_drill.roster[1]
	for i in rotation_drill.roster.size():
		var player:Node3D=rotation_drill.roster[i]
		player.position=coach.position+Vector3((i-1)*1.05,0,2.3)
		player.rotation.y=atan2(coach.position.x-player.position.x,coach.position.z-player.position.z)
	camera.position=coach.position+Vector3(3.1,2.2,4.4)
	camera.look_at(coach.position+Vector3(.1,1.4,.8))
	add_child(captions)
	captions.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	captions.offset_left=-340
	captions.offset_right=340
	captions.offset_top=-132
	var line:=Label.new()
	line.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	line.text="Coach Ellis\n"+WELCOME
	line.add_theme_constant_override("outline_size",5)
	captions.add_child(line)
	captions.add_child(prompt)
	captions.hide()
	add_child(film)
	film.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	film.expand=true
	film.finished.connect(next_shot)
	add_child(curtain)
	curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	curtain.mouse_filter=Control.MOUSE_FILTER_IGNORE
	curtain.color=Color.BLACK
	curtain.hide()
	workout_label=line
	if CareerSession.stage()=="footwork": begin_run()
	elif CareerSession.stage()=="pepper" and not CareerSession.data.get_value(CareerSession.key(),"footwork_done",false):
		CareerSession.checkpoint("footwork",0)
		begin_run()
	elif CareerSession.stage() in ["pepper","pepper_complete"]: pair_up()
	elif CareerSession.stage()=="welcome": welcome()
	else:
		phase="montage"
		MenuPresentation.set_music(true)
		film.stream=MOMENTS[0]
		film.play()

func next_shot() -> void:
	if phase!="montage": return
	shot+=1
	elapsed=0
	if shot<MOMENTS.size():
		film.stream=MOMENTS[shot]
		film.play()
	else:
		curtain.show()
		phase="fade"
		curtain.modulate.a=0.
		var fade:=create_tween()
		fade.tween_property(curtain,"modulate:a",1.,.4)
		fade.tween_callback(welcome)
		fade.tween_property(curtain,"modulate:a",0.,.7)
		fade.tween_callback(curtain.hide)

func welcome() -> void:
	MenuPresentation.set_music(false)
	film.stop()
	film.hide()
	captions.show()
	phase="welcome"
	elapsed=0
	CareerSession.checkpoint("welcome",0)
	var voices:=DisplayServer.tts_get_voices_for_language("en") if DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH) else PackedStringArray()
	if voices.size(): DisplayServer.tts_speak(WELCOME,voices[0])
	coach.rotation.y=atan2(setter.position.x-coach.position.x,setter.position.z-coach.position.z)

func _exit_tree() -> void:
	if phase=="welcome": DisplayServer.tts_stop()
	if not marker.is_inside_tree(): marker.free()
	super._exit_tree()

func training_prompt(entries:Array,keyboard:String) -> void:
	if Xbox.keyboard_prompts():
		for child in prompt.get_children():
			prompt.remove_child(child)
			child.queue_free()
		var keys:=Label.new()
		keys.text=keyboard
		prompt.add_child(keys)
	else: Xbox.prompts(prompt,entries)

func begin_run() -> void:
	phase="footwork"
	film.hide()
	captions.show()
	leg=0
	rings.setting_cues=false
	rings.show()
	setter.position=Vector3(3.3,.04,-4.5)
	setter.rotation.y=0
	camera.fov=76.
	camera.position=Vector3(0,6.,-10.)
	camera.look_at(Vector3(0,.5,-.7))
	ball.hide()
	for i in rotation_drill.workers.size(): rotation_drill.workers[i].actor.position=Vector3(-6.7,.04,-3.5+i*1.05)
	coach.position=Vector3(6.6,.04,-.3)
	for i in range(1,rotation_drill.roster.size()):
		rotation_drill.roster[i].position=Vector3(6.6,.04,1.+i)
	var ring:=TorusMesh.new()
	ring.inner_radius=.42
	ring.outer_radius=.52
	marker.mesh=ring
	var mat:=StandardMaterial3D.new()
	mat.albedo_color=Color("ffd364")
	ring.material=mat
	world.add_child(marker)
	if not shuffle_steps.has(setter): shuffle_steps[setter]=preload("res://scripts/directional_footwork.gd").new(setter)
	run_prompt()

func run_prompt() -> void:
	marker.position=ROUTE[(leg+1)%4] if route_state=="laps" else ROUTE[0]
	workout_label.add_theme_font_size_override("font_size",28)
	workout_label.text="Run to the left baseline marker"
	match route_state:
		"retry": workout_label.text="Lap broken   -   Return to the start"
		"focus","back":
			workout_label.text="KEEP HOLDING FOCUS" if route_state=="back" else "HOLD TO SHUFFLE"
			training_prompt([["LT","Keep holding"],["View","Press Back / View"]] if route_state=="back" else [["LT","Hold to shuffle"]],"Hold Ctrl + press Backspace" if route_state=="back" else "Hold Ctrl")
			return
		"laps": workout_label.text="Lap %d of 2   -   %s"%[1+floori(leg/4.),["Shuffle across the baseline","Round the right post","Shuffle across the net","Return past the left post"][leg%4]]
	training_prompt([["LT","Keep holding"]] if route_state=="laps" else [[JOY_BUTTON_LEFT_STICK,"Move"]],"Hold Ctrl" if route_state=="laps" else "WASD to move")

func run_step(delta:float,direction:Vector3,focus:bool,sprinting:bool) -> void:
	var velocity:=direction.limit_length(1.)*GroundControls.speed(focus,sprinting)
	setter.position+=velocity*delta
	setter.position.x=clampf(setter.position.x,-6.,6.)
	setter.position.z=clampf(setter.position.z,-5.,6.)
	if focus: setter.play_action("idle",.14)
	else: setter.play_travel_gait(velocity)
	setter.animator.advance(delta)
	GroundControls.shuffle(setter,shuffle_steps[setter],velocity,focus,delta)
	if sprinting and velocity.length()>.1: setter.stamina.spend(delta*setter.stamina.SPRINT_DRAIN,"Sprint")
	else: setter.stamina.recover(delta)
	if route_state=="laps":
		var closest:=Geometry3D.get_closest_point_to_segment(setter.position,ROUTE[leg%4],marker.position)
		if (not focus and velocity.length()>.1) or setter.position.distance_to(closest)>.55:
			leg=0
			route_state="retry"
		elif setter.position.distance_to(marker.position)<.28:
			leg+=1
			if leg==8:
				CareerSession.data.set_value(CareerSession.key(),"footwork_done",true)
				CareerSession.checkpoint("pepper",0)
				reception_brief()
				return
		else: return
	else:
		var next:=route_state
		if setter.position.distance_to(ROUTE[0])<.38: next="back" if focus else "focus"
		elif route_state in ["back","focus"]: next="approach"
		if next==route_state: return
		route_state=next
	run_prompt()

func reception_brief() -> void:
	phase="gather"
	marker.hide()
	rings.hide()
	prompt.hide()
	curtain.show()
	curtain.modulate.a=0.
	var fade:=create_tween()
	fade.tween_property(curtain,"modulate:a",1.,.45)
	fade.tween_callback(func():
		coach.position=Vector3(0,.04,-.3)
		for i in rotation_drill.roster.size():
			var actor:Node3D=rotation_drill.roster[i]
			actor.position=coach.position+Vector3((i-1)*.95,0,1.45)
			actor.look_at(coach.position,Vector3.UP,true)
			actor.play_action("idle")
		coach.rotation.y=0.
		camera.position=Vector3(3.1,2.2,4.4)
		camera.look_at(coach.position+Vector3(0,1.2,.65))
		workout_label.text="Coach Ellis: Good job. Bring it in. Next is reception. Watch the platform angle as the ball goes back to the feeder."
		if DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
			var voices:=DisplayServer.tts_get_voices_for_language("en")
			if voices.size(): DisplayServer.tts_speak(workout_label.text,voices[0]))
	fade.tween_property(curtain,"modulate:a",0.,.45)
	fade.tween_interval(5.)
	fade.tween_property(curtain,"modulate:a",1.,.4)
	fade.tween_callback(func():
		pair_up()
		phase="demo"
		pepper.demonstrating=true
		workout_label.text="Reception demo   -   Watch the forearms meet the ball")
	fade.tween_property(curtain,"modulate:a",0.,.5)
	fade.tween_callback(curtain.hide)

func pair_up() -> void:
	film.hide()
	captions.show()
	if marker.is_inside_tree(): marker.hide()
	phase="pepper"
	rings.setting_cues=false
	rings.show()
	camera.fov=68.
	camera.position=Vector3(0,5.8,-10.)
	camera.look_at(Vector3(.7,1.,-.45))
	training_prompt([[JOY_BUTTON_A,"Hold to receive"]],"Hold Space to receive")
	pepper.configure(self,workout_label,CareerSession.progress())

func finish_pepper() -> void:
	phase="pepper_complete"
	training_prompt([[JOY_BUTTON_A,"Continue"]],"Enter to continue")

func _process(delta:float) -> void:
	elapsed+=delta
	if phase!="montage":
		for seat in seats_in_use: seat.update()
	if phase=="footwork":
		var stick:=Vector2(axis(JOY_AXIS_LEFT_X),axis(JOY_AXIS_LEFT_Y))
		if stick.length()<.15: stick=Vector2.ZERO
		stick+=Vector2(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W)))
		run_step(delta,Vector3(-stick.x,0,-stick.y),GroundControls.focus(axis),GroundControls.sprint(axis))
	elif phase in ["pepper","demo"]:
		pepper.tick(delta)
		if phase=="demo" and pepper.pairs[0].caught and pepper.pairs[0].age>=2.95:
			phase="demo_ready"
			prompt.show()
			training_prompt([[JOY_BUTTON_A,"Play"]],"Enter to play")
	if phase=="footwork":
		workout_label.modulate=Color.WHITE.lerp(Color("ffcc58"),.5+.5*sin(elapsed*5.)) if route_state in ["focus","back"] else Color.WHITE
	if coach and coach.has_meta("coach_face"):
		var talking:=(phase=="welcome" and elapsed<8.) or phase=="gather"
		coach.get_meta("coach_face").set_shader_parameter("shout",(.24+.18*sin(elapsed*19.)) if talking else 0.)
	if phase=="montage" and elapsed>=2.4: next_shot()
	if phase=="welcome" and elapsed>=7.5 and (not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH) or not DisplayServer.tts_is_speaking() or elapsed>=18.):
		phase="ready"
		training_prompt([[JOY_BUTTON_A,"Start practice"]],"Enter to start practice")

func _input(event:InputEvent) -> void:
	if phase=="footwork" and route_state=="back" and GroundControls.focus(axis) and ((event is InputEventJoypadButton and event.button_index==JOY_BUTTON_BACK and event.pressed) or (event is InputEventKey and event.keycode==KEY_BACKSPACE and event.pressed)):
		route_state="laps"
		run_prompt()
		get_viewport().set_input_as_handled()
	elif phase=="demo_ready" and event.is_action_pressed("ui_accept"):
		pepper.demonstrating=false
		var pair:Dictionary=pepper.pairs[0]
		pair.age=0.
		pair.caught=false
		pair.hit=false
		pair.swing=false
		pair.flying=false
		phase="pepper"
		workout_label.text="0 / 5 passes"
		training_prompt([[JOY_BUTTON_A,"Hold to receive"]],"Hold Space to receive")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept") and phase=="ready":
		get_viewport().set_input_as_handled()
		if CareerSession.checkpoint("footwork",0): begin_run()
	elif phase=="pepper" and (event.is_action_pressed("ui_accept") or event.is_action_released("ui_accept")):
		pepper.button(event.is_action_pressed("ui_accept"))
		get_viewport().set_input_as_handled()
	elif (phase=="pepper_complete" and event.is_action_pressed("ui_accept")) or (phase in ["footwork","pepper","pepper_complete"] and event.is_action_pressed("ui_cancel")):
		get_viewport().set_input_as_handled()
		MenuPresentation.load_scene("res://scenes/story.tscn")
