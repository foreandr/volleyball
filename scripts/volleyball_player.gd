extends Node3D
@export var team_color := Color("2c8fe5")
@export var player_number := 1
var model: Node3D
var skeleton: Skeleton3D
var animator: AnimationPlayer
var animation_slots := {"idle":"base/Idle","run":"base/Jog_Fwd","jump":"base/Jump_Start","land":"base/Jump_Land"}

func _ready() -> void:
	model = preload("res://assets/characters/base/Superhero_Male_FullBody.gltf").instantiate()
	add_child(model)
	skeleton = model.find_child("Skeleton3D",true,false)
	for mesh: MeshInstance3D in skeleton.find_children("*","MeshInstance3D",true,false):
		for surface in mesh.mesh.get_surface_count():
			var original := mesh.mesh.surface_get_material(surface)
			if original == null: continue
			var skin := original.duplicate() as StandardMaterial3D
			skin.roughness = 0.85
			skin.metallic_specular = 0.2
			if skin.resource_name.begins_with("MI_Superhero"):
				mesh.mesh = preload("res://assets/outfits/brutus_body.res")
				skin.albedo_texture = preload("res://assets/characters/base/T_Superhero_Male_Light.png")
				var outfit := MeshInstance3D.new()
				outfit.mesh = preload("res://assets/outfits/brutus_outfit.res")
				outfit.skin = mesh.skin
				skeleton.add_child(outfit)
				outfit.skeleton = outfit.get_path_to(skeleton)
				for slot in outfit.mesh.get_surface_count():
					var cloth := StandardMaterial3D.new()
					cloth.albedo_color = team_color if slot == 0 else Color("26333e")
					if slot == 2: cloth.albedo_color = Color("c5c9cc")
					cloth.roughness = 0.9
					cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
					outfit.set_surface_override_material(slot,cloth)
			mesh.set_surface_override_material(surface,skin)
	animator = AnimationPlayer.new()
	animator.name = "AnimationPlayer"
	model.add_child(animator)
	# Each player owns editable copies; custom poses never alter the source library.
	var library: AnimationLibrary = preload("res://assets/animations/UAL1_Standard.glb").duplicate(true)
	animator.add_animation_library("base",library)
	play_action("idle")
	animator.advance(float(player_number)*0.31)
	for slot in ["idle","run","jump","land","serve","pass","set","spike","block"]:
		var path := "user://animations/%s_%s.tres" % [name,slot]
		if ResourceLoader.exists(path): install_custom(load(path),slot,false)
	play_action("idle")

func play_action(action: String) -> void:
	var clip: String = animation_slots.get(action,action)
	if animator.has_animation(clip): animator.play(clip,0.15)

func install_custom(resource: Resource, slot := "idle", save := true) -> bool:
	var library := AnimationLibrary.new()
	if resource is Animation:
		library.add_animation("clip",resource.duplicate(true))
	elif resource is AnimationLibrary:
		library = resource.duplicate(true)
	else: return false
	if library.get_animation_list().is_empty(): return false
	var key := "custom_"+slot
	if animator.has_animation_library(key): animator.remove_animation_library(key)
	animator.add_animation_library(key,library)
	animation_slots[slot] = key+"/"+str(library.get_animation_list()[0])
	if save:
		DirAccess.make_dir_recursive_absolute("user://animations")
		ResourceSaver.save(library,"user://animations/%s_%s.tres" % [name,slot])
	play_action(slot)
	return true
