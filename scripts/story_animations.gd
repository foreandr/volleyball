extends "res://scripts/create.gd"
const BallPreview = preload("res://scripts/animation_ball_preview.gd")
const Flight = preload("res://scripts/pass_flight.gd")
const Catalog = preload("res://scripts/volleyball_animations.gd")
const MOVE_TYPES := {
	"Forearm reception":["Forearm"],
	"Spiking":["Line Hit","Cross Hit"],
	"Serving":["Float","Spin","Hybrid","Skyball","Underhand","Standing Float","Standing Spin"],
	"Blocking":["Straight","Left","Right"],
	"Setting":["Forward","Back","Left","Right"],
	"Chasing":["Forward","Back","Left","Right"]
}
const CATEGORIES := ["Forearm reception","Spiking","Serving","Blocking","Setting","Chasing"]
var content: VBoxContainer
var category_buttons: Dictionary = {}
var selected_category := ""
var type_indices: Dictionary = {}
var type_label: Label
var animation_list
var trigger_held := {}
var edit_button: Button
var selected_entry: Dictionary = {}
var ball_preview: Node3D
var setup_drag: RefCounted
var angle_control: VBoxContainer
var source_clip: Animation
var trajectory_solver: RefCounted
var render_clip: Animation
var preview_clock := 0.0
var drill_status: Label
var timing_meter: Control
var reception_controls: VBoxContainer
var replace_body_layer := false
var recipe_poll := 0.0
var recipe_signature := 0
var recipe_revision := -1
var body_recipe_text := FileAccess.get_file_as_string("res://assets/animation_recipes/reception_bodies.json")

func _ready() -> void:
	process_priority = 10
	super._ready()
	timing_meter = preload("res://scripts/reception_timing_meter.gd").new()
	var overlay := Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.get_parent().add_child(overlay)
	overlay.add_child(timing_meter)
	setup_drag = preload("res://scripts/court_setup_drag.gd").new(self)
	preview_camera.fov = 42.0
	preview_camera.far = 150.0
	if not StorySession.animation_return.is_empty():
		var destination: Dictionary = StorySession.animation_return.duplicate()
		StorySession.animation_return.clear()
		destination.category = Catalog.category_name(destination.category)
		destination.type = Catalog.type_name(destination.category,destination.type)
		if MOVE_TYPES.has(destination.category):
			type_indices[destination.category] = MOVE_TYPES[destination.category].find(destination.type)
			select_category(destination.category)
			for index in animation_list.item_count:
				if animation_list.get_item_metadata(index).id == destination.get("id",""):
					animation_list.select(index)
					preview_animation(index)
					break

func build_preview_stage(world: Node3D) -> void:
	world.add_child(preload("res://scripts/preview_court.gd").new())
	orbit_yaw = -2.2
	orbit_pitch = 0.26
	max_view_distance = 60.0
	pan_limits = Vector3(12,15,48)
	view_distance = 16.0
	view_focus = Vector3(0,2.0,4.0)

func has_ball_controls() -> bool:
	return true

func build_ball_controls(host: VBoxContainer) -> void:
	angle_control = preload("res://scripts/pass_angle_control.gd").new()
	host.add_child(angle_control)
	angle_control.angle_requested.connect(apply_output_angle)
	angle_control.feed_aim_changed.connect(update_feed_aim)

func screen_title() -> String:
	return "ANIMATIONS"

func initial_profile() -> Dictionary:
	return StorySession.active.get("profile",Profile.load_profile()).duplicate(true)

func build_controls(controls: VBoxContainer) -> void:
	content = controls
	show_categories()

func clear_content() -> void:
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	reception_controls = null
	drill_status = null
	animation_list = null
	edit_button = null
	selected_entry.clear()
	type_label = null

func set_title(text: String) -> void:
	var heading := find_child("ScreenTitle",true,false) as Label
	if heading: heading.text = text

func show_categories() -> void:
	if is_instance_valid(right_panel): right_panel.hide()
	if is_instance_valid(ball_preview): ball_preview.stop()
	if is_instance_valid(preview_player): preview_player.play_action("idle")
	selected_category = ""
	clear_content()
	set_title("ANIMATIONS")
	category_buttons.clear()
	for category in CATEGORIES:
		var entry := button(category,select_category.bind(category))
		entry.name = category
		entry.custom_minimum_size.y = 52
		entry.alignment = HORIZONTAL_ALIGNMENT_LEFT
		content.add_child(entry)
		category_buttons[category] = entry

func select_category(category: String) -> void:
	category = Catalog.category_name(category)
	if not MOVE_TYPES.has(category): return
	selected_category = category
	clear_content()
	set_title(category.to_upper())
	var row := HBoxContainer.new()
	row.visible = MOVE_TYPES[category].size()>1
	row.add_theme_constant_override("separation",8)
	content.add_child(row)
	var previous := button("L2 <",cycle_type.bind(-1))
	previous.name = "PreviousType"
	previous.custom_minimum_size = Vector2(52,44)
	previous.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.add_child(previous)
	type_label = label("",19)
	type_label.name = "MoveType"
	type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	type_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	type_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(type_label)
	var next := button("> R2",cycle_type.bind(1))
	next.name = "NextType"
	next.custom_minimum_size = Vector2(52,44)
	next.size_flags_horizontal = Control.SIZE_SHRINK_END
	row.add_child(next)
	if category=="Forearm reception":
		reception_controls = preload("res://scripts/reception_controls.gd").new()
		content.add_child(reception_controls)
		reception_controls.changed.connect(func(part):
			if part=="body": replace_body_layer = true
			apply_output_angle(angle_control.requested))
		content.add_child(label("Forearms / platform",18))
	if category == "Forearm reception":
		var platforms := OptionButton.new()
		platforms.name = "PlatformPicker"
		platforms.custom_minimum_size.y = 38
		animation_list = platforms
	else:
		var list := ItemList.new()
		list.name = "AnimationList"
		list.allow_reselect = true
		list.item_activated.connect(open_editor)
		list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		animation_list = list
	animation_list.add_theme_font_size_override("font_size",18)
	animation_list.item_selected.connect(preview_animation)
	content.add_child(animation_list)
	if category == "Forearm reception":
		drill_status = label("F1 to play  |  WASD to move\nHold Space just before contact",16)
		drill_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(drill_status)
	edit_button = button("Edit",open_editor)
	edit_button.name = "EditAnimation"
	content.add_child(edit_button)
	refresh_type()
	animation_list.grab_focus()

func current_type() -> String:
	if selected_category.is_empty(): return ""
	return MOVE_TYPES[selected_category][type_indices.get(selected_category,0)]

func refresh_type() -> void:
	right_panel.hide()
	angle_control.hide()
	type_label.text = current_type()
	animation_list.clear()
	selected_entry.clear()
	if is_instance_valid(edit_button): edit_button.disabled = true
	for entry in Catalog.entries(selected_category,current_type()):
		var index: int = animation_list.item_count
		animation_list.add_item(entry.name)
		animation_list.set_item_metadata(index,entry)
	if animation_list.item_count > 0:
		var initial := 0
		if selected_category == "Forearm reception":
			for index in animation_list.item_count:
				if animation_list.get_item_metadata(index).id == "straight_pass_02":
					initial = index
					break
		animation_list.select(initial)
		preview_animation(initial)
	elif is_instance_valid(preview_player):
		preview_player.play_action("idle")
		if is_instance_valid(ball_preview): ball_preview.stop()

func preview_animation(index: int) -> void:
	if not is_instance_valid(preview_player): return
	replace_body_layer = false
	var entry: Dictionary = animation_list.get_item_metadata(index)
	selected_entry = entry.duplicate(true)
	if is_instance_valid(edit_button): edit_button.disabled = false
	angle_control.apply_setup(preview_player)
	if is_instance_valid(reception_controls): reception_controls.apply(preview_player)
	source_clip = Catalog.load_clip(entry,preview_player)
	if source_clip==null: return
	recipe_signature = Catalog.Recipes.signature(str(entry.get("recipe","")))
	recipe_revision = Catalog.Recipes.revision
	trajectory_solver = preload("res://scripts/pass_trajectory_solver.gd").new(preview_player,source_clip)
	render_clip = source_clip
	if source_clip.has_meta("contact_time"):
		render_clip = trajectory_solver.solve(StorySession.pass_output_angle if StorySession.pass_output_angle >= 0 else 45.0,StorySession.pass_distance).clip
	preview_player.install_custom(render_clip,"preview",false)
	if not is_instance_valid(ball_preview):
		ball_preview = BallPreview.new()
		preview_player.get_parent().add_child(ball_preview)
	ball_preview.practice_mode = selected_category == "Forearm reception"
	ball_preview.configure(preview_player,render_clip)
	if is_instance_valid(reception_controls): reception_controls.show_result(render_clip)
	preview_clock = minf(0,ball_preview.contact_time-ball_preview.feed_duration)
	preview_player.animator.play("custom_preview/clip",0)
	preview_player.animator.advance(0)
	preview_player.animator.pause()
	right_panel.visible = ball_preview.active
	angle_control.visible = ball_preview.active
	if ball_preview.active: sync_ball_results(float(render_clip.get_meta("desired_output_angle",ball_preview.output_angle())))

func apply_output_angle(value: float) -> void:
	if source_clip == null or not source_clip.has_meta("contact_time"): return
	angle_control.apply_setup(preview_player)
	if is_instance_valid(reception_controls): reception_controls.apply(preview_player,replace_body_layer)
	StorySession.pass_output_angle = value
	var result: Dictionary = trajectory_solver.solve(value,StorySession.pass_distance)
	var last_contact_clock: float = ball_preview.last_time
	render_clip = result.clip
	preview_player.install_custom(render_clip,"preview",false)
	preview_player.animator.play("custom_preview/clip",0)
	preview_player.animator.seek(ball_preview.animation_time(preview_clock),true)
	preview_player.animator.advance(0)
	preview_player.animator.pause()
	ball_preview.configure(preview_player,render_clip)
	if is_instance_valid(reception_controls): reception_controls.show_result(render_clip)
	ball_preview.tick(preview_clock,false)
	ball_preview.last_time = last_contact_clock
	angle_control.pending = false
	sync_ball_results(value)

func update_feed_aim() -> void:
	if not is_instance_valid(ball_preview) or not ball_preview.active: return
	angle_control.apply_feed_aim(preview_player)
	ball_preview.recalculate()
	ball_preview.tick(preview_clock,false)
	sync_ball_results(angle_control.requested)

func sync_ball_results(value: float) -> void:
	if ball_preview.missed:
		angle_control.actual_label.visible = true
		angle_control.actual_label.text = "Feed aimed at the selected arrow"
		return
	angle_control.sync_feed(ball_preview.feed_info)
	angle_control.sync_output(ball_preview)
	angle_control.display_result(value,ball_preview.output_angle(),Flight.distance(ball_preview.impact_point,ball_preview.outgoing))

func reception_drill_active() -> bool:
	return is_instance_valid(ball_preview) and ball_preview.active and ball_preview.practice_mode

func _process(delta: float) -> void:
	super._process(delta)
	var in_control: bool = player_controls!=null and player_controls.active
	if not in_control:
		recipe_poll += delta
		if recipe_poll>=0.4:
			recipe_poll = 0
			refresh_recipes()
	if not is_instance_valid(ball_preview) or not ball_preview.active:
		timing_meter.hide()
		return
	var first := minf(0,ball_preview.contact_time-ball_preview.feed_duration)
	var last: float = ball_preview.cycle_end()
	var previous := preview_clock
	if setup_drag.mode.is_empty() or reception_drill_active():
		preview_clock = first+fposmod(preview_clock-first+delta,last-first)
	if reception_drill_active():
		if preview_clock < previous:
			ball_preview.reset_practice_serve()
			if in_control: drill_status.text = "Next serve  |  Hold Space just before contact"
		elif in_control:
			ball_preview.try_practice_pass(previous,preview_clock,player_controls.receive_hold)
			var floor_time: float = ball_preview.contact_time+ball_preview.practice_floor_time
			if ball_preview.crossed(preview_clock,floor_time): ball_preview.finish_practice_serve()
		timing_meter.update_timing(in_control,player_controls.receive_hold,ball_preview.practice_grade,delta)
		if not in_control:
			preview_player.animator.seek(0.0,true)
			drill_status.text = "F1 to play  |  WASD to move\nHold Space just before contact"
	else:
		timing_meter.hide()
		if not in_control: preview_player.animator.seek(ball_preview.animation_time(preview_clock),true)
	ball_preview.tick(preview_clock,true)

func refresh_recipes() -> void:
	if selected_category!="Forearm reception" or selected_entry.is_empty(): return
	Catalog.Recipes.refresh()
	var body_path := "res://assets/animation_recipes/reception_bodies.json"
	var text := FileAccess.get_file_as_string(body_path)
	var body_changed := false
	if text!=body_recipe_text:
		var parser := JSON.new()
		if parser.parse(text)==OK and parser.data is Dictionary:
			preload("res://scripts/reception_layers.gd").BODIES = parser.data
			body_recipe_text = text
			body_changed = true
	var id: String = selected_entry.id
	if recipe_revision!=Catalog.Recipes.revision:
		recipe_revision = Catalog.Recipes.revision
		animation_list.clear()
		for entry in Catalog.entries(selected_category,current_type()):
			var index: int = animation_list.item_count
			animation_list.add_item(entry.name)
			animation_list.set_item_metadata(index,entry)
			if entry.id==id:
				animation_list.select(index)
				selected_entry = entry.duplicate(true)
	var signature := Catalog.Recipes.signature(str(selected_entry.get("recipe","")))
	if signature==recipe_signature and not body_changed: return
	var replacement := Catalog.load_clip(selected_entry,preview_player)
	if replacement==null: return
	source_clip = replacement
	recipe_signature = signature
	preload("res://scripts/pass_trajectory_solver.gd").cache.clear()
	trajectory_solver = preload("res://scripts/pass_trajectory_solver.gd").new(preview_player,source_clip)
	apply_output_angle(angle_control.requested)

func handle_preview_input(event: InputEvent) -> void:
	if player_controls!=null and player_controls.active:
		super.handle_preview_input(event)
		return
	if setup_drag != null and setup_drag.handle(event):
		preview.accept_event()
		return
	super.handle_preview_input(event)

func open_editor(index := -1) -> void:
	if index >= 0: preview_animation(index)
	if selected_entry.is_empty(): return
	StorySession.edit_entry = selected_entry.duplicate(true)
	StorySession.edit_animation = render_clip
	StorySession.animation_return = {"category":selected_category,"type":current_type(),"id":selected_entry.id}
	get_tree().change_scene_to_file("res://scenes/animation_editor.tscn")

func cycle_type(direction: int) -> void:
	if selected_category.is_empty(): return
	type_indices[selected_category] = posmod(int(type_indices.get(selected_category,0))+direction,MOVE_TYPES[selected_category].size())
	refresh_type()

func open_menu() -> void:
	if not selected_category.is_empty():
		var previous := selected_category
		show_categories()
		category_buttons[previous].grab_focus()
	else: get_tree().change_scene_to_file("res://scenes/story.tscn")

func _input(event: InputEvent) -> void:
	super._input(event)
	if event is InputEventKey and event.keycode in [KEY_F1,KEY_F2]: return
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B:
		open_menu()
		get_viewport().set_input_as_handled()
		return
	if selected_category.is_empty(): return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Z and event.ctrl_pressed and not (event.shift_pressed or event.alt_pressed or event.meta_pressed):
			var focus := get_viewport().gui_get_focus_owner()
			if not (focus is LineEdit or focus is TextEdit) and not player_controls.active and angle_control.visible:
				if angle_control.undo_placement(): get_viewport().set_input_as_handled()
			return
		if event.keycode in [KEY_Q,KEY_E]:
			cycle_type(-1 if event.keycode == KEY_Q else 1)
			get_viewport().set_input_as_handled()
	if event is InputEventJoypadMotion and event.axis in [JOY_AXIS_TRIGGER_LEFT,JOY_AXIS_TRIGGER_RIGHT]:
		var key := str(event.device)+":"+str(event.axis)
		if event.axis_value <= 0.25: trigger_held[key] = false
		elif event.axis_value >= 0.6 and not trigger_held.get(key,false):
			trigger_held[key] = true
			cycle_type(-1 if event.axis == JOY_AXIS_TRIGGER_LEFT else 1)
			get_viewport().set_input_as_handled()
