extends Node3D

const RUNOFF_HALF_WIDTH := 6.5
const RUNOFF_NEAR_BASELINE := -7.0
const RUNOFF_FAR_BASELINE := 15.0

static func clamp_setter(point: Vector3, front_limit := 2.5) -> Vector3:
	return Vector3(clampf(point.x,-RUNOFF_HALF_WIDTH,RUNOFF_HALF_WIDTH),point.y,clampf(point.z,RUNOFF_NEAR_BASELINE,front_limit))

static func clamp_set_aim(point: Vector3) -> Vector2:
	return Vector2(clampf(point.x,-RUNOFF_HALF_WIDTH,RUNOFF_HALF_WIDTH),clampf(point.z,RUNOFF_NEAR_BASELINE,RUNOFF_FAR_BASELINE))

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
	box("Runoff",Vector3(24,0.12,68),Vector3(0,-0.08,16),material("275469"))
	# Nine by eighteen metres; passer is five metres inside the near baseline.
	for index in range(30):
		var color := "c69158" if index%3 == 0 else ("d1a269" if index%3 == 1 else "cca067")
		box("Floorboard%d" % index,Vector3(0.3,0.06,18),Vector3(-4.35+index*0.3,0.01,4),material(color))
	for x in [-4.5,4.5]: box("Sideline",Vector3(0.05,0.008,18.05),Vector3(x,0.045,4),boundary)
	for z in [-5.0,13.0,1.0,7.0]: box("CourtLine",Vector3(9,0.008,0.05),Vector3(0,0.045,z),boundary)
	box("CenterLine",Vector3(9,0.008,0.05),Vector3(0,0.045,4),boundary)
	pole("LeftPost",-5.05,white)
	pole("RightPost",5.05,white)
	add_child(preload("res://scripts/dynamic_net.gd").new())
	for x in [-4.8,4.8]: box("SideTape",Vector3(0.05,1.0,0.025),Vector3(x,1.97,4),white)
	for x in [-4.5,4.5]:
		for stripe in range(8): box("Antenna",Vector3(0.018,0.1,0.018),Vector3(x,2.52+stripe*0.1,4),white if stripe%2 == 0 else material("cf493d"))
	var wall := material("243a4b")
	box("FarWall",Vector3(24,3.5,0.2),Vector3(0,1.65,49),wall)
	box("LeftWall",Vector3(0.2,3.5,68),Vector3(-12,1.65,16),wall)
	box("RightWall",Vector3(0.2,3.5,68),Vector3(12,1.65,16),wall)
	box("FarWallStripe",Vector3(24,0.18,0.03),Vector3(0,1.1,48.88),material("4f7c8b"))

static func add_preview_lighting(world: Node) -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("1b2a38")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("dce9f2")
	settings.ambient_light_energy = 0.4
	environment.environment = settings
	world.add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35,-35,0)
	key.light_energy = 0.65
	key.shadow_enabled = true
	world.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20,145,0)
	fill.light_color = Color("91bfe6")
	fill.light_energy = 0.3
	world.add_child(fill)
