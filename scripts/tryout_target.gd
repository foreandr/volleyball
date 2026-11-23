extends Node3D

var is_net := false
var mouth_radius := 0.46
var depth := 0.64
var mesh := ImmediateMesh.new()
var cord := StandardMaterial3D.new()
var sag := 0.0
var velocity := 0.0

func rod(a: Vector3,b: Vector3,r: float,color: Color) -> void:
	var item := MeshInstance3D.new()
	var tube := CylinderMesh.new()
	tube.top_radius = r
	tube.bottom_radius = r
	tube.height = a.distance_to(b)
	tube.radial_segments = 8
	item.mesh = tube
	var surface := StandardMaterial3D.new()
	surface.albedo_color = color
	item.material_override = surface
	item.position = (a+b)/2
	item.quaternion = Quaternion(Vector3.UP,(b-a).normalized())
	add_child(item)

func _ready() -> void:
	var hoop := TorusMesh.new()
	hoop.inner_radius = mouth_radius-0.02
	hoop.outer_radius = mouth_radius+0.025
	var rim := MeshInstance3D.new()
	rim.mesh = hoop
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color("ed7543")
	rim.material_override = paint
	add_child(rim)
	if is_net:
		for side in [-1,1]:
			var foot := Vector3(side*mouth_radius,-position.y+0.1,0)
			rod(foot,Vector3(side*mouth_radius,0,0),0.025,Color.SILVER)
			rod(foot+Vector3.FORWARD*0.46,foot+Vector3.BACK*0.46,0.035,Color.DIM_GRAY)
	var basket := MeshInstance3D.new()
	basket.mesh = mesh
	cord.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cord.albedo_color = Color("eee5ca") if is_net else Color("ae633e")
	cord.cull_mode = BaseMaterial3D.CULL_DISABLED
	add_child(basket)
	rebuild()

func knot(i: int,j: int) -> Vector3:
	var t := j/6.0
	var angle := TAU*(i+0.5*(j%2))/20
	var radius := mouth_radius*lerpf(1,0.48 if is_net else 0.80,t)
	return Vector3(cos(angle)*radius,-depth*t-sag*t,sin(angle)*radius)

func rebuild() -> void:
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES if is_net else Mesh.PRIMITIVE_TRIANGLES,cord)
	for i in 20:
		for j in 6:
			var a := knot(i,j)
			var b := knot(i+1,j)
			var c := knot(i,j+1)
			var d := knot(i+1,j+1)
			if is_net:
				for point in [a,c,b,c]: mesh.surface_add_vertex(point)
			else:
				for point in [a,b,c,b,d,c]: mesh.surface_add_vertex(point)
	mesh.surface_end()

func impact() -> void:
	if is_net: velocity = 2.1

func _process(delta: float) -> void:
	if absf(sag)+absf(velocity)<0.001: return
	var dt := minf(delta,0.05)
	velocity += (-72*sag-8*velocity)*dt
	sag += velocity*dt
	rebuild()
