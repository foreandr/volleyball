extends MeshInstance3D

const LANDING_RADIUS := 0.90
const SIDE_LANDING_RADIUS := 0.55
const LONG_LANDING_RADIUS := 1.55
const LONG_SIDE_RADIUS := 1.10
const DIVE_RADIUS := 2.22
const DIVE_SIDE_RADIUS := 1.72
const PANCAKE_RADIUS := 2.88
var selected := 0
var selected_distance := 1
var show_dive_ring := false:
	set(value):
		if value == show_dive_ring: return
		show_dive_ring = value

func _ready() -> void:
	name = "DirectionArrows"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func supports(index: int, distance: int) -> bool:
	if distance == 5: return index in [2,3,4,6,7,8]
	if distance == 4: return index == 1
	if distance == 3: return index in [0,1,2,3,7,8]
	return distance in [1,2] and index >= 0 and index <= 8

func select_direction(index: int, distance := 1) -> void:
	if not supports(index,distance): return
	if selected == index and selected_distance == distance: return
	selected = index
	selected_distance = distance

func pick(local_point: Vector3) -> Vector2i:
	var point := Vector2(local_point.x,local_point.z)
	if point.length() <= 0.27: return Vector2i(0,1 if selected_distance >= 4 else selected_distance)
	var closest := Vector2i(-1,1)
	var best := 0.25
	for distance in range(1,6 if show_dive_ring else 3):
		for index in range(1,9):
			if not supports(index,distance): continue
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
	if distance == 4: radius = PANCAKE_RADIUS
	if distance == 5: radius = 3.20
	return direction(index)*radius

func direction(index: int) -> Vector3:
	var angle := (index-1)*TAU/8.0
	return Vector3(-sin(angle),0,cos(angle))
