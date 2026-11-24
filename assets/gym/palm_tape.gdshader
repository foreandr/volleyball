shader_type spatial;

uniform vec3 center;
uniform vec3 axis;
varying vec3 local_hand;

void vertex(){
	local_hand=vec3(UV2,COLOR.r*.6-.3)-center;
	VERTEX+=NORMAL*.0018;
}

void fragment(){
	float along=dot(local_hand,axis);
	if(abs(along)>.013 || length(local_hand)>.063) discard;
	float lap=1.-smoothstep(.0004,.0014,abs(along+local_hand.z*.16));
	float edge=smoothstep(.010,.0125,abs(along));
	float yarn=cos(along*5200.)*(1.-smoothstep(.0003,.001,fwidth(along)));
	ALBEDO=vec3(.79,.755,.68)*(1.-.19*lap-.08*edge+.035*yarn);
	ROUGHNESS=.92;
	SPECULAR=.2;
}