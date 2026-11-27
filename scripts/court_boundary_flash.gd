extends Node3D

const NET_Z=preload("res://scripts/net_collision.gd").NET_Z
var boundary_ink:=StandardMaterial3D.new()
var timer:=Timer.new()
var verdict:=0

func _ready() -> void:
	boundary_ink.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in 4:
		var edge := MeshInstance3D.new()
		var strip := BoxMesh.new()
		var sign_side := -1. if i%2==0 else 1.
		strip.size=Vector3(.065,.004,9.) if i<2 else Vector3(9.,.004,.065)
		edge.mesh=strip
		edge.material_override=boundary_ink
		edge.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(edge)
		edge.position=Vector3(sign_side*4.475,.063,0.) if i<2 else Vector3(0,.063,sign_side*4.475)
	add_child(timer)
	timer.one_shot=true
	timer.timeout.connect(display.bind(0))
	hide()

func flash(point:Vector3,inside:bool) -> void:
	position.z=NET_Z+(4.5 if point.z>=NET_Z else -4.5)
	display(1 if inside else -1)
	timer.start(1.)

func display(value:int) -> void:
	verdict=value
	boundary_ink.albedo_color=Color("#30ee76") if value==1 else Color("#ff394b")
	visible=value!=0
