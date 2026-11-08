extends SceneTree
const Author = preload("res://tools/animation_author.gd")
func _initialize() -> void:
	var model := preload("res://assets/characters/base/Superhero_Male_FullBody.gltf").instantiate()
	var rig: Skeleton3D = model.find_child("Skeleton3D",true,false)
	var author := Author.new(rig,preload("res://assets/animations/goalkeeper_idle.tres"))
	for number in range(2,12):
		var recipe: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/animation_recipes/straight_pass_%02d.json" % number))
		var clip := author.bake(recipe)
		var path := "res://assets/animations/straight_pass_%02d.res" % number
		print(recipe.name,": ",ResourceSaver.save(clip,path,ResourceSaver.FLAG_COMPRESS))
	model.free()
	quit()
