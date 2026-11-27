extends Node

const Profile = preload("res://scripts/player_profile.gd")
const Kit = preload("res://scripts/practice_kit.gd")
const DIRECTORY := "user://school_headshots"
var textures := {}
var jobs: Array[Dictionary] = []
var busy := false
var lineup_studio:SubViewport
var lineup_actor:Node3D
var lineup_camera:Camera3D

func request(values: Dictionary, variant := 0, color := Color("e97937"), full_length := false) -> Texture2D:
	var profile := Profile.clean(values)
	var key := (JSON.stringify(profile) + ("" if full_length else str(variant)) + color.to_html() + ("-lineup-v3" if full_length else "-build-v2") + ("-captain" if not full_length and variant==Kit.SCHOOL_CAPTAIN_VARIANT else "")).sha256_text()
	if textures.has(key): return textures[key]
	var path := DIRECTORY.path_join(key + ".png")
	var texture := ImageTexture.new()
	textures[key] = texture
	if FileAccess.file_exists(path):
		var saved := Image.load_from_file(path)
		if saved != null and not saved.is_empty():
			texture.set_image(saved)
			return texture
	if DisplayServer.get_name() != "headless":
		jobs.append({"full_length":full_length,"profile":profile,"variant":variant,"color":color,"path":path,"texture":texture})
		if not busy:
			busy = true
			render_queue.call_deferred()
	return texture

func render_queue() -> void:
	DirAccess.make_dir_recursive_absolute(DIRECTORY)
	while not jobs.is_empty():
		var job: Dictionary = jobs.pop_front()
		if job.full_length:
			await render_lineup(job)
			continue
		var studio := SubViewport.new()
		studio.world_3d = World3D.new()
		studio.size = Vector2i(256,256)
		studio.transparent_bg = false
		add_child(studio)
		var environment := Environment.new()
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = Color("556978")
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = Color.WHITE
		environment.ambient_light_energy = 0.85
		studio.world_3d.environment = environment
		var actor := preload("res://scripts/volleyball_player.gd").new()
		actor.team_color = job.color
		studio.add_child(actor)
		actor.apply_profile(job.profile)
		Kit.apply(actor,false,job.variant,true)
		actor.play_action("base/Idle",0)
		actor.animator.advance(0)
		actor.animator.pause()
		var rig := actor.skeleton
		var head := rig.to_global(rig.get_bone_global_pose(rig.find_bone("Head")).origin)
		var center := head - Vector3.UP * 0.07
		var camera := Camera3D.new()
		studio.add_child(camera)
		camera.position = center + Vector3.BACK * 1.4
		camera.look_at(center)
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 0.74 * actor.height_cm / 180.0
		var light := DirectionalLight3D.new()
		studio.add_child(light)
		light.rotation_degrees = Vector3(-22,18,0)
		studio.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		var image := studio.get_texture().get_image()
		job.texture.set_image(image)
		if image.save_png(job.path) != OK: push_error("Could not save school headshot.")
		studio.queue_free()
		await get_tree().process_frame
	busy = false


func render_lineup(job:Dictionary) -> void:
	if not lineup_studio:
		lineup_studio=SubViewport.new()
		lineup_studio.world_3d=World3D.new()
		lineup_studio.size=Vector2i(160,224)
		lineup_studio.transparent_bg=true
		add_child(lineup_studio)
		var light:=DirectionalLight3D.new()
		light.rotation_degrees=Vector3(-22,18,0)
		lineup_studio.add_child(light)
		var ambient:=Environment.new()
		ambient.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
		ambient.ambient_light_color=Color.WHITE
		ambient.ambient_light_energy=.85
		lineup_studio.world_3d.environment=ambient
		lineup_actor=preload("res://scripts/volleyball_player.gd").new()
		lineup_studio.add_child(lineup_actor)
		Kit.apply(lineup_actor,false,0,false)
		lineup_actor.get_node("DirectionArrows").hide()
		lineup_camera=Camera3D.new()
		lineup_camera.projection=Camera3D.PROJECTION_ORTHOGONAL
		lineup_studio.add_child(lineup_camera)
	lineup_actor.team_color=job.color
	lineup_actor.apply_profile(job.profile)
	lineup_actor.shirt_fabric.set_shader_parameter("fabric",job.color)
	lineup_actor.play_action("base/Idle",0)
	lineup_actor.animator.advance(0)
	lineup_actor.animator.pause()
	var center:Vector3=Vector3.UP*lineup_actor.height_cm/200.
	lineup_camera.position=center+Vector3(.27,.04,3.)
	lineup_camera.look_at(center)
	lineup_camera.size=lineup_actor.height_cm/100.+.27
	# The first draw may contain only the rigid kit while skinned meshes and
	# shader pipelines finish preparing. Publish the assembled figure.
	lineup_studio.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	var image:Image
	for frame in 45:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		if frame<2: continue
		image=lineup_studio.get_texture().get_image()
		if complete_figure(image): break
	lineup_studio.render_target_update_mode=SubViewport.UPDATE_DISABLED
	if not complete_figure(image):
		push_warning("Lineup portrait still loading for "+str(job.profile.name))
		if not job.get("retried",false):
			job.retried=true
			jobs.append(job)
		else:
			for key in textures:
				if textures[key]==job.texture:
					textures.erase(key)
					break
		return
	job.texture.set_image(image)
	if image.save_png(job.path)!=OK: push_error("Could not save lineup portrait.")
	await get_tree().process_frame

func complete_figure(image:Image) -> bool:
	if image==null or image.is_empty(): return false
	# Require a head, a filled upper torso, and legs within the fitted camera.
	for band in [Vector3i(21,52,14),Vector3i(61,100,27),Vector3i(137,192,14)]:
		var widest:=0
		for y in range(band.x,band.y,4):
			var filled:=0
			for x in range(24,136,2):
				if image.get_pixel(x,y).a>.50: filled+=2
			widest=maxi(widest,filled)
		if widest<band.z: return false
	return true
