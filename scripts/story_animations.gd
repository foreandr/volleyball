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
	var clip: Animation = load(entry.path)
	preview_player.install_custom(clip,"preview",false)
	if not is_instance_valid(ball_preview):
		ball_preview = preload("res://scripts/animation_ball_preview.gd").new()
		preview_player.get_parent().add_child(ball_preview)
	ball_preview.configure(preview_player,clip)

func _process(_delta: float) -> void:
	if is_instance_valid(ball_preview) and ball_preview.active:
		ball_preview.tick(preview_player.animator.current_animation_position,preview_player.animator.is_playing())

func open_editor(index := -1) -> void:
	if index >= 0: preview_animation(index)
	if selected_entry.is_empty(): return
	StorySession.edit_entry = selected_entry.duplicate(true)
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
