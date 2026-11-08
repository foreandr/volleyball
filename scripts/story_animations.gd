extends "res://scripts/create.gd"
const Catalog = preload("res://scripts/volleyball_animations.gd")
const MOVE_TYPES := {
	"Passing":["Straight","Left","Right","Dive Left","Dive Right"],
	"Spiking":["Line Hit","Cross Hit"],
	"Serving":["Float","Spin","Hybrid","Skyball","Underhand","Standing Float","Standing Spin"],
	"Blocking":["Straight","Left","Right"],
	"Setting":["Forward","Back","Left","Right"],
	"Digging":["Straight","Left","Right","Dive Left","Dive Right"],
	"Chasing":["Forward","Back","Left","Right"]
}
const CATEGORIES := ["Passing","Spiking","Serving","Blocking","Setting","Digging","Chasing"]
var content: VBoxContainer
var category_buttons: Dictionary = {}
var selected_category := ""
var type_indices: Dictionary = {}
var type_label: Label
var animation_list: ItemList
var trigger_held := {}
var edit_button: Button
var selected_entry: Dictionary = {}
var ball_preview: Node3D
var angle_control: VBoxContainer
var source_clip: Animation
var trajectory_solver: RefCounted
var render_clip: Animation

func _ready() -> void:
	process_priority = 10
	super._ready()
	if not StorySession.animation_return.is_empty():
		var destination: Dictionary = StorySession.animation_return.duplicate()
		StorySession.animation_return.clear()
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
	max_view_distance = 24.0
	pan_limits = Vector3(9,5,17)
	view_distance = 9.5
	view_focus = Vector3(0,1.0,1.8)

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
	angle_control = null
	animation_list = null
	edit_button = null
	selected_entry.clear()
	type_label = null

func set_title(text: String) -> void:
	var heading := find_child("ScreenTitle",true,false) as Label
	if heading: heading.text = text

func show_categories() -> void:
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
	if not MOVE_TYPES.has(category): return
	selected_category = category
	clear_content()
	set_title(category.to_upper())
	var row := HBoxContainer.new()
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
	angle_control = preload("res://scripts/pass_angle_control.gd").new()
	content.add_child(angle_control)
	angle_control.angle_requested.connect(apply_output_angle)
	animation_list = ItemList.new()
	animation_list.name = "AnimationList"
	animation_list.allow_reselect = true
	animation_list.add_theme_font_size_override("font_size",18)
	animation_list.item_selected.connect(preview_animation)
	animation_list.item_activated.connect(open_editor)
	animation_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(animation_list)
	edit_button = button("Edit",open_editor)
	edit_button.name = "EditAnimation"
	content.add_child(edit_button)
	refresh_type()
	animation_list.grab_focus()

func current_type() -> String:
	if selected_category.is_empty(): return ""
	return MOVE_TYPES[selected_category][type_indices.get(selected_category,0)]

func refresh_type() -> void:
	angle_control.hide()
	type_label.text = current_type()
	animation_list.clear()
	selected_entry.clear()
	if is_instance_valid(edit_button): edit_button.disabled = true
	for entry in Catalog.entries(selected_category,current_type()):
		var index := animation_list.add_item(entry.name)
		animation_list.set_item_metadata(index,entry)
	if animation_list.item_count > 0:
		animation_list.select(0)
		preview_animation(0)
	elif is_instance_valid(preview_player):
		preview_player.play_action("idle")
		if is_instance_valid(ball_preview): ball_preview.stop()

func preview_animation(index: int) -> void:
	if not is_instance_valid(preview_player): return
	var entry: Dictionary = animation_list.get_item_metadata(index)
	selected_entry = entry.duplicate(true)
	if is_instance_valid(edit_button): edit_button.disabled = false
	source_clip = load(entry.path)
	trajectory_solver = preload("res://scripts/pass_trajectory_solver.gd").new(preview_player,source_clip)
	render_clip = source_clip
	if source_clip.has_meta("contact_time") and StorySession.pass_output_angle >= 0:
		render_clip = trajectory_solver.solve(StorySession.pass_output_angle).clip
	preview_player.install_custom(render_clip,"preview",false)
	if not is_instance_valid(ball_preview):
		ball_preview = preload("res://scripts/animation_ball_preview.gd").new()
		preview_player.get_parent().add_child(ball_preview)
	ball_preview.configure(preview_player,render_clip)
	angle_control.visible = ball_preview.active
	if ball_preview.active: angle_control.display_result(float(render_clip.get_meta("desired_output_angle",ball_preview.output_angle())),ball_preview.output_angle())

func apply_output_angle(value: float) -> void:
	if source_clip == null or not source_clip.has_meta("contact_time"): return
	StorySession.pass_output_angle = value
	var result: Dictionary = trajectory_solver.solve(value)
	var clock: float = preview_player.animator.current_animation_position
	var running: bool = preview_player.animator.is_playing()
	var last_contact_clock: float = ball_preview.last_time
	render_clip = result.clip
	preview_player.install_custom(render_clip,"preview",false)
	preview_player.animator.play("custom_preview/clip",0)
	preview_player.animator.seek(clock,true)
	preview_player.animator.advance(0)
	if not running: preview_player.animator.pause()
	ball_preview.configure(preview_player,render_clip)
	ball_preview.tick(clock,false)
	ball_preview.last_time = last_contact_clock
	angle_control.display_result(value,ball_preview.output_angle())

func _process(_delta: float) -> void:
	if is_instance_valid(ball_preview) and ball_preview.active:
		ball_preview.tick(preview_player.animator.current_animation_position,preview_player.animator.is_playing())

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
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B:
		open_menu()
		get_viewport().set_input_as_handled()
		return
	if selected_category.is_empty(): return
	if event is InputEventKey and event.pressed and not event.echo:
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
