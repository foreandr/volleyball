extends CanvasLayer

const Xbox = preload("res://scripts/xbox_controls.gd")
const ReplayControls=preload("res://scripts/replay_controls.gd")
const SUB := 4
var speed := 1.
var slow_speed := .25
var frame_number := Label.new()
var rate := Button.new()
var toggle_boxes: CheckButton
var show_boxes := false
var boxes: Array[MeshInstance3D] = []
const SAMPLE_INTERVAL := 0.1
const MAX_SAMPLES := 450
@onready var game = get_parent()
var history: Array[Dictionary] = []
var live := {}
var camera := Camera3D.new()
var slider := HSlider.new()
var panel := PanelContainer.new()
var elapsed := 0.0
var sample_interval := SAMPLE_INTERVAL
var sample_limit := MAX_SAMPLES
var active := false
var replay_hand := AudioStreamPlayer.new()
var replay_whistle := AudioStreamPlayer.new()
var replay_floor := AudioStreamPlayer.new()
var playing := false
var playback_elapsed := 0.
var hidden_controls := []
var modifiers := []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 100
	replay_hand.stream=preload("res://assets/audio/hand_gym_01.wav")
	replay_floor.stream=preload("res://assets/audio/floor_impacts.tres")
	for player in [replay_hand,replay_floor,replay_whistle]:
		player.max_polyphony=3
		add_child(player)
	if "practice_blockers" in game:
		sample_interval=1./60.
		sample_limit=900
	layer = 90
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_bottom = -18
	panel.add_theme_stylebox_override("panel",MenuPresentation.box(Color("0c1b28ed"),Color("70dfc2"),3))
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation",3)
	panel.add_child(layout)
	for entries in [[["LS","Move"],["RS","Look"],["LB","Lower"],["RB","Raise"],["X","Zoom in"],["B","Zoom out"]],[["LT","Rewind"],["RT","Advance"],["D-pad Left/Right","Frame"],["A","Play / pause"],["View","Exit"]]]:
		var row := HBoxContainer.new()
		row.alignment=BoxContainer.ALIGNMENT_CENTER
		layout.add_child(row)
		Xbox.prompts(row,entries)
	if Xbox.keyboard_prompts():
		var legend := Label.new()
		legend.text="Space play/pause    Drag to rewind    WASD move    Q/E down/up    Middle-drag look    Scroll zoom    Esc return"
		layout.add_child(legend)
	var tools := HBoxContainer.new()
	tools.alignment=BoxContainer.ALIGNMENT_CENTER
	layout.add_child(tools)
	for direction: int in [-1,1]:
		var arrow := Button.new()
		arrow.text="<" if direction<0 else ">"
		arrow.tooltip_text="Previous frame" if direction<0 else "Next frame"
		arrow.pressed.connect(step_frame.bind(direction))
		tools.add_child(arrow)
	tools.add_child(frame_number)
	rate.text="Slow-mo  1x"
	var rates := [1.,.25,.125,.0625,.5]
	rate.pressed.connect(func(): set_replay_speed(rates[(rates.find(speed)+1)%rates.size()]))
	var rs_prompt := HBoxContainer.new()
	tools.add_child(rs_prompt)
	Xbox.prompts(rs_prompt,[["RS","Click"]])
	tools.add_child(rate)
	if "practice_blockers" in game:
		var ls_prompt := HBoxContainer.new()
		tools.add_child(ls_prompt)
		Xbox.prompts(ls_prompt,[["LS","Click"]])
		toggle_boxes=CheckButton.new()
		toggle_boxes.text="Block hitboxes"
		toggle_boxes.toggled.connect(func(on): show_boxes=on; display_frame(slider.value))
		tools.add_child(toggle_boxes)
	layout.add_child(slider)
	slider.step = 1
	slider.value_changed.connect(func(value): if active: display_frame(value))
	panel.hide()

func set_replay_speed(value: float) -> void:
	speed=value
	if speed<1.: slow_speed=speed
	rate.text="Slow-mo  %s" % ("1x" if speed==1. else "1/%dx" % roundi(1./speed))
	if slider.value>=slider.max_value: slider.value=0
	playing=true
	playback_elapsed=0.

func capture(rendered := false) -> Dictionary:
	var objects := {}
	var poses := {}
	var candidates: Array = game.world.get_children()
	if "receiving_team" in game:
		for actor in game.receiving_team:
			if actor.get_parent()!=game.world: candidates.append(actor)
	if "defense_map" in game and game.defense_map.player!=null:
		candidates.append(game.defense_map.player)
	for obj in candidates:
		if obj is not Node3D: continue
		if "skeleton" in obj and obj.skeleton is Skeleton3D:
			var rig: Skeleton3D = obj.skeleton
			var bones: Array[Transform3D] = []
			for bone in rig.get_bone_count(): bones.append(rig.get_bone_pose(bone))
			poses[rig] = bones
			if rendered:
				for modifier in rig.get_children():
					if "replay_bones" in modifier: modifier.replay_bones = bones
			objects[obj.model] = [obj.model.transform,obj.model.visible]
		elif obj != game.ball and obj is not RigidBody3D and obj not in game.targets and obj not in game.rotation_drill.bins and obj != game.rotation_drill.basket: continue
		objects[obj] = [obj.global_transform,obj.visible] if "skeleton" in obj else [obj.transform,obj.visible]
	var arms := {}
	var armed := {}
	if "practice_blockers" in game:
		var actors: Array=game.wall if "wall_jumps" in game else game.blockers if "blockers" in game else game.practice_blockers
		var jumps: Array=game.wall_jumps if "wall_jumps" in game else game.jumps if "blockers" in game else game.practice_jumps
		for slot in actors.size():
			if not actors[slot].visible: continue
			var jump = jumps[slot]
			for i in 2:
				var key: int=slot*2+i
				armed[key]=jump!=null and jump.hands.size()>i
				if armed[key]:
					arms[key]=[jump.shoulders[i],jump.elbows[i],jump.wrists[i],jump.hands[i]]
				else:
					var points := []
					var side := "_l" if i==0 else "_r"
					for bone in ["upperarm","lowerarm","hand","middle_03"]:
						points.append(preload("res://scripts/gym_physics.gd").joint(actors[slot],bone+side))
					arms[key]=points
			if jump!=null:
				for side in jump.body_chains.size():
					var key: int = -1-slot*2-side
					arms[key]=jump.body_chains[side]
					armed[key]=true
	var timing: Dictionary=game.rings.displayed_timing.duplicate()
	var verdict := ""
	if "reception_release" in game:
		if game.pass_timing_ready and (game.phase==("serve_return" if game.control_digger else "serve_flight") or not game.reception_release.is_empty()):
			var meter: Dictionary=game.pass_meter()
			verdict=game.reception_release.get("label","")
			var actor: Node3D=game.controlled_passer()
			timing[actor]={"position":Vector3(actor.global_position.x,.055,actor.global_position.z),"value":meter.value,"perfect":Vector2(.33,.67),"contact":Vector2(.08,.90),"miss":Color("14191d"),"highlight":not game.reception_release.is_empty(),"black_cursor":not game.receive_held,"stamina":actor.stamina.fraction()}
		if game.reception_result!="": verdict+=("  /  " if verdict!="" else "")+game.reception_result
	return {"held_buttons":game.held_input.read_buttons(),"landing":game.projected_landing(),"release_verdict":verdict,"timing":timing,"boundary":game.court_boundary.verdict,"boundary_z":game.court_boundary.position.z,"impact":game.get_meta("block_impact_segment",Vector2i(-999,-1)),"rally":game.get("replay_rally"),"armed":armed,"arms":arms,"floor_count":game.floor_sound_count,"floor_db":game.floor_impact.volume_db,"spike_count":game.spike_sound_count if "spike_sound_count" in game else 0,"block_sound_count":game.block_sound_count if "block_sound_count" in game else 0,"objects":objects,"poses":poses,"whistle_count":game.coach_motion.whistle_cue.play_count,"floor_stream":game.floor_impact.stream,"whistle_height":game.coach_motion.whistle_cue.raised}

func apply(sample: Dictionary) -> void:
	game.held_input.display(sample.get("held_buttons",-1))
	game.landing_ring.place(sample.get("landing",Vector3.INF))
	game.rings.replay_timing(sample.timing)
	game.court_boundary.position.z=sample.get("boundary_z",8.5)
	game.court_boundary.display(sample.get("boundary",0))
	game.coach_motion.whistle_cue.raised = sample.whistle_height
	for obj in live.objects:
		if not is_instance_valid(obj): continue
		if not sample.objects.has(obj):
			obj.hide()
			continue
		var state: Array = sample.objects[obj]
		if "skeleton" in obj: obj.global_transform=state[0]
		else: obj.transform = state[0]
		obj.visible = state[1]
	for rig in sample.poses:
		if not is_instance_valid(rig): continue
		var bones: Array = sample.poses[rig]
		for i in bones.size(): rig.set_bone_pose(i,bones[i])

func step_frame(direction: int) -> void:
	playing=false
	playback_elapsed=0.
	slider.value=clampf((floorf(slider.value/SUB)+1. if direction>0 else ceilf(slider.value/SUB)-1.)*SUB,0.,slider.max_value)

func display_frame(value: float) -> void:
	if history.is_empty(): return
	var first := mini(int(value)/SUB,history.size()-1)
	frame_number.text="Frame %d / %d" % [first+1,history.size()]
	var a := history[first]
	if a.release_verdict!="": frame_number.text+="    "+a.release_verdict
	var b := history[mini(first+1,history.size()-1)]
	var t := fmod(value,SUB)/SUB
	apply(a)
	if t>0. and a.rally==b.rally:
		for obj in a.objects:
			if is_instance_valid(obj) and b.objects.has(obj):
				var interpolated: Transform3D=a.objects[obj][0].interpolate_with(b.objects[obj][0],t)
				if "skeleton" in obj: obj.global_transform=interpolated
				else: obj.transform=interpolated
		for rig in a.poses:
			if not is_instance_valid(rig) or not b.poses.has(rig): continue
			for i in a.poses[rig].size():
				rig.set_bone_pose(i,a.poses[rig][i].interpolate_with(b.poses[rig][i],t))
		var timing: Dictionary=a.timing.duplicate(true)
		for actor in timing:
			if b.timing.has(actor) and not timing[actor].highlight:
				timing[actor].value=lerpf(timing[actor].value,b.timing[actor].value,t)
				timing[actor].position=timing[actor].position.lerp(b.timing[actor].position,t)
		game.rings.replay_timing(timing)
	for mesh in boxes: mesh.hide()
	if not show_boxes: return
	var used := 0
	for arm in a.arms:
		var points: Array=a.arms[arm].duplicate()
		var actors: Array=game.wall if "wall_jumps" in game else game.blockers if "blockers" in game else game.practice_blockers
		var idx: int=arm if arm>=0 else -1-arm
		var actor: Node3D=actors[idx/2]
		var side := "_l" if idx%2==0 else "_r"
		var joints := ["upperarm"+side,"lowerarm"+side,"hand"+side,"middle_03"+side] if arm>=0 else ["upperarm"+side,"neck_01"]
		if arm<0 and idx%2==0: joints.append("Head")
		points.clear()
		for joint in joints: points.append(preload("res://scripts/gym_physics.gd").joint(actor,joint))
		if arm<0 and idx%2==0: points.append(points[2]+points[1].direction_to(points[2])*.11)
		for i in points.size()-1:
			var segment: Vector3=points[i+1]-points[i]
			if segment.length_squared()<.000001: continue
			if used==boxes.size():
				var mesh := MeshInstance3D.new()
				mesh.mesh=CapsuleMesh.new()
				var mat := StandardMaterial3D.new()
				mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
				mat.no_depth_test=true
				mat.render_priority=100
				mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mesh.material_override=mat
				game.world.add_child(mesh)
				boxes.append(mesh)
			var capsule := boxes[used]
			capsule.material_override.albedo_color=Color(.08,1.,.44,.65) if a.armed[arm] else Color(.25,.72,1.,.48)
			if a.impact==Vector2i(arm,i) and a.block_sound_count>history[maxi(first-3,0)].block_sound_count:
				capsule.material_override.albedo_color=Color(1.,.06,.04,.88)
			used+=1
			var radius: float=preload("res://scripts/match_block.gd").ARM_RADII[i] if arm>=0 else preload("res://scripts/match_block.gd").BODY_RADII[i]
			capsule.mesh.radius=radius
			capsule.mesh.height=segment.length()+2.*radius
			capsule.global_transform=Transform3D(Basis(Quaternion(Vector3.UP,segment.normalized())),(points[i]+points[i+1])*.5)
			capsule.show()

func toggle() -> void:
	if active:
		for mesh in boxes: mesh.hide()
		apply(live)
		active = false
		game.held_input.reviewing=false
		playing = false
		replay_hand.stop()
		replay_floor.stop()
		replay_whistle.stop()
		for modifier in modifiers: modifier.active = true
		modifiers.clear()
		game.camera.make_current()
		camera.get_parent().remove_child(camera)
		for control in hidden_controls: control.show()
		hidden_controls.clear()
		panel.hide()
		live = {}
		get_tree().paused = false
		return
	if get_tree().paused: return
	live = capture()
	history.append(live)
	if history.size()>sample_limit: history.pop_front()
	for rig in live.poses:
		for modifier in rig.get_children():
			if modifier is SkeletonModifier3D and modifier.active:
				modifiers.append(modifier)
				modifier.active = false
	for control in game.get_children():
		if control is Control and control.visible:
			hidden_controls.append(control)
			control.hide()
	game.world.add_child(camera)
	camera.global_transform = game.camera.global_transform
	camera.fov = game.camera.fov
	camera.make_current()
	get_tree().paused = true
	active = true
	game.held_input.reviewing=true
	slider.max_value = (history.size()-1)*SUB
	slider.set_value_no_signal(slider.max_value)
	display_frame(slider.value)
	panel.show()

func _exit_tree() -> void:
	if active: get_tree().paused = false
	if not camera.is_inside_tree(): camera.free()

var setter_frames: Array[Dictionary] = []
var previous_set: Array[Dictionary] = []
var previous_contact := -1
var rep_clock := 0.
var last_toss := -INF
var contact_index := -1

func record_setter(delta: float) -> void:
	var attack := game.has_method("frame_editor_attacker")
	if attack:
		if game.phase not in ["set_contact","set","spike","drop"]: return
	elif not game.solo_setting or game.phase not in ["pass","forehead_catch","set_contact","set"]: return
	if last_toss!=game.last_toss:
		last_toss=game.last_toss
		if contact_index>=0 or (attack and setter_frames.size()>1 and previous_set.is_empty()):
			previous_set=setter_frames
			previous_contact=contact_index
		setter_frames=[]
		rep_clock=0.
		contact_index=-1
	rep_clock+=delta
	var frame_count := mini(360,1+floori(rep_clock*60.))
	if setter_frames.size()>=frame_count: return
	var actor = game.frame_editor_blocker() if game.has_method("frame_editor_blocker") else game.frame_editor_attacker() if attack else game.setter
	var pose: Array[Transform3D]=[]
	for i in actor.skeleton.get_bone_count(): pose.append(actor.skeleton.get_bone_pose(i))
	for modifier in actor.skeleton.get_children():
		if "editor_bones" in modifier: modifier.editor_bones=pose
	var contact_phase: bool = game.phase=="spike" if attack else game.phase in ["forehead_catch","set_contact","set"]
	if contact_phase and contact_index<0: contact_index=setter_frames.size()
	while setter_frames.size()<frame_count:
		setter_frames.append({"time":setter_frames.size()/60.,"ball":game.ball.global_transform,
			"actors":[{"root":actor.transform,"bones":pose}]})

func edit_setter_frames() -> void:
	var replay := preload("res://scripts/match_replay.gd").new()
	var use_previous := contact_index<0 and not previous_set.is_empty()
	replay.frames=previous_set if use_previous else setter_frames
	var contact := previous_contact if use_previous else contact_index
	replay.index=contact if contact>=0 else replay.frames.size()-1
	var attack := game.has_method("frame_editor_attacker")
	var actor = game.frame_editor_blocker() if game.has_method("frame_editor_blocker") else game.frame_editor_attacker() if attack else game.setter
	if replay.frames.is_empty():
		var bones: Array[Transform3D]=[]
		for i in actor.skeleton.get_bone_count(): bones.append(actor.skeleton.get_bone_pose(i))
		for i in 2: replay.frames.append({"time":i/60.,"ball":game.ball.global_transform,"actors":[{"root":actor.transform,"bones":bones}]})
		replay.index=0
	StorySession.edit_animation=replay.bake_recorded_actor(actor,0,"Blocker 509" if game.has_method("frame_editor_blocker") else "Attacker spike" if attack else "Setter release",contact,true)
	StorySession.edit_entry={"id":"camp_setter_catch","name":"Setter release","category":"Setting","type":"Overhead"}
	if attack: StorySession.edit_entry={"id":"camp_attacker_spike","name":"Attacker spike","category":"Attacking","type":"Spike"}
	if game.has_method("frame_editor_blocker"): StorySession.edit_entry={"id":"camp_blocker_509","name":"Blocker 509","category":"Blocking","type":"Block"}
	StorySession.animation_draft.clear()

func _process(delta: float) -> void:
	if active:
		if CareerSession.prompt.visible: return
		var pad_id: int=game.pad()
		var scrub:=ReplayControls.scrub(pad_id)
		if scrub!=0.: playing=false
		if playing or scrub!=0.:
			playback_elapsed+=delta*(scrub if scrub!=0. else speed)
			var tick := sample_interval/SUB
			var frames := int(playback_elapsed/tick)
			if frames!=0:
				playback_elapsed=fmod(playback_elapsed,tick)
				var old_index := int(slider.value)
				slider.value+=frames
				for i in range(old_index/SUB+1,int(slider.value)/SUB+1):
					var sample := history[i]
					var prior := history[i-1]
					for hit in ["spike_count","block_sound_count"]:
						if sample[hit]>prior[hit]:
							replay_hand.volume_db=-2.
							replay_hand.play()
					if sample.whistle_count>prior.whistle_count:
						replay_whistle.stream=game.coach_motion.whistle_cue.sound.stream
						replay_whistle.play()
					if sample.floor_count>prior.floor_count:
						replay_floor.stream=sample.floor_stream
						replay_floor.volume_db=sample.floor_db
						replay_floor.play()
				if slider.value>=slider.max_value: playing=false
		ReplayControls.move_camera(camera,pad_id,delta)
	elif not get_tree().paused:
		record_setter(delta)
		elapsed += delta
		if elapsed >= sample_interval:
			elapsed = fmod(elapsed,sample_interval)
			history.append(capture(true))
			if history.size()>sample_limit: history.pop_front()

func _input(event: InputEvent) -> void:
	if not active or CareerSession.prompt.visible: return
	if event is InputEventJoypadButton and event.device==game.pad():
		if event.pressed:
			match event.button_index:
				JOY_BUTTON_A:
					if slider.value>=slider.max_value: slider.value=0
					playing=not playing
					playback_elapsed=0.
				JOY_BUTTON_RIGHT_STICK: set_replay_speed(slow_speed if speed==1. else 1.)
				JOY_BUTTON_LEFT_STICK:
					if toggle_boxes!=null: toggle_boxes.button_pressed=not toggle_boxes.button_pressed
				JOY_BUTTON_BACK: toggle()
				JOY_BUTTON_DPAD_LEFT,JOY_BUTTON_DPAD_RIGHT:
					playing=false
					step_frame(1 if event.button_index==JOY_BUTTON_DPAD_RIGHT else -1)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed:
		match event.physical_keycode:
			KEY_SPACE:
				if event.is_echo(): return
				if slider.value>=slider.max_value: slider.value=0
				playing=not playing
				playback_elapsed=0.
			KEY_ESCAPE: toggle()
			KEY_LEFT: step_frame(-1)
			KEY_RIGHT: step_frame(1)
			_: return
	elif not ReplayControls.mouse_camera(camera,event): return
	get_viewport().set_input_as_handled()
