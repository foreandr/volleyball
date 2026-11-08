extends Node3D
const Net = preload("res://scripts/net_collision.gd")
var mesh_node: MeshInstance3D
var tape_node: MeshInstance3D
var resting := false
var last_time := -INF
var last_hit := 0

func _ready() -> void:
	name = "DynamicNet"
	mesh_node = MeshInstance3D.new()
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("25363a")
	mesh_node.material_override = dark
	add_child(mesh_node)
	tape_node = MeshInstance3D.new()
	var white := StandardMaterial3D.new()
	white.albedo_color = Color("f4eee1")
	white.cull_mode = BaseMaterial3D.CULL_DISABLED
	tape_node.material_override = white
	add_child(tape_node)
	sample({},0)

func vertex(hit: Dictionary, time: float, x: float, y: float) -> Vector3:
	var point := Vector3(x,y,4)
	return point+Net.surface_offset(hit,time,point)

func sample(hit: Dictionary, time: float) -> void:
	var active: bool = not hit.is_empty() and hit.kind!="under" and time>=float(hit.time) and time<float(hit.release_time)+1.1
	if not active and resting: return
	var signature := hash(hit)
	if active and signature==last_hit and is_equal_approx(time,last_time): return
	last_hit = signature
	last_time = time
	resting = not active
	var current: Dictionary = hit if active else {}
	var points: Array[Vector3] = []
	for row in range(11):
		for column in range(97): points.append(vertex(current,time,-4.8+column*0.1,1.47+row*0.1))
	var body := ImmediateMesh.new()
	body.surface_begin(Mesh.PRIMITIVE_LINES)
	for row in range(11):
		for column in range(97):
			var index := row*97+column
			if column<96:
				body.surface_add_vertex(points[index])
				body.surface_add_vertex(points[index+1])
			if row<10:
				body.surface_add_vertex(points[index])
				body.surface_add_vertex(points[index+97])
	body.surface_end()
	mesh_node.mesh = body
	var tapes := ImmediateMesh.new()
	tapes.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for tape in [Vector2(2.47,0.035),Vector2(1.47,0.02)]:
		for column in range(96):
			var x := -4.8+column*0.1
			var corners: Array[Vector3] = [vertex(current,time,x,tape.x-tape.y),vertex(current,time,x+0.1,tape.x-tape.y),vertex(current,time,x+0.1,tape.x+tape.y),vertex(current,time,x,tape.x+tape.y)]
			for index in [0,1,2,0,2,3]:
				tapes.surface_set_normal(Vector3.FORWARD)
				tapes.surface_add_vertex(corners[index])
	tapes.surface_end()
	tape_node.mesh = tapes
