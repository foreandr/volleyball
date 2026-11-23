shader_type spatial;
varying vec3 court;
void vertex(){court=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
float hash(vec2 p){return fract(sin(dot(p,vec2(15.31,83.7)))*4375.2);}
float noise2(vec2 p){
	vec2 i=floor(p),u=fract(p); u=u*u*(3.0-2.0*u);
	return mix(mix(hash(i),hash(i+vec2(1,0)),u.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),u.x),u.y);
}
void fragment(){
	vec2 p=court.xz;
	float row=floor(p.x/0.095);
	vec2 board=vec2(p.x/.095,p.y/1.68+hash(vec2(row,3.))*5.);
	float seed=hash(floor(board));
	vec2 q=fract(board);
	float grain=noise2(vec2(p.x*92.+1.2*sin(p.y*2.+seed*30.),p.y*2.5));
	vec3 maple=mix(vec3(.61,.436,.272),vec3(.70,.52,.345),seed*.55+grain*.45);
	float edge=min(min(q.x,1.-q.x)*.095,min(q.y,1.-q.y)*1.68);
	float joint=1.-smoothstep(0.,max(.0015,fwidth(edge)),edge);
	ALBEDO=maple*(1.-0.17*joint);
	ROUGHNESS=.34+grain*.06;
	SPECULAR=.63;
	CLEARCOAT=.38;
	CLEARCOAT_ROUGHNESS=.2;
}
