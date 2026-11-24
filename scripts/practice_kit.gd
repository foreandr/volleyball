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
			kit.set_shader_parameter("team_crest",preload("res://assets/gym/falcon.svg"))
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
			if not coach:
				var gusset := MeshInstance3D.new()
				gusset.mesh=skin_surface
				gusset.skin=node.skin
				rig.add_child(gusset)
				gusset.skeleton=gusset.get_path_to(rig)
				var lining := ShaderMaterial.new()
				lining.shader=preload("res://assets/gym/underarm_gusset.gdshader")
				gusset.material_override=lining
				actor.underarm_fabric=lining
			if not coach and variant%3==2: compression(rig,node,skin_surface)
			face_hair(rig,node,skin_surface,coach,variant)
			if not coach and variant%4==1 and variant%5!=4:
				palm_tape(rig,node,skin_surface,"l" if variant%2==0 else "r")
		if shirt:
			# The skinned print replaces only the jersey. Keep shoes and trousers.
			var invisible := StandardMaterial3D.new()
			invisible.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			invisible.albedo_color = Color.TRANSPARENT
			node.set_surface_override_material(0,invisible)
			node.set_surface_override_material(2,invisible)
			if not coach: shorts(rig,node,variant,actor,print_texture)
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
				uniform vec3 inertia; uniform float motion; varying vec2 cut; varying float azimuth;
				float ankle_fold(float height,float angle){
					float gathered=smoothstep(.092,.135,height)*(1.-smoothstep(.22,.42,height));
					return gathered*.006*cos(height*89.+1.7*sin(angle)+.45*cos(angle*3.));
				}
				float knee_fold(vec2 pattern,float angle){
					float offset=pattern.y-.493+.032*cos(angle)+.012*sin(2.*angle);
					float rear=1.-smoothstep(-.45,.82,sin(angle));
					float envelope=exp(-offset*offset/.0031);
					return .0065*rear*envelope*sin(offset*106.+.42*sin(angle));
				}
				void vertex(){
					cut=UV2;
					azimuth=atan(COLOR.r*.6-.30,abs(cut.x)-.13);
					float ankle=smoothstep(.092,.135,cut.y)*(1.-smoothstep(.22,.42,cut.y));
					float gather=ankle_fold(cut.y,azimuth);
					VERTEX+=NORMAL*(ankle*.014+gather+knee_fold(cut,azimuth));
					float weight=1.-smoothstep(.38,1.02,UV2.y);
					VERTEX+=weight*inertia*.38;
					VERTEX+=NORMAL*(.019+.011*weight+.012*weight*motion*sin(UV2.y*28.+UV2.x*22.-TIME*12.));
				}
				void fragment(){
					if(cut.y<.088 || cut.y>1.12)discard;
					float cuff=1.-smoothstep(.111,.116,cut.y);
					float side=1.-smoothstep(.15,.24,abs(sin(azimuth)));
					side*=smoothstep(.14,.20,abs(cut.x))*smoothstep(.11,.14,cut.y);
					// A tapered woven stripe follows the outseam from hip to ankle.
					float outseam=sin(azimuth+.10*sin((cut.y-.12)*3.8));
					float width=mix(.12,.24,smoothstep(.14,.86,cut.y));
					float dist=abs(outseam)-width;
					float aa=max(.012,fwidth(dist));
					float outer=smoothstep(.14,.19,abs(cut.x))*smoothstep(.11,.13,cut.y);
					float insert=(1.-smoothstep(-aa,aa,dist))*outer;
					float piping=(1.-smoothstep(.014,.026+aa,abs(dist)))*outer;
					ALBEDO=mix(vec3(.026,.042,.055),vec3(.041,.060,.069),side);
					ALBEDO=mix(ALBEDO,vec3(.054,.104,.083),insert);
					ALBEDO=mix(ALBEDO,vec3(.23,.26,.225),piping*.78);
					float rib=cos(azimuth*65.)*(1.-smoothstep(.009,.045,fwidth(azimuth)));
					ALBEDO*=1.-cuff*(.24-.08*rib);
					float relief=knee_fold(cut,azimuth)+ankle_fold(cut.y,azimuth);
					vec3 dx=dFdx(VERTEX), dy=dFdy(VERTEX);
					vec3 u=cross(dy,NORMAL), v=cross(NORMAL,dx);
					float det=dot(dx,u);
					if(abs(det)>1e-10) NORMAL=normalize(NORMAL-(u*dFdx(relief)+v*dFdy(relief))/det);
					ROUGHNESS=mix(.77,.88,cuff);
				}"""
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
		if variant%5!=4:
			tape_hand(rig,"l" if variant%2==0 else "r",1+variant%3)

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

static func shorts(rig: Skeleton3D,outfit: MeshInstance3D,variant: int,actor: Node3D,number: Texture2D) -> void:
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """shader_type spatial;
	render_mode cull_disabled;
	uniform vec3 inertia; uniform float motion; uniform float hem_y; uniform vec2 stride; uniform vec4 accent:source_color; varying float depth; uniform vec4 cloth:source_color; uniform sampler2D knit_surface:repeat_enable,filter_linear_mipmap_anisotropic; varying vec2 rest;
	uniform sampler2D leg_number:source_color,filter_linear_mipmap_anisotropic;
	float pleat_height(vec2 pattern,float hem,float ripple){
		float raised=pattern.x>0.?stride.x:stride.y;
		float pleat=sin(abs(pattern.x)*99.+pattern.y*31.);
		return hem*((.009+raised*.010)*pleat+motion*.014*ripple);
	}
	void vertex(){rest=UV2; depth=COLOR.r*.6-.3;
		float hem=1.-smoothstep(hem_y,hem_y+.22,rest.y);
		float ripple=sin(rest.x*47.+rest.y*25.-TIME*14.);
		float fold_height=pleat_height(rest,hem,ripple);
		VERTEX+=NORMAL*(.004+hem*(.013+motion*.012)+fold_height);
		VERTEX+=hem*inertia*.65;
		VERTEX.y+=hem*motion*.009*ripple;}
	void fragment(){

		// A bound side vent gives the cuff clearance over the outside of the thigh.
		float side=smoothstep(.135,.19,abs(rest.x));
		// Dolphin hems sweep upward over the outer thigh. The rear panel hangs lower.
		float vent_depth=depth+.018;
		float vent_span=mix(.047,.080,smoothstep(-.012,.012,vent_depth));
		float sweep=1.-smoothstep(0.,vent_span,abs(vent_depth));
		float vent=side*(.043*sweep+.009*smoothstep(.01,.095,vent_depth));
		float edge_height=rest.y-hem_y-vent;
		if(edge_height<-.001) discard;
		float hem=1.-smoothstep(.005,.009,edge_height);
		float outer=smoothstep(.12,.17,abs(rest.x));
		float opening=.028+.034*(1.-smoothstep(hem_y,hem_y+.19,rest.y));
		float seam=abs(depth+.018)-opening;
		float panel=outer*(1.-smoothstep(-.002,.002,seam));
		// Open-knit side inserts end above the folded leg opening.
		vec2 cell=vec2(depth/.0042,rest.y/.0048);
		float detail=1.-smoothstep(.22,.8,max(fwidth(cell.x),fwidth(cell.y)));
		cell.x+=.5*mod(floor(cell.y),2.);
		float eyelet=1.-smoothstep(.12,.36,length(fract(cell)-.5));
		vec3 insert=accent.rgb*(1.12-.49*detail*eyelet*(1.-hem));
		ALBEDO=mix(cloth.rgb,insert,panel);
		ALBEDO=mix(ALBEDO,cloth.rgb*1.55,hem*.75);
		float topstitch=1.-smoothstep(.00065,.0015+fwidth(edge_height),abs(edge_height-.006));
		ALBEDO*=1.-.21*topstitch;
		float piping=outer*(1.-smoothstep(.001,.003+fwidth(seam),abs(seam)));
		ALBEDO=mix(ALBEDO,mix(cloth.rgb,accent.rgb,.42)*1.8,piping*.82);
		// Recover the changing pleat slope in view space so the gym lights
		// follow the raised thigh and the fabric settling around the cuff.
		vec3 dx=dFdx(VERTEX), dy=dFdy(VERTEX);
		vec3 tx=cross(dy,NORMAL), ty=cross(NORMAL,dx);
		float area=dot(dx,tx);
		// Evaluate folds across the panel so lighting stays smooth across mesh edges.
		float fold_height=pleat_height(rest,1.-smoothstep(hem_y,hem_y+.22,rest.y),
			sin(rest.x*47.+rest.y*25.-TIME*14.));
		vec3 slope=(tx*dFdx(fold_height)+ty*dFdy(fold_height))*sign(area)/max(abs(area),.0000001);
		NORMAL=normalize(NORMAL-clamp(slope,vec3(-.65),vec3(.65))*.62);
		float folds=sin(rest.x*84.+rest.y*38.)*hem;
		vec3 yarn=texture(knit_surface,UV*28.).rgb;
		vec2 grain=(yarn.rg-.5)*.32;
		NORMAL_MAP=normalize(vec3(grain+vec2(folds*.12,.035*hem),1.))*.5+.5;
		ALBEDO*=.97+.06*yarn.b;
		// A smaller transfer on the left leg matches the player's jersey number.
		vec2 number_uv=vec2((rest.x-.105)/.072+.5,(hem_y+.085-rest.y)/.041);
		if(FRONT_FACING && depth>.041 && all(greaterThanEqual(number_uv,vec2(0.))) && all(lessThanEqual(number_uv,vec2(1.)))){
			float ink=texture(leg_number,number_uv).a;
			ALBEDO=mix(ALBEDO,vec3(.86,.82,.72),ink*.94);
		}
		// The folded cuff exposes the reverse of the fabric during a raised stride.
		if(!FRONT_FACING){
			ALBEDO=mix(cloth.rgb*.61,cloth.rgb*.89,hem)*(.92+.16*yarn.b);
			NORMAL_MAP_DEPTH=.45;
		}
		ROUGHNESS=.78+.06*hem+.07*(yarn.b-.5);
	}"""
	material.shader = shader
	material.set_shader_parameter("knit_surface",preload("res://assets/gym/training_knit.png"))
	actor.jersey_materials.append(material)
	var hem := .69+.019*(variant%7)
	material.set_shader_parameter("hem_y",hem)
	material.set_shader_parameter("cloth",Color.from_hsv(fmod(.55+.147*variant,1.),.32,.24+.045*(variant%4)))
	material.set_shader_parameter("accent",[Color("415565"),Color("713e32"),Color("42584c"),Color("555063")][variant%4])
	var part := MeshInstance3D.new()
	var template := preload("res://assets/characters/volleyball/practice_shorts.res")
	var arrays := template.surface_get_arrays(0)
	var positions: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var pattern: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV2]
	var depths := PackedColorArray()
	depths.resize(positions.size())
	for i in positions.size():
		depths[i]=Color(clampf((positions[i].z+.3)/.6,0.,1.),0.,0.)
		# Taper the covered waistband toward the hips so a forward bend
		# keeps the rear shorts panel underneath the loose practice shirt.
		var waist := smoothstep(.92,1.035,pattern[i].y)
		positions[i].z=lerpf(positions[i].z,-.025,waist*.24)
		positions[i].x*=1.-waist*.075
		var shortening := (hem-.69)*(1.-smoothstep(.69,.96,pattern[i].y))
		positions[i].y+=shortening
		pattern[i].y+=shortening
	arrays[Mesh.ARRAY_COLOR]=depths
	arrays[Mesh.ARRAY_VERTEX]=positions
	arrays[Mesh.ARRAY_TEX_UV2]=pattern
	var tailored := ArrayMesh.new()
	tailored.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},template.surface_get_format(0))
	part.mesh=tailored
	material.set_shader_parameter("leg_number",number)
	actor.shorts_fabric=material
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
	uniform float knee_center;
	uniform float knee_depth;
	uniform float open_back;
	float rear_opening(float lateral,float height,float depth){
		float radius=length(vec2(lateral/.046,height/.031));
		return open_back*(1.-smoothstep(.37,.49,depth))*(1.-smoothstep(.92,1.,radius));
	}
	// Rounded foam face with lateral wings and articulation channels.
	float pad_face(float lateral,float height){
		vec2 radius=vec2(lateral/.069,height/.070);
		return 1.-smoothstep(.72,1.06,length(radius));
	}
	float flex_channel(float lateral,float height,float bend){
		float line=abs(height+.014-abs(lateral)*.40);
		float lower_line=abs(height+.042-abs(lateral)*.24);
		float width=mix(.0035,.0075,bend);
		return max(1.-smoothstep(.0015,width,line),.72*(1.-smoothstep(.001,width*.8,lower_line)));
	}
	uniform float sock_top; uniform vec4 sock_trim:source_color; uniform float striped;
	uniform vec4 pad_color:source_color;
	varying vec3 anatomy;
	varying vec2 loads;
	float contour(vec2 point,vec2 center,vec2 radius){
		vec2 d=(point-center)/radius;
		return exp(-dot(d,d));
	}
	varying float enabled_side;
	varying float pad;
	varying float knee_facing;
	varying float foam;
	varying float sock;
	void vertex(){
		y=UV2.y;
		float flex=UV2.x>0.?knee_flex.x:knee_flex.y;
		float k=y-knee_height;
		float enabled=UV2.x>0.?padded.x:padded.y;
		enabled_side=enabled;
		pad=enabled*(1.-smoothstep(.087,.094,abs(k)));
		float lateral=abs(UV2.x)-knee_center;
		float depth=.5+(COLOR.r*.6-.3-knee_depth)/.20;
		pad*=1.-rear_opening(lateral,k,depth);
		foam=pad*smoothstep(.49,.62,depth)*pad_face(lateral,k);
		knee_facing=depth;
		foam*=1.-mix(.24,.52,flex)*flex_channel(lateral,k,flex);
		sock=1.-smoothstep(sock_top,sock_top+.004,y);
		// Compress the sock inside the heel cup and release it above the collar.
		float inside_shoe=1.-smoothstep(.064,.117,y);
		float rolled_edge=pad*smoothstep(.073,.079,abs(k))*(1.-smoothstep(.083,.091,abs(k)));
		VERTEX+=NORMAL*(pad*.005+rolled_edge*.003+foam*.018+sock*.002-inside_shoe*.012);
		anatomy=vec3(abs(UV2.x),y,COLOR.r);
		loads=vec2(flex,UV2.x>0.?calf_load.x:calf_load.y);
	}
	void fragment(){if(y>hem_y+.055 || y<.070)discard; ALBEDO=texture(skin_map,UV).rgb; NORMAL_MAP=texture(muscles,UV).rgb; NORMAL_MAP_DEPTH=.68; ROUGHNESS=mix(.42,.86,texture(roughness_map,UV).r);
		float yarn=.5+.5*cos(y*1250.)*(1.-smoothstep(.0007,.003,fwidth(y)));
		float sock_mask=1.-smoothstep(sock_top,sock_top+.003,y);
		float pad_mask=enabled_side*(1.-smoothstep(.087,.091,abs(y-knee_height)));
		float back_hole=rear_opening(anatomy.x-knee_center,y-knee_height,knee_facing);
		pad_mask*=1.-back_hole;
		float below_cuff=sock_top-y;
		float stripe_dist=min(abs(below_cuff-.014),abs(below_cuff-.025));
		float stripe=striped*(1.-smoothstep(.002,.003+fwidth(y),stripe_dist));
		float cuff=1.-smoothstep(.030,.036,below_cuff);
		float angle=atan((anatomy.z-.5)*.6,anatomy.x-knee_center);
		float rib=cos(angle*56.)*(1.-smoothstep(.015,.055,fwidth(angle)));
		// Denser knitting wraps the ankle below the striped cuff.
		float course=y-.122-.018*cos(angle);
		float ankle_band=(1.-smoothstep(.012,.015,abs(course)))*(1.-cuff);
		float knit_phase=angle*45.+course*970.;
		float diagonal=cos(knit_phase)*(1.-smoothstep(.65,2.9,fwidth(knit_phase)));
		float selvage=1.-smoothstep(.0006,.0019+fwidth(course),abs(abs(course)-.010));
		vec3 sock_base=mix(vec3(.68,.69,.66),mix(vec3(.53,.55,.52),sock_trim.rgb,.13),ankle_band);
		vec3 knit_color=mix(sock_base*(1.+ankle_band*(.075*diagonal-.13*selvage)),sock_trim.rgb,stripe);
		ALBEDO=mix(ALBEDO,knit_color*(.91+.09*yarn-.08*cuff+.095*cuff*rib),sock_mask);
		float height=y-knee_height;
		float lateral=anatomy.x-knee_center;
		float face=pad_face(lateral,height)*smoothstep(.49,.62,knee_facing);
		float channel=flex_channel(lateral,height,loads.x)*face;
		float binding=smoothstep(.075,.081,abs(height));
		// Foam bunches into a soft lip above each articulation groove on a bent knee.
		float fold_width=mix(.0035,.0075,loads.x);
		float fold_top=height+.014-abs(lateral)*.40-fold_width;
		float fold_bottom=height+.042-abs(lateral)*.24-fold_width*.8;
		float fold_edge=min(abs(fold_top),abs(fold_bottom));
		float foam_lip=(1.-smoothstep(.001,.004+fwidth(height),fold_edge))*face;
		float edging=1.-smoothstep(.001,.0035,abs(abs(height)-.076));
		float opening_edge=1.-smoothstep(.03,.14,abs(length(vec2(lateral/.046,height/.031))-1.));
		float edging_back=open_back*opening_edge*(1.-smoothstep(.37,.49,knee_facing));
		float cover=.74-.19*edging_back+.12*yarn+.14*face-.25*channel-.16*binding+.11*edging;
		// Perimeter stitching joins the abrasion-resistant face to the stretch sleeve.
		vec2 face_uv=vec2(lateral/.069,height/.070);
		float radius=length(face_uv);
		float rim_dist=abs(radius-.91);
		float seam=(1.-smoothstep(.016,.041+fwidth(radius),rim_dist))*smoothstep(.49,.62,knee_facing);
		float stitch_phase=atan(face_uv.y,face_uv.x)*52.;
		float stitch=.5+.5*cos(stitch_phase)*(1.-smoothstep(.55,2.6,fwidth(stitch_phase)));
		vec2 vent_grid=vec2(angle*5.73,height*105.);
		vent_grid.x+=.5*mod(floor(vent_grid.y),2.);
		float vent=1.-smoothstep(.12,.26,length(fract(vent_grid)-.5));
		float vent_zone=(1.-face)*(1.-smoothstep(.054,.069,abs(height)));
		cover+=foam_lip*(.08+.21*loads.x)+face*(.075-.11*yarn)-seam*(.27-.15*stitch)-.24*vent*vent_zone;
		// The elastic binding is knitted around the leg, across the direction of stretch.
		float cuff_phase=angle*96.;
		float cuff_ribs=cos(cuff_phase)*(1.-smoothstep(.65,2.8,fwidth(cuff_phase)));
		float folded_edge=1.-smoothstep(.0008,.0026+fwidth(height),abs(abs(height)-.084));
		cover+=binding*(.105*cuff_ribs+.14*folded_edge);
		ALBEDO=mix(ALBEDO,pad_color.rgb*cover,pad_mask);
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
		// Give each foam lobe a crown and depress the stitched hinge as the knee bends.
		float foam_profile=.0045*face*(1.-smoothstep(.15,.98,radius))
			-.0026*channel-.0008*seam;
		float surface_height=relief*(1.-gear)+pad_mask*foam_profile;
		vec3 slope=dFdx(surface_height)*u+dFdy(surface_height)*v;
		if(abs(determinant)>1e-10) NORMAL=normalize(NORMAL-clamp(slope/determinant,vec3(-.8),vec3(.8)));
		NORMAL_MAP_DEPTH=mix(.93,.08,gear);
		SSS_STRENGTH=.18*(1.-gear);
		SPECULAR=mix(.36,.22,gear);
		ROUGHNESS=mix(ROUGHNESS,.88-.18*face*pad_mask,gear);}"""
	skin.shader = cut
	var both := variant>=20 or variant==0 or variant%4==1
	skin.set_shader_parameter("padded",Vector2(float(both or variant%4==2),float(both or variant%4==3)))
	skin.set_shader_parameter("pad_color",Color("dfdfd7") if variant%3==1 else Color("343d44"))
	skin.set_shader_parameter("striped",float(variant%3!=0))
	skin.set_shader_parameter("sock_trim",[Color("5c674f"),Color("844238"),Color("384c62")][variant%3])
	skin.set_shader_parameter("sock_top",.155+.027*(variant%4))
	var knee := rig.get_bone_global_rest(rig.find_bone("calf_l")).origin
	skin.set_shader_parameter("knee_depth",knee.z)
	skin.set_shader_parameter("knee_height",knee.y)
	skin.set_shader_parameter("knee_center",absf(knee.x))
	skin.set_shader_parameter("open_back",float(variant%3!=2))
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

# Separate wraps follow their own finger bones, leaving the joints free.
static func tape_hand(rig: Skeleton3D,side: String,count: int) -> void:
	var cloth := ShaderMaterial.new()
	cloth.shader=preload("res://assets/gym/athletic_tape.gdshader")
	for i in count:
		var digit: String=["index","middle","ring"][i]
		var bone := digit+"_01_"+side
		var joint := rig.get_bone_rest(rig.find_bone(digit+"_02_"+side)).origin
		var radius := clampf(joint.length()*.37,.0115,.0165)
		tape_band(rig,bone,joint*.52,joint.normalized(),radius,radius,joint.length()*.60,cloth)

static func palm_tape(rig: Skeleton3D,body: MeshInstance3D,skin_surface: ArrayMesh,side: String) -> void:
	var wrist := rig.get_bone_global_rest(rig.find_bone("hand_"+side)).origin
	var index := rig.get_bone_global_rest(rig.find_bone("index_01_"+side)).origin
	var pinky := rig.get_bone_global_rest(rig.find_bone("pinky_01_"+side)).origin
	var knuckles := (index+pinky)*.5
	var material := ShaderMaterial.new()
	material.shader=preload("res://assets/gym/palm_tape.gdshader")
	material.set_shader_parameter("center",wrist.lerp(knuckles,.59))
	material.set_shader_parameter("axis",(knuckles-wrist).normalized())
	material.set_shader_parameter("across",(index-pinky).slide((knuckles-wrist).normalized()).normalized())
	var wrap := MeshInstance3D.new()
	wrap.mesh=skin_surface
	wrap.skin=body.skin
	wrap.material_override=material
	rig.add_child(wrap)
	wrap.skeleton=wrap.get_path_to(rig)

static func tape_band(rig: Skeleton3D,bone: String,center: Vector3,axis: Vector3,width: float,depth: float,height: float,cloth: Material,across := Vector3.ZERO) -> void:
	var mount := BoneAttachment3D.new()
	mount.bone_name=bone
	rig.add_child(mount)
	var band := CylinderMesh.new()
	band.top_radius=1.
	band.bottom_radius=1.04
	band.height=1.
	band.cap_top=false
	band.cap_bottom=false
	band.radial_segments=36
	var part := MeshInstance3D.new()
	part.mesh=band
	part.material_override=cloth
	mount.add_child(part)
	var basis_ := Basis(Quaternion(Vector3.UP,axis)) if across.is_zero_approx() else Basis(across,axis,across.cross(axis))
	part.transform=Transform3D(basis_*Basis.from_scale(Vector3(width,height,depth)),center)

static func compression(rig: Skeleton3D,body: MeshInstance3D,surface: ArrayMesh) -> void:
	var elbow := rig.get_bone_global_rest(rig.find_bone("lowerarm_r")).origin
	var wrist := rig.get_bone_global_rest(rig.find_bone("hand_r")).origin
	var fabric := ShaderMaterial.new()
	fabric.shader=preload("res://assets/gym/compression_sleeve.gdshader")
	fabric.set_shader_parameter("elbow",elbow)
	fabric.set_shader_parameter("forearm",wrist-elbow)
	var part := MeshInstance3D.new()
	part.mesh=surface
	part.skin=body.skin
	part.material_override=fabric
	rig.add_child(part)
	part.skeleton=part.get_path_to(rig)

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
	var textile := ShaderMaterial.new()
	textile.shader=preload("res://assets/gym/court_shoe.gdshader")
	textile.set_shader_parameter("shoe_atlas",preload("res://assets/characters/footwear/running_shoes.png"))
	textile.set_shader_parameter("tint",Color.WHITE if coach else [Color.WHITE,Color("dfecff"),Color("ffe0a8"),Color("d5e4cf")][variant%4])
	textile.set_shader_parameter("counter_color",Color("303737") if coach else [Color("374351"),Color("b2583a"),Color("545d66"),Color("496663"),Color("c6aa69")][variant%5])
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
	uniform bool gray; uniform float temple_recess;
	uniform vec4 tone:source_color;
	varying vec3 p;
	void vertex(){p=vec3(UV2,COLOR.r*.6-.3);VERTEX+=NORMAL*.002;}
	void fragment(){
		float grain=fract(sin(dot(floor(p.xy*2100.)+floor(p.z*1900.),vec2(12.9898,78.233)))*43758.54);
		float line=1.685+.065*smoothstep(-.055,.075,p.z)+.01*abs(sin(p.x*32.));
		float temple=smoothstep(.035,.077,abs(p.x))*smoothstep(-.008,.058,p.z);
		line+=temple*temple_recess;
		// Crop above the ear and leave a narrow tapered sideburn in front of it.
		float side=smoothstep(.055,.077,abs(p.x));
		float ear_arch=exp(-pow(abs(p.z+.017)/.028,2.));
		float sideburn=exp(-pow(abs(p.z-.025)/.012,2.));
		line+=side*(.017*ear_arch-(.027+.38*temple_recess)*sideburn);
		// Short growth blends the hairline into the longer moving locks.
		float comb=p.x*2100.+p.z*540.+sin(p.y*55.+p.x*33.)*4.;
		float fibers=cos(comb)*(1.-smoothstep(.9,3.,fwidth(comb)));
		float edge_height=p.y-line+.0028*fibers;
		float growth=smoothstep(-.006,.020,edge_height);
		bool scalp=growth>grain;
		float edge=1.632+.020*smoothstep(.04,.078,abs(p.x));
		float cheek=smoothstep(-.005,.009,edge-p.y);
		float taper=smoothstep(1.551,1.566,p.y)*smoothstep(.005,.018,p.z);
		float lip=exp(-dot(vec2(p.x/.031,(p.y-1.624)/.009),vec2(p.x/.031,(p.y-1.624)/.009)));
		float density=cheek*taper*(1.-lip)*(.78+.18*(1.-smoothstep(1.58,1.62,p.y)));
		// Sweep the moustache down toward the corners, leaving the lip and philtrum visible.
		float wing=abs(p.x)/.033;
		float lip_line=1.637-.009*wing*wing;
		float moustache=(1.-smoothstep(.78,1.,wing))*(1.-smoothstep(.002,.006,abs(p.y-lip_line)))
			*smoothstep(.045,.068,p.z)*(.62+.38*smoothstep(.001,.007,abs(p.x)));
		density=max(density,.91*moustache);
		bool jaw=gray && abs(p.x)<.092 && density>grain;
		if(!scalp && !jaw) discard;
		float strand=.5+.5*cos(p.y*620.+abs(p.x)*390.+p.z*160.);
		float silver=gray ? smoothstep(.37,.88,grain)*(.26+.32*strand) : 0.;
		ALBEDO=mix(tone.rgb,tone.rgb*1.65,silver)*(.72+.47*grain);
		if(scalp){
			float root_light=1.-smoothstep(.018,.055,edge_height);
			ALBEDO*=(1.+.34*fibers)*(1.+.36*root_light);
			if(gray){
				// Group short silver fibers into locks combed toward the nape.
				float flow=p.x*810.+3.2*sin(p.y*48.+p.z*18.)+.7*sin(p.x*135.);
				float lock=.5+.5*cos(flow)*(1.-smoothstep(.85,3.,fwidth(flow)));
				float salt=smoothstep(.35,.76,.58*lock+.42*grain);
				ALBEDO=tone.rgb*mix(.36,1.20,salt)*(.88+.18*fibers);
			}
		}
		if(jaw){
			float whisker=p.y*1850.+abs(p.x)*mix(820.,350.,moustache)+p.z*460.;
			float fiber=cos(whisker)*(1.-smoothstep(.7,2.8,fwidth(whisker)));
			ALBEDO*= (.70+.30*strand)*(.92+.20*fiber-.19*moustache);
		}
		ROUGHNESS=.94;
	}"""
	var mat := ShaderMaterial.new()
	mat.shader=shader
	mat.set_shader_parameter("gray",coach)
	mat.set_shader_parameter("temple_recess",.021 if coach else .003+.013*(.5+.5*sin(variant*2.39996)))
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
	var waved_crop := style==0 and variant>=7
	var lock_count := 3600 if style==1 or waved_crop else 1080
	for i in lock_count:
		var y := rng.randf()
		var a := rng.randf()*TAU
		var radial := sqrt(1.-y*y)
		var normal := Vector3(radial*cos(a),y,radial*sin(a))
		var root := Vector3(.084*normal.x,.134+.074*y,-.013+.093*normal.z)
		var comb := Vector3(parting,-.35,-.95)
		var length_factor := 1.
		var crown := smoothstep(.22,.86,y)
		match style:
			0:
				length_factor=.48+.54*crown
				if waved_crop:
					# Lay short locks outward from a slightly off-centre crown.
					var pole := Vector3(parting,.94,-.24).normalized()
					comb=(normal-pole).slide(normal)+.26*pole.cross(normal)
			1:
				# Sweep the longer forelock across the crown above cropped sides.
				var fringe := smoothstep(-.45,.42,normal.z)*smoothstep(.16,.68,y)
				length_factor=.42+.65*crown+1.05*fringe
				comb=Vector3(.9,.08,-.52)
			2: length_factor=.38+1.35*crown
			3:
				# Parted curtains sweep out at the brow and tuck back over each ear.
				var fringe := smoothstep(-.24,.66,normal.z)*smoothstep(.10,.66,y)
				var temple := smoothstep(.38,.86,absf(normal.x))
				var side := 1. if normal.x>parting else -1.
				comb=Vector3(side*(.58+.35*fringe),-.48-.45*temple,.48*fringe-.72*temple)
				length_factor=.55+.62*crown+.48*fringe
			4:
				length_factor=.25+1.24*(1.-smoothstep(.22,.68,absf(normal.x-parting*.4)))
				comb=Vector3(parting,.70,-.85)
			5:
				# Draw the side hair up and back into the knot at the occiput.
				var tie := Vector3(parting*.025,.196+.005*(variant%3),-.092)
				comb=(tie-root).normalized()
				length_factor=.38+.34*smoothstep(-.8,.65,normal.z)
			6: length_factor=.62+.68*crown
		# Let the crown grow out of a whorl before it joins the combed sides.
		var crown_axis := Vector3(parting*.62,.95,-.28).normalized()
		var outward := (normal-crown_axis).slide(normal)
		var swirl := crown_axis.cross(normal)
		var handed := 1. if variant%2==0 else -1.
		var whorl := (outward*.78+swirl*handed).normalized()
		var influence := 0. if style==5 else smoothstep(.68,.97,normal.dot(crown_axis))
		var sweep := comb.slide(normal).normalized().lerp(whorl,influence*.92).normalized()
		if style in [1,3]:
			var part_line := absf(normal.x-parting-.16*normal.z)
			length_factor*=lerpf(.38,1.,smoothstep(.01,.12,part_line)*crown+1.-crown)
		var across := normal.cross(sweep).normalized()
		var length: float = actor.hair_length*length_factor*rng.randf_range(.75,1.25)
		var width := rng.randf_range(.005,.011)
		var pigment := rng.randf_range(.65,1.)
		if style==1:
			# Interleave short underlayers with fine surface locks so daylight
			# cannot reveal the lattice beneath a lifted forelock.
			var layer := rng.randf()
			length*=lerpf(.62,1.,layer)
			width*=lerpf(1.05,.42,layer)
			pigment*=lerpf(.72,1.,layer)
		# The green channel stores compliance relative to the simulated guide length.
		# Cropped sides track the scalp while long tips lag behind a head turn.
		var compliance := clampf(length/actor.hair_length,.12,1.6)/1.6
		if style==5: compliance*=.45
		var wave_ridge := 0.
		if waved_crop:
			var pole := Vector3(parting,.94,-.24).normalized()
			var arc := acos(clampf(normal.dot(pole),-1.,1.))
			wave_ridge=.5+.5*cos(arc*32.+.65*sin(a*2.))
			length*=.65+.40*wave_ridge
			pigment*=.74+.26*wave_ridge
		var coiled := style in [2,6]
		var lift := .10 if style==5 else .28
		if style==3: lift+=.22*crown*smoothstep(-.24,.66,normal.z)
		if waved_crop: lift=.10+.42*wave_ridge
		if style==1: lift+=.27*smoothstep(-.45,.42,normal.z)*crown
		# Neighboring ringlets share a direction, while the pitch changes across the crown.
		var patch := sin(normal.x*9.+normal.z*6.+variant)
		var turns := TAU*((1.4 if style==2 else 1.9)+.28*patch)
		var start_angle := 1.3*sin(normal.z*8.-normal.x*5.+variant)
		var winding := -1. if patch<-.2 else 1.
		var rows := 16 if coiled else (8 if style==1 else 4)
		for row in rows:
			for uv: Vector2 in [Vector2(0,0),Vector2(1,0),Vector2(0,1),Vector2(1,0),Vector2(1,1),Vector2(0,1)]:
				var t := (row+uv.y)/float(rows)
				var curl := sin(t*PI)*length*lift
				var lateral := 0.
				if coiled:
					var twist := start_angle+t*turns
					curl=length*(.55*t+.12*(cos(start_angle)-cos(twist)))
					lateral=length*.17*winding*(sin(twist)-sin(start_angle))
				# Orient the material tangent along the curved lock so reflected
				# gym lights follow its length, including the turn of a coil.
				var tangent := sweep
				if coiled:
					var twist := start_angle+t*turns
					tangent+=normal*(.55+.12*turns*sin(twist))+across*.17*winding*turns*cos(twist)
				else: tangent+=normal*lift*PI*cos(t*PI)
				tangent=tangent.normalized()
				var surface_normal := across.cross(tangent).normalized()
				if surface_normal.dot(normal)<0.: surface_normal=-surface_normal
				var cross_section := across.slide(tangent).normalized()
				var edge_slope := (uv.x*2.-1.)*(.85 if coiled else .62)
				tool.set_normal((surface_normal+cross_section*edge_slope).normalized())
				tool.set_tangent(Plane(tangent,1.))
				tool.set_uv(Vector2(uv.x,t))
				tool.set_uv2(Vector2(normal.x,normal.z)*.5+Vector2.ONE*.5)
				tool.set_color(Color(pigment,compliance,clampf(length/.20,0.,1.)))
				tool.add_vertex(root+sweep*length*t+normal*(curl+.002+.003*t)+across*(lateral+(uv.x-.5)*width*(1.-.87*t)))
	# Gather longer cuts into a wrapped knot at the back of the crown.
	# Each ribbon coils around the tie; overlap keeps the interior opaque.
	if style==5 or (style==3 and variant>=7):
		var radius := .037+.003*(variant%4)
		var center := Vector3(parting*.025,.196+.005*(variant%3),-.092)
		# The densely wound interior blocks daylight between the surface locks.
		var core := MeshInstance3D.new()
		var interior := SphereMesh.new()
		interior.radius=radius*.94
		interior.height=interior.radius*2.
		core.mesh=interior
		core.position=center
		var inner_hair := StandardMaterial3D.new()
		inner_hair.albedo_color=color.darkened(.28)
		inner_hair.roughness=.91
		core.material_override=inner_hair
		scalp.add_child(core)
		var band := MeshInstance3D.new()
		var elastic := TorusMesh.new()
		elastic.inner_radius=radius*.80
		elastic.outer_radius=radius*.95
		band.mesh=elastic
		band.rotation.x=PI*.5
		band.position=center+Vector3.BACK*radius*.51
		var binding := StandardMaterial3D.new()
		binding.albedo_color=Color("30282c")
		binding.roughness=.86
		band.material_override=binding
		scalp.add_child(band)
		for strand in 144:
			var latitude := asin(rng.randf_range(-1.,1.))
			var longitude := rng.randf()*TAU
			var pigment := rng.randf_range(.62,1.)
			for row in 8:
				for corner: Vector2 in [Vector2.ZERO,Vector2.RIGHT,Vector2.DOWN,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]:
					var t := (row+corner.y)/8.
					var lat := clampf(latitude+(corner.x-.5)*.16+.14*sin(t*PI),-1.55,1.55)
					var lon := longitude+t*2.4
					var n := Vector3(cos(lat)*cos(lon),sin(lat),cos(lat)*sin(lon))
					var tangent := Vector3(-sin(lon),0,cos(lon))
					tool.set_normal(n)
					tool.set_tangent(Plane(tangent,1.))
					tool.set_color(Color(pigment,.06,0))
					tool.set_uv(Vector2(corner.x,t*.38))
					tool.set_uv2(Vector2(.5,.05))
					tool.add_vertex(center+n*radius*(1.+.06*sin(PI*t)))
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
