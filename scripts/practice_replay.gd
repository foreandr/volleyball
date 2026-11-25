extends CanvasLayer

const SAMPLE_INTERVAL := 0.1
const MAX_SAMPLES := 450
@onready var game = get_parent()
var history: Array[Dictionary] = []
var live := {}
var camera := Camera3D.new()
var slider := HSlider.new()
var panel := VBoxContainer.new()
var elapsed := 0.0
var sample_interval := SAMPLE_INTERVAL
var sample_limit := MAX_SAMPLES
var active := false
var playing := false
var playback_elapsed := 0.
var hidden_controls := []
var modifiers := []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 100
	if "block_sound_count" in game:
		sample_interval=1./60.
		sample_limit=900
	layer = 90
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_bottom = -18
	var legend := Label.new()
	legend.text = "Replay    |    Space play/pause    Drag to rewind    |    WASD move    Q/E down/up    |    Middle-drag look    Scroll zoom    |    Esc return"
	legend.add_theme_constant_override("outline_size",5)
	panel.add_child(legend)
	panel.add_child(slider)
	slider.step = 1
	slider.value_changed.connect(func(value): if active: apply(history[int(value)]))
	panel.hide()

func capture(rendered := false) -> Dictionary:
	var objects := {}
	var poses := {}
	for obj in game.world.get_children():
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
		objects[obj] = [obj.transform,obj.visible]
	return {"block_sound_count":game.block_sound_count if "block_sound_count" in game else 0,"objects":objects,"poses":poses,"whistle_height":game.coach_motion.whistle_cue.raised}

func apply(sample: Dictionary) -> void:
	game.coach_motion.whistle_cue.raised = sample.whistle_height
	for obj in live.objects:
		if not is_instance_valid(obj): continue
		if not sample.objects.has(obj):
			obj.hide()
			continue
		var state: Array = sample.objects[obj]
		obj.transform = state[0]
		obj.visible = state[1]
	for rig in sample.poses:
		if not is_instance_valid(rig): continue
		var bones: Array = sample.poses[rig]
		for i in bones.size(): rig.set_bone_pose(i,bones[i])

func toggle() -> void:
	if active:
		apply(live)
		active = false
		playing = false
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
	slider.max_value = history.size()-1
	slider.set_value_no_signal(slider.max_value)
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
		if playing:
			playback_elapsed+=delta
			var frames := floori(playback_elapsed/sample_interval)
			if frames>0:
				playback_elapsed=fmod(playback_elapsed,sample_interval)
				var old_index := int(slider.value)
				slider.value+=frames
				if history[int(slider.value)].block_sound_count>history[old_index].block_sound_count:
					game.hand_impact.play()
				if slider.value>=slider.max_value: playing=false
		var direction := Vector3(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),0,float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W)))
		var rise := float(Input.is_physical_key_pressed(KEY_E))-float(Input.is_physical_key_pressed(KEY_Q))
		camera.global_position += (camera.global_basis*direction+Vector3.UP*rise).limit_length(1)*delta*5.0
	elif not get_tree().paused:
		record_setter(delta)
		elapsed += delta
		if elapsed >= sample_interval:
			elapsed = fmod(elapsed,sample_interval)
			history.append(capture(true))
			if history.size()>sample_limit: history.pop_front()

func _input(event: InputEvent) -> void:
	if not active or CareerSession.prompt.visible: return
	if event is InputEventKey and event.pressed:
		match event.physical_keycode:
			KEY_SPACE:
				if event.is_echo(): return
				if slider.value>=slider.max_value: slider.value=0
				playing=not playing
				playback_elapsed=0.
			KEY_ESCAPE: toggle()
			KEY_LEFT: slider.value -= 1
			KEY_RIGHT: slider.value += 1
			_: return
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
		camera.rotation.y -= event.relative.x*0.004
		camera.rotation.x = clampf(camera.rotation.x-event.relative.y*0.004,-1.54,1.54)
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		camera.fov = clampf(camera.fov+(-3 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 3),12,100)
	else: return
	get_viewport().set_input_as_handled()
