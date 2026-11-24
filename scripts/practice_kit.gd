extends RefCounted

const FABRIC := preload("res://assets/gym/practice_kit.gdshader")

# Skinning transforms VERTEX before the material runs. Store bind-pose garment
# coordinates separately so piping and screen printing follow the fabric.
static func tailored_surface(source: ArrayMesh,surface: int,jacket := false) -> ArrayMesh:
	var arrays := source.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	var coords := PackedVector2Array()
	var depths := PackedColorArray()
	coords.resize(vertices.size())
	depths.resize(vertices.size())
	for i in vertices.size():
		var p := vertices[i]
		if jacket:
			# A rounded lower abdomen and fuller flanks continue into the trouser waist.
			var belly := exp(-pow((p.y-1.075)/.205,2.))*smoothstep(.31,.18,absf(p.x))
			var flank := exp(-pow((p.y-1.05)/.23,2.))
			vertices[i].x+=p.x*.31*flank*smoothstep(.32,.19,absf(p.x))
			vertices[i].z+=belly*(.095*smoothstep(-.095,.085,p.z)-.032*(1.-smoothstep(-.13,0.,p.z)))
			vertices[i].y-=.035*belly*smoothstep(.01,.10,p.z)
		if jacket and p.y>.99 and p.y<1.57:
			var ease := smoothstep(.99,1.10,p.y)*(1.-smoothstep(1.48,1.57,p.y))
			vertices[i]+=Vector3(arrays[Mesh.ARRAY_NORMAL][i])*(.01+.021*ease)
			if absf(p.x)<.20: vertices[i].z+=.039*ease*smoothstep(0,.11,p.z)
		if jacket and surface==0:
			var panel := (1.-smoothstep(.15,.25,absf(p.x)))*(1.-smoothstep(-.10,-.035,p.z))*smoothstep(.98,1.08,p.y)*(1.-smoothstep(1.45,1.55,p.y))
			var back := -.186+.048*pow(absf(p.x)/.22,2.)
			vertices[i].z=lerpf(vertices[i].z,minf(vertices[i].z,back),panel)
			normals[i]=normals[i].lerp(Vector3(p.x*2.8,.05,-1.).normalized(),panel*.95).normalized()
		coords[i] = Vector2(p.x,p.y)
		depths[i] = Color(clampf((p.z+0.3)/0.6,0,1),0,0,1)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_TEX_UV2] = coords
	arrays[Mesh.ARRAY_COLOR] = depths
	var shaped := ArrayMesh.new()
	shaped.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},source.surface_get_format(surface)&Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
	return shaped

static func apply(actor: Node3D,coach: bool,variant := 0) -> void:
	var rig: Skeleton3D = actor.skeleton
	var outer_shirt: MeshInstance3D
	if coach:
		actor.set_height_cm(174)
		actor.scale*=Vector3(1.01,1,1.01)
	elif variant>0:
		if variant<20: actor.set_height_cm(166+(variant*13)%36)
		actor.scale*=Vector3(.88+.036*(variant%7),1,.90+.045*((variant*3)%6))
	if variant>0 and variant<20:
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
		if sleeves:
			var kit := ShaderMaterial.new()
			kit.shader=FABRIC
			kit.set_shader_parameter("knit_surface",preload("res://assets/gym/training_knit.png"))
			actor.shirt_fabric=kit
			if not coach: actor.sleeve_cloth=preload("res://scripts/sleeve_cloth.gd").new()
			actor.jersey_origin=actor.global_position
			actor.jersey_materials.append(kit)
			kit.set_shader_parameter("phase",variant*1.79)
			kit.set_shader_parameter("fabric",Color("223d3c") if coach else Color("ac4029"))
			kit.set_shader_parameter("trim",Color("cad4bf") if coach else Color("55302c"))
			kit.set_shader_parameter("lettering",print_texture)
			kit.set_shader_parameter("jacket",coach)
			var original := preload("res://assets/characters/base/Superhero_Male_FullBody.gltf").instantiate()
			var torso: MeshInstance3D=original.find_child("SuperHero_Male",true,false)
			var shell := MeshInstance3D.new()
			var skin_surface := tailored_surface(torso.mesh,0,coach)
			shell.mesh=skin_surface if coach else preload("res://assets/characters/volleyball/training_tee/fitted.res")
			original.free()
			shell.skin=node.skin
			rig.add_child(shell)
			shell.skeleton=shell.get_path_to(rig)
			shell.material_override=kit
			outer_shirt=shell
			face_hair(rig,node,skin_surface,coach,variant)
		if shirt:
			# The skinned print replaces only the jersey. Keep shoes and trousers.
			var invisible := StandardMaterial3D.new()
			invisible.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			invisible.albedo_color = Color.TRANSPARENT
			node.set_surface_override_material(0,invisible)
			node.set_surface_override_material(2,invisible)
			if not coach: shorts(rig,node,variant,actor)
			else:
				var pants := MeshInstance3D.new()
				var source=preload("res://assets/characters/base/Superhero_Male_FullBody.gltf").instantiate()
				var body: MeshInstance3D=source.find_child("SuperHero_Male",true,false)
				pants.mesh=tailored_surface(body.mesh,0,true)
				source.free()
				pants.skin=node.skin
				rig.add_child(pants)
				pants.skeleton=pants.get_path_to(rig)
				var shell_fabric := ShaderMaterial.new()
				var trouser_shader := Shader.new()
				trouser_shader.code="""shader_type spatial;
				uniform vec3 inertia; uniform float motion; varying vec2 cut;
				void vertex(){
					cut=UV2;
					float weight=1.-smoothstep(.38,1.02,UV2.y);
					VERTEX+=weight*inertia*.38;
					VERTEX+=NORMAL*(.019+.011*weight+.012*weight*motion*sin(UV2.y*28.+UV2.x*22.-TIME*12.));
				}
				void fragment(){ if(cut.y<.088 || cut.y>1.12)discard; float cuff=1.-smoothstep(.094,.112,cut.y); ALBEDO=vec3(.026,.042,.055)*(1.-cuff*.22); ROUGHNESS=.84; }"""
				shell_fabric.shader=trouser_shader
				pants.material_override=shell_fabric
				actor.jersey_materials.append(shell_fabric)
				node.set_surface_override_material(1,invisible)
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
		haircut(scalp,hair,variant,actor)
		if variant%4==1: compression(rig,"hand_l","middle_01_l",.042,.041,Color("d6cdc0"))
		if variant%3==2: compression(rig,"lowerarm_r","hand_r",.061,.042,Color("252e35"))

	reshape_build(rig,coach,variant)
	if outer_shirt: actor.dressed_surface.configure(outer_shirt,rig)

# Taper upper arms in bind space, before joints pose them, so bare skin and
# fabric follow the same silhouette. Leave wrists, ankles and face registered.
static func reshape_build(rig: Skeleton3D,coach: bool,variant: int) -> void:
	var factor := [.77,.64,.91,.69,.82,.73][variant%6] as float
	if coach: factor=.72
	for part: MeshInstance3D in rig.get_children().filter(func(n): return n is MeshInstance3D):
		if not part.skin or not part.mesh is ArrayMesh: continue
		var original := part.mesh
		var shaped := ArrayMesh.new()
		var covered_skin := not coach and original==preload("res://assets/characters/volleyball/body.res")
		for i in original.get_surface_count():
			var arrays := original.surface_get_arrays(i)
			var verts: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			for j in verts.size():
				var v := verts[j]
				if covered_skin:
					v.z=lerpf(v.z,-.025,(1.-smoothstep(.14,.21,absf(v.x)))*smoothstep(1.1,1.22,v.y)*(1.-smoothstep(1.47,1.57,v.y))*.32)
					# Tuck the skin inside the upper sleeve. Fade out before
					# the cuff so the exposed arm keeps its actual silhouette.
					var covered := smoothstep(.09,.18,absf(v.x))*(1.-smoothstep(.32,.37,absf(v.x)))*smoothstep(1.19,1.34,v.y)
					v.y=lerpf(v.y,1.48,covered*.46)
					v.z=lerpf(v.z,-.035,covered*.46)
				var arm := smoothstep(.17,.30,absf(v.x))*(1.-smoothstep(.51,.73,absf(v.x)))*smoothstep(1.18,1.35,v.y)
				var thickness := lerpf(1.,factor,arm)
				v.y=1.48+(v.y-1.48)*thickness
				v.z=-.035+(v.z+.035)*thickness
				if not coach:
					var torso := (1.-smoothstep(.15,.27,absf(v.x)))*exp(-pow((v.y-1.35)/.15,2.))
					v.z*=lerpf(1.,factor,torso)
					v.x*=1.+(.035+.065*(variant%4))*exp(-pow((v.y-1.06)/.14,2.))
				verts[j]=v
			arrays[Mesh.ARRAY_VERTEX]=verts
			shaped.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},original.surface_get_format(i))
			shaped.surface_set_material(i,original.surface_get_material(i))
		part.mesh=shaped

static func shorts(rig: Skeleton3D,outfit: MeshInstance3D,variant: int,actor: Node3D) -> void:
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """shader_type spatial;
	uniform vec3 inertia; uniform float motion; uniform float hem_y; uniform vec4 cloth:source_color; uniform sampler2D knit_surface:repeat_enable,filter_linear_mipmap_anisotropic; varying vec2 rest;
	void vertex(){rest=UV2;
		float tailoring=(hem_y-.69)*(1.-smoothstep(.69,.96,rest.y));
		VERTEX.y+=tailoring; rest.y+=tailoring;
		float hem=1.-smoothstep(hem_y,hem_y+.22,rest.y);
		float ripple=sin(rest.x*47.+rest.y*25.-TIME*14.);
		VERTEX+=NORMAL*(.004+hem*(.017+motion*(.018+.025*ripple)));
		VERTEX+=hem*inertia*.65;
		VERTEX.y+=hem*motion*.009*ripple;}
	void fragment(){

		float hem=1.-smoothstep(hem_y+.005,hem_y+.009,rest.y);
		float side=smoothstep(.154,.174,abs(rest.x));
		ALBEDO=mix(cloth.rgb,cloth.rgb*.74,side);
		ALBEDO=mix(ALBEDO,cloth.rgb*1.55,hem*.75);
		float piping=1.-smoothstep(.001,.004,abs(abs(rest.x)-.166));
		ALBEDO=mix(ALBEDO,cloth.rgb*1.65,piping*.55);
		float folds=sin(rest.x*84.+rest.y*38.)*hem;
		vec3 yarn=texture(knit_surface,UV*28.).rgb;
		vec2 grain=(yarn.rg-.5)*.32;
		NORMAL_MAP=normalize(vec3(grain+vec2(folds*.12,.035*hem),1.))*.5+.5;
		ALBEDO*=.97+.06*yarn.b;
		ROUGHNESS=.78+.06*hem+.07*(yarn.b-.5);
	}"""
	material.shader = shader
	material.set_shader_parameter("knit_surface",preload("res://assets/gym/training_knit.png"))
	actor.jersey_materials.append(material)
	var hem := .69+.019*(variant%7)
	material.set_shader_parameter("hem_y",hem)
	material.set_shader_parameter("cloth",Color.from_hsv(fmod(.55+.147*variant,1.),.32,.24+.045*(variant%4)))
	var part := MeshInstance3D.new()
	part.mesh = preload("res://assets/characters/volleyball/practice_shorts.res")
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
	uniform sampler2D muscles:hint_normal; uniform sampler2D roughness_map; uniform float hem_y; uniform sampler2D skin_map:source_color; varying float y;
	uniform vec2 knee_flex;
	uniform vec2 calf_load;
	uniform vec2 padded;
	uniform float knee_height;
	uniform float sock_top;
	uniform vec4 pad_color:source_color;
	varying vec3 anatomy;
	varying vec2 loads;
	float contour(vec2 point,vec2 center,vec2 radius){
		vec2 d=(point-center)/radius;
		return exp(-dot(d,d));
	}
	varying float enabled_side;
	varying float pad;
	varying float foam;
	varying float sock;
	void vertex(){
		y=UV2.y;
		float flex=UV2.x>0.?knee_flex.x:knee_flex.y;
		float k=y-knee_height;
		float enabled=UV2.x>0.?padded.x:padded.y;
		enabled_side=enabled;
		pad=enabled*(1.-smoothstep(.087,.094,abs(k)));
		foam=pad*smoothstep(.50,.64,COLOR.r)*(1.-smoothstep(.050,.079,abs(k)));
		sock=1.-smoothstep(sock_top,sock_top+.004,y);
		VERTEX+=NORMAL*(pad*.005+foam*.018+sock*.002);
		anatomy=vec3(abs(UV2.x),y,COLOR.r);
		loads=vec2(flex,UV2.x>0.?calf_load.x:calf_load.y);
	}
	void fragment(){if(y>hem_y+.02 || y<.045)discard; ALBEDO=texture(skin_map,UV).rgb; NORMAL_MAP=texture(muscles,UV).rgb; NORMAL_MAP_DEPTH=.68; ROUGHNESS=mix(.42,.86,texture(roughness_map,UV).r);
		float yarn=.5+.5*cos(y*1250.)*(1.-smoothstep(.0007,.003,fwidth(y)));
		float sock_mask=1.-smoothstep(sock_top,sock_top+.003,y);
		float pad_mask=enabled_side*(1.-smoothstep(.087,.091,abs(y-knee_height)));
		ALBEDO=mix(ALBEDO,vec3(.68,.69,.66)*(.88+.12*yarn),sock_mask);
		float panel=.5+.5*cos((y-knee_height)*120.);
		ALBEDO=mix(ALBEDO,pad_color.rgb*(.74+.12*yarn+.14*panel*foam),pad_mask);
		float gear=max(pad_mask,sock_mask);
		vec2 p=anatomy.xy;
		float front=smoothstep(.46,.61,anatomy.z);
		float quad=contour(p,vec2(.077,.555),vec2(.038,.076))+contour(p,vec2(.167,.666),vec2(.042,.135));
		float ham=contour(p,vec2(.084,.644),vec2(.034,.135))+contour(p,vec2(.172,.657),vec2(.039,.14));
		float calf=contour(p,vec2(.091,.316),vec2(.037,.081))+contour(p,vec2(.156,.352),vec2(.038,.079));
		float relief=mix(ham,quad,front)*(.005+.003*loads.x)+calf*(1.-front)*(.006+.003*loads.y);
		vec3 dx=dFdx(VERTEX), dy=dFdy(VERTEX);
		vec3 u=cross(dy,NORMAL),v=cross(NORMAL,dx);
		float determinant=dot(dx,u);
		vec3 slope=dFdx(relief)*u+dFdy(relief)*v;
		if(abs(determinant)>1e-10) NORMAL=normalize(NORMAL-(1.-gear)*slope/determinant);
		NORMAL_MAP_DEPTH=mix(.93,.08,gear);
		SSS_STRENGTH=.18*(1.-gear);
		SPECULAR=mix(.36,.22,gear);
		ROUGHNESS=mix(ROUGHNESS,.88,gear);}"""
	skin.shader = cut
	var both := variant>=20 or variant==0 or variant%4==1
	skin.set_shader_parameter("padded",Vector2(float(both or variant%4==2),float(both or variant%4==3)))
	skin.set_shader_parameter("pad_color",Color("dfdfd7") if variant%3==1 else Color("343d44"))
	skin.set_shader_parameter("sock_top",.155+.027*(variant%4))
	skin.set_shader_parameter("knee_height",rig.get_bone_global_rest(rig.find_bone("calf_l")).origin.y)
	skin.set_shader_parameter("muscles",preload("res://assets/characters/base/T_Superhero_Male_Normal.png"))
	skin.set_shader_parameter("roughness_map",preload("res://assets/characters/base/T_Superhero_Male_Roughness.png"))
	skin.set_shader_parameter("hem_y",hem)
	skin.set_shader_parameter("skin_map",preload("res://assets/characters/base/T_Superhero_Male_Light.png"))
	actor.leg_skin=skin
	legs.material_override = skin
	source.free()

static func number_texture(number: int) -> Texture2D:
	var digits := str(number)
	var sheet := preload("res://assets/gym/jersey_digits.png").get_image()
	var img := Image.create(96*digits.length(),144,false,Image.FORMAT_RGBA8)
	for i in digits.length():
		img.blit_rect(sheet,Rect2i(int(digits[i])*96,0,96,144),Vector2i(i*96,0))
	img.generate_mipmaps()
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
	var trainer := MeshInstance3D.new()
	trainer.mesh=preload("res://assets/characters/footwear/running_l.obj") if side=="l" else preload("res://assets/characters/footwear/running_r.obj")
	var textile := StandardMaterial3D.new()
	textile.albedo_texture=preload("res://assets/characters/footwear/running_shoes.png")
	textile.albedo_color=Color.WHITE if coach else [Color.WHITE,Color("dfecff"),Color("ffe0a8"),Color("d5e4cf")][variant%4]
	textile.roughness=.78
	trainer.material_override=textile
	last.add_child(trainer)
	rig.set_meta("sole_"+side,last)

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

static func haircut(scalp: Node3D,color: Color,variant: int,actor: Node3D) -> void:
	var style := variant%7
	var parting := sin(variant*2.39996)*.46
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed=217+variant
	actor.hair_length=.022+.009*style
	for i in 1080:
		var y := rng.randf()
		var a := rng.randf()*TAU
		var radial := sqrt(1.-y*y)
		var normal := Vector3(radial*cos(a),y,radial*sin(a))
		var root := Vector3(.084*normal.x,.134+.074*y,-.013+.093*normal.z)
		var comb := Vector3(parting,-.35,-.95)
		var length_factor := 1.
		var crown := smoothstep(.22,.86,y)
		match style:
			0: length_factor=.48+.54*crown
			1: comb=Vector3(.92,-.18,parting)
			2: length_factor=.38+1.35*crown
			3: comb=Vector3(signf(normal.x-parting),-.6,.42)
			4:
				length_factor=.25+1.24*(1.-smoothstep(.22,.68,absf(normal.x-parting*.4)))
				comb=Vector3(parting,.70,-.85)
			5: comb=Vector3(parting,-.65,.92)
			6: length_factor=.62+.68*crown
		var sweep := comb.slide(normal).normalized()
		var across := normal.cross(sweep).normalized()
		var length: float = actor.hair_length*length_factor*rng.randf_range(.75,1.25)
		var width := rng.randf_range(.005,.011)
		var pigment := rng.randf_range(.65,1.)
		var coiled := style in [2,6]
		var rows := 9 if coiled else 4
		for row in rows:
			for uv: Vector2 in [Vector2(0,0),Vector2(1,0),Vector2(0,1),Vector2(1,0),Vector2(1,1),Vector2(0,1)]:
				var t := (row+uv.y)/float(rows)
				var curl := sin(t*PI)*length*.28
				var lateral := 0.
				if coiled:
					var twist := t*TAU*(1.4 if style==2 else 1.9)
					curl=length*(.48*t+.14*(1.-cos(twist)))
					lateral=length*.18*sin(twist)
				tool.set_normal(normal)
				tool.set_uv(Vector2(uv.x,t))
				tool.set_uv2(Vector2(normal.x,normal.z)*.5+Vector2.ONE*.5)
				tool.set_color(Color(pigment,0,0))
				tool.add_vertex(root+sweep*length*t+normal*(curl+.002+.003*t)+across*(lateral+(uv.x-.5)*width*(1.-.87*t)))
	var locks := MeshInstance3D.new()
	locks.mesh=tool.commit()
	scalp.add_child(locks)
	var mat := ShaderMaterial.new()
	mat.shader=preload("res://assets/gym/practice_hair.gdshader")
	mat.set_shader_parameter("tone",color)
	mat.set_shader_parameter("phase",variant*1.79)
	locks.material_override=mat
	actor.hair_mount=scalp
	actor.hair_material=mat
