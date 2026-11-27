extends MeshInstance3D

const Flight = preload("res://scripts/pass_flight.gd")
var location: Callable

static func attach(ball: Node3D, prediction: Callable) -> MeshInstance3D:
	var marker := new()
	marker.location=prediction
	ball.add_child(marker)
	return marker

static func ballistic(origin: Vector3, velocity: Vector3, gravity := 9.81) -> Vector3:
	return origin+velocity*Flight.landing_time(origin,velocity,gravity)

static func parabola(start: Vector3,end: Vector3,duration: float,height: float) -> Vector3:
	if duration<=0. or height<=0.: return Vector3.INF
	var gravity := 8.*height/(duration*duration)
	return ballistic(start,(end-start)/duration+Vector3.UP*4.*height/duration,gravity)

func _ready() -> void:
	top_level=true
	process_priority=50
	var ring := TorusMesh.new()
	ring.inner_radius=.34
	ring.outer_radius=.43
	ring.rings=40
	ring.ring_segments=6
	mesh=ring
	scale.y=.12
	cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ink := StandardMaterial3D.new()
	ink.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.albedo_color=Color("ffd278")
	material_override=ink
	hide()

func _process(_delta: float) -> void:
	place(location.call())

func place(target: Vector3) -> void:
	visible=target.is_finite() and get_parent().is_visible_in_tree()
	if visible: global_position=Vector3(target.x,.078,target.z)
