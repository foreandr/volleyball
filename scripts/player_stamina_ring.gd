extends MeshInstance3D

const SEGMENTS := 48
const INNER := 0.47
const OUTER := 0.54
var surface := ImmediateMesh.new()
var style := StandardMaterial3D.new()
var shown_fraction := -1.0

func _ready() -> void:
	name = "StaminaRing"
	position.y = 0.031
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	style.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	style.cull_mode = BaseMaterial3D.CULL_DISABLED
	style.vertex_color_use_as_albedo = true
	mesh = surface
	set_fraction(1.0)

func set_fraction(fraction: float) -> void:
	if is_equal_approx(shown_fraction,fraction): return
	shown_fraction = fraction
	surface.clear_surfaces()
	surface.surface_begin(Mesh.PRIMITIVE_TRIANGLES,style)
	draw_arc(0.0,fraction,Color("ffb72d"))
	draw_arc(fraction,1.0,Color("343d49"))
	surface.surface_end()

func draw_arc(from: float, to: float, color: Color) -> void:
	surface.surface_set_color(color)
	if to <= from: return
	for index in range(floori(from*SEGMENTS),ceili(to*SEGMENTS)):
		var a := TAU*maxf(from,float(index)/SEGMENTS)
		var b := TAU*minf(to,float(index+1)/SEGMENTS)
		var start := Vector3(sin(a),0,cos(a))
		var end := Vector3(sin(b),0,cos(b))
		for point in [start*INNER,start*OUTER,end*OUTER,start*INNER,end*OUTER,end*INNER]:
			surface.surface_add_vertex(point)
