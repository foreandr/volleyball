extends RefCounted

# Four mobile rings hang from the pinned armhole. The displacement
# field is sampled on the skinned garment in its original bind coordinates.
const AROUND := 16
const ROWS := 5
const PER_ARM := AROUND*ROWS
var particles := PackedVector3Array()
var previous := PackedVector3Array()
var anchors := PackedVector3Array()
var offsets := PackedVector3Array()
var links: Array[Vector2i]=[]
var stiffness := PackedFloat32Array()
var last_dt := 0.
var upper := PackedInt32Array()
var lower := PackedInt32Array()
var last_root := Vector3.ZERO

func link(a: int,b: int,strength := 1.) -> void:
	links.append(Vector2i(a,b))
	stiffness.append(strength)

func setup(rig: Skeleton3D) -> void:
	for side in ["l","r"]:
		upper.append(rig.find_bone("upperarm_"+side))
		lower.append(rig.find_bone("lowerarm_"+side))
	for side in 2:
		var sign_ := 1. if side==0 else -1.
		var start := rig.get_bone_global_rest(upper[side]).origin
		var end := rig.get_bone_global_rest(lower[side]).origin
		for row in ROWS:
			var x := sign_*(.195+.039*row)
			var center := start.lerp(end,clampf((x-start.x)/(end.x-start.x),0.,1.))
			for j in AROUND:
				var angle := TAU*j/AROUND
				anchors.append(Vector3(x,center.y+.076*cos(angle),center.z+.076*sin(angle)))
		for row in ROWS:
			for j in AROUND:
				var a := side*PER_ARM+row*AROUND+j
				var b := side*PER_ARM+row*AROUND+(j+1)%AROUND
				link(a,b)
				if row>0:
					link(a,a-AROUND)
					link(a,b-AROUND)
				if row>1: link(a,a-2*AROUND,.10)
	particles.resize(anchors.size())
	previous.resize(anchors.size())
	offsets.resize(anchors.size())

func update(rig: Skeleton3D,material: ShaderMaterial,delta: float,air: Vector3) -> void:
	var reset := anchors.is_empty()
	if reset: setup(rig)
	reset=reset or last_root.distance_to(rig.global_position)>.6
	last_root=rig.global_position
	var targets := PackedVector3Array()
	targets.resize(anchors.size())
	var shoulders := PackedVector3Array()
	var elbows := PackedVector3Array()
	for side in 2:
		var pose := rig.global_transform*rig.get_bone_global_pose(upper[side])
		var frame := pose*rig.get_bone_global_rest(upper[side]).affine_inverse()
		shoulders.append(pose.origin)
		elbows.append(rig.to_global(rig.get_bone_global_pose(lower[side]).origin))
		for k in PER_ARM:
			var i := side*PER_ARM+k
			targets[i]=frame*anchors[i]
			if reset:
				particles[i]=targets[i]
				previous[i]=targets[i]
	# Measure in the posed frame so a larger athlete does not contract
	# the sleeve towards the dimensions of the source mannequin.
	var lengths := PackedFloat32Array()
	lengths.resize(links.size())
	for j in links.size():
		lengths[j]=targets[links[j].x].distance_to(targets[links[j].y])
	var steps := maxi(1,ceili(minf(delta,.067)*120.))
	var dt := minf(delta,.067)/steps
	for step in steps:
		for i in particles.size():
			var old := particles[i]
			if i%PER_ARM<AROUND: particles[i]=targets[i]
			else:
				var ratio := clampf(dt/last_dt,.25,4.) if step==0 and last_dt>0. else 1.
				var velocity := (old-previous[i])*ratio*exp(-9.*dt)
				var radial := (targets[i]-Geometry3D.get_closest_point_to_segment(targets[i],shoulders[i/PER_ARM],elbows[i/PER_ARM])).normalized()
				var pressure := air*absf(air.dot(radial))*2.4
				particles[i]+=velocity+(pressure+Vector3.DOWN*9.81+(targets[i]-old)*100.)*dt*dt
			previous[i]=old
		for iteration in 4:
			for j in links.size():
				var a := links[j].x
				var b := links[j].y
				var difference := particles[b]-particles[a]
				var correction := stiffness[j]*difference*(1.-lengths[j]/maxf(.00001,difference.length()))
				var free_a := a%PER_ARM>=AROUND
				var free_b := b%PER_ARM>=AROUND
				if free_a: particles[a]+=correction*(.5 if free_b else 1.)
				if free_b: particles[b]-=correction*(.5 if free_a else 1.)
			for i in particles.size():
				if i%PER_ARM<AROUND: continue
				var side := i/PER_ARM
				var axis := Geometry3D.get_closest_point_to_segment(particles[i],shoulders[side],elbows[side])
				var radial := particles[i]-axis
				if radial.length()<.062: particles[i]=axis+radial.normalized()*.062
	last_dt=dt
	var inverse := rig.global_basis.inverse()
	for i in particles.size():
		offsets[i]=inverse*((particles[i]-targets[i]).limit_length(.034))
	material.set_shader_parameter("sleeve_offset",offsets)
