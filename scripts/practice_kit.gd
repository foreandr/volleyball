extends RefCounted

const FABRIC := preload("res://assets/gym/practice_kit.gdshader")

# Skinning transforms VERTEX before the material runs. Store bind-pose garment
# coordinates separately so piping and screen printing follow the fabric.
static func tailored_surface(source: ArrayMesh,surface: int) -> ArrayMesh:
	var arrays := source.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var coords := PackedVector2Array()
	var depths := PackedColorArray()
	coords.resize(vertices.size())
	depths.resize(vertices.size())
	for i in vertices.size():
		var p := vertices[i]
		coords[i] = Vector2(p.x,p.y)
		depths[i] = Color(clampf((p.z+0.3)/0.6,0,1),0,0,1)
	arrays[Mesh.ARRAY_TEX_UV2] = coords
	arrays[Mesh.ARRAY_COLOR] = depths
	var shaped := ArrayMesh.new()
	shaped.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},source.surface_get_format(surface)&Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
	return shaped

static func apply(actor: Node3D,coach: bool) -> void:
	var rig: Skeleton3D = actor.skeleton
	for side in ["l","r"]: court_shoe(rig,side,coach)
	for node: MeshInstance3D in rig.find_children("*","MeshInstance3D",true,false):
		var shirt := node.mesh == preload("res://assets/characters/volleyball/outfit.res")
		var sleeves := coach and node.mesh == preload("res://assets/characters/volleyball/body.res")
		if not shirt and not sleeves: continue
		var kit := ShaderMaterial.new()
		kit.shader = FABRIC
		kit.set_shader_parameter("fabric",Color("223d3c") if coach else Color("b34421"))
		kit.set_shader_parameter("trim",Color("cad4bf") if coach else Color("182d36"))
		kit.set_shader_parameter("lettering",preload("res://assets/gym/varsity_mark.png"))
		kit.set_shader_parameter("jacket",coach)
		kit.set_shader_parameter("sleeves",sleeves)
		var shell := MeshInstance3D.new()
		shell.mesh = tailored_surface(node.mesh,0)
		shell.skin = node.skin
		rig.add_child(shell)
		shell.skeleton = shell.get_path_to(rig)
		shell.material_override = kit
		if shirt:
			# The skinned print replaces only the jersey. Keep shoes and trousers.
			var invisible := StandardMaterial3D.new()
			invisible.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			invisible.albedo_color = Color.TRANSPARENT
			node.set_surface_override_material(0,invisible)

# Build the shoe in rig rest space, then inherit the ankle's animated transform.
static func court_shoe(rig: Skeleton3D,side: String,coach: bool) -> void:
	var name_ := "foot_"+side
	var rest := rig.get_bone_global_rest(rig.find_bone(name_))
	var toe := rig.get_bone_global_rest(rig.find_bone("ball_"+side)).origin
	var mount := BoneAttachment3D.new()
	mount.bone_name = name_
	rig.add_child(mount)
	var last := Node3D.new()
	mount.add_child(last)
	var forward := (toe-rest.origin).slide(Vector3.UP).normalized()
	var center := rest.origin.lerp(toe,0.54)
	center.y = 0.0
	last.transform = rest.affine_inverse()*Transform3D(Basis.looking_at(forward,Vector3.UP,true),center)
	var upper := Color("324341") if coach else Color("e4e0cf")
	shoe_part(last,Vector3(0,.022,.015),Vector3(.135,.052,.31),Color("413e36"))
	shoe_part(last,Vector3(0,.043,.015),Vector3(.14,.062,.306),Color("e4d9bb"))
	shoe_part(last,Vector3(0,.075,.017),Vector3(.133,.095,.302),upper)
	shoe_part(last,Vector3(0,.102,-.056),Vector3(.124,.115,.15),upper)
	for i in 4:
		var lace := shoe_part(last,Vector3(0,.122-i*.005,-.017+i*.021),Vector3(.076,.009,.012),Color("b1afa3") if coach else Color("423e34"))
		lace.rotation.y = .14 if i%2==0 else -.14

static func shoe_part(parent: Node3D,at: Vector3,dimensions: Vector3,color: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 20
	mesh.rings = 10
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.scale = dimensions
	part.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .76
	part.material_override = material
	parent.add_child(part)
	return part
