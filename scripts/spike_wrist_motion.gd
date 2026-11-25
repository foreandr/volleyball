extends RefCounted

# Measure wrist rotation in the resting hand's anatomical axes.
static func constrain(wanted: Quaternion, previous: Quaternion, rest: Quaternion, along: Vector3, across: Vector3, dt: float) -> Quaternion:
	var relative := (rest.inverse()*wanted).normalized()
	if relative.w<0.: relative=-relative
	var vector := Vector3(relative.x,relative.y,relative.z)
	if vector.length_squared()>.0000001:
		vector=vector.normalized()*2.*atan2(vector.length(),relative.w)
	var normal := along.cross(across).normalized()
	# Most axial roll belongs in the forearm; permit more flexion than lateral bend.
	var limit := Vector3(deg_to_rad(18.),deg_to_rad(55.),deg_to_rad(23.))
	var angles := Vector3(vector.dot(along),vector.dot(across),vector.dot(normal))
	angles/=maxf(1.,(angles/limit).length())
	vector=along*angles.x+across*angles.y+normal*angles.z
	var target := rest
	if vector.length_squared()>.0000001: target=rest*Quaternion(vector.normalized(),vector.length())
	var gap := previous.angle_to(target)
	var fraction := minf(1.-exp(-18.*dt),deg_to_rad(210.)*dt/maxf(.00001,gap))
	return previous.slerp(target,fraction).normalized()
