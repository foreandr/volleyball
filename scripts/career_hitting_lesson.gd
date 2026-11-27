extends "res://scripts/attacking_camp.gd"

const POSITIONS:=["Left (4)","Middle (3)","Right (2)"]
const ZONES:=[1,6,5]
const HALF_ZONE:=1.35
const SIDELINE:=Vector3(5.4,.04,.65)
var career_hitter:Node3D
var sideline_actor:Node3D
var makes:=0

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
	sideline_actor=waiting
	waiting.position=SIDELINE
	waiting.look_at(Vector3(0,SIDELINE.y,3),Vector3.UP,true)
	waiting.play_action("idle",0.)
	waiting.animator.advance(0.)

func zone_center() -> Vector3:
	return Vector3([2.9,0.,-2.9][makes%3],.065,BallNet.NET_Z+5.8)

func camp_title() -> String:
	return "Hitting   /   %s to zone %d   /   Set height %d   /   %d of 9 correct"%[POSITIONS[mini(2,makes/3)],ZONES[makes%3],height_preset(),makes]

func reset_feed() -> void:
	attack_lane=mini(2,makes/3)
	next_set=Vector3([3.65,0.,-3.65][attack_lane],2.65,3.)
	super.reset_feed()
	mark.position=zone_center()
	panel.show()
	title.text=camp_title()

func update_prompts(next:String) -> void:
	if cpu_hitter: entry_widget=EntryPrompt.mount(controls_row,"Enter")
	else:
		Xbox.prompts(controls_row,[["LS","Move / aim"],["LT","Lock on"],["RT","Sprint"],[JOY_BUTTON_X,"Hold left"],[JOY_BUTTON_Y,"Hold middle"],[JOY_BUTTON_B,"Hold right"],[JOY_BUTTON_LEFT_SHOULDER,"Roll"],[JOY_BUTTON_RIGHT_SHOULDER,"Tip"]])

func _input(event:InputEvent) -> void:
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
