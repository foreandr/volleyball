extends RefCounted
var page: Control
var mode := ""
var drag_plane: Plane
var grab_offset := Vector3.ZERO
var press_position := Vector2.ZERO
var click_point := Vector2.INF
var click_mode := "ball"
var moved := false

func _init(host: Control) -> void:
	page = host

func screen_position(position: Vector2) -> Vector2:
	return position*Vector2(page.preview_camera.get_viewport().size)/page.preview.size

func handle(event: InputEvent) -> bool:
	if not is_instance_valid(page.ball_preview) or not page.ball_preview.active: return false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			if mode.is_empty(): return false
			if mode=="player" and moved: StorySession.save_preview_setup()
			if mode == "player" and not moved and click_point.is_finite(): page.angle_control.place_point(click_point,click_mode)
			page.angle_control.finish_placement()
			mode = ""
			return true
		var camera: Camera3D = page.preview_camera
		var point := screen_position(event.position)
		var source: Vector3 = page.ball_preview.source_ball.global_position
		var plane_height := 0.065
		press_position = event.position
		moved = false
		var floor_hit: Variant = Plane(Vector3.UP,0.065).intersects_ray(camera.project_ray_origin(point),camera.project_ray_normal(point))
		click_point = Vector2(floor_hit.x,floor_hit.z) if floor_hit is Vector3 else Vector2.INF
		var chosen := "ball" if page.angle_control.tabs.current_tab == 0 else "destination"
		click_mode = chosen
		var origin := source if chosen == "ball" else Vector3(StorySession.pass_destination.x,0.065,StorySession.pass_destination.y)
		var handle_point: Vector3 = origin if chosen == "destination" else page.ball_preview.source_ground.global_position
		var picked_handle := not camera.is_position_behind(handle_point) and camera.unproject_position(handle_point).distance_to(point)<20
		var picked_source := chosen == "ball" and not camera.is_position_behind(source) and camera.unproject_position(source).distance_to(point)<22
		if not picked_handle and not picked_source and floor_hit is Vector3 and page.selected_category == "Forearm reception":
			var arrows: MeshInstance3D = page.preview_player.get_node("DirectionArrows")
			var aim: int = arrows.pick(arrows.to_local(floor_hit))
			if aim >= 0:
				page.angle_control.select_feed_aim(aim)
				page.preview.grab_focus()
				return true
		var foot: Vector3 = page.preview_player.global_position
		var head: Vector3 = foot+Vector3.UP*page.preview_player.scale.y*1.8
		var player_hit := false
		if not camera.is_position_behind(foot):
			var bottom := camera.unproject_position(foot)
			var top := camera.unproject_position(head)
			player_hit = point.distance_to(Geometry2D.get_closest_point_to_segment(point,top,bottom))<maxf(16,bottom.distance_to(top)*0.24)
		mode = "player" if player_hit and not picked_handle and not picked_source else chosen
		if mode == "player":
			origin = foot
			plane_height = foot.y
		elif picked_source: plane_height = source.y
		drag_plane = Plane(Vector3.UP,plane_height)
		var hit: Variant = drag_plane.intersects_ray(camera.project_ray_origin(point),camera.project_ray_normal(point))
		if not hit is Vector3:
			mode = ""
			return false
		page.angle_control.begin_placement()
		if mode == "player" or picked_handle or picked_source: grab_offset = origin-hit
		else:
			grab_offset = Vector3.ZERO
			page.angle_control.place_point(Vector2(clampf(hit.x,-9,9),clampf(hit.z,-8,44)),chosen)
		page.preview.grab_focus()
		return true
	if event is InputEventMouseMotion and not mode.is_empty():
		if event.position.distance_to(press_position)>3: moved = true
		if mode == "player" and not moved: return true
		var camera: Camera3D = page.preview_camera
		var point := screen_position(event.position)
		var hit: Variant = drag_plane.intersects_ray(camera.project_ray_origin(point),camera.project_ray_normal(point))
		if hit is Vector3:
			var target: Vector3 = hit+grab_offset
			if mode == "player": StorySession.pass_start = Vector2(clampf(target.x,-4,4),clampf(target.z,-4.5,2.5))
			else: page.angle_control.place_point(Vector2(clampf(target.x,-9,9),clampf(target.z,-8,44)),mode)
			page.angle_control.pending = true
		return true
	return false
