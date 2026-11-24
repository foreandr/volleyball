extends Node

const Profile = preload("res://scripts/player_profile.gd")
const Kit = preload("res://scripts/practice_kit.gd")
const DIRECTORY := "user://school_headshots"
var textures := {}
var jobs: Array[Dictionary] = []
var busy := false

func request(values: Dictionary, variant := 0, color := Color("e97937")) -> Texture2D:
	var profile := Profile.clean(values)
	var key := (JSON.stringify(profile) + str(variant) + color.to_html()).sha256_text()
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
		jobs.append({"profile":profile,"variant":variant,"color":color,"path":path,"texture":texture})
		if not busy:
			busy = true
			render_queue.call_deferred()
	return texture

func render_queue() -> void:
	DirAccess.make_dir_recursive_absolute(DIRECTORY)
	while not jobs.is_empty():
		var job: Dictionary = jobs.pop_front()
		var studio := SubViewport.new()
		studio.world_3d = World3D.new()
		studio.size = Vector2i(256,256)
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
		Kit.apply(actor,false,job.variant)
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

