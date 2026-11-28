extends "res://scripts/serving_camp.gd"

const ZONES:=CareerSession.SERVE_ZONES
const TARGET_OFFSETS:=[Vector2(3.,7.5),Vector2(-3.,7.5),Vector2(0.,7.5)]
const TARGET_HALF_SIZE:=1.5
const PROGRESS_KEY:="serving_zones_156"
var demo_target:=0
var gathering := false
var address_time := 0.
var teammates: Array = []
var role_picker:OptionButton
var start_match:Button
var role_panel:HBoxContainer

func call_team_in() -> void:
	if gathering or not CareerSession.practice_stage.is_empty() or not finished_serving(): return
	gathering=true
	watching=false
	pending_serve=-1
	ball.hide()
	target_patch.hide()
	panel.hide()
	for driver in serves: driver.hide()
	say(coach,"Everyone, bring it in!",1.5)
	get_tree().create_timer(1.5,false).timeout.connect(func(): fade_into_drill(stage_huddle))

func stage_huddle() -> void:
	var crowd=get_children().filter(func(node): return node.get_script()==preload("res://scripts/practice_ambience.gd")).front()
	var athletes:Array=crowd.partners.duplicate()
	for pair in crowd.get_children():
		if pair.get_script()==crowd.get_script():
			athletes.append_array(pair.partners)
			pair.set_process(false)
			pair.orb.hide()
	crowd.set_process(false)
	crowd.orb.hide()
	for seat in crowd.seats:
		if athletes.size()==11: break
		athletes.append(seat.actor)
	hitter.apply_profile(CareerSession.profile())
	for actor in athletes:
		rotation_drill.roster.append(actor)
		teammates.append(actor.attributes.duplicate(true))
	var group:Array=rotation_drill.roster+[coach]
	for i in group.size():
		var actor:Node3D=group[i]
		var angle:=TAU*i/group.size()-PI
		actor.position=rotation_drill.HUDDLE_CENTER+Vector3(sin(angle),0,cos(angle))*1.52
		actor.look_at(rotation_drill.HUDDLE_CENTER,Vector3.UP,true)
		actor.play_action("base/Idle",0.)
		actor.animator.advance(0.)
	camera.position=Vector3(-2.7,2.65,-5.6)
	camera.fov=40.
	camera.look_at(rotation_drill.HUDDLE_CENTER+Vector3.UP*1.04)
	rotation_drill.huddle_speech="Thanks for coming out, everyone. Let's play six on six! What position do you want?"
	rotation_drill.huddle_radius=1.27
	phase="scrimmage_huddle"

func show_positions() -> void:
	role_panel=HBoxContainer.new()
	role_picker=OptionButton.new()
	start_match=Button.new()
	add_child(role_panel)
	role_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	role_panel.alignment=BoxContainer.ALIGNMENT_CENTER
	role_panel.offset_left=-300
	role_panel.offset_right=300
	role_panel.offset_top=-85
	role_panel.offset_bottom=-30
	role_panel.add_child(role_picker)
	role_picker.add_item("Choose your position")
	role_picker.set_item_disabled(0,true)
	for label in ["Setter","Outside hitter 1","Outside hitter 2","Opposite","Middle blocker 1","Middle blocker 2","Libero"]:
		role_picker.add_item(label)
	role_picker.select(0)
	role_panel.add_child(start_match)
	start_match.text="Start 6v6"
	start_match.disabled=true
	role_picker.item_selected.connect(func(index): start_match.disabled=index<=0)
	start_match.pressed.connect(func():
		var index:=role_picker.selected-1
		if index>=0: CareerSession.open_scrimmage(CareerSession.SCRIMMAGE_ROLES[index],teammates))
	role_picker.grab_focus()

var target_patch:=MeshInstance3D.new()

func finished_serving() -> bool:
	return CareerSession.completed_serve_zones(hits)==ZONES.size()

func target_index() -> int:
	if watching: return demo_target
	for i in ZONES.size():
		if hits.count(ZONES[i])<CareerSession.SERVES_PER_ZONE: return i
	return ZONES.size()-1

func target_center() -> Vector3:
	var offset:Vector2=TARGET_OFFSETS[target_index()]
	return Vector3(offset.x,.052,BallNet.NET_Z+offset.y)

func target_number() -> int:
	return ZONES[target_index()]

func refresh_target() -> void:
	if not watching and finished_serving():
		target_patch.hide()
		title.text="Serving complete   /   3 of 3"
		return
	target_patch.show()
	target_patch.position=target_center()
	title.text="Serve to zone %d"%target_number() if watching else "Zone %d: %d/%d serves   ·   %d/%d zones complete"%[target_number(),hits.count(target_number()),CareerSession.SERVES_PER_ZONE,CareerSession.completed_serve_zones(hits),ZONES.size()]

func next_serve() -> void:
	super.next_serve()
	if watching: destination=target_center()
	refresh_target()

var demo_wait:=0.
var hits:Array=[]
var serves_in:int:
	get: return hits.size()

var watching:=true
var entry_widget:Control
var join_time:=0.

func update_prompts(next:String) -> void:
	if watching:
		if not is_instance_valid(entry_widget):
			entry_widget=preload("res://scripts/drill_entry_prompt.gd").mount(controls_row,"Enter")
	elif next!="defend": super.update_prompts(next)

func _process(delta:float) -> void:
	if gathering:
		if settings.visible or get_tree().paused: return
		update_speech(delta)
		if phase=="scrimmage_huddle":
			rotation_drill.huddle(delta)
			if rotation_drill.huddle_planted:
				address_time+=delta
				if address_time>=2. and not is_instance_valid(role_panel): show_positions()
		return
	if watching and not changing_turn and not settings.visible and not get_tree().paused and not replay_inspector.active:
		var down:=Input.is_key_pressed(KEY_ENTER) or (pad()>=0 and Input.is_joy_button_pressed(pad(),Xbox.physical(JOY_BUTTON_A)))
		join_time=join_time+delta if down else 0.
		if is_instance_valid(entry_widget): entry_widget.set_fraction(join_time)
		if join_time>=1.: fade_into_drill(enter_turn)
		if phase=="serve_ready":
			demo_wait+=delta
			if pending_serve<0 and demo_wait>=.8:
				demo_wait=0.
				handle_serve_button(SPIN_SERVE,true)
		elif phase=="serve_toss" and not is_finite(release_time) and serve_meter_error()>=-.01: handle_serve_button(SPIN_SERVE,false)
	super._process(delta)

func _input(event:InputEvent) -> void:
	if gathering:
		if event.is_action_pressed("ui_cancel") and (not role_picker or not role_picker.get_popup().visible): settings.show()
		elif event is InputEventJoypadButton and event.pressed and event.button_index==Xbox.physical(JOY_BUTTON_START): settings.show()
		return
	if watching and not settings.visible and not get_tree().paused:
		if event is InputEventJoypadButton and event.button_index in [Xbox.physical(JOY_BUTTON_A),Xbox.physical(JOY_BUTTON_X),Xbox.physical(JOY_BUTTON_Y),Xbox.physical(JOY_BUTTON_B)]: return
		if event is InputEventKey and event.keycode in [KEY_ENTER,KEY_SPACE,KEY_Q,KEY_W,KEY_E,KEY_R]: return
	super._input(event)

func enter_turn() -> void:
	toss_style=SPIN_SERVE
	spin_selection=0
	watching=false
	prompt_phase=""
	next_serve()
	if not CareerSession.profile().is_empty(): hitter.apply_profile(CareerSession.profile())
	coach_motion.whistle_cue.signal_drill(coach)

func start_drill() -> void:
	if CareerSession.practice_stage.is_empty():
		var saved=CareerSession.data.get_value(CareerSession.key(),PROGRESS_KEY,[])
		if saved is Array:
			for zone in saved:
				if zone in ZONES and hits.count(zone)<CareerSession.SERVES_PER_ZONE: hits.append(zone)
	super.start_drill()
	register_student(hitter,1)
	pin_attack.status.hide()
	middle_decoy.status.hide()
	for actor in passers+wall+[receiving_setter,receiving_middle,pin_hitter]:
		actor.hide()
	coach.position=Vector3(-5.,.04,BallNet.NET_Z-.35)
	coach.show()
	coach.play_action("idle")
	var surface:=PlaneMesh.new()
	surface.size=Vector2.ONE*TARGET_HALF_SIZE*2.
	var ink:=StandardMaterial3D.new()
	ink.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	ink.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.albedo_color=Color(.19,.94,.47,.47)
	surface.material=ink
	target_patch.mesh=surface
	world.add_child(target_patch)
	refresh_target()
	if finished_serving(): call_team_in.call_deferred()

func update_serve_aim(delta:float) -> void:
	if watching: destination=target_center()
	super.update_serve_aim(0. if watching else delta)

func build_rally_sliders() -> void:
	pass

func step_serve_reception(_shot,_previous:Vector3,_delta:float) -> void:
	pass

func show_service_ace() -> void:
	if not watching and finished_serving(): return
	var gap:=ball.position-target_center()
	if absf(gap.x)>TARGET_HALF_SIZE or absf(gap.z)>TARGET_HALF_SIZE:
		message.text="In, outside zone %d"%target_number()
		coach_react("miss")
		return
	message.text="Zone %d hit"%target_number()
	coach_react("praise")
	if watching:
		demo_target=(demo_target+1)%ZONES.size()
		return
	hits.append(target_number())
	CareerSession.data.set_value(CareerSession.key(),PROGRESS_KEY,hits.duplicate())
	CareerSession.checkpoint("serving_complete" if finished_serving() else "serving_lesson",serves_in)
	refresh_target()
	if finished_serving(): call_team_in.call_deferred()

func serve_out() -> void:
	message.text="Serve out"

func save_and_leave_drill() -> void:
	if CareerSession.checkpoint("serving_complete" if finished_serving() else "serving_lesson",serves_in):
		MenuPresentation.load_scene("res://scenes/story.tscn")

func reset_drill() -> void:
	hits.clear()
	CareerSession.data.set_value(CareerSession.key(),PROGRESS_KEY,[])
	if CareerSession.checkpoint("serving_lesson",0): MenuPresentation.load_scene(scene_file_path)
