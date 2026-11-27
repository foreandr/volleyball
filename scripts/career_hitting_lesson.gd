extends "res://scripts/attacking_camp.gd"

const POSITIONS:=["Left (4)","Middle (3)","Right (2)"]
const ZONES:=[1,6,5]
const HALF_ZONE:=1.35
const SIDELINE:=Vector3(5.4,.04,.65)
var career_hitter:Node3D
var sideline_actor:Node3D
var makes:=0
var demo_target:=0
var demo_hit:=false
var platform_held:=false
var receive_release:=INF
var platform:=preload("res://scripts/bump_setting.gd").new()
var toss_start:=Vector3.ZERO
var receive_point:=Vector3.ZERO
const RECEIVE_TIME:=1.65

func saved_set_percent() -> float:
	return SET_HEIGHTS[2]

func save_set_height(value:float) -> void:
	set_arc_percent=value
	title.text=camp_title()
	update_prompts(phase)

var join_time:=0.
var entry_widget:Control
var mark:=MeshInstance3D.new()
var closing:=false

func start_drill() -> void:
	makes=clampi(CareerSession.progress() if CareerSession.stage()=="hitting_lesson" else 0,0,8)
	var surface:=PlaneMesh.new()
	surface.size=Vector2.ONE*HALF_ZONE*2.
	var ink:=StandardMaterial3D.new()
	ink.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	ink.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.albedo_color=Color(.22,1.,.56,.48)
	surface.material=ink
	mark.mesh=surface
	world.add_child(mark)
	super.start_drill()
	if not CareerSession.profile().is_empty(): hitter.apply_profile(CareerSession.profile())
	world.add_child(platform)
	platform.hide()
	career_hitter=hitter
	var teammate:=athlete(hitter.position,"e97937")
	register_student(teammate,1)
	preload("res://scripts/practice_kit.gd").apply(teammate,false,1)
	energy[teammate]=teammate.stamina
	switch_attacker(teammate,career_hitter)
	say(coach,"Watch the approach. Then hit the highlighted zone from each position.",4.)

func switch_attacker(active:Node3D,waiting:Node3D) -> void:
	rings.extra_jumps.erase(waiting)
	rings.extra_jumps[active]=attack_jump
	hitter=active
	platform.setter=hitter
	if platform.cone==null: platform.configure(hitter,preload("res://assets/animations/straight_pass_02.res"))
	else: platform.set_receive_clip(preload("res://assets/animations/straight_pass_02.res"))
	jump_height=float(active.attributes.vertical_in)*.0254
	sideline_actor=waiting
	waiting.position=SIDELINE
	waiting.look_at(Vector3(0,SIDELINE.y,3),Vector3.UP,true)
	waiting.play_action("idle",0.)
	waiting.animator.advance(0.)

func zone_center() -> Vector3:
	return Vector3([2.9,0.,-2.9][demo_target if cpu_hitter else makes%3],.065,BallNet.NET_Z+5.8)

func shot_landing(origin:Vector3) -> Vector3:
	if not cpu_hitter: return super.shot_landing(origin)
	var target:=zone_center()
	target.y=Contact.BALL_RADIUS
	return target

func begin(next:String) -> void:
	if cpu_hitter and next=="spike": demo_hit=true
	super.begin(next)

func camp_title() -> String:
	if cpu_hitter: return "Hitting   /   Reyes to zone %d" % ZONES[demo_target]
	return "Hitting   /   %s to zone %d   /   Set height %d   /   %d of 9 correct"%[POSITIONS[mini(2,makes/3)],ZONES[makes%3],height_preset(),makes]

func reset_feed() -> void:
	if cpu_hitter and demo_hit: demo_target=(demo_target+1)%ZONES.size()
	demo_hit=false
	coach_station=Vector3(-.58,0,BallNet.NET_Z+2.6)
	attack_lane=mini(2,makes/3)
	next_set=Vector3([3.65,0.,-3.65][attack_lane],2.65,3.)
	super.reset_feed()
	mark.position=zone_center()
	panel.show()
	title.text=camp_title()

func change_feed_phase(next:String) -> void:
	if next=="pass" and phase=="feed" and is_instance_valid(hitter):
		toss_start=ball.position
		hitter.look_at(Vector3(coach.position.x,hitter.position.y,coach.position.z),Vector3.UP,true)
		platform.apply_pose(platform.contact_frame,1.)
		receive_point=platform.platform_center()
		hitter.play_action("idle")
		hitter.animator.advance(0.)
		platform_held=false
		receive_release=INF
		super.change_feed_phase("receive_toss")
		return
	super.change_feed_phase(next)

func step_attack(delta:float) -> void:
	super.step_attack(delta)
	if phase=="feed":
		coach.look_at(Vector3(hitter.position.x,coach.position.y,hitter.position.z),Vector3.UP,true)
	elif phase=="receive_toss":
		var t:=minf(elapsed,RECEIVE_TIME)
		platform.apply_pose(maxf(0.,platform.contact_frame+t-RECEIVE_TIME),smoothstep(RECEIVE_TIME-.65,RECEIVE_TIME-.18,t))
		ball.position=toss_start.lerp(receive_point,t/RECEIVE_TIME)+Vector3.UP*4.905*t*(RECEIVE_TIME-t)
		message.text="Coach toss"
		if elapsed>=RECEIVE_TIME and (cpu_hitter or is_finite(receive_release) or elapsed>=RECEIVE_TIME+.16):
			if not cpu_hitter and (absf(receive_release-RECEIVE_TIME)>.16 or platform.platform_center().distance_to(ball.position)>.5):
				attack_floor_pending=true
				drop_velocity=(receive_point-toss_start)/RECEIVE_TIME+Vector3.DOWN*4.905*RECEIVE_TIME
				message.text="Missed reception"
				begin("drop")
				return
			if not cpu_hitter: ContactTiming.scored("Reception",receive_release-RECEIVE_TIME,absf(receive_release-RECEIVE_TIME)<.05,true)
			source=platform.platform_center()
			ball.position=source
			var apex:=maxf(5.8,catch_point.y+.5)
			var rise:=sqrt(2.*(apex-source.y)/9.81)
			forehead_arrival=rise+sqrt(2.*(apex-forehead_target.y)/9.81)
			contact_time=rise+sqrt(2.*(apex-catch_point.y)/9.81)
			super.change_feed_phase("pass")
	elif phase=="pass":
		if elapsed<.35: platform.apply_pose(platform.contact_frame+elapsed,1.-smoothstep(.05,.35,elapsed))
		message.text="Pass to setter"

func attacking_receive_meter() -> Dictionary:
	if phase!="receive_toss" or cpu_hitter or (not platform_held and not is_finite(receive_release)): return {}
	var offset := (receive_release if is_finite(receive_release) else elapsed)-RECEIVE_TIME
	return {"value":clampf(.5+offset/.4,0.,1.),"released":is_finite(receive_release)}

func update_prompts(next:String) -> void:
	if cpu_hitter: entry_widget=EntryPrompt.mount(controls_row,"Enter")
	elif next=="receive_toss": Xbox.prompts(controls_row,[["A","Hold / release to receive"]])
	else:
		Xbox.prompts(controls_row,[["LS","Move / aim"],["LT","Lock on"],["RT","Sprint"],[JOY_BUTTON_X,"Hold left"],[JOY_BUTTON_Y,"Hold middle"],[JOY_BUTTON_B,"Hold right"],[JOY_BUTTON_LEFT_SHOULDER,"Roll"],[JOY_BUTTON_RIGHT_SHOULDER,"Tip"]])

func _input(event:InputEvent) -> void:
	if phase=="receive_toss" and not cpu_hitter and not settings.visible and not get_tree().paused and not event.is_echo():
		if (event is InputEventJoypadButton and event.button_index==Xbox.physical(JOY_BUTTON_A)) or (event is InputEventKey and event.physical_keycode==KEY_SPACE):
			if event.is_pressed(): platform_held=true
			elif platform_held and not is_finite(receive_release):
				receive_release=elapsed
				platform_held=false
			get_viewport().set_input_as_handled()
			return
	if not settings.visible and (event is InputEventJoypadButton and event.button_index==Xbox.physical(JOY_BUTTON_BACK) or event is InputEventKey and event.physical_keycode==KEY_TAB): return
	super._input(event)

func _process(delta:float) -> void:
	if closing: return
	if sideline_actor and not settings.visible: sideline_actor.animator.advance(delta)
	if cpu_hitter and not changing_turn and not settings.visible and not get_tree().paused:
		var down:=Input.is_key_pressed(KEY_ENTER) or (pad()>=0 and Input.is_joy_button_pressed(pad(),Xbox.physical(JOY_BUTTON_A)))
		join_time=join_time+delta if down else 0.
		if is_instance_valid(entry_widget): entry_widget.set_fraction(join_time)
		if join_time>=1.: fade_into_drill(enter_hitting_turn)
	super._process(delta)

func enter_hitting_turn() -> void:
	cpu_hitter=false
	switch_attacker(career_hitter,hitter)
	if rotation_drill.issued: rotation_drill.free_ball(Vector3.ZERO)
	coach_motion.whistle_cue.signal_drill(coach)
	reset_feed()
	update_prompts(phase)

func attack_surface_contact(point:Vector3,floor_hit:bool) -> void:
	var first_contact:=not attack_decided
	super.attack_surface_contact(point,floor_hit)
	if cpu_hitter or not first_contact or not attack_decided or not floor_hit or not drop_net_hit.is_empty(): return
	var error:=point-zone_center()
	if absf(error.x)>HALF_ZONE or absf(error.z)>HALF_ZONE: return
	makes+=1
	if makes==9:
		closing=true
		CareerSession.checkpoint("hitting_lesson_complete",9)
		MenuPresentation.load_scene("res://scenes/story.tscn")
	else:
		CareerSession.checkpoint("hitting_lesson",makes)
		title.text=camp_title()
		mark.position=zone_center()

func reset_drill() -> void:
	if CareerSession.checkpoint("hitting_lesson",0): MenuPresentation.load_scene(scene_file_path)

func leave() -> void:
	if CareerSession.checkpoint("hitting_lesson",makes): MenuPresentation.load_scene("res://scenes/story.tscn")
