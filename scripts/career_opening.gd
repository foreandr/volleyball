extends "res://scripts/indoor_practice.gd"

const MOMENTS := [preload("res://assets/menu/highlights/serve.ogv"),preload("res://assets/menu/highlights/dig.ogv"),preload("res://assets/menu/highlights/spike.ogv"),preload("res://assets/menu/highlights/block.ogv")]
const WELCOME := "Welcome to tryouts. Around here, the first job is keeping the ball alive for somebody else. Start on the baseline. Watch the first runner. Run to the net, shuffle across, backpedal, then shuffle home. Twice. After that, grab a partner for pepper."
var film:=VideoStreamPlayer.new()
var shot:=0
var captions:=VBoxContainer.new()
var prompt:=HBoxContainer.new()
var curtain:=ColorRect.new()
var partner:Node3D
const ROUTE := [Vector3(4.35,.04,-4.5),Vector3(4.35,.04,3.4),Vector3(-4.35,.04,3.4),Vector3(-4.35,.04,-4.5)]
var leg:=0
var enter_time:=0.
var enter_meter:=ProgressBar.new()
const COACH_SIDELINE:=Vector3(5.65,.04,4.)
var runner_line:Array=[]
var demo_outcomes:=preload("res://scripts/demo_outcomes.gd").new()
var mistake_leg:=-1
var mistake_distance:=0.
var previous_mistake_leg:=-1

func plan_demo_runner() -> void:
	mistake_leg=-1
	if demo_outcomes.next_misses():
		mistake_leg=randi_range(0,3) if previous_mistake_leg<0 else (previous_mistake_leg+randi_range(1,3))%4
		previous_mistake_leg=mistake_leg
		mistake_distance=randf_range(1.1,6.4)

var entering_lane:=false
var exits:Dictionary={}
var corner_grace:=0.
const CORNER_GRACE:=.85
var watchers:Array=[]
var idle_heads:Dictionary={}
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
	captions.add_child(enter_meter)
	enter_meter.custom_minimum_size=Vector2(92,5)
	enter_meter.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
	enter_meter.show_percentage=false
	enter_meter.max_value=1.
	enter_meter.hide()
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
	elif CareerSession.stage() in ["moving_reception","moving_reception_complete"]:
		pepper.moving=true
		pair_up()
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
	phase="footwork_demo"
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
	watchers=rotation_drill.roster.duplicate()
	for worker in rotation_drill.workers: watchers.append(worker.actor)
	for i in watchers.size():
		var actor:Node3D=watchers[i]
		actor.position=Vector3(4.35-i*1.05,.04,-5.55)
		actor.rotation.y=atan2(-actor.position.x,5.)
		actor.play_action("idle",0.)
		actor.animator.advance(.1)
		var rig:Skeleton3D=actor.skeleton
		idle_heads[actor]=rig.get_bone_pose_rotation(rig.find_bone("Head"))
	runner_line=watchers.duplicate()
	for athlete_:Node3D in watchers:
		if athlete_!=setter and int(athlete_.get_meta("school_jersey_number",0))==504:
			partner=athlete_
			break
	runner_line.erase(partner)
	runner_line.erase(setter)
	coach.position=COACH_SIDELINE
	plan_demo_runner()
	partner.position=ROUTE[0]
	partner.rotation.y=0.
	var square:=BoxMesh.new()
	square.size=Vector3(.98,.018,.98)
	var mat:=StandardMaterial3D.new()
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color=Color("48ff69")
	square.material=mat
	marker.mesh=square
	world.add_child(marker)
	for actor in watchers:
		if not shuffle_steps.has(actor): shuffle_steps[actor]=preload("res://scripts/directional_footwork.gd").new(actor)
	place_drill_captions()
	run_prompt()

func place_drill_captions() -> void:
	captions.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	captions.offset_left=-360
	captions.offset_right=360
	captions.offset_top=34
	workout_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	prompt.alignment=BoxContainer.ALIGNMENT_CENTER

func run_prompt() -> void:
	var segment:=leg%4
	marker.position=ROUTE[(segment+1)%4]
	if phase=="footwork_demo":
		show_demo_prompt()
		return
	workout_label.show()
	prompt.show()
	workout_label.add_theme_font_size_override("font_size",30)
	var cue:String=["Run here","Shuffle right along the net","Run backwards to the baseline","Shuffle left to the start"][segment]
	workout_label.text="Lap %d of 2   /   %s"%[1+floori(leg/4.),cue]
	training_prompt([["LT","Hold to shuffle"]] if segment%2==1 else [],"Hold Ctrl to shuffle" if segment%2==1 else "")

func show_demo_prompt() -> void:
	workout_label.hide()
	prompt.show()
	training_prompt([[JOY_BUTTON_A,"Hold to enter the drill"]],"Hold Enter to enter the drill")

func move_in_line(actor:Node3D,goal:Vector3,dt:float) -> bool:
	var previous:=actor.position
	actor.position=previous.move_toward(goal,dt*3.4)
	var velocity:Vector3=(actor.position-previous)/maxf(dt,.001)
	if velocity.length()>.05:
		GroundControls.face(actor,velocity,dt,5.)
		actor.play_travel_gait(velocity)
	else:
		GroundControls.face(actor,Vector3(0,0,1.)-actor.position,dt,2.)
		actor.play_action("idle",.18)
	actor.animator.advance(dt)
	return actor.position.distance_to(goal)<.02

func advance_line(dt:float) -> void:
	for i in runner_line.size():
		var actor:Node3D=runner_line[i]
		var slot:=Vector3(3.3-i*1.05,.04,-5.65)
		if exits.has(actor):
			var path:Array=exits[actor]
			if move_in_line(actor,path[0],dt):
				path.pop_front()
				if path.is_empty(): exits.erase(actor)
		else: move_in_line(actor,slot,dt)

func run_step(delta:float,direction:Vector3,focus:bool,sprinting:bool) -> void:
	var demo:=phase=="footwork_demo"
	var runner:Node3D=partner if demo else setter
	advance_line(delta)
	GroundControls.face(coach,runner.position-coach.position,delta,3.)
	if entering_lane:
		if move_in_line(runner,ROUTE[0],delta):
			entering_lane=false
			runner.rotation.y=0.
		return
	# Spend the corner allowance only while the stick is still moving.
	# Keep the foot planted until the new gait engages.
	if runner.position.distance_to(ROUTE[leg%4])>.75: corner_grace=0.
	if not demo and focus!=(leg%2==1) and corner_grace>0.:
		if direction.length()>.1: corner_grace=maxf(0.,corner_grace-delta)
		return
	var velocity:=direction.limit_length(1.)*GroundControls.speed(focus,sprinting)
	runner.position+=velocity*delta
	runner.position.x=clampf(runner.position.x,-4.65,4.65)
	runner.position.z=clampf(runner.position.z,-4.9,3.65)
	if focus: runner.play_action("idle",.14)
	else: runner.play_travel_gait(velocity)
	runner.animator.advance(delta)
	GroundControls.shuffle(runner,shuffle_steps[runner],velocity,focus,delta)
	if sprinting and velocity.length()>.1: runner.stamina.spend(delta*runner.stamina.SPRINT_DRAIN,"Sprint")
	else: runner.stamina.recover(delta)
	for actor:Node3D in watchers:
		if actor==runner: continue
		if exits.has(actor): continue
		var local:=actor.to_local(runner.position)
		var rig:Skeleton3D=actor.skeleton
		var id:=rig.find_bone("Head")
		var parent:=rig.get_bone_global_pose(rig.get_bone_parent(id)).basis.orthonormalized()
		var turn:=Quaternion(parent.inverse()*Vector3.UP,clampf(atan2(local.x,local.z),-.92,.92))
		rig.set_bone_pose_rotation(id,rig.get_bone_pose_rotation(id).slerp(turn*idle_heads[actor],1.-exp(-5.*delta)))
	var line:=Geometry3D.get_closest_point_to_segment(runner.position,ROUTE[leg%4],marker.position)
	if demo and leg==mistake_leg and runner.position.distance_to(ROUTE[leg])>=mistake_distance:
		finish_demo_lap(false)
		return
	if not demo and ((focus!=(leg%2==1) and velocity.length()>.1 and runner.position.distance_to(marker.position)>.55) or runner.position.distance_to(line)>.7):
		coach_react("lane" if runner.position.distance_to(line)>.7 else ("shuffle" if leg%2==1 else "run"))
		leg=0
		corner_grace=CORNER_GRACE
		runner.position=ROUTE[0]
	elif runner.position.distance_to(marker.position)<.3:
		leg+=1
		corner_grace=CORNER_GRACE
		if demo and leg==4:
			finish_demo_lap(true)
		elif not demo and leg==4: coach_react("praise")
		elif leg==8:
			CareerSession.data.set_value(CareerSession.key(),"footwork_done",true)
			CareerSession.checkpoint("pepper",0)
			reception_brief()
			return
	else: return
	run_prompt()

func finish_demo_lap(passed:bool) -> void:
	coach_react("praise" if passed else "dismiss")
	plan_demo_runner()
	leg=0
	runner_line.append(partner)
	var tail_x:=3.3-(runner_line.size()-1)*1.05
	exits[partner]=[Vector3(5.15,.04,partner.position.z),Vector3(5.15,.04,-6.6),Vector3(tail_x,.04,-6.6)]
	partner=runner_line.pop_front()
	entering_lane=true
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
	fade.tween_callback(pair_up)
	fade.tween_property(curtain,"modulate:a",0.,.5)
	fade.tween_callback(curtain.hide)

func pair_up() -> void:
	place_drill_captions()
	coach.position=COACH_SIDELINE
	rings.participants=[setter]
	rings.match_meter=pepper.meter
	film.hide()
	captions.show()
	if marker.is_inside_tree(): marker.hide()
	phase="pepper"
	rings.setting_cues=false
	rings.show()
	camera.fov=68.
	camera.position=Vector3(0,5.8,-10.)
	camera.look_at(Vector3(.7,1.,-.45))
	training_prompt([[JOY_BUTTON_A,"Hold, then release at contact"]],"Hold Space, then release at contact")
	pepper.demonstrating=CareerSession.progress()<5
	pepper.configure(self,workout_label,CareerSession.progress())
	if pepper.demonstrating:
		phase="demo"
		show_demo_prompt()
		if pepper.moving:
			workout_label.show()
			workout_label.text="Moving reception   /   Watch the pass to the setter"
			say(coach,"Focus on me before every toss. Shuffle under the ball and pass to the setter.",5.)

func moving_prompt(waiting:bool) -> void:
	workout_label.text="%d / 5 passes to setter"%pepper.score
	if waiting:
		training_prompt([["LT","Face coach for the toss"]],"Hold Ctrl to face coach")
	else:
		training_prompt([["LT","Focus"],["Move","Shuffle"],[JOY_BUTTON_A,"Hold, release at contact"]],"Ctrl to focus / WASD to shuffle / Hold Space, release at contact")

func finish_pepper() -> void:
	phase="pepper_complete"
	training_prompt([[JOY_BUTTON_A,"Continue"]],"Enter to continue")

func fade_receiver_exit() -> void:
	if curtain.visible: return
	curtain.z_index=20
	curtain.modulate.a=0.
	curtain.show()
	var fade:=create_tween().set_trans(Tween.TRANS_SINE)
	fade.tween_property(curtain,"modulate:a",.32,.18)
	fade.tween_property(curtain,"modulate:a",0.,.30)
	fade.tween_callback(curtain.hide)

func enter_drill() -> void:
	var was_footwork:=phase=="footwork_demo"
	phase="handoff"
	enter_time=0.
	enter_meter.hide()
	prompt.hide()
	curtain.show()
	curtain.z_index=20
	curtain.modulate.a=0.
	var fade:=create_tween()
	fade.tween_property(curtain,"modulate:a",1.,.22)
	fade.tween_callback(func():
		speech_left=0.
		if was_footwork:
			partner.position=setter.position
			runner_line.append(partner)
			partner.play_action("idle",0.)
			leg=0
			entering_lane=false
			setter.position=ROUTE[0]
			setter.rotation.y=0.
			corner_grace=CORNER_GRACE
			phase="footwork"
			run_prompt()
		else:
			pepper.start_human_turn()
			phase="pepper"
			workout_label.show()
			prompt.show()
			workout_label.text="%d / 5 passes"%pepper.score
			training_prompt([[JOY_BUTTON_A,"Hold, then release at contact"]],"Hold Space, then release at contact")
		coach_motion.whistle_cue.signal_drill(coach))
	fade.tween_property(curtain,"modulate:a",0.,.28)
	fade.tween_callback(curtain.hide)

func receive_down() -> bool:
	return Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_ENTER) or (pad()>=0 and Input.is_joy_button_pressed(pad(),Xbox.physical(JOY_BUTTON_A)))

func _process(delta:float) -> void:
	elapsed+=delta
	if phase=="handoff" and pepper and pepper.moving: pepper.move_off_turn(delta)
	if phase in ["demo","footwork_demo"]:
		enter_time=enter_time+delta if receive_down() else 0.
		enter_meter.value=enter_time
		enter_meter.visible=enter_time>0.
		if enter_time>=1.: enter_drill()
	update_speech(delta)
	if phase!="montage":
		for seat in seats_in_use: seat.update()
	if coach and coach_motion.whistle_cue.signal_time>=0.: coach_motion.whistle_cue.step_whistle(coach,delta)
	if phase in ["footwork","footwork_demo"]:
		marker.mesh.material.albedo_color=Color("168239").lerp(Color("73ff78"),.5+.5*cos(elapsed*5.))
	if phase=="footwork_demo":
		var shuffle:=leg%2==1
		if leg==mistake_leg and partner.position.distance_to(ROUTE[leg])>mistake_distance-.9: shuffle=not shuffle
		run_step(delta,partner.position.direction_to(marker.position),shuffle,false)
	elif phase=="footwork":
		var stick:=Vector2(axis(JOY_AXIS_LEFT_X),axis(JOY_AXIS_LEFT_Y))
		if stick.length()<.15: stick=Vector2.ZERO
		stick+=Vector2(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W)))
		run_step(delta,Vector3(-stick.x,0,-stick.y),GroundControls.focus(axis),GroundControls.sprint(axis))
	elif phase in ["pepper","demo"] or (phase=="pepper_complete" and pepper.moving):
		GroundControls.face(coach,pepper.pairs[0].receiver.position-coach.position,delta,3.)
		pepper.tick(delta)
	if coach and coach.has_meta("coach_face"):
		var talking:=(phase=="welcome" and elapsed<8.) or phase=="gather" or (speaker==coach and speech_left>0.)
		coach.get_meta("coach_face").set_shader_parameter("shout",(.24+.18*sin(elapsed*19.)) if talking else 0.)
	if phase=="montage" and elapsed>=2.4: next_shot()
	if phase=="welcome" and elapsed>=7.5 and (not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH) or not DisplayServer.tts_is_speaking() or elapsed>=18.):
		phase="ready"
		training_prompt([[JOY_BUTTON_A,"Start practice"]],"Enter to start practice")

func opening_checkpoint() -> String:
	if pepper.moving:
		var done:=phase=="pepper_complete" or (not pepper.demonstrating and pepper.attempts>=5)
		return "moving_reception_complete" if done else "moving_reception"
	if not pepper.pairs.is_empty(): return "pepper_complete" if phase=="pepper_complete" else "pepper"
	if phase in ["footwork","footwork_demo"] or phase=="handoff": return "footwork"
	return "origin" if phase=="montage" else "welcome"

func save_and_leave_drill() -> void:
	var stage:=opening_checkpoint()
	if CareerSession.checkpoint(stage,pepper.score if not pepper.pairs.is_empty() else 0):
		MenuPresentation.load_scene("res://scenes/main.tscn")

func reset_drill() -> void:
	var stage:=opening_checkpoint().trim_suffix("_complete")
	if stage=="moving_reception":
		CareerSession.data.set_value(CareerSession.key(),"moving_attempts",0)
	if CareerSession.checkpoint(stage,0): MenuPresentation.load_scene(scene_file_path)

func _input(event:InputEvent) -> void:
	if get_tree().paused or settings.visible: return
	if event is InputEventJoypadButton and event.pressed: active_pad=event.device
	var start:bool=event is InputEventJoypadButton and event.button_index==Xbox.physical(JOY_BUTTON_START)
	var escape:bool=event is InputEventKey and event.keycode==KEY_ESCAPE and not event.echo
	if (start or escape) and event.is_pressed():
		settings.show()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_accept") and phase=="ready":
		get_viewport().set_input_as_handled()
		if CareerSession.checkpoint("footwork",0): begin_run()
	elif phase=="pepper":
		if event is InputEventJoypadButton and event.button_index==Xbox.physical(JOY_BUTTON_A):
			pepper.button(event.pressed)
			get_viewport().set_input_as_handled()
			return
		if event is InputEventKey and event.keycode in [KEY_SPACE,KEY_ENTER] and not event.echo:
			pepper.button(event.pressed)
			get_viewport().set_input_as_handled()
			return
	if phase=="pepper_complete" and event.is_action_pressed("ui_accept") and not pepper.moving:
		get_viewport().set_input_as_handled()
		if CareerSession.checkpoint("moving_reception",0): MenuPresentation.load_scene("res://scenes/career_opening.tscn")
		return
	if phase=="pepper_complete" and event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		MenuPresentation.load_scene("res://scenes/story.tscn")
