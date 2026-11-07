extends "res://scripts/create.gd"
const CATEGORIES := ["Passing","Spiking","Serving","Blocking","Setting","Digging","Chasing"]
var animation_list: ItemList
var category_panels: Dictionary = {}
var animation_lists: Dictionary = {}
var category_buttons: Dictionary = {}
var selected_category := "Passing"

func screen_title() -> String:
	return "ANIMATIONS"

func initial_profile() -> Dictionary:
	return StorySession.active.get("profile",Profile.load_profile()).duplicate(true)

func build_controls(controls: VBoxContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	controls.add_child(scroll)
	var sections := VBoxContainer.new()
	sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sections.add_theme_constant_override("separation",8)
	scroll.add_child(sections)
	var group := ButtonGroup.new()
	for category in CATEGORIES:
		var section := panel()
		section.name = category+"Panel"
		sections.add_child(section)
		category_panels[category] = section
		var content := VBoxContainer.new()
		content.add_theme_constant_override("separation",4)
		section.add_child(content)
		var heading := Button.new()
		heading.text = category
		heading.name = category
		heading.custom_minimum_size.y = 44
		heading.toggle_mode = true
		heading.button_group = group
		heading.alignment = HORIZONTAL_ALIGNMENT_LEFT
		heading.pressed.connect(select_category.bind(category))
		content.add_child(heading)
		category_buttons[category] = heading
		var list := ItemList.new()
		list.name = category+"Animations"
		list.custom_minimum_size.y = 100
		content.add_child(list)
		animation_lists[category] = list
	animation_list = animation_lists.Passing
	select_category(selected_category)

func select_category(category: String) -> void:
	selected_category = category
	for key in animation_lists:
		animation_lists[key].visible = key == category
		category_buttons[key].set_pressed_no_signal(key == category)

func open_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/story.tscn")
