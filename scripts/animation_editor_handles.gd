extends Control
var editor: Control
func _draw() -> void:
	if not is_instance_valid(editor) or editor.session == null: return
	for handle in editor.handle_points():
		var selected: bool = editor.is_selected_bone(handle.bone)
		var color := Color("ffce70") if selected else Color(0.4,0.8,1.0,0.55)
		draw_circle(handle.screen,6 if selected else 4,Color(0.02,0.05,0.08,0.8))
		draw_arc(handle.screen,9 if selected else 5,0,TAU,24,color,2,true)
		if selected:
			var pivot: Vector2 = editor.preview_camera.unproject_position(editor.bone_world(handle.bone))
			draw_line(pivot,handle.screen,color,2,true)
			draw_circle(pivot,3,color)
