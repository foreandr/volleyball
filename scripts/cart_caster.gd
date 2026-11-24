extends Node3D

const RADIUS := .085
var wheel := Node3D.new()
var last_center := Vector3.ZERO

func _ready() -> void:
	var fork := StandardMaterial3D.new()
	fork.albedo_color=Color("acb3b1")
	fork.metallic=.78
	fork.roughness=.32
	var rubber := StandardMaterial3D.new()
	rubber.albedo_color=Color("30353a")
	rubber.roughness=.84
	var cap := StandardMaterial3D.new()
	cap.albedo_color=Color("68716e")
	var stem := MeshInstance3D.new()
	var pin := CylinderMesh.new()
	pin.top_radius=.018
	pin.bottom_radius=.018
	pin.height=.10
	stem.mesh=pin
	stem.material_override=fork
	stem.position.y=.115
	add_child(stem)
	for side in [-1.,1.]:
		var plate := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size=Vector3(.012,.105,.032)
		plate.mesh=box
		plate.position=Vector3(side*.037,.046,-.008)
		plate.rotation.x=-.15
		plate.material_override=fork
		add_child(plate)
	add_child(wheel)
	disc(wheel,RADIUS,.060,rubber)
	disc(wheel,.052,.062,cap)
	disc(wheel,.017,.091,fork)
	var mark := MeshInstance3D.new()
	var bar := BoxMesh.new()
	bar.size=Vector3(.064,.009,.026)
	mark.mesh=bar
	mark.position.z=.031
	mark.material_override=fork
	wheel.add_child(mark)
	last_center=global_position

func disc(parent: Node3D,radius: float,width: float,material: Material) -> void:
	var item := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius=radius
	cylinder.bottom_radius=radius
	cylinder.height=width
	cylinder.radial_segments=36
	item.mesh=cylinder
	item.rotation.z=PI*.5
	item.material_override=material
	parent.add_child(item)

func _process(dt: float) -> void:
	var floor_y := .04 if absf(global_position.x)<4.5 and absf(global_position.z-4.)<9. else -.02
	global_position.y=floor_y+RADIUS
	var center := global_position
	var travel := (center-last_center).slide(Vector3.UP)
	last_center=center
	if travel.length_squared()<.00000001: return
	var forward := travel.normalized()
	var heading := atan2(forward.x,forward.z)
	var angles := global_rotation
	angles.y=rotate_toward(angles.y,heading,dt*12.)
	global_rotation=angles
	wheel.rotate_x(travel.dot(global_basis.z)/RADIUS)
