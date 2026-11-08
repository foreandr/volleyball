extends SceneTree
const Author = preload("res://tools/animation_author.gd")
func _initialize() -> void:
	var model := preload("res://assets/characters/base/Superhero_Male_FullBody.gltf").instantiate()
	var rig: Skeleton3D = model.find_child("Skeleton3D",true,false)
	var recipe: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/animation_recipes/straight_pass_01.json"))
	var author := Author.new(rig,preload("res://assets/animations/goalkeeper_idle.tres"))
	var clip := author.bake(recipe)
	print("Straight pass baked: ",ResourceSaver.save(clip,"res://assets/animations/straight_pass_01.tres"))
	model.free()
	quit()
