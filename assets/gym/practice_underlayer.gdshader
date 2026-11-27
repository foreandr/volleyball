shader_type spatial;
render_mode cull_disabled;
uniform sampler2D skin_map : source_color;
uniform sampler2D skin_normal : hint_normal;
uniform vec4 skin_tint:source_color=vec4(1.);
uniform float sleeve_end;
uniform vec2 shoulder_ends=vec2(-1.);
varying vec3 bind;
void vertex(){
	bind=vec3(UV2,COLOR.r*.6-.3);
	VERTEX+=NORMAL*.0014;
}
void fragment(){
	float x=abs(bind.x);
	if(bind.y<1.28 || x<.062 || x>.675 || (x<.20 && bind.y>1.56)) discard;
	float tip=bind.x>0.?shoulder_ends.x:shoulder_ends.y;
	if(tip<0.) tip=sleeve_end;
	bool covered=tip>0. && x<tip;
	if(covered){
		float cuff=1.-smoothstep(.009,.013,tip-x);
		float rib=cos(bind.y*970.+bind.z*580.)*(1.-smoothstep(.001,.004,fwidth(bind.y)+fwidth(bind.z)));
		ALBEDO=mix(vec3(.032,.042,.048),vec3(.017,.023,.030),cuff)*(.98+.035*rib);
		ROUGHNESS=.81;
	}else{
		ALBEDO=texture(skin_map,UV).rgb*skin_tint.rgb;
		NORMAL_MAP=texture(skin_normal,UV).rgb;
		NORMAL_MAP_DEPTH=.65;
		ROUGHNESS=.83;
	}
}
