extends "res://scripts/indoor_practice.gd"

const MOMENTS := [preload("res://assets/menu/highlights/serve.ogv"),preload("res://assets/menu/highlights/dig.ogv"),preload("res://assets/menu/highlights/spike.ogv"),preload("res://assets/menu/highlights/block.ogv")]
const WELCOME := "Welcome to tryouts. Around here, the first job is keeping the ball alive for somebody else. Start on the baseline. Run to the net, shuffle across, backpedal, then shuffle home. After that, grab a partner for pepper."
var film:=VideoStreamPlayer.new()
var shot:=0
var captions:=VBoxContainer.new()
var prompt:=HBoxContainer.new()
var curtain:=ColorRect.new()
var partner:Node3D
const ROUTE := [Vector3(4.1,.04,-4.6),Vector3(4.1,.04,3.45),Vector3(-4.1,.04,3.45),Vector3(-4.1,.04,-4.6)]
const ROUTE_TEXT := ["Run forward to the net","Shuffle across the net","Backpedal to the baseline","Shuffle along the baseline"]
var leg:=0
var marker:=MeshInstance3D.new()
var returning_to_start:=false
var shuffle_distance:=0.
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
	leg=clampi(CareerSession.progress(),0,3)
	setter.position=ROUTE[leg]
	setter.rotation.y=0
	camera.position=Vector3(0,7.1,-13.8)
	camera.look_at(Vector3(0,.5,-.7))
	ball.hide()
	for i in rotation_drill.workers.size(): rotation_drill.workers[i].actor.position=Vector3(-5.65,.04,-3.5+i*1.05)
	coach.position=Vector3(5.35,.04,-.3)
	for i in range(1,rotation_drill.roster.size()):
		rotation_drill.roster[i].position=Vector3(5.5,.04,1.+i)
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
	marker.position=ROUTE[leg if returning_to_start else (leg+1)%4]
	workout_label.text="Footwork   ·   %d / 4\n%s"%[leg+1,"Return to the marker to retry the shuffle" if returning_to_start else ROUTE_TEXT[leg]]
	if leg%2==1 and not returning_to_start: training_prompt([["LT","Hold to shuffle"]],"Hold Ctrl to shuffle")
	else: training_prompt([[JOY_BUTTON_LEFT_STICK,"Move"]],"WASD to move")

func run_step(delta:float,direction:Vector3,focus:bool,sprinting:bool) -> void:
	var velocity:=direction.limit_length(1.)*GroundControls.speed(focus,sprinting)
	var previous:Vector3=setter.position
	setter.position+=velocity*delta
	setter.position.x=clampf(setter.position.x,-4.55,4.55)
	setter.position.z=clampf(setter.position.z,-5.,3.6)
	if focus: setter.play_action("idle",.14)
	else: setter.play_travel_gait(velocity)
	setter.animator.advance(delta)
	GroundControls.shuffle(setter,shuffle_steps[setter],velocity,focus,delta)
	if leg%2==1 and focus and not returning_to_start and absf(setter.position.z-ROUTE[leg].z)<1.:
		shuffle_distance+=signf(marker.position.x-ROUTE[leg].x)*(setter.position.x-previous.x)
	if setter.position.distance_to(marker.position)>.52: return
	if returning_to_start:
		returning_to_start=false
	elif leg%2==1 and shuffle_distance<6.8:
		returning_to_start=true
	else:
		leg+=1
		if leg>=4:
			CareerSession.data.set_value(CareerSession.key(),"footwork_done",true)
			CareerSession.checkpoint("pepper",0)
			pair_up()
			return
		CareerSession.checkpoint("footwork",leg)
	shuffle_distance=0.
	run_prompt()

func pair_up() -> void:
	film.hide()
	captions.show()
	if marker.is_inside_tree(): marker.hide()
	phase="pepper"
	camera.position=Vector3(2.9,4.4,-9.6)
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
	elif phase=="pepper": pepper.tick(delta)
	if coach and coach.has_meta("coach_face"):
		var talking:=phase=="welcome" and elapsed<8.
		coach.get_meta("coach_face").set_shader_parameter("shout",(.24+.18*sin(elapsed*19.)) if talking else 0.)
	if phase=="montage" and elapsed>=2.4: next_shot()
	if phase=="welcome" and elapsed>=7.5 and (not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH) or not DisplayServer.tts_is_speaking() or elapsed>=18.):
		phase="ready"
		training_prompt([[JOY_BUTTON_A,"Start practice"]],"Enter to start practice")

func _input(event:InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and phase=="ready":
		get_viewport().set_input_as_handled()
		if CareerSession.checkpoint("footwork",0): begin_run()
	elif phase=="pepper" and (event.is_action_pressed("ui_accept") or event.is_action_released("ui_accept")):
		pepper.button(event.is_action_pressed("ui_accept"))
		get_viewport().set_input_as_handled()
	elif (phase=="pepper_complete" and event.is_action_pressed("ui_accept")) or (phase in ["footwork","pepper","pepper_complete"] and event.is_action_pressed("ui_cancel")):
		get_viewport().set_input_as_handled()
		MenuPresentation.load_scene("res://scenes/story.tscn")
