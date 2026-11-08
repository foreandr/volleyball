extends RefCounted
var page: Control
var mode := ""
var drag_plane: Plane
var grab_offset := Vector3.ZERO

func _init(host: Control) -> void:
	page = host

func screen_position(position: Vector2) -> Vector2:
	return position*Vector2(page.preview_camera.get_viewport().size)/page.preview.size

func handle(event: InputEvent) -> bool:
	if not is_instance_valid(page.ball_preview) or not page.ball_preview.active: return false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			if mode.is_empty(): return false
			mode = ""
			return true
		var camera: Camera3D = page.preview_camera
		var point := screen_position(event.position)
		var source: Vector3 = page.ball_preview.source_ball.global_position
		var plane_height := source.y
		var live_ball: Vector3 = page.ball_preview.global_position
		var picked_source := not camera.is_position_behind(source) and camera.unproject_position(source).distance_to(point)<22
		var picked_live: bool = page.ball_preview.ball.visible and not camera.is_position_behind(live_ball) and camera.unproject_position(live_ball).distance_to(point)<16
		if picked_source or picked_live:
			if picked_live and not picked_source: plane_height = live_ball.y
			mode = "ball"
		else:
			var foot: Vector3 = page.preview_player.global_position
			var head: Vector3 = foot+Vector3.UP*page.preview_player.scale.y*1.8
			if camera.is_position_behind(foot): return false
			var bottom := camera.unproject_position(foot)
			var top := camera.unproject_position(head)
			var closest := Geometry2D.get_closest_point_to_segment(point,top,bottom)
			if point.distance_to(closest)>maxf(16,bottom.distance_to(top)*0.24): return false
			mode = "player"
			source = foot
			plane_height = foot.y
		drag_plane = Plane(Vector3.UP,plane_height)
		var hit: Variant = drag_plane.intersects_ray(camera.project_ray_origin(point),camera.project_ray_normal(point))
		grab_offset = source-hit if hit is Vector3 else Vector3.ZERO
		page.preview.grab_focus()
		return true
	if event is InputEventMouseMotion and not mode.is_empty():
		var camera: Camera3D = page.preview_camera
		var point := screen_position(event.position)
		var hit: Variant = drag_plane.intersects_ray(camera.project_ray_origin(point),camera.project_ray_normal(point))
		if hit is Vector3:
			var target: Vector3 = hit+grab_offset
			if mode == "player": StorySession.pass_start = Vector2(clampf(target.x,-4,4),clampf(target.z,-4.5,2.5))
			else: StorySession.feed_spot = Vector2(clampf(target.x,-4.2,4.2),clampf(target.z,5.5,13))
			page.angle_control.pending = true
		return true
	return false
