extends "res://scripts/indoor_practice.gd"

const MOMENTS := [preload("res://assets/menu/highlights/serve.ogv"),preload("res://assets/menu/highlights/dig.ogv"),preload("res://assets/menu/highlights/spike.ogv"),preload("res://assets/menu/highlights/block.ogv")]
const WELCOME := "Welcome to tryouts. Around here, the first job is keeping the ball alive for somebody else. Find a partner. We'll start with pepper."
var film:=VideoStreamPlayer.new()
var shot:=0
var captions:=VBoxContainer.new()
var prompt:=HBoxContainer.new()
var curtain:=ColorRect.new()
var partner:Node3D

func start_drill() -> void:
	for child in get_children():
		if child is Control: child.hide()
	for target in targets: target.hide()
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
	if CareerSession.stage()=="pepper": pair_up()
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
	super._exit_tree()

func pair_up() -> void:
	film.hide()
	captions.hide()
	phase="pepper"
	setter.position=Vector3(-.8,.04,1.)
	partner.position=setter.position+Vector3(0,0,3.4)
	setter.rotation.y=0
	partner.rotation.y=PI
	camera.position=setter.position+Vector3(2.8,2.,-3.3)
	camera.look_at(setter.position+Vector3(0,1.1,1.3))
	ball.position=partner.position+Vector3(.24,1.,-.23)
	ball.show()

func _process(delta:float) -> void:
	elapsed+=delta
	if coach and coach.has_meta("coach_face"):
		var talking:=phase=="welcome" and elapsed<8.
		coach.get_meta("coach_face").set_shader_parameter("shout",(.24+.18*sin(elapsed*19.)) if talking else 0.)
	if phase=="montage" and elapsed>=2.4: next_shot()
	if phase=="welcome" and elapsed>=7.5 and (not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH) or not DisplayServer.tts_is_speaking() or elapsed>=18.):
		phase="ready"
		Xbox.prompts(prompt,[[JOY_BUTTON_A,"Start practice"]])

func _input(event:InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and phase=="ready":
		get_viewport().set_input_as_handled()
		if CareerSession.checkpoint("pepper",0): pair_up()
	elif phase=="pepper" and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		MenuPresentation.load_scene("res://scenes/story.tscn")
