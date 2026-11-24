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

static func apply(actor: Node3D,coach: bool,variant := 0) -> void:
	var rig: Skeleton3D = actor.skeleton
	if coach:
		actor.set_height_cm(174)
		actor.scale*=Vector3(1.23,1,1.32)
	elif variant>0:
		actor.set_height_cm(166+(variant*13)%36)
		actor.scale*=Vector3(.88+.036*(variant%7),1,.90+.045*((variant*3)%6))
	if variant>0:
		var build := float((variant*5)%9)/8.
		for side in ["l","r"]:
			var thigh := rig.find_bone("thigh_"+side)
			rig.set_bone_pose_scale(thigh,Vector3(.94+.12*build,.96+.08*build,.94+.12*build))
			var arm := rig.find_bone("upperarm_"+side)
			rig.set_bone_pose_scale(arm,Vector3(.9+.23*build,1,.9+.23*build))
		var spine := rig.find_bone("spine_01")
		rig.set_bone_pose_scale(spine,Vector3(1,1.045-.09*build,1))
	var print_texture: Texture2D=preload("res://assets/gym/practice_502.svg") if variant==0 else number_texture(502+variant)
	for side in ["l","r"]: court_shoe(rig,side,coach,variant)
	for node: MeshInstance3D in rig.find_children("*","MeshInstance3D",true,false):
		var shirt := node.mesh == preload("res://assets/characters/volleyball/outfit.res")
		var sleeves := node.mesh == preload("res://assets/characters/volleyball/body.res")
		if not shirt and not sleeves: continue
		var kit := ShaderMaterial.new()
		kit.shader = FABRIC
		kit.set_shader_parameter("fabric",Color("223d3c") if coach else Color("b34421"))
		kit.set_shader_parameter("trim",Color("cad4bf") if coach else Color("182d36"))
		kit.set_shader_parameter("lettering",print_texture)
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
			if not coach: shorts(rig,node,variant)
	if not coach:
		var head := rig.find_bone("Head")
		var mount := BoneAttachment3D.new()
		mount.bone_name=rig.get_bone_name(head)
		rig.add_child(mount)
		var scalp := Node3D.new()
		mount.add_child(scalp)
		var rest := rig.get_bone_global_rest(head)
		scalp.transform=rest.affine_inverse()*Transform3D(Basis.IDENTITY,rest.origin)
		var hair := Color.from_hsv(.065+.004*variant,.42,.13+.065*(variant%6))
		shoe_part(scalp,Vector3(0,.17,-.014),Vector3(.20,.085+.013*(variant%4),.217),hair)
		if variant%3==1: shoe_part(scalp,Vector3(0,.15,-.112),Vector3(.092,.095,.09),hair)
		for side in ["l","r"]:
			if variant==0 or variant%4==1 or (variant%4==2 and side=="l") or (variant%4==3 and side=="r"): knee_pad(rig,side)
			if variant%3==1: compression(rig,"calf_"+side,"foot_"+side,.067,.044,Color("e3ded2"))
		if variant%4==1: compression(rig,"hand_l","middle_01_l",.042,.041,Color("d6cdc0"))
		if variant%3==2: compression(rig,"lowerarm_r","hand_r",.061,.042,Color("252e35"))

static func shorts(rig: Skeleton3D,outfit: MeshInstance3D,variant: int) -> void:
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """shader_type spatial;
	uniform vec4 cloth:source_color; varying vec2 rest;
	void vertex(){rest=UV2;VERTEX+=NORMAL*.004;}
	void fragment(){
		if(rest.y<.70) discard;
		float hem=1.-smoothstep(.704,.714,rest.y);
		ALBEDO=mix(cloth.rgb,vec3(.80,.43,.21),hem);
		ROUGHNESS=.84;
	}"""
	material.shader = shader
	material.set_shader_parameter("cloth",Color.from_hsv(fmod(.55+.147*variant,1.),.32,.24+.045*(variant%4)))
	var part := MeshInstance3D.new()
	part.mesh = tailored_surface(outfit.mesh,1)
	part.skin = outfit.skin
	rig.add_child(part)
	part.skeleton = part.get_path_to(rig)
	part.material_override = material
	outfit.set_surface_override_material(1,outfit.get_surface_override_material(0))
	# Restore the underlying skinned legs from the source character.
	var source := preload("res://assets/characters/base/Superhero_Male_FullBody.gltf").instantiate()
	var body: MeshInstance3D = source.find_child("SuperHero_Male",true,false)
	var legs := MeshInstance3D.new()
	legs.mesh = tailored_surface(body.mesh,0)
	legs.skin = outfit.skin
	rig.add_child(legs)
	legs.skeleton = legs.get_path_to(rig)
	var skin := ShaderMaterial.new()
	var cut := Shader.new()
	cut.code = """shader_type spatial;
	uniform sampler2D skin_map:source_color; varying float y;
	void vertex(){y=UV2.y;} void fragment(){if(y>.72 || y<.095)discard; ALBEDO=texture(skin_map,UV).rgb; ROUGHNESS=.75;}"""
	skin.shader = cut
	skin.set_shader_parameter("skin_map",preload("res://assets/characters/base/T_Superhero_Male_Light.png"))
	legs.material_override = skin
	source.free()

static func number_texture(number: int) -> Texture2D:
	var rows := ["75557","26227","71747","71717","55711","74717","74757","71111","75757","75717"]
	var img := Image.create(96,48,false,Image.FORMAT_RGBA8)
	var digits := str(number)
	for n in digits.length():
		var glyph: String=rows[int(digits[n])]
		for y in 5:
			for x in 3:
				if int(glyph[y]) & (4>>x): img.fill_rect(Rect2(4+n*31+x*8,4+y*8,8,8),Color.WHITE)
	return ImageTexture.create_from_image(img)

static func compression(rig: Skeleton3D,bone: String,child: String,upper: float,lower: float,color: Color) -> void:
	var socket := BoneAttachment3D.new()
	socket.bone_name = bone
	rig.add_child(socket)
	var axis := rig.get_bone_rest(rig.find_bone(child)).origin
	var part := MeshInstance3D.new()
	var sleeve := CylinderMesh.new()
	sleeve.bottom_radius = upper
	sleeve.top_radius = lower
	sleeve.height = axis.length()*.79
	part.mesh = sleeve
	part.position = axis*.56
	part.quaternion = Quaternion(Vector3.UP,axis.normalized())
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	part.material_override = mat
	socket.add_child(part)

static func knee_pad(rig: Skeleton3D,side: String) -> void:
	var name_ := "calf_"+side
	var rest := rig.get_bone_global_rest(rig.find_bone(name_))
	var socket := BoneAttachment3D.new()
	socket.bone_name = name_
	rig.add_child(socket)
	var pad := Node3D.new()
	socket.add_child(pad)
	pad.transform = rest.affine_inverse()*Transform3D(Basis.IDENTITY,rest.origin)
	shoe_part(pad,Vector3(0,-.018,0),Vector3(.146,.186,.151),Color("1d252b"))
	shoe_part(pad,Vector3(0,-.008,.056),Vector3(.125,.12,.076),Color("36414a"))


# Build the shoe in rig rest space, then inherit the ankle's animated transform.
static func court_shoe(rig: Skeleton3D,side: String,coach: bool,variant: int) -> void:
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
	var upper: Color = Color("324341") if coach else [Color("e4e0cf"),Color("23528c"),Color("df7638"),Color("252e38"),Color("b6cc7d")][variant%5]
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
