shader_type spatial;

uniform vec3 center;
uniform vec3 axis;
uniform vec3 across;
varying vec3 local_hand;

void vertex(){
	local_hand=vec3(UV2,COLOR.r*.6-.3)-center;
	VERTEX+=NORMAL*.0018;
}

void fragment(){
	float along=dot(local_hand,axis);
	float lateral=dot(local_hand,across);
	float depth=dot(local_hand,cross(axis,across));
	// Two angled courses meet around the back of the hand. The upper
	// course overlaps the first and casts a narrow shadow at its edge.
	float course=along-.16*lateral;
	float upper=along+.12*lateral-.007;
	if(min(abs(course+.005)-.009,abs(upper)-.009)>0. || length(local_hand)>.063) discard;
	float seam=upper+.009;
	float feather=max(.00035,fwidth(seam));
	float shadow=1.-smoothstep(0.,.0017+feather,abs(seam+.00065));
	float rim=1.-smoothstep(0.,feather+.00035,abs(seam-.00035));
	float transverse=lateral+.50*depth;
	vec2 thread=vec2(course/.00125,transverse/.00105);
	vec2 detail=1.-smoothstep(vec2(.18),vec2(.5),fwidth(thread));
	vec2 weave=cos(thread*6.283185)*detail;
	ALBEDO=vec3(.79,.755,.68)*(1.-.24*shadow+.10*rim+.035*weave.x+.023*weave.y);
	ROUGHNESS=.92;
	SPECULAR=.2;
}
