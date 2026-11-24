extends Node3D

const Profile = preload("res://scripts/player_profile.gd")
const FOREARM_PLATFORM := "straight_pass_02"
const ForearmReach = preload("res://scripts/forearm_reach_pose.gd")
const ForwardDive = preload("res://scripts/forward_reception_dive.gd")
const SideKneeSlide = preload("res://scripts/side_knee_slide.gd")
const PassRecipes = preload("res://scripts/pass_recipe_library.gd")

var attributes: Dictionary = Profile.clean({})
var kit_material: StandardMaterial3D
var pose_author: RefCounted
@export var team_color := Color("2c8fe5")
@export var player_number := 1
var display_name := "Player"
var height_cm: float = Profile.DEFAULTS.height_cm
var handedness := "Right"
var mirror_animation := false
var model: Node3D
var skeleton: Skeleton3D
var animator: AnimationPlayer
var animation_slots := {"idle":"volleyball/goalkeeper_idle","run":"base/Jog_Fwd","jump":"base/Jump_Start","land":"base/Jump_Land"}

func _ready() -> void:
	set_height_cm(height_cm)
	add_child(preload("res://scripts/player_direction_arrows.gd").new())
	model = preload("res://assets/characters/base/Superhero_Male_FullBody.gltf").instantiate()
	if mirror_animation:
		var reflection := Node3D.new()
		reflection.name = "AnimationReflection"
		reflection.basis = Basis.from_scale(Vector3(-1.0,1.0,1.0))
		add_child(reflection)
		reflection.add_child(model)
	else: add_child(model)
	skeleton = model.find_child("Skeleton3D",true,false)
	for mesh: MeshInstance3D in skeleton.find_children("*","MeshInstance3D",true,false):
		for surface in mesh.mesh.get_surface_count():
			var original := mesh.mesh.surface_get_material(surface)
			if original == null: continue
			var skin := original.duplicate() as StandardMaterial3D
			if mirror_animation: skin.cull_mode = BaseMaterial3D.CULL_DISABLED
			skin.roughness = 0.85
			skin.metallic_specular = 0.2
			if skin.resource_name=="MI_Hair_1":
				skin.albedo_color=Color("503d31")
			if skin.resource_name=="MI_Eyes":
				skin.roughness=.22
				skin.metallic_specular=.52
				skin.clearcoat_enabled=true
				skin.clearcoat=.82
				skin.clearcoat_roughness=.075
				skin.normal_enabled=true
				skin.normal_texture=preload("res://assets/characters/base/T_Eye_Normal.png")
				skin.normal_scale=.32
			if skin.resource_name.begins_with("MI_Superhero"):
				skin.normal_enabled=true
				skin.normal_texture=preload("res://assets/characters/base/T_Superhero_Male_Normal.png")
				skin.normal_scale=.65
				skin.roughness_texture=preload("res://assets/characters/base/T_Superhero_Male_Roughness.png")
				skin.roughness=.83
				skin.metallic_specular=.36
				skin.subsurf_scatter_enabled=true
				skin.subsurf_scatter_skin_mode=true
				skin.subsurf_scatter_strength=.18
				mesh.mesh = preload("res://assets/characters/volleyball/body.res")
				skin.albedo_texture = preload("res://assets/characters/base/T_Superhero_Male_Light.png")
				var outfit := MeshInstance3D.new()
				outfit.mesh = preload("res://assets/characters/volleyball/outfit.res")
				outfit.skin = mesh.skin
				skeleton.add_child(outfit)
				outfit.skeleton = outfit.get_path_to(skeleton)
				for slot in outfit.mesh.get_surface_count():
					var cloth := StandardMaterial3D.new()
					cloth.albedo_color = team_color if slot == 0 else Color("26333e")
					if slot == 2: cloth.albedo_color = Color("c5c9cc")
					if slot == 0: kit_material = cloth
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
	var volleyball := AnimationLibrary.new()
	volleyball.add_animation("goalkeeper_idle",preload("res://assets/animations/goalkeeper_idle.tres").duplicate(true))
	animator.add_animation_library("volleyball",volleyball)
	play_action("idle")
	animator.advance(float(player_number)*0.31)

func play_action(action: String, blend := 0.15) -> void:
	if action == "forearm" and not animation_slots.has(action):
		PassRecipes.refresh()
		var platform := PassRecipes.clip(self,FOREARM_PLATFORM)
		if platform != null: install_custom(platform,action,false)
		return
	var clip: String = animation_slots.get(action,action)
	if animator.has_animation(clip): animator.play(clip,blend)

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

func apply_profile(profile: Dictionary) -> void:
	var values := Profile.clean(profile)
	attributes = values
	display_name = values.name
	set_height_cm(values.height_cm)
	handedness = values.handedness

func set_height_cm(value: float) -> void:
	height_cm = value
	scale = Vector3.ONE*(height_cm/180.0)

func get_pose_author() -> RefCounted:
	if pose_author == null:
		pose_author = preload("res://tools/animation_author.gd").new(skeleton,preload("res://assets/animations/goalkeeper_idle.tres"))
	return pose_author

func animation_side(side: String) -> String:
	return ("r" if side == "l" else "l") if mirror_animation else side

func pose_reception_reach(step: Vector3, travel: Vector3, weight: float, progress: float, ready: Array[Transform3D], reach: Dictionary, knee_slide: bool, direction: int, contact: Vector3) -> void:
	if mirror_animation:
		step.x = -step.x
		travel.x = -travel.x
		if reach.get("court_lead",false) or reach.side_lunge or reach.rear_diagonal or absf(step.x) > 0.10 and absf(step.x) > absf(step.z)*0.55:
			reach = reach.duplicate()
			reach.lead = animation_side(reach.lead)
	ForearmReach.sample(skeleton,get_pose_author(),step,travel,weight,progress,ready,reach,knee_slide,direction,contact)

func pose_reception_dive(ready: Array[Transform3D], clasp: Array[Transform3D], start: Vector3, heading: Vector3, time: float, ball_point: Vector3, release_time: float, pancake := false, travel_scale := 1.0, track_platform := false, wide_arm := "", slide_heading := Vector3.ZERO) -> void:
	ForwardDive.sample(self,get_pose_author(),ready,clasp,start,heading,time,ball_point,release_time,pancake,travel_scale,track_platform,wide_arm,slide_heading)

func pose_reception_knee_slide(from_pose: Array[Transform3D], ready: Array[Transform3D], start: Vector3, side: String, time: float, contact: Dictionary) -> void:
	SideKneeSlide.sample(self,get_pose_author(),from_pose,ready,start,side,time,contact)

var shorts_fabric: ShaderMaterial
var hair_material: ShaderMaterial
var hair_mount: Node3D
const HAIR_GUIDES := [Vector3(-.08,.18,0),Vector3(.08,.18,0),Vector3(0,.18,.08),Vector3(0,.18,-.09)]
var hair_anchors := PackedVector3Array()
var hair_offsets := PackedVector3Array()
var hair_speeds := PackedVector3Array()
var hair_length := .04

func update_hair(dt: float) -> void:
	if hair_anchors.is_empty():
		hair_offsets.resize(4)
		hair_speeds.resize(4)
		for guide: Vector3 in HAIR_GUIDES: hair_anchors.append(hair_mount.to_global(guide))
	var local_basis := hair_mount.global_basis.inverse()
	# Longer cuts swing farther and settle more slowly after a plant.
	var length_mix := smoothstep(.022,.076,hair_length)
	var stiffness := lerpf(540.,175.,length_mix)
	var damping := lerpf(33.,14.,length_mix)
	var steps := maxi(1,ceili(minf(dt,.12)*120.))
	var h := minf(dt,.12)/steps
	for i in HAIR_GUIDES.size():
		var anchor := hair_mount.to_global(HAIR_GUIDES[i])
		var shift := anchor-hair_anchors[i]
		hair_anchors[i]=anchor
		if shift.length()>.45:
			hair_offsets[i]=Vector3.ZERO
			hair_speeds[i]=Vector3.ZERO
		else:
			for j in steps:
				# The head moves the roots immediately. Unsupported tips
				# retain world-space inertia before the lock springs back.
				hair_offsets[i]-=shift/steps
				var wind_force := fabric_airflow*hair_length*(12.+3.*sin(fabric_time*2.2+i))
				hair_speeds[i]+=wind_force*h
				hair_speeds[i]+=(-hair_offsets[i]*(stiffness+i*9.)-hair_speeds[i]*damping)*h
				hair_offsets[i]=(hair_offsets[i]+hair_speeds[i]*h).limit_length(hair_length*.58)
		hair_material.set_shader_parameter("guide_"+str(i),local_basis*hair_offsets[i])

var jersey_materials: Array[ShaderMaterial]=[]
var jersey_origin := Vector3.ZERO
var jersey_speed := 0.
var dressed_surface := preload("res://scripts/dressed_contact.gd").new()
var sleeve_cloth: RefCounted
var underarm_fabric: ShaderMaterial
var shirt_fabric: ShaderMaterial
var leg_skin: ShaderMaterial
var exertion_total := 0.0
var exertion_sample := 0.0
var dampness := 0.0
@export var fabric_airflow := Vector3(.48,0,.15)
var fabric_time := 0.
var cloth_offset := Vector3.ZERO
var cloth_velocity := Vector3.ZERO

func _process(dt: float) -> void:
	if jersey_materials.is_empty() or dt<=0.: return
	fabric_time+=dt
	var gust := .77+.23*sin(fabric_time*1.7+global_position.x*.6)
	var air := fabric_airflow*gust
	if sleeve_cloth: sleeve_cloth.update(skeleton,shirt_fabric,dt,air)
	if shirt_fabric:
		var tension := Vector2.ZERO
		for i in 2:
			var side: String=["l","r"][i]
			var shoulder := skeleton.get_bone_global_pose(skeleton.find_bone("upperarm_"+side)).origin
			var elbow := skeleton.get_bone_global_pose(skeleton.find_bone("lowerarm_"+side)).origin
			tension[i]=smoothstep(-.82,.20,(elbow-shoulder).normalized().y)
		shirt_fabric.set_shader_parameter("arm_lift",tension)
		if underarm_fabric: underarm_fabric.set_shader_parameter("arm_lift",tension)
	if leg_skin:
		var flex := Vector2.ZERO
		var calf_load := Vector2.ZERO
		var stride := Vector2.ZERO
		for i in 2:
			var side: String=["l","r"][i]
			var hip := skeleton.get_bone_global_pose(skeleton.find_bone("thigh_"+side)).origin
			var knee := skeleton.get_bone_global_pose(skeleton.find_bone("calf_"+side)).origin
			var ankle := skeleton.get_bone_global_pose(skeleton.find_bone("foot_"+side)).origin
			stride[i]=smoothstep(.08,.85,absf((knee-hip).normalized().z))
			flex[i]=smoothstep(.12,1.65,(knee-hip).angle_to(ankle-knee))
			var toe_id := skeleton.find_bone("ball_"+side)
			if toe_id>=0:
				var toe := skeleton.get_bone_global_pose(toe_id).origin
				var rest_shin := skeleton.get_bone_global_rest(skeleton.find_bone("calf_"+side)).origin
				var rest_ankle := skeleton.get_bone_global_rest(skeleton.find_bone("foot_"+side)).origin
				var rest_toe := skeleton.get_bone_global_rest(toe_id).origin
				var neutral := (rest_shin-rest_ankle).angle_to(rest_toe-rest_ankle)
				calf_load[i]=smoothstep(.025,.53,(knee-ankle).angle_to(toe-ankle)-neutral)
		if shorts_fabric: shorts_fabric.set_shader_parameter("stride",stride)
		leg_skin.set_shader_parameter("calf_load",calf_load)
		leg_skin.set_shader_parameter("knee_flex",flex)
	if hair_material and hair_mount:
		update_hair(dt)
	var displacement := global_position-jersey_origin
	var travel := displacement.length()
	if shirt_fabric:
		var work := maxf(0.,exertion_total-exertion_sample)*.004
		if travel<1.: work+=travel*.0017
		exertion_sample=exertion_total
		dampness=clampf(dampness+work-dt*.00012,0.,1.)
		shirt_fabric.set_shader_parameter("dampness",dampness)
	var drag := Vector3.ZERO
	if travel<1.:
		drag=(global_basis.orthonormalized().inverse()*(air-displacement/dt)*.012).limit_length(.065)
	var steps := maxi(1,ceili(minf(dt,.10)*120.))
	var h := minf(dt,.10)/steps
	for i in steps:
		cloth_velocity+=((drag-cloth_offset)*155.-cloth_velocity*13.)*h
		cloth_offset+=cloth_velocity*h
	jersey_origin=global_position
	var speed := clampf(travel/dt/6.2,0.,1.) if travel<1. else 0.
	jersey_speed=lerpf(jersey_speed,speed,1.-exp(-dt*(12. if speed>jersey_speed else 5.)))
	for material in jersey_materials:
		material.set_shader_parameter("motion",jersey_speed)
		material.set_shader_parameter("inertia",cloth_offset)
