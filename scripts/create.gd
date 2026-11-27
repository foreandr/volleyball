extends Control
const Profile = preload("res://scripts/player_profile.gd")
var profile: Dictionary = Profile.load_profile()
var budget_label: Label
var name_field: LineEdit

var hand_field: OptionButton
var save_button: Button
var preview: SubViewportContainer
var preview_camera: Camera3D
var preview_player: Node3D
var orbit_yaw := 0.0
var orbit_pitch := 0.12
var view_distance := 3.8
var view_focus := Vector3(0,0.98,0)
var max_view_distance := 8.0
var pan_limits := Vector3(1.5,2.4,1.5)
var stage_camera := {}
var dragging := false
var panning := false
var ball_controls_host: VBoxContainer
var right_panel: PanelContainer
var player_controls: RefCounted

func _ready() -> void:
	profile = initial_profile()
	MenuPresentation.backdrop(self,false)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge,24)
	add_child(margin)
	var column := VBoxContainer.new()
	column.name = "ScreenColumn"
	column.add_theme_constant_override("separation",18)
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title_block := VBoxContainer.new()
	title_block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_block)
	var title := label(screen_title(),32)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.name = "ScreenTitle"
	title.add_theme_color_override("font_color",Color("73e1d2"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_block.add_child(title)
	var subtitle := screen_subtitle()
	if not subtitle.is_empty():
		var build := label(subtitle,14)
		build.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		build.tooltip_text = subtitle
		title_block.add_child(build)
	var back := button("Back",open_menu)
	back.custom_minimum_size = Vector2(110,44)
	back.size_flags_horizontal = Control.SIZE_SHRINK_END
	header.add_child(back)
	var workspace_row := HBoxContainer.new()
	workspace_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace_row.add_theme_constant_override("separation",12)
	column.add_child(workspace_row)
	var split := HSplitContainer.new()
	split.name = "Workspace"
	split.split_offset = 320
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace_row.add_child(split)
	var tools := panel()
	tools.name = "LeftPanel"
	tools.custom_minimum_size.x = 300
	split.add_child(tools)
	var tool_margin := MarginContainer.new()
	for edge in ["left","right","top","bottom"]: tool_margin.add_theme_constant_override("margin_"+edge,20)
	tools.add_child(tool_margin)
	var controls := VBoxContainer.new()
	controls.add_theme_constant_override("separation",16)
	var tool_scroll := ScrollContainer.new()
	tool_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tool_scroll.follow_focus = true
	tool_margin.add_child(tool_scroll)
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tool_scroll.add_child(controls)
	var stage := panel()
	stage.name = "RightPreview"
	stage.custom_minimum_size.x = 400
	split.add_child(stage)
	preview = SubViewportContainer.new()
	preview.name = "CharacterPreview"
	preview.stretch = true
	preview.focus_mode = Control.FOCUS_ALL
	preview.mouse_default_cursor_shape = Control.CURSOR_DRAG
	preview.gui_input.connect(handle_preview_input)
	stage.add_child(preview)
	var viewport := SubViewport.new()
	viewport.name = "CharacterViewport"
	viewport.own_world_3d = true
	viewport.size = Vector2i(880,600)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	preview.add_child(viewport)
	build_preview(viewport)
	if has_ball_controls():
		right_panel = panel()
		right_panel.name = "BallPanel"
		right_panel.custom_minimum_size.x = 300
		workspace_row.add_child(right_panel)
		var inset := MarginContainer.new()
		for edge in ["left","right","top","bottom"]: inset.add_theme_constant_override("margin_"+edge,16)
		right_panel.add_child(inset)
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.follow_focus = true
		inset.add_child(scroll)
		ball_controls_host = VBoxContainer.new()
		ball_controls_host.name = "BallControls"
		ball_controls_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ball_controls_host.add_theme_constant_override("separation",12)
		scroll.add_child(ball_controls_host)
		build_ball_controls(ball_controls_host)
	build_controls(controls)
	if has_ball_controls(): player_controls = preload("res://scripts/preview_player_control.gd").new(self)
	if is_instance_valid(name_field): name_field.grab_focus()
	else: preview.grab_focus()

func has_ball_controls() -> bool:
	return false

func build_ball_controls(_host: VBoxContainer) -> void:
	pass

func screen_title() -> String:
	return "CREATE PLAYER"

func screen_subtitle() -> String:
	return ""

func initial_profile() -> Dictionary:
	if CareerSession.outfitting: return Profile.clean(CareerSession.profile())
	if CareerSession.creating: return CareerSession.base_profile()
	return StorySession.draft.duplicate(true) if StorySession.creating_story else Profile.load_profile()

const STEPS := ["Athlete","Wardrobe","Attributes"]
const SLOTS := {
	"Chest":["Jersey length","Jersey fit","Underlayer"], "Legs":["Shorts design","Leg sleeves","Knee support"],
	"Feet":["Shoe cut","Shoe design","Shoe color","Sock height","Sock color","Ankle support"],
	"Hands":["Finger tape"], "Head":["Headwear","Sunglasses"]
}
var step := 0
var wardrobe_slot := "Chest"
var creator_controls: VBoxContainer
var measurement_sliders:Dictionary={}
var pad_keyboard:ConfirmationDialog
var grooming:=""
var body_view:Dictionary={}
var camera_blend:Tween

func build_controls(controls: VBoxContainer) -> void:
	creator_controls=controls
	profile=Profile.clean(profile)
	profile.age=clampi(profile.age,16,18)
	if not profile.has("jersey_number"): profile.jersey_number=7
	if CareerSession.outfitting: step=1
	render_step()

func render_step() -> void:
	var controls := creator_controls
	for child in controls.get_children():
		controls.remove_child(child)
		child.queue_free()
	measurement_sliders.clear()
	name_field=null
	budget_label=null
	save_button=null
	if not grooming.is_empty():
		render_grooming(controls)
		return
	var progress := label("ATHLETE CREATION    /    %d OF 3" % (step+1),13)
	progress.modulate=Color("73e1d2")
	controls.add_child(progress)
	controls.add_child(label(STEPS[step],28))
	if step>0 and (CareerSession.creating or CareerSession.outfitting):
		budget_label=MenuPresentation.wallet(controls,remaining_points())
	match step:
		0:
			name_field=add_text(controls,"Name","name",32)
			add_attribute(controls,"Age","age",16,18,profile.age)
			add_text(controls,"Hometown","hometown",64)
			add_attribute(controls,"Height","height_cm",60,84,profile.height_cm/2.54)
			add_attribute(controls,"Wingspan (in)","wingspan_in",48,96,profile.wingspan_in)
			for caption in Profile.MEASUREMENTS:
				var field: Array=Profile.MEASUREMENTS[caption]
				add_attribute(controls,caption,field[0],field[1],field[2],profile[field[0]])
			add_choice(controls,"Natural position","position",Profile.POSITIONS)
			add_choice(controls,"Handedness","handedness",["Right","Left"])
			controls.add_child(button("Hair and face",open_grooming))
		1:
			add_attribute(controls,"Jersey number","jersey_number",0,99,profile.jersey_number)
			var slots := GridContainer.new()
			slots.columns=2
			controls.add_child(slots)
			for slot in SLOTS:
				var item := button(slot,change_slot.bind(slot))
				item.toggle_mode=true
				item.button_pressed=slot==wardrobe_slot
				slots.add_child(item)
				if item.button_pressed: item.grab_focus()
			controls.add_child(HSeparator.new())
			for key in SLOTS[wardrobe_slot]: add_choice(controls,key,key,Profile.KIT_CHOICES[key])
		2:
			add_attribute(controls,"Vertical jump (in)","vertical_in",30,60,profile.vertical_in)
			var rules:=Profile.build_rules(profile)
			for rating in Profile.RATINGS:
				add_attribute(controls,"Arm swing speed" if rating=="Arm swing" else rating,rating,40 if CareerSession.creating else 0,Profile.training_limit(rules.get(rating,Vector2i(100,0))),profile[rating])
	var advance := button("Equip wardrobe" if CareerSession.outfitting else "Create athlete" if step==2 else "Next   /   "+STEPS[step+1],advance_step)
	controls.add_child(advance)
	save_button=advance
	save_button.disabled=str(profile.name).strip_edges().is_empty() or ((CareerSession.creating or CareerSession.outfitting) and remaining_points()<0)
	if step==0: name_field.grab_focus()
	if step==2: controls.find_children("*","HSlider",false,false)[0].grab_focus()

func open_grooming() -> void:
	body_view={"focus":view_focus,"distance":view_distance,"yaw":orbit_yaw,"pitch":orbit_pitch}
	grooming="Hair"
	var rig:Skeleton3D=preview_player.skeleton
	var head:=rig.to_global(rig.get_bone_global_pose(rig.find_bone("Head")).origin)
	shift_camera(head+Vector3.UP*.09,.76,.13,.04)
	render_step()

func shift_camera(focus:Vector3,distance:float,yaw:float,pitch:float) -> void:
	if camera_blend: camera_blend.kill()
	camera_blend=create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	camera_blend.tween_property(self,"view_focus",focus,.25)
	camera_blend.tween_property(self,"view_distance",distance,.25)
	camera_blend.tween_property(self,"orbit_yaw",yaw,.25)
	camera_blend.tween_property(self,"orbit_pitch",pitch,.25)
	camera_blend.chain().tween_callback(update_camera)

func close_grooming() -> void:
	preview_player.apply_profile(profile)
	grooming=""
	shift_camera(body_view.focus,body_view.distance,body_view.yaw,body_view.pitch)
	render_step()
	for child in creator_controls.get_children():
		if child is Button and child.text=="Hair and face": child.grab_focus()

func render_grooming(controls:VBoxContainer) -> void:
	controls.add_child(label("Hair and face",27))
	var categories:=GridContainer.new()
	categories.columns=2
	controls.add_child(categories)
	for category in ["Hair","Hair color","Eyebrows","Facial hair"]:
		var tab:=button(category,func():
			grooming=category
			render_step())
		tab.toggle_mode=true
		tab.set_pressed_no_signal(category==grooming)
		categories.add_child(tab)
	controls.add_child(HSeparator.new())
	var grid:=GridContainer.new()
	grid.columns=2
	controls.add_child(grid)
	var choices:Array=Profile.HAIRSTYLES if grooming=="Hair" else (Profile.HAIR_COLORS.keys() if grooming=="Hair color" else Profile.KIT_CHOICES[grooming])
	var group:=ButtonGroup.new()
	for choice in choices:
		var tile:=button(str(choice),func():
			profile[grooming]=choice
			update_profile())
		var show_choice:=func():
			if not is_instance_valid(preview_player) or not tile.is_inside_tree() or grooming.is_empty(): return
			var sample:=profile.duplicate()
			sample[grooming]=choice
			preview_player.apply_profile(sample)
		tile.focus_entered.connect(show_choice)
		tile.mouse_entered.connect(show_choice)
		tile.button_group=group
		tile.toggle_mode=true
		tile.custom_minimum_size.y=43
		if grooming=="Hair color":
			tile.icon=MenuPresentation.color_chip(Profile.HAIR_COLORS[choice])
		grid.add_child(tile)
		tile.set_pressed_no_signal(choice==profile[grooming])
		if tile.button_pressed: tile.grab_focus()
	controls.add_child(button("Done",close_grooming))

func change_slot(slot: String) -> void:
	wardrobe_slot=slot
	render_step()

func advance_step() -> void:
	if CareerSession.outfitting:
		if CareerSession.equip(profile): open_menu()
	elif step==2: save_player()
	else:
		step+=1
		render_step()

func add_text(host: VBoxContainer,caption: String,key: String,limit: int) -> LineEdit:
	host.add_child(label(caption,16))
	var field := LineEdit.new()
	field.text=profile[key]
	field.max_length=limit
	host.add_child(field)
	field.text_changed.connect(func(value): profile[key]=value; update_profile())
	return field

func add_choice(host: VBoxContainer,caption: String,key: String,choices: Array) -> void:
	host.add_child(label(caption,16))
	var picker := OptionButton.new()
	for choice in choices:
		var price := 0
		if key in Profile.KIT_CHOICES and (CareerSession.creating or CareerSession.outfitting):
			var owned := CareerSession.inventory() if CareerSession.outfitting else []
			price=CareerSession.gear_price(key,choice,owned)
		picker.add_item(str(choice)+("   %d VP" % price if price else ""))
	picker.select(choices.find(profile[key]))
	host.add_child(picker)
	picker.item_selected.connect(func(i):
		var previous: Variant=profile[key]
		profile[key]=choices[i]
		if (CareerSession.creating or CareerSession.outfitting) and remaining_points()<0:
			profile[key]=previous
			picker.select(choices.find(previous))
		update_profile())
	if key in Profile.KIT_CHOICES and (CareerSession.creating or CareerSession.outfitting):
		picker.get_popup().about_to_popup.connect(func():
			var owned := CareerSession.inventory() if CareerSession.outfitting else []
			var budget := remaining_points()+CareerSession.gear_price(key,profile[key],owned)
			for i in choices.size(): picker.set_item_disabled(i,CareerSession.gear_price(key,choices[i],owned)>budget))

func measurement(caption: String,key: String,value: int) -> String:
	if key=="height_cm": return "Height   %d in   (%d ft %d in)" % [value,value/12,value%12]
	if key in Profile.RATINGS:
		var rule:Vector2i=Profile.build_rules(profile).get(key,Vector2i(100,0))
		return "%s   %d / %d"%[caption,clampi(value+rule.y,0,rule.x),rule.x]
	return "%s   %d" % [caption,value]

func add_attribute(parent: VBoxContainer, caption: String, key: String, minimum: int, maximum: int, initial: float) -> void:
	var heading := label(measurement(caption,key,roundi(initial)),16)
	parent.add_child(heading)
	var slider := HSlider.new()
	slider.min_value=minimum
	slider.max_value=maximum
	slider.step=1
	slider.value=initial
	parent.add_child(slider)
	measurement_sliders[key]=slider
	if Profile.BUILD_HELP.has(key):
		MenuPresentation.stat_help(slider,heading,caption,func(): return Profile.build_note(key,profile),false)
	if key=="vertical_in":
		MenuPresentation.rating_bar(parent,slider)
		MenuPresentation.stat_help(slider,heading,caption,"Jump height on serves, attacks and blocks. Each inch costs one volleyball point.")
	if key in Profile.RATING_HELP:
		MenuPresentation.rating_bar(parent,slider)
		MenuPresentation.stat_help(slider,heading,caption,Profile.RATING_HELP[key])
	slider.value_changed.connect(func(value: float):
		if CareerSession.creating and (key in Profile.RATINGS or key=="vertical_in"):
			value=minf(value,float(profile[key])+remaining_points())
			slider.set_value_no_signal(value)
		heading.text=measurement(caption,key,int(value))
		var old_inches:=float(profile.height_cm)/2.54
		var follow_mass:=absf(profile.weight_lb-Profile.natural_weight(old_inches))<.51
		var follow_reach:=absf(profile.reach_in-Profile.natural_reach(old_inches,profile.wingspan_in))<.51
		profile[key]=value*2.54 if key=="height_cm" else value
		if key=="height_cm" and follow_mass and measurement_sliders.has("weight_lb"): measurement_sliders.weight_lb.value=Profile.natural_weight(value)
		if key=="height_cm" and measurement_sliders.has("wingspan_in") and absf(profile.wingspan_in-old_inches)<.51:
			measurement_sliders.wingspan_in.value=value
		if key in ["height_cm","wingspan_in"] and follow_reach and measurement_sliders.has("reach_in"):
			measurement_sliders.reach_in.value=Profile.natural_reach(profile.height_cm/2.54,profile.wingspan_in)
		update_profile())

func save_player() -> void:
	SchoolHeadshots.request(profile)
	if CareerSession.creating:
		if CareerSession.create_athlete(profile):
			CareerSession.enter_origin = true
			CareerSession.creating = false
			MenuPresentation.load_scene("res://scenes/story.tscn")
		return
	if StorySession.creating_story:
		if StorySession.save_new(profile) == OK:
			MenuPresentation.load_scene("res://scenes/story_animations.tscn")
		else: show_save_error()
	else:
		if Profile.save_profile(profile) == OK: open_menu()
		else: show_save_error()

func show_save_error() -> void:
	var dialog := AcceptDialog.new()
	dialog.dialog_text = "Unable to save player."
	add_child(dialog)
	dialog.popup_centered()

func build_preview(viewport: SubViewport) -> void:
	var world := Node3D.new()
	viewport.add_child(world)
	light_preview_stage(world)
	build_preview_stage(world)
	preview_player = preload("res://scripts/volleyball_player.gd").new()
	preview_player.name = "PreviewPlayer"
	preview_player.position.y = 0.04
	preview_player.apply_profile(profile)
	world.add_child(preview_player)
	preload("res://scripts/practice_kit.gd").apply(preview_player,false)
	preview_camera = Camera3D.new()
	preview_camera.name = "PreviewCamera"
	preview_camera.fov = 38.0
	preview_camera.near = 0.05
	preview_camera.far = 50
	stage_camera = {"yaw":orbit_yaw,"pitch":orbit_pitch,"distance":view_distance,"focus":view_focus}
	preview_camera.current = true
	world.add_child(preview_camera)
	update_camera()

func light_preview_stage(world: Node3D) -> void:
	preload("res://scripts/preview_court.gd").add_preview_lighting(world)

func build_preview_stage(world: Node3D) -> void:
	var platform := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.8
	cylinder.bottom_radius = 0.8
	cylinder.height = 0.08
	platform.mesh = cylinder
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("304654")
	material.roughness = 0.9
	platform.material_override = material
	world.add_child(platform)

func handle_preview_input(event: InputEvent) -> void:
	if player_controls!=null and player_controls.active and not event is InputEventKey: return
	if event is InputEventKey and event.pressed:
		handle_keyboard(event)
		return
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_MIDDLE]: dragging = event.pressed
		if event.button_index == MOUSE_BUTTON_RIGHT: panning = event.pressed
		if event.pressed:
			preview.grab_focus()
			if event.button_index == MOUSE_BUTTON_WHEEL_UP: zoom_view(0.9)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: zoom_view(1.1)
		preview.accept_event()
	if event is InputEventMouseMotion:
		if panning:
			pan_view(event.relative)
		elif dragging:
			orbit_yaw -= event.relative.x*0.008
			orbit_pitch = clampf(orbit_pitch+event.relative.y*0.006,-0.15,1.35)
			update_camera()
		if panning or dragging: preview.accept_event()

func _process(delta: float) -> void:
	if camera_blend and camera_blend.is_running(): update_camera()
	if player_controls!=null:
		player_controls.step(delta)
		if player_controls.active: return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return
	if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_ALT) or Input.is_key_pressed(KEY_META): return
	var direction := Vector2(
		float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_W))-float(Input.is_physical_key_pressed(KEY_S)))
	pan_camera(direction,delta)

func camera_pan_delta(direction: Vector2, delta: float, speed: float) -> Vector3:
	var right := preview_camera.global_basis.x
	var forward := -preview_camera.global_basis.z
	right.y = 0
	forward.y = 0
	return (right.normalized()*direction.x+forward.normalized()*direction.y)*speed*delta

func pan_camera(direction: Vector2, delta: float) -> void:
	if direction.length_squared()<0.001: return
	var speed := clampf(view_distance*0.45,1.0,30.0)
	view_focus += camera_pan_delta(direction.normalized(),delta,speed)
	view_focus.x = clampf(view_focus.x,-pan_limits.x,pan_limits.x)
	view_focus.z = clampf(view_focus.z,-pan_limits.z,pan_limits.z)
	update_camera()

func pan_view(pixels: Vector2) -> void:
	view_focus += (-preview_camera.global_basis.x*pixels.x+preview_camera.global_basis.y*pixels.y)*view_distance*0.0015
	view_focus.x = clampf(view_focus.x,-pan_limits.x,pan_limits.x)
	view_focus.y = clampf(view_focus.y,-0.2,pan_limits.y)
	view_focus.z = clampf(view_focus.z,-pan_limits.z,pan_limits.z)
	update_camera()

func zoom_view(factor: float) -> void:
	view_distance = clampf(view_distance*factor,1.4,max_view_distance)
	update_camera()

func set_view(yaw: float) -> void:
	reset_view()
	orbit_yaw = yaw
	update_camera()

func reset_view() -> void:
	orbit_yaw = stage_camera.get("yaw",0.0)
	orbit_pitch = stage_camera.get("pitch",0.12)
	view_distance = stage_camera.get("distance",3.8)
	view_focus = stage_camera.get("focus",Vector3(0,0.98,0))
	update_camera()

func update_camera() -> void:
	preview_camera.position = view_focus+Vector3(sin(orbit_yaw)*cos(orbit_pitch),sin(orbit_pitch),cos(orbit_yaw)*cos(orbit_pitch))*view_distance
	preview_camera.look_at(view_focus)

func panel() -> PanelContainer:
	var result := PanelContainer.new()
	var style := MenuPresentation.box(Color("122330"),Color("407370"),2)
	for edge in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]: style.set_content_margin(edge,1)
	result.add_theme_stylebox_override("panel",style)
	return result

func label(text: String, size: int) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size",size)
	return result

func button(text: String, action: Callable) -> Button:
	var result := Button.new()
	result.text = text
	result.custom_minimum_size = Vector2(80,38)
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.pressed.connect(action)
	return result

func remaining_points() -> int:
	if CareerSession.outfitting: return CareerSession.balance()-CareerSession.gear_cost(profile,CareerSession.inventory())
	return CareerSession.STARTING_VP-CareerSession.spent(profile)-CareerSession.gear_cost(profile,[])

func update_profile() -> void:
	if CareerSession.creating or CareerSession.outfitting:
		if is_instance_valid(budget_label): budget_label.text=str(remaining_points())
	elif StorySession.creating_story: StorySession.draft = Profile.clean(profile)
	elif not creator_controls: Profile.save_profile(profile)
	if is_instance_valid(save_button): save_button.disabled = profile.name.strip_edges().is_empty() or ((CareerSession.creating or CareerSession.outfitting) and remaining_points()<0)
	if is_instance_valid(preview_player): preview_player.apply_profile(profile)

func open_menu() -> void:
	if not grooming.is_empty():
		close_grooming()
		return
	if CareerSession.outfitting:
		CareerSession.outfitting=false
		MenuPresentation.load_scene("res://scenes/story.tscn")
		return
	if creator_controls and step>0:
		step-=1
		render_step()
		return
	if CareerSession.creating:
		CareerSession.creating = false
		MenuPresentation.load_scene("res://scenes/story.tscn")
		return
	if StorySession.creating_story:
		StorySession.cancel_creation()
		MenuPresentation.load_scene("res://scenes/story.tscn")
	else: MenuPresentation.load_scene("res://scenes/main.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.is_action_pressed("ui_cancel"):
		open_menu()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed: handle_keyboard(event)

func handle_keyboard(event: InputEventKey) -> void:
	if player_controls!=null and player_controls.handle_key(event):
		get_viewport().set_input_as_handled()
		return
	match event.keycode:
		KEY_ESCAPE: open_menu()
		KEY_R,KEY_F: reset_view()
		KEY_PLUS,KEY_EQUAL,KEY_KP_ADD: zoom_view(0.9)
		KEY_MINUS,KEY_KP_SUBTRACT: zoom_view(1.1)
		KEY_LEFT,KEY_RIGHT,KEY_UP,KEY_DOWN:
			var direction := Vector2.ZERO
			if event.keycode == KEY_LEFT: direction.x = -1
			if event.keycode == KEY_RIGHT: direction.x = 1
			if event.keycode == KEY_UP: direction.y = -1
			if event.keycode == KEY_DOWN: direction.y = 1
			if event.shift_pressed: pan_view(direction*20)
			else:
				orbit_yaw -= direction.x*0.12
				orbit_pitch = clampf(orbit_pitch+direction.y*0.08,-0.15,1.35)
				update_camera()
		_: return
	get_viewport().set_input_as_handled()

func edit_draft(action:String,draft:Label,letters:Array[Button],limit:int) -> void:
	match action:
		"Shift":
			var lower:=letters[0].text=="A"
			for letter in letters: letter.text=letter.text.to_lower() if lower else letter.text.to_upper()
		"Space": draft.text=(draft.text+" ").left(limit)
		"Backspace": draft.text=draft.text.left(maxi(0,draft.text.length()-1))
		"Clear": draft.text=""

func edit_with_controller(field:LineEdit) -> void:
	if is_instance_valid(pad_keyboard): return
	var dialog:=ConfirmationDialog.new()
	pad_keyboard=dialog
	dialog.title="Edit "+("name" if field==name_field else "hometown")
	dialog.ok_button_text="Done"
	dialog.get_cancel_button().text="Cancel"
	add_child(dialog)
	var content:=VBoxContainer.new()
	dialog.add_child(content)
	var draft:=Label.new()
	draft.text=field.text
	content.add_child(draft)
	var grid:=GridContainer.new()
	grid.columns=10
	content.add_child(grid)
	var letters:Array[Button]=[]
	for character in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-'.":
		var key:=Button.new()
		key.text=character
		key.custom_minimum_size=Vector2(42,38)
		grid.add_child(key)
		letters.append(key)
		key.pressed.connect(func(): draft.text=(draft.text+key.text).left(field.max_length))
	var actions:=HBoxContainer.new()
	content.add_child(actions)
	for caption in ["Shift","Space","Backspace","Clear"]:
		var key:=Button.new()
		key.text=caption
		actions.add_child(key)
		key.pressed.connect(edit_draft.bind(caption,draft,letters,field.max_length))
	dialog.confirmed.connect(func():
		field.text=draft.text
		field.text_changed.emit(field.text))
	dialog.visibility_changed.connect(func():
		if not dialog.visible:
			dialog.queue_free()
			field.grab_focus())
	dialog.popup_centered()
	letters[0].grab_focus()

func _input(event: InputEvent) -> void:
	if is_instance_valid(pad_keyboard): return
	if event is InputEventJoypadButton and event.is_action_pressed("ui_accept"):
		var field:=get_viewport().gui_get_focus_owner() as LineEdit
		if field and creator_controls and creator_controls.is_ancestor_of(field) and not (field.get_parent() is SpinBox):
			get_viewport().set_input_as_handled()
			edit_with_controller(field)
			return
	if event is InputEventKey and event.keycode in [KEY_F1,KEY_F2] and player_controls!=null:
		handle_keyboard(event)
