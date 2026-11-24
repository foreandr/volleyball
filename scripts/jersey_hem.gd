extends RefCounted

# A ring of linked hem particles hangs from the animated lower torso.
# Distances are measured in world space so turning or stopping excites the cloth.
const COUNT := 12
var anchors := PackedVector3Array()
var points := PackedVector3Array()
var previous := PackedVector3Array()
var offsets := PackedVector3Array()
var bone := -1
var inverse_rest := Transform3D.IDENTITY
var last_center := Vector3.INF
var last_step := 0.
# Front and back edges of both straps can slide over the shoulder.
var strap_points := PackedVector3Array()
var strap_speeds := PackedVector3Array()
var strap_bones := PackedInt32Array()
var strap_inverse_rest: Array[Transform3D]=[]

func update_straps(rig: Skeleton3D, fabric: ShaderMaterial, steps: int, h: float, reset: bool) -> void:
	if strap_bones.is_empty():
		for side in ["l","r"]:
			var clavicle:=rig.find_bone("clavicle_"+side)
			strap_bones.append(clavicle)
			strap_inverse_rest.append(rig.get_bone_global_rest(clavicle).affine_inverse())
		strap_points.resize(4)
		strap_speeds.resize(4)
	var offsets_local:=PackedVector3Array()
	for i in 4:
		var side:=i/2
		var sign_x:=1. if side==0 else -1.
		var sign_z:=1. if i%2==0 else -1.
		var pose:=rig.global_transform*rig.get_bone_global_pose(strap_bones[side])*strap_inverse_rest[side]
		var target:=pose*Vector3(sign_x*.131,1.506,-.018+sign_z*.064)
		var normal:=(pose.basis*Vector3(sign_x*.38,.68,sign_z*.62)).normalized()
		if reset:
			strap_points[i]=target
			strap_speeds[i]=Vector3.ZERO
		for step in steps:
			var force:=(target-strap_points[i])*230.+Vector3.DOWN*9.81
			strap_speeds[i]=(strap_speeds[i]+force*h)*exp(-13.*h)
			strap_points[i]+=strap_speeds[i]*h
			var gap:=(strap_points[i]-target).dot(normal)
			if gap<0.:
				strap_points[i]-=normal*gap
				strap_speeds[i]-=normal*minf(0.,strap_speeds[i].dot(normal))
			strap_points[i]=target+(strap_points[i]-target).limit_length(.027)
		offsets_local.append(rig.global_basis.inverse()*(strap_points[i]-target))
	fabric.set_shader_parameter("strap_offsets",offsets_local)


func update(rig: Skeleton3D, fabric: ShaderMaterial, dt: float, wind: Vector3) -> void:
	if bone<0:
		bone=rig.find_bone("spine_01")
		inverse_rest=rig.get_bone_global_rest(bone).affine_inverse()
		for i in COUNT:
			var a:=TAU*i/COUNT
			anchors.append(Vector3(.166*sin(a),1.04,-.018+.128*cos(a)))
		points.resize(COUNT)
		previous.resize(COUNT)
		offsets.resize(COUNT)
	var frame:=rig.global_transform*rig.get_bone_global_pose(bone)*inverse_rest
	var reset:=not last_center.is_finite() or last_center.distance_to(frame.origin)>.55
	last_center=frame.origin
	var steps:=maxi(1,ceili(minf(dt,.067)*120.))
	var h:=minf(dt,.067)/steps
	update_straps(rig,fabric,steps,h,reset)
	var targets:=PackedVector3Array()
	var normals:=PackedVector3Array()
	var normal_frame:=frame.basis.inverse().transposed()
	for i in COUNT:
		targets.append(frame*anchors[i])
		var a:=TAU*i/COUNT
		normals.append((normal_frame*Vector3(sin(a)/.166,0.,cos(a)/.128)).normalized())
		if reset:
			points[i]=targets[i]
			previous[i]=targets[i]
	for step in steps:
		for i in COUNT:
			var point:=points[i]
			var ratio:=clampf(h/last_step,.25,4.) if last_step>0. and step==0 else 1.
			var velocity:=(point-previous[i])*ratio*exp(-8.*h)
			points[i]+=velocity+((targets[i]-point)*250.+Vector3.DOWN*9.81+wind*1.8)*h*h
			previous[i]=point
		for iteration in 3:
			for i in COUNT:
				var j:=(i+1)%COUNT
				var edge:=points[j]-points[i]
				var correction:=edge*.5*(1.-targets[i].distance_to(targets[j])/maxf(.0001,edge.length()))
				points[i]+=correction
				points[j]-=correction
			# Eliminate inward travel after every constraint sweep so contact also
			# changes the next Verlet velocity. The shader resolves finer skin detail.
			for i in COUNT:
				var separation:=(points[i]-targets[i]).dot(normals[i])
				if separation<-.006: points[i]+=normals[i]*(-.006-separation)
	last_step=h
	var inverse_basis:=rig.global_basis.inverse()
	for i in COUNT:
		offsets[i]=inverse_basis*(points[i]-targets[i]).limit_length(.060)
	fabric.set_shader_parameter("hem_particles",offsets)
