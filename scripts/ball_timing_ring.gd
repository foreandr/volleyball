extends Node3D

const OUTER_RADIUS := 2.0
const CENTER_RADIUS := 0.092
var timing_ring: MeshInstance3D
var timing_center: MeshInstance3D
var timing_style := StandardMaterial3D.new()

func _ready() -> void:
	timing_style.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var rim := TorusMesh.new()
	rim.inner_radius = 0.93
	rim.outer_radius = 1.0
	timing_ring = marker(rim,0.018)
	var dot := CylinderMesh.new()
	dot.top_radius = CENTER_RADIUS
	dot.bottom_radius = CENTER_RADIUS
	dot.height = 0.008
	timing_center = marker(dot,0.023)
	hide()

func marker(shape: Mesh, lift: float) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = shape
	part.position.y = lift
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	part.material_override = timing_style
	add_child(part)
	return part

func update_timing(elapsed: float, arrival: float, green_start: float, green_end: float, resolved := false) -> void:
	var lead := arrival-elapsed
	visible = elapsed >= 0.0 and lead >= -0.10 and not resolved
	if not visible: return
	var ideal := (green_start+green_end)*0.5
	var remaining := clampf((lead-ideal)/maxf(arrival-ideal,0.001),0.0,1.0)
	var radius := lerpf(CENTER_RADIUS,OUTER_RADIUS,remaining)
	timing_ring.scale = Vector3(radius,1.0,radius)
	var color := Color("ffdb51")
	if lead < green_start: color = Color("ff7855")
	elif lead <= green_end: color = Color("65ff94")
	timing_style.albedo_color = color
