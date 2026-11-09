extends MeshInstance3D

const SEGMENTS := 32
const TARGET_RING := 0.20
var shape := ImmediateMesh.new()
var tint := StandardMaterial3D.new()
var previous_origin := Vector3.INF
var previous_target := Vector3.INF
var previous_spread := -1.0

func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tint.cull_mode = BaseMaterial3D.CULL_DISABLED
	tint.vertex_color_use_as_albedo = true
	mesh = shape
	hide()

func show_spread(origin: Vector3, target: Vector3, spread: float) -> void:
	show()
	if origin.is_equal_approx(previous_origin) and target.is_equal_approx(previous_target) and is_equal_approx(spread,previous_spread):
		return
	previous_origin = origin
	previous_target = target
	previous_spread = spread
	var radius := maxf(TARGET_RING,spread)
	var color := Color("65ff94") if spread <= 0.0 else Color("b447df")
	shape.clear_surfaces()
	shape.surface_begin(Mesh.PRIMITIVE_TRIANGLES,tint)
	for segment in range(SEGMENTS):
		shape.surface_set_color(Color(color,0.13))
		shape.surface_add_vertex(origin)
		shape.surface_set_color(Color(color,0.25))
		shape.surface_add_vertex(rim(target,radius,segment))
		shape.surface_add_vertex(rim(target,radius,segment+1))
	shape.surface_end()
	shape.surface_begin(Mesh.PRIMITIVE_LINE_STRIP,tint)
	shape.surface_set_color(Color(color,0.85))
	for segment in range(SEGMENTS+1):
		shape.surface_add_vertex(rim(target,radius,segment))
	shape.surface_end()

func rim(center: Vector3, radius: float, segment: int) -> Vector3:
	var angle := TAU*segment/SEGMENTS
	return center+Vector3(cos(angle)*radius,0.0,sin(angle)*radius)
