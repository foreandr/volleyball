extends MeshInstance3D

const Accuracy = preload("res://scripts/reception_accuracy.gd")
const SEGMENTS := 32
var shape := ImmediateMesh.new()
var tint := StandardMaterial3D.new()
var previous_origin := Vector3.INF
var previous_target := Vector3.INF
var previous_spread := -1.0
var previous_peak := Vector3.INF
var previous_height_spread := -1.0
var previous_depth := Vector3.INF

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

func show_set_spread(origin: Vector3, target: Vector3, peak: Vector3, bounds: Vector2, depth_axis: Vector3) -> void:
	var tight := bounds.x*Accuracy.SET_TIGHT_FRACTION
	var center := target+depth_axis*(tight-bounds.x)*0.5
	var depth := depth_axis*(tight+bounds.x)*0.5
	show_spread(origin,center,bounds.x*Accuracy.SET_WIDTH_FRACTION,peak,bounds.y,depth)

func show_spread(origin: Vector3, target: Vector3, spread: float, peak := Vector3.ZERO, height_spread := 0.0, depth := Vector3.ZERO) -> void:
	show()
	if origin.is_equal_approx(previous_origin) and target.is_equal_approx(previous_target) and is_equal_approx(spread,previous_spread) and peak.is_equal_approx(previous_peak) and is_equal_approx(height_spread,previous_height_spread) and depth.is_equal_approx(previous_depth):
		return
	previous_origin = origin
	previous_target = target
	previous_spread = spread
	previous_peak = peak
	previous_height_spread = height_spread
	previous_depth = depth
	var radius := maxf(0.04,spread)
	var long_axis := Vector3.BACK*radius if depth.is_zero_approx() else depth
	var across := Vector3.UP.cross(long_axis.normalized())*radius
	var color := Color("65ff94") if spread <= 0.0 else Color("b447df")
	shape.clear_surfaces()
	shape.surface_begin(Mesh.PRIMITIVE_TRIANGLES,tint)
	for segment in range(SEGMENTS):
		shape.surface_set_color(Color(color,0.13))
		shape.surface_add_vertex(origin)
		shape.surface_set_color(Color(color,0.25))
		shape.surface_add_vertex(rim(target,across,long_axis,segment))
		shape.surface_add_vertex(rim(target,across,long_axis,segment+1))
	shape.surface_end()
	shape.surface_begin(Mesh.PRIMITIVE_LINE_STRIP,tint)
	shape.surface_set_color(Color(color,0.85))
	for segment in range(SEGMENTS+1):
		shape.surface_add_vertex(rim(target,across,long_axis,segment))
	shape.surface_end()
	if height_spread > 0.001:
		shape.surface_begin(Mesh.PRIMITIVE_LINES,tint)
		shape.surface_set_color(Color(color,0.85))
		shape.surface_add_vertex(peak-Vector3.UP*height_spread)
		shape.surface_add_vertex(peak+Vector3.UP*height_spread)
		for sign_ in [-1.0,1.0]:
			var cap: Vector3 = peak+Vector3.UP*height_spread*sign_
			shape.surface_add_vertex(cap-Vector3.RIGHT*0.12)
			shape.surface_add_vertex(cap+Vector3.RIGHT*0.12)
		shape.surface_end()

func rim(center: Vector3, across: Vector3, depth: Vector3, segment: int) -> Vector3:
	var angle := TAU*segment/SEGMENTS
	return center+across*cos(angle)+depth*sin(angle)
