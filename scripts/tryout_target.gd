extends Node3D

var beacon := MeshInstance3D.new()
var is_net := false
var mouth_radius := 0.42
var depth := 0.64
var mesh := ImmediateMesh.new()
var cord := StandardMaterial3D.new()
var sag := 0.0
var velocity := 0.0

func rod(a: Vector3,b: Vector3,r: float,color: Color) -> void:
	var item := MeshInstance3D.new()
	var tube := CylinderMesh.new()
	tube.top_radius = r
	tube.bottom_radius = r
	tube.height = a.distance_to(b)
	tube.radial_segments = 8
	item.mesh = tube
	var surface := StandardMaterial3D.new()
	surface.albedo_color = color
	surface.metallic = 0.6
	surface.roughness = 0.35
	item.material_override = surface
	item.position = (a+b)/2
	item.quaternion = Quaternion(Vector3.UP,(b-a).normalized())
	add_child(item)
	var shape := CylinderShape3D.new()
	shape.height = tube.height
	shape.radius = r
	preload("res://scripts/gym_physics.gd").solid(item,shape,32)

func _ready() -> void:
	var hoop := TorusMesh.new()
	hoop.inner_radius = mouth_radius-0.02
	hoop.outer_radius = mouth_radius+0.025
	var rim := MeshInstance3D.new()
	rim.mesh = hoop
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color("ed7543")
	rim.material_override = paint
	add_child(rim)
	var halo := TorusMesh.new()
	halo.inner_radius=mouth_radius+.055
	halo.outer_radius=mouth_radius+.102
	beacon.mesh=halo
	beacon.position.y=.032
	beacon.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var glow := Shader.new()
	glow.code="""shader_type spatial;
	render_mode unshaded;
	void vertex(){ VERTEX.xz*=1.+.06*sin(TIME*3.); }
	void fragment(){ ALBEDO=vec3(.12,.94,.78)*(1.2+.22*sin(TIME*3.)); }
	"""
	var highlight := ShaderMaterial.new()
	highlight.shader=glow
	beacon.material_override=highlight
	add_child(beacon)
	beacon.hide()
	for i in 20:
		var a := TAU*i/20.
		var b := TAU*(i+1)/20.
		var start := Vector3(cos(a),0,sin(a))*mouth_radius
		var end := Vector3(cos(b),0,sin(b))*mouth_radius
		var segment := Node3D.new()
		segment.position = (start+end)/2.
		segment.quaternion = Quaternion(Vector3.UP,(end-start).normalized())
		add_child(segment)
		var shape := CapsuleShape3D.new()
		shape.radius = .022
		shape.height = start.distance_to(end)+.044
		preload("res://scripts/gym_physics.gd").solid(segment,shape,32)
	if is_net:
		for side in [-1,1]:
			var foot := Vector3(side*mouth_radius,-position.y+0.1,0)
			rod(foot,Vector3(side*mouth_radius,0,0),0.025,Color.SILVER)
			rod(foot+Vector3.FORWARD*0.46,foot+Vector3.BACK*0.46,0.035,Color.DIM_GRAY)
			for z in [-0.39,0.39]:
				rod(foot+Vector3(-.032,-.005,z),foot+Vector3(.032,-.005,z),.067,Color("20272b"))
			rod(foot+Vector3.FORWARD*.40,foot+Vector3.UP*.48,.014,Color.SILVER)
	else:
		var base := CylinderMesh.new()
		base.top_radius = mouth_radius*.81
		base.bottom_radius = base.top_radius
		base.height = .022
		var bottom := MeshInstance3D.new()
		bottom.mesh = base
		bottom.material_override = paint
		bottom.position.y = -depth
		add_child(bottom)
		for y in [-.035,-.075,-depth+.035]:
			var rib := MeshInstance3D.new()
			var band := TorusMesh.new()
			var r := mouth_radius*lerpf(1,.8,-y/depth)
			band.outer_radius = r+.012
			band.inner_radius = r-.003
			rib.mesh = band
			rib.material_override = paint
			rib.position.y = y
			add_child(rib)
		# Hollow side walls keep the target opening available to a falling ball.
		for i in 16:
			var angle := TAU*i/16
			var wall := Node3D.new()
			wall.position = Vector3(sin(angle)*mouth_radius*.9,-depth*.5,cos(angle)*mouth_radius*.9)
			wall.rotation.y = angle
			wall.rotate_object_local(Vector3.RIGHT,.18)
			add_child(wall)
			var shape := BoxShape3D.new()
			shape.size = Vector3(mouth_radius*.39,depth,.025)
			preload("res://scripts/gym_physics.gd").solid(wall,shape,32)
	var basket := MeshInstance3D.new()
	basket.mesh = mesh
	cord.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if is_net else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	cord.roughness = .42
	cord.albedo_color = Color("eee5ca") if is_net else Color("bb6034")
	cord.cull_mode = BaseMaterial3D.CULL_DISABLED
	add_child(basket)
	rebuild()

func knot(i: int,j: int) -> Vector3:
	var t := j/6.0
	var angle := TAU*(i+0.5*(j%2))/20
	var radius := mouth_radius*lerpf(1,0.48 if is_net else 0.80,t)
	return Vector3(cos(angle)*radius,-depth*t-sag*t,sin(angle)*radius)

func rebuild() -> void:
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES if is_net else Mesh.PRIMITIVE_TRIANGLES,cord)
	for i in 20:
		for j in 6:
			var a := knot(i,j)
			var b := knot(i+1,j)
			var c := knot(i,j+1)
			var d := knot(i+1,j+1)
			if is_net:
				for point in [a,c,b,c]: mesh.surface_add_vertex(point)
			else:
				for point in [a,b,c,b,d,c]:
					mesh.surface_set_normal(Vector3(point.x,-0.12,point.z).normalized())
					mesh.surface_add_vertex(point)
	mesh.surface_end()

func impact() -> void:
	if is_net: velocity = 2.1

func _process(delta: float) -> void:
	if absf(sag)+absf(velocity)<0.001: return
	var dt := minf(delta,0.05)
	velocity += (-72*sag-8*velocity)*dt
	sag += velocity*dt
	rebuild()
