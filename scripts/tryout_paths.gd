extends RefCounted

const STEP := .35
var graph := AStarGrid2D.new()
var paths := {}
var initialized := false

func build(world: Node3D) -> void:
	graph.region = Rect2i(-29,-26,59,67)
	graph.cell_size = Vector2.ONE*STEP
	graph.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	graph.update()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .34
	capsule.height = 1.76
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 16|32
	var state := world.get_world_3d().direct_space_state
	for x in range(graph.region.position.x,graph.region.end.x):
		for z in range(graph.region.position.y,graph.region.end.y):
			query.transform.origin = Vector3(x*STEP,.96,z*STEP)
			if not state.intersect_shape(query,1).is_empty(): graph.set_point_solid(Vector2i(x,z))
	initialized = true

func cell(p: Vector3) -> Vector2i:
	var origin := Vector2i(roundi(p.x/STEP),roundi(p.z/STEP)).clamp(graph.region.position,graph.region.end-Vector2i.ONE)
	var best := origin
	var distance := INF
	for dx in range(-4,5):
		for dz in range(-4,5):
			var id := origin+Vector2i(dx,dz)
			if graph.region.has_point(id) and not graph.is_point_solid(id):
				var d := Vector2(id.x*STEP-p.x,id.y*STEP-p.z).length_squared()
				if d<distance:
					best=id
					distance=d
	return best

func waypoint(actor: Node3D,goal: Vector3,delta: float) -> Vector3:
	var state: Dictionary = paths.get(actor,{})
	if state.is_empty(): return goal
	state.age += delta
	if state.age>=4.0 or goal.distance_to(state.goal)>.65:
		paths.erase(actor)
		return goal
	var points: PackedVector2Array = state.points
	var here := Vector2(actor.position.x,actor.position.z)
	while state.index<points.size() and here.distance_to(points[state.index])<.15: state.index+=1
	if state.index>=points.size(): return goal
	var p := points[state.index]
	return Vector3(p.x,goal.y,p.y)

func reroute(actor: Node3D,goal: Vector3) -> void:
	if paths.has(actor): return
	if not initialized: build(actor)
	var points := graph.get_point_path(cell(actor.position),cell(goal),true)
	if points.size()>1:
		paths[actor]={"points":points,"index":1,"goal":goal,"age":0.0}

# Plan around the current occupants without changing the static gym grid.
func detour(actor: Node3D,goal: Vector3,occupied: Array) -> void:
	if not initialized: build(actor)
	var start := cell(actor.position)
	var temporary: Array[Vector2i]=[]
	for at: Vector3 in occupied:
		var center := Vector2i(roundi(at.x/STEP),roundi(at.z/STEP))
		for x in range(-2,3):
			for z in range(-2,3):
				var id := center+Vector2i(x,z)
				if id==start or not graph.region.has_point(id) or graph.is_point_solid(id): continue
				if Vector2(id.x*STEP-at.x,id.y*STEP-at.z).length()>.68: continue
				graph.set_point_solid(id)
				temporary.append(id)
	var points := graph.get_point_path(start,cell(goal),true)
	for id in temporary: graph.set_point_solid(id,false)
	paths.erase(actor)
	if points.size()>1:
		paths[actor]={"points":points,"index":1,"goal":goal,"age":0.}
