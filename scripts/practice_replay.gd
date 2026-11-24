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
var active := false
var hidden_controls := []
var modifiers := []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 100
	layer = 90
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_bottom = -18
	var legend := Label.new()
	legend.text = "Replay    |    Drag to rewind    |    WASD move    Q/E down/up    |    Middle-drag look    Scroll zoom    |    Esc return"
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
		elif obj != game.ball and obj is not RigidBody3D and obj not in game.rotation_drill.bins and obj != game.rotation_drill.basket: continue
		objects[obj] = [obj.transform,obj.visible]
	return {"objects":objects,"poses":poses}

func apply(sample: Dictionary) -> void:
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
	if history.size()>MAX_SAMPLES: history.pop_front()
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

func _process(delta: float) -> void:
	if active:
		if CareerSession.prompt.visible: return
		var direction := Vector3(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),0,float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W)))
		var rise := float(Input.is_physical_key_pressed(KEY_E))-float(Input.is_physical_key_pressed(KEY_Q))
		camera.global_position += (camera.global_basis*direction+Vector3.UP*rise).limit_length(1)*delta*5.0
	elif not get_tree().paused:
		elapsed += delta
		if elapsed >= SAMPLE_INTERVAL:
			elapsed = fmod(elapsed,SAMPLE_INTERVAL)
			history.append(capture(true))
			if history.size()>MAX_SAMPLES: history.pop_front()

func _input(event: InputEvent) -> void:
	if not active or CareerSession.prompt.visible: return
	if event is InputEventKey and event.pressed:
		match event.physical_keycode:
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
