extends MeshInstance3D

func _ready() -> void:
	name = "DirectionArrows"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var surface := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color("67e8ff")
	surface.surface_begin(Mesh.PRIMITIVE_TRIANGLES,material)
	for direction in range(8):
		var forward := Vector3(sin(direction*TAU/8),0,cos(direction*TAU/8))
		var side := Vector3(forward.z,0,-forward.x)
		var tail := forward*0.86+Vector3.UP*0.025
		var neck := forward*1.18+Vector3.UP*0.025
		var tip := forward*1.52+Vector3.UP*0.025
		for point in [tail-side*0.055,tail+side*0.055,neck+side*0.055,tail-side*0.055,neck+side*0.055,neck-side*0.055,neck-side*0.18,neck+side*0.18,tip]:
			surface.surface_add_vertex(point)
	surface.surface_end()
	mesh = surface
