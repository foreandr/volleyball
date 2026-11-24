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
		if sleeves: face_hair(rig,node,shell.mesh,coach,variant)
		if shirt:
			# The skinned print replaces only the jersey. Keep shoes and trousers.
			var invisible := StandardMaterial3D.new()
			invisible.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			invisible.albedo_color = Color.TRANSPARENT
			node.set_surface_override_material(0,invisible)
			node.set_surface_override_material(2,invisible)
			if not coach: shorts(rig,node,variant)
			else:
				for side in ["l","r"]: compression(rig,"calf_"+side,"foot_"+side,.068,.047,Color("253239"))
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
		haircut(scalp,hair,variant)
		for side in ["l","r"]:
			if variant==0 or variant%4==1 or (variant%4==2 and side=="l") or (variant%4==3 and side=="r"): knee_pad(rig,side)
			if variant%3==1: compression(rig,"calf_"+side,"foot_"+side,.067,.044,Color("e3ded2"))
		if variant%4==1: compression(rig,"hand_l","middle_01_l",.042,.041,Color("d6cdc0"))
		if variant%3==2: compression(rig,"lowerarm_r","hand_r",.061,.042,Color("252e35"))

static func shorts(rig: Skeleton3D,outfit: MeshInstance3D,variant: int) -> void:
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """shader_type spatial;
	uniform float hem_y; uniform vec4 cloth:source_color; varying vec2 rest;
	void vertex(){rest=UV2;VERTEX+=NORMAL*.004;}
	void fragment(){
		if(rest.y<hem_y) discard;
		float hem=1.-smoothstep(hem_y+.004,hem_y+.014,rest.y);
		ALBEDO=mix(cloth.rgb,vec3(.80,.43,.21),hem);
		ROUGHNESS=.84;
	}"""
	material.shader = shader
	var hem := .65+.019*(variant%7)
	material.set_shader_parameter("hem_y",hem)
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
	uniform float hem_y; uniform sampler2D skin_map:source_color; varying float y;
	void vertex(){y=UV2.y;} void fragment(){if(y>hem_y+.02 || y<.095)discard; ALBEDO=texture(skin_map,UV).rgb; ROUGHNESS=.75;}"""
	skin.shader = cut
	skin.set_shader_parameter("hem_y",hem)
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
	# Continuous elastic sleeve spans the kneecap, with a thicker anterior pad.
	for i in 3:
		var cuff := CylinderMesh.new()
		cuff.radial_segments=36
		cuff.height=[.026,.15,.026][i]
		cuff.top_radius=[.088,.086,.078][i]
		cuff.bottom_radius=[.086,.078,.077][i]
		var band := MeshInstance3D.new()
		band.mesh=cuff
		band.position.y=.075-i*.086
		band.scale.z=1.06
		var knit := StandardMaterial3D.new()
		knit.albedo_color=Color("313840") if i!=1 else Color("232b31")
		knit.roughness=.96
		band.material_override=knit
		pad.add_child(band)
	shoe_part(pad,Vector3(0,-.003,.070),Vector3(.145,.142,.050),Color("343e47"))
	for x in [-.045,.045]:
		shoe_part(pad,Vector3(x,.002,.086),Vector3(.008,.085,.008),Color("485058"))


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
	var upper: Color = Color("324341") if coach else [Color("ede9df"),Color("23528c"),Color("df7638"),Color("252e38"),Color("b6cc7d")][variant%5]
	# Loft heel, waist, forefoot and toe sections separately for each layer.
	var profile := [Vector2(-.14,.044),Vector2(-.115,.062),Vector2(-.064,.065),Vector2(.005,.052),Vector2(.08,.071),Vector2(.133,.065),Vector2(.168,.046),Vector2(.183,.015)]
	shoe_shell(last,profile,[.023,.022,.021,.02,.019,.02,.027,.036],.019,Color("373934"),side)
	shoe_shell(last,profile,[.052,.054,.052,.048,.043,.041,.046,.047],.028,Color("e6e1d1"),side)
	shoe_shell(last,profile,[.092,.129,.134,.123,.091,.072,.060,.048],.042,upper,side)
	shoe_part(last,Vector3(0,.113,-.084),Vector3(.104,.038,.091),Color("252a30"))
	shoe_part(last,Vector3(0,.119,-.020),Vector3(.072,.047,.104),upper.lightened(.18))
	for i in 4:
		for sign_ in [-1,1]:
			var lace := shoe_part(last,Vector3(sign_*.014,.140-i*.007,-.040+i*.021),Vector3(.056,.008,.010),Color("5d6468") if variant==0 else Color("eee9db"))
			lace.rotation.y=sign_*.43
	for sign_ in [-1,1]:
		var panel := shoe_part(last,Vector3(sign_*.055,.077,.017),Vector3(.014,.03,.113),upper.lightened(.40))
		panel.rotation.x=-.19

static func shoe_shell(parent: Node3D,profile: Array,tops: Array,thickness: float,color: Color,side: String) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sections := []
	for i in profile.size():
		var p: Vector2=profile[i]
		var row := PackedVector3Array()
		var top: float=tops[i]
		var bottom := maxf(.006,top-thickness) if thickness<.04 else .042
		for j in 20:
			var a := TAU*j/20.
			var x := cos(a)*p.y
			var y := lerpf(bottom,top,(sin(a)+1.)*.5)
			row.append(Vector3(x+(.012 if side=="l" else -.012)*smoothstep(.08,.18,p.x),y,p.x))
		sections.append(row)
	for i in range(sections.size()-1):
		for j in 20:
			var k := (j+1)%20
			for v in [sections[i][j],sections[i+1][j],sections[i][k],sections[i][k],sections[i+1][j],sections[i+1][k]]: surface.add_vertex(v)
	for j in range(1,19):
		for v in [sections[0][0],sections[0][j+1],sections[0][j],sections[-1][0],sections[-1][j],sections[-1][j+1]]: surface.add_vertex(v)
	surface.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.mesh=surface.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color=color
	mat.roughness=.77
	mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	if thickness>=.04:
		var textile := Shader.new()
		textile.code="""shader_type spatial;
		render_mode cull_disabled;
		uniform vec4 upper:source_color;
		varying vec3 p;
		void vertex(){p=VERTEX;}
		void fragment(){
			float mesh=sin(p.x*1800.)*sin(p.z*1750.);
			float wing=smoothstep(.031,.055,abs(p.x));
			float seam=abs(p.z-(.020+.58*(abs(p.x)-.044)+.55*(p.y-.075)));
			float stripe=wing*(1.-smoothstep(.006,.010,seam));
			float toe=smoothstep(.110,.117,p.z+abs(p.x)*.45);
			float heel=1.-smoothstep(-.094,-.085,p.z);
			vec3 facing=mix(upper.rgb,upper.rgb*.49,max(toe*.40,heel*.80));
			ALBEDO=mix(facing*(1.+.035*mesh),vec3(.09,.17,.18),stripe);
			ROUGHNESS=mix(.91,.65,max(toe,heel));
		}"""
		var fabric := ShaderMaterial.new()
		fabric.shader=textile
		fabric.set_shader_parameter("upper",color)
		mesh.material_override=fabric
	else: mesh.material_override=mat
	parent.add_child(mesh)

static func face_hair(rig: Skeleton3D,body: MeshInstance3D,mesh: ArrayMesh,coach: bool,variant: int) -> void:
	# Follow the jaw and scalp vertices so stubble and hairlines inherit the face shape.
	var part := MeshInstance3D.new()
	part.mesh=mesh
	part.skin=body.skin
	rig.add_child(part)
	part.skeleton=part.get_path_to(rig)
	var shader := Shader.new()
	shader.code="""shader_type spatial;
	uniform bool gray;
	uniform vec4 tone:source_color;
	varying vec3 p;
	void vertex(){p=vec3(UV2,COLOR.r*.6-.3);VERTEX+=NORMAL*.002;}
	void fragment(){
		float grain=fract(sin(dot(floor(p.xy*2100.)+floor(p.z*1900.),vec2(12.9898,78.233)))*43758.54);
		float line=1.685+.065*smoothstep(-.055,.075,p.z)+.01*abs(sin(p.x*32.));
		bool scalp=p.y>line+grain*.002;
		float edge=1.632+.020*smoothstep(.04,.078,abs(p.x));
		bool jaw=gray && p.y>1.555 && p.y<edge+grain*.002 && p.z>.008 && abs(p.x)<.092;
		if(!scalp && !jaw) discard;
		ALBEDO=tone.rgb*(.72+.47*grain);ROUGHNESS=.94;
	}"""
	var mat := ShaderMaterial.new()
	mat.shader=shader
	mat.set_shader_parameter("gray",coach)
	mat.set_shader_parameter("tone",Color("929087") if coach else Color.from_hsv(.065+.004*variant,.42,.13+.065*(variant%6)))
	part.material_override=mat

static func haircut(scalp: Node3D,color: Color,variant: int) -> void:
	var style := variant%7

	if style==0: return
	match style:
		1,5:
			for i in 8:
				var strand := shoe_part(scalp,Vector3((i-3.5)*.021,.20-absf(i-3.5)*.006,-.02),Vector3(.032,.046,.19),color.lightened(.015*(i%3)))
				strand.rotation.y=.13 if style==1 else -.27
			if style==5: shoe_part(scalp,Vector3(0,.166,-.121),Vector3(.12,.103,.105),color)
		2,6:
			for i in 38:
				var h := (i+.5)/38.
				var a := i*2.39996
				var r := sqrt(1.-h*h)
				var loc := Vector3(.088*r*cos(a),.16+.061*h,-.016+.096*r*sin(a))
				shoe_part(scalp,loc,Vector3.ONE*(.049 if style==2 else .069),color.lightened(.012*(i%4)))
		3:
			for i in 6:
				var lock := shoe_part(scalp,Vector3((i-2.5)*.027,.205,-.005),Vector3(.056,.059,.164),color)
				lock.rotation.z=-.48
		4:
			shoe_part(scalp,Vector3(0,.224,-.076),Vector3(.115,.095,.115),color)

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
