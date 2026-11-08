extends SceneTree
const Recipes = preload("res://scripts/pass_recipe_library.gd")
class RigHost extends Node3D:
	var skeleton: Skeleton3D

func _initialize() -> void: call_deferred("build")

func build() -> void:
	var output := "res://work/pass-batch"
	var ids: Array = []
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): output = argument.trim_prefix("--out=")
		else: ids.append(argument)
	Recipes.refresh()
	if ids.is_empty(): ids = Recipes.records.keys()
	var model := preload("res://assets/characters/base/Superhero_Male_FullBody.gltf").instantiate()
	var actor := RigHost.new()
	actor.skeleton = model.find_child("Skeleton3D",true,false)
	if DirAccess.make_dir_recursive_absolute(output)!=OK:
		push_error("Cannot create batch output: "+output)
		quit(1)
		return
	var start := Time.get_ticks_msec()
	for id in ids:
		# IDs become filenames, never paths outside the chosen output folder.
		if str(id).validate_filename()!=str(id):
			quit(1)
			return
		var animation := Recipes.clip(actor,str(id))
		if animation==null or ResourceSaver.save(animation,output.path_join(str(id)+".res"),ResourceSaver.FLAG_COMPRESS)!=OK:
			push_error("Cannot build recipe: "+str(id))
			quit(1)
			return
	print("Built ",ids.size()," passes in ",Time.get_ticks_msec()-start," ms: ",output)
	model.free()
	actor.free()
	quit()
