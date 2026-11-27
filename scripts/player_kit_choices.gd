extends RefCounted
const Profile = preload("res://scripts/player_profile.gd")
const COLORS := ["f2eee6","292d31","233952","aa343b","e6bf54","32685e"]

static func pick(actor: Node3D, field: String) -> int:
	return Profile.KIT_CHOICES[field].find(actor.attributes[field])

static func apply(actor: Node3D) -> void:
	var v: int=actor.get_meta("kit_variant",0)
	var rig: Skeleton3D=actor.skeleton
	for side in ["l","r"]:
		var shoe: ShaderMaterial=rig.get_meta("sole_"+side).get_child(0).material_override
		var cut := pick(actor,"Shoe cut")
		shoe.set_shader_parameter("collar_rise",[0.,.038,.082][v%3 if cut==0 else cut-1])
		var design := pick(actor,"Shoe design")
		shoe.set_shader_parameter("design",v%4 if design==0 else design-1)
		var tint := pick(actor,"Shoe color")
		var palette := ["eceee9","192e48","f2eee6","b64136","35414b","f1cc60","416864","405da1","ded8d0"]
		shoe.set_shader_parameter("tint",Color(palette[v%9] if tint==0 else COLORS[tint-1]))
		var tape: String=actor.attributes["Finger tape"]
		for item in rig.get_children():
			if item.is_in_group("finger_tape_"+side):
				item.visible=(v%5!=4 and side==("l" if v%2==0 else "r")) if tape=="Team" else (tape=="Both" or tape==("Left" if side=="l" else "Right"))
		var hand_key:="Left hand" if side=="l" else "Right hand"
		if actor.attributes[hand_key]!="Team":
			for item in rig.get_children():
				if item.is_in_group("finger_tape_"+side): item.visible=actor.attributes[hand_key]=="Tape"
	if actor.leg_skin:
		for region in ["ankle","calf","quad"]:
			actor.leg_skin.set_shader_parameter(region+"_options",Vector2i(pick(actor,"Left "+region),pick(actor,"Right "+region)))
		actor.leg_skin.set_shader_parameter("knee_override",Vector2i(pick(actor,"Left knee"),pick(actor,"Right knee")))
		var height := pick(actor,"Sock height")
		actor.leg_skin.set_shader_parameter("sock_top",[.32,.12,.21,.42,.17,.28,.48][v%7] if height==0 else [.12,.21,.32,.48][height-1])
		var tint := pick(actor,"Sock color")
		var palette := ["f1eee6","fafafa","313947","892f38","f5f2e8","284661","36393a","33635b"]
		actor.leg_skin.set_shader_parameter("sock_color",Color(palette[v%8] if tint==0 else COLORS[tint-1]))
		var sleeve := pick(actor,"Leg sleeves")
		actor.leg_skin.set_shader_parameter("tights_hem",[2.,.30,.075,2.,.33,2.,.29][v%7] if sleeve==0 else [2.,.30,.075][sleeve-1])
	if actor.shorts_fabric: actor.shorts_fabric.set_shader_parameter("print_style",pick(actor,"Shorts design"))
	if actor.has_meta("underlayer_material"):
		var tips:=[-1.,0.,.42,.66]
		actor.get_meta("underlayer_material").set_shader_parameter("shoulder_ends",Vector2(tips[pick(actor,"Left shoulder")],tips[pick(actor,"Right shoulder")]))
		var shirt := pick(actor,"Underlayer")
		actor.get_meta("underlayer_material").set_shader_parameter("sleeve_end",[0.,.42,.66,0.,0.][v%5] if shirt==0 else [0.,.42,.66][shirt-1])
	var scalp: Node3D=actor.get_meta("kit_scalp")
	var style: String=actor.attributes.Headwear+"/"+actor.attributes.Sunglasses+"/"+actor.attributes.Eyebrows+"/"+actor.attributes["Eyebrow color"]
	if scalp.get_meta("accessory_style","")==style: return
	scalp.set_meta("accessory_style",style)
	var pieces := scalp.get_node_or_null("Accessories")
	if pieces:
		scalp.remove_child(pieces)
		pieces.queue_free()
	pieces=Node3D.new()
	pieces.name="Accessories"
	scalp.add_child(pieces)
	if actor.attributes.Headwear=="Headband":
		var band := CylinderMesh.new()
		band.height=.031
		band.top_radius=.096
		band.bottom_radius=.094
		part(pieces,band,Vector3(0,.13,.003),Vector3(1,1,1.06),Color("f3f0e8"))
	if actor.attributes.Eyebrows!="Natural" or actor.attributes["Eyebrow color"]!="Natural":
		for sign_ in [-1.,1.]:
			part(pieces,SphereMesh.new(),Vector3(sign_*.038,.118,.086),Vector3(.045,.010 if actor.attributes.Eyebrows=="Full" else .005,.010),Profile.HAIR_COLORS[actor.attributes["Eyebrow color"]])
	if actor.attributes.Headwear=="Cap":
		part(pieces,SphereMesh.new(),Vector3(0,.165,-.003),Vector3(.20,.13,.215),Color("283c49"))
		part(pieces,SphereMesh.new(),Vector3(0,.152,.096),Vector3(.16,.014,.14),Color("283c49"))
	if actor.attributes.Sunglasses=="Sport":
		for sign_ in [-1.,1.]:
			part(pieces,SphereMesh.new(),Vector3(sign_*.039,.100,.090),Vector3(.078,.043,.019),Color("192a35"))
			part(pieces,BoxMesh.new(),Vector3(sign_*.078,.105,.042),Vector3(.007,.008,.092),Color("263139"))
		part(pieces,BoxMesh.new(),Vector3(0,.108,.093),Vector3(.025,.007,.007),Color("263139"))

static func part(parent: Node3D,mesh: Mesh,point: Vector3,size_: Vector3,color: Color) -> void:
	var node := MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	material.albedo_color=color
	node.mesh=mesh
	node.material_override=material
	node.position=point
	node.scale=size_
	parent.add_child(node)
