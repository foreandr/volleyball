extends MeshInstance3D

const LANDING_RADIUS := 0.90
const SIDE_LANDING_RADIUS := 0.55
const LONG_LANDING_RADIUS := 1.55
const LONG_SIDE_RADIUS := 1.10
const DIVE_RADIUS := 2.22
const DIVE_SIDE_RADIUS := 1.72
var selected := 0
var selected_distance := 1
var show_dive_ring := false:
	set(value):
		if value == show_dive_ring: return
		show_dive_ring = value
		rebuild()

func _ready() -> void:
	name = "DirectionArrows"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rebuild()

func select_direction(index: int, distance := 1) -> void:
	if selected == index and selected_distance == distance: return
	selected = index
	selected_distance = distance
	rebuild()

func pick(local_point: Vector3) -> Vector2i:
	var point := Vector2(local_point.x,local_point.z)
	if point.length() <= 0.27: return Vector2i(0,selected_distance)
	var closest := Vector2i(-1,1)
	var best := 0.25
	for distance in range(1,4 if show_dive_ring else 3):
		for index in range(1,9):
			var center := arrow_center(index,distance)
			var candidate := point.distance_to(Vector2(center.x,center.z))
			if candidate <= best:
				closest = Vector2i(index,distance)
				best = candidate
	return closest

func landing_target() -> Vector3:
	return to_global(arrow_center(selected,selected_distance))

func arrow_center(index: int, distance := 1) -> Vector3:
	var side := index in [3,7]
	var radius := SIDE_LANDING_RADIUS if side else LANDING_RADIUS
	if distance == 2: radius = LONG_SIDE_RADIUS if side else LONG_LANDING_RADIUS
	if distance == 3: radius = DIVE_SIDE_RADIUS if side else DIVE_RADIUS
	return direction(index)*radius

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
	for distance in range(1,4 if show_dive_ring else 3):
		for index in range(1,9):
			var color: Color = [Color("67e8ff"),Color("c291ff"),Color("2859d4")][distance-1]
			if index == selected and distance == selected_distance: color = Color("ff4848")
			surface.surface_set_color(color)
			var forward := direction(index)
			var side := Vector3(forward.z,0,-forward.x)
			var neck := arrow_center(index,distance)+Vector3.UP*0.025
			var tail := neck-forward*0.19
			var tip := neck+forward*0.22
			for point in [tail-side*0.045,tail+side*0.045,neck+side*0.045,tail-side*0.045,neck+side*0.045,neck-side*0.045,neck-side*0.12,neck+side*0.12,tip]:
				surface.surface_add_vertex(point)
	surface.surface_end()
	surface.surface_begin(Mesh.PRIMITIVE_LINE_STRIP,material)
	surface.surface_set_color(Color("ff4848") if selected == 0 else Color("67e8ff"))
	for i in range(33):
		var angle := i*TAU/32.0
		surface.surface_add_vertex(Vector3(sin(angle)*0.30,0.025,cos(angle)*0.30))
	surface.surface_end()
	mesh = surface
