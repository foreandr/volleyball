extends "res://scripts/attacking_camp.gd"

const POSITIONS:=["Left (4)","Middle (3)","Right (2)"]
const ZONES:=[1,6,5]
const HALF_ZONE:=1.35
var feed_after_return:=""
var career_hitter:Node3D
var sideline_actor:Node3D
var makes:=0
var demo_target:=0
var demo_hit:=false
var platform_held:=false
var receive_release:=INF
var reception:=preload("res://scripts/mapped_reception.gd").new()
var zones:Array[Dictionary]=[]
var motion:Dictionary={}
var receive_at:=0.
var touched_at:=-INF
var modifier_states:Dictionary={}
var feed_index:=0
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
	coach_only_feeds=true
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
	world.add_child(reception)
	reception.pose_origin=Node3D.new()
	world.add_child(reception.pose_origin)
	reception.defenders.append(reception.pose_origin)
	reception.clips=JSON.parse_string(FileAccess.get_file_as_string("res://assets/reception_studio.json"))
	zones=reception.assigned_boxes()
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
	finish_reception()
	hitter=active
	jump_height=float(active.attributes.vertical_in)*.0254
	sideline_actor=waiting
	if cpu_hitter: active.position=GroundControls.BACK_LEFT
	waiting.position=GroundControls.BACK_MIDDLE
	waiting.look_at(Vector3(coach.position.x,waiting.position.y,coach.position.z),Vector3.UP,true)
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
	finish_reception()
	if cpu_hitter and demo_hit: demo_target=(demo_target+1)%ZONES.size()
	demo_hit=false
	coach_station=Vector3(-.58,0,BallNet.NET_Z+2.6)
	attack_lane=mini(2,makes/3)
	next_set=Vector3([3.65,0.,-3.65][attack_lane],2.65,3.)
	var previous:=hitter.position
	super.reset_feed()
	hitter.position=Vector3(previous.x,START.y,previous.z)
	prep_velocity=Vector3.ZERO
	if cpu_hitter and phase in ["cart","walk"]:
		feed_after_return=phase
		begin("return_to_five")
	mark.position=zone_center()
	panel.show()
	title.text=camp_title()

func change_feed_phase(next:String) -> void:
	if next=="pass" and phase=="feed" and is_instance_valid(hitter):
		toss_start=ball.position
		var offsets:=[Vector3(0,1.12,.58),Vector3(-.34,1.55,.54),Vector3(.10,2.05,.42)]
		receive_point=GroundControls.BACK_LEFT+Vector3(offsets[feed_index%offsets.size()])
		feed_index+=1
		receive_at=RECEIVE_TIME
		touched_at=-INF
		platform_held=false
		receive_release=INF
		super.change_feed_phase("receive_toss")
		return
	super.change_feed_phase(next)

func team_controls_approach() -> bool:
	return phase in ["return_to_five","cart","walk","feed","between","drop","spike"]

func step_attack(delta:float) -> void:
	if phase=="return_to_five":
		super.step_attack(delta)
		if rotation_drill.walk(hitter,GroundControls.BACK_LEFT,delta,5.2):
			prep_velocity=Vector3.ZERO
			hitter.look_at(Vector3(coach.position.x,hitter.position.y,coach.position.z),Vector3.UP,true)
			begin(feed_after_return)
		return
	var before_step:=hitter.position
	super.step_attack(delta)
	if not motion.is_empty(): reception.pose_origin.position+=(hitter.position-before_step).slide(Vector3.UP)
	if phase in ["cart","feed"]:
		GroundControls.face(coach,GroundControls.BACK_LEFT-coach.position,delta)
	elif phase=="receive_toss":
		var previous:=ball.position
		ball.position=feed_point(elapsed)
		message.text="Coach toss"
		var armed:=cpu_hitter or platform_held or is_finite(receive_release)
		if armed and motion.is_empty() and elapsed>RECEIVE_TIME-.6: bind_reception()
		if not motion.is_empty():
			var frame:=clampf(motion.contact+60.*(elapsed-receive_at),0.,motion.frames)
			reception.sample_receiver(motion,frame,true,reception.legs)
			if reception.segment_touch(motion,previous,ball.position): touched_at=elapsed
		var released:=cpu_hitter or absf(receive_release-receive_at)<=.21
		if released and elapsed-touched_at<=.095:
			if not cpu_hitter: ContactTiming.scored("Reception",receive_release-receive_at,absf(receive_release-receive_at)<.05,true)
			source=ball.position
			var apex:=maxf(5.8,catch_point.y+.5)
			var rise:=sqrt(2.*(apex-source.y)/9.81)
			forehead_arrival=rise+sqrt(2.*(apex-forehead_target.y)/9.81)
			contact_time=rise+sqrt(2.*(apex-catch_point.y)/9.81)
			super.change_feed_phase("pass")
		elif ball.position.y<=Contact.BALL_RADIUS:
			finish_reception()
			attack_floor_pending=true
			drop_velocity=(receive_point-toss_start)/RECEIVE_TIME+Vector3.UP*9.81*(RECEIVE_TIME*.5-elapsed)
			message.text="Missed reception"
			begin("drop")
	elif phase=="pass":
		if not motion.is_empty():
			if elapsed<.28:
				reception.sample_receiver(motion,minf(motion.frames,motion.contact+elapsed*60.),true,reception.legs)
			else: finish_reception()
		message.text="Pass to setter"

func feed_point(t:float) -> Vector3:
	return toss_start.lerp(receive_point,t/RECEIVE_TIME)+Vector3.UP*4.905*t*(RECEIVE_TIME-t)

func bind_reception() -> void:
	var home:=hitter.position
	var facing:=atan2(toss_start.x-home.x,toss_start.z-home.z)
	var t:=elapsed
	var previous:=(feed_point(t)-home).rotated(Vector3.UP,-facing)
	while t<RECEIVE_TIME+.30:
		t+=1./60.
		var point:=(feed_point(t)-home).rotated(Vector3.UP,-facing)
		var best:Dictionary={}
		var earliest:=INF
		for zone in zones:
			var span:=reception.zone_interval(previous,point,zone.bounds)
			if span.y>span.x and span.x<earliest:
				earliest=span.x
				best=zone
		if not best.is_empty():
			receive_at=t-(1.-earliest)/60.
			reception.set_intercept=feed_point(receive_at)
			reception.incoming_lead_seconds=maxf(0.,receive_at-elapsed)
			reception.feed_kmh=3.6*receive_point.distance_to(toss_start)/RECEIVE_TIME
			reception.pass_goal=forehead_target
			for mod in hitter.skeleton.get_children():
				if mod is SkeletonModifier3D: modifier_states[mod]=mod.active
			var original:=hitter.global_transform
			motion=reception.begin_mapped_motion(reception.pose_origin,hitter,home,toss_start,best,.12)
			receive_at=reception.align_contact(motion,feed_point,receive_at,elapsed,RECEIVE_TIME+.30)
			hitter.global_transform=original
			trace("attack_reception_grid",{"clip":motion.id,"kind":motion.kind,"cell":str(best.cell)})
			return
		previous=point

func finish_reception() -> void:
	if motion.is_empty(): return
	for mod in modifier_states: mod.active=modifier_states[mod]
	modifier_states.clear()
	hitter.global_basis=Basis(Vector3.UP,hitter.rotation.y)*Basis.from_scale(reception.athlete_scale)
	hitter.position.y=START.y
	hitter.play_action("idle",.18)
	hitter.animator.play()
	motion={}
	reception.player=null

func attacking_receive_meter() -> Dictionary:
	if phase!="receive_toss" or cpu_hitter or (not platform_held and not is_finite(receive_release)): return {}
	var offset := (receive_release if is_finite(receive_release) else elapsed)-receive_at
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
