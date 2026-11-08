extends Node3D

func material(color: String, roughness := 0.85) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = Color(color)
	result.roughness = roughness
	return result

func box(label_: String, size_: Vector3, center: Vector3, style: Material) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	item.name = label_
	var mesh := BoxMesh.new()
	mesh.size = size_
	item.mesh = mesh
	item.position = center
	item.material_override = style
	add_child(item)
	return item

func pole(label_: String, x: float, style: Material) -> void:
	var item := MeshInstance3D.new()
	item.name = label_
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.055
	mesh.bottom_radius = 0.055
	mesh.height = 2.65
	item.mesh = mesh
	item.position = Vector3(x,1.365,4)
	item.material_override = style
	add_child(item)
	box(label_+"Padding",Vector3(0.23,1.7,0.23),Vector3(x,0.89,4),material("245f84"))

func _ready() -> void:
	name = "VolleyballCourt"
	var white := material("f4eee1")
	var boundary := material("f7f3e5")
	box("Runoff",Vector3(19,0.12,28),Vector3(0,-0.08,4),material("275469"))
	# Nine by eighteen metres; passer is five metres inside the near baseline.
	for index in range(30):
		var color := "c69158" if index%3 == 0 else ("d1a269" if index%3 == 1 else "cca067")
		box("Floorboard%d" % index,Vector3(0.3,0.06,18),Vector3(-4.35+index*0.3,0.01,4),material(color))
	for x in [-4.5,4.5]: box("Sideline",Vector3(0.05,0.008,18.05),Vector3(x,0.045,4),boundary)
	for z in [-5.0,13.0,1.0,7.0]: box("CourtLine",Vector3(9,0.008,0.05),Vector3(0,0.045,z),boundary)
	box("CenterLine",Vector3(9,0.008,0.05),Vector3(0,0.045,4),boundary)
	pole("LeftPost",-5.05,white)
	pole("RightPost",5.05,white)
	var net := ImmediateMesh.new()
	net.surface_begin(Mesh.PRIMITIVE_LINES)
	for column in range(97):
		var x := -4.8+column*0.1
		net.surface_add_vertex(Vector3(x,1.47,4))
		net.surface_add_vertex(Vector3(x,2.47,4))
	for row in range(11):
		var y := 1.47+row*0.1
		net.surface_add_vertex(Vector3(-4.8,y,4))
		net.surface_add_vertex(Vector3(4.8,y,4))
	net.surface_end()
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "NetMesh"
	mesh_instance.mesh = net
	mesh_instance.material_override = material("25363a")
	add_child(mesh_instance)
	box("TopTape",Vector3(9.6,0.07,0.025),Vector3(0,2.47,4),white)
	box("BottomTape",Vector3(9.6,0.04,0.025),Vector3(0,1.47,4),white)
	for x in [-4.8,4.8]: box("SideTape",Vector3(0.05,1.0,0.025),Vector3(x,1.97,4),white)
	for x in [-4.5,4.5]:
		for stripe in range(8): box("Antenna",Vector3(0.018,0.1,0.018),Vector3(x,2.52+stripe*0.1,4),white if stripe%2 == 0 else material("cf493d"))
	var wall := material("243a4b")
	box("FarWall",Vector3(19,3.5,0.2),Vector3(0,1.65,18),wall)
	box("LeftWall",Vector3(0.2,3.5,28),Vector3(-9.5,1.65,4),wall)
	box("RightWall",Vector3(0.2,3.5,28),Vector3(9.5,1.65,4),wall)
	box("FarWallStripe",Vector3(19,0.18,0.03),Vector3(0,1.1,17.88),material("4f7c8b"))
