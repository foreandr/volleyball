extends MeshInstance3D

const LANDING_RADIUS := 0.90
const SIDE_LANDING_RADIUS := 0.65
var selected := 0

func _ready() -> void:
	name = "DirectionArrows"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rebuild()

func select_direction(index: int) -> void:
	if selected == index: return
	selected = index
	rebuild()

func pick(local_point: Vector3) -> int:
	var point := Vector2(local_point.x,local_point.z)
	if point.length() <= 0.32: return 0
	var closest := -1
	var distance := 0.34
	for index in range(1,9):
		var center := arrow_center(index)
		var candidate := point.distance_to(Vector2(center.x,center.z))
		if candidate <= distance:
			closest = index
			distance = candidate
	return closest

func landing_target() -> Vector3:
	return to_global(arrow_center(selected))

func arrow_center(index: int) -> Vector3:
	return direction(index)*(SIDE_LANDING_RADIUS if index in [3,7] else LANDING_RADIUS)

func direction(index: int) -> Vector3:
	var angle := (index-1)*TAU/8.0
	return Vector3(-sin(angle),0,cos(angle))

func rebuild() -> void:
	var surface := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	surface.surface_begin(Mesh.PRIMITIVE_TRIANGLES,material)
	for index in range(1,9):
		surface.surface_set_color(Color("ff4848") if index == selected else Color("67e8ff"))
		var forward := direction(index)
		var side := Vector3(forward.z,0,-forward.x)
		var neck := arrow_center(index)+Vector3.UP*0.025
		var tail := neck-forward*0.32
		var tip := neck+forward*0.34
		for point in [tail-side*0.055,tail+side*0.055,neck+side*0.055,tail-side*0.055,neck+side*0.055,neck-side*0.055,neck-side*0.18,neck+side*0.18,tip]:
			surface.surface_add_vertex(point)
	surface.surface_end()
	surface.surface_begin(Mesh.PRIMITIVE_LINE_STRIP,material)
	surface.surface_set_color(Color("ff4848") if selected == 0 else Color("67e8ff"))
	for i in range(33):
		var angle := i*TAU/32.0
		surface.surface_add_vertex(Vector3(sin(angle)*0.30,0.025,cos(angle)*0.30))
	surface.surface_end()
	mesh = surface
