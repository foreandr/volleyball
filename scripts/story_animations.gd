extends "res://scripts/create.gd"
var animation_list: ItemList

func screen_title() -> String:
	return "ANIMATIONS"

func initial_profile() -> Dictionary:
	return StorySession.active.get("profile",Profile.load_profile()).duplicate(true)

func build_controls(controls: VBoxContainer) -> void:
	animation_list = ItemList.new()
	animation_list.name = "AnimationList"
	animation_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	controls.add_child(animation_list)

func open_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/story.tscn")
