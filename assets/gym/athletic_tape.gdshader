shader_type spatial;

// Godot's cylinder unwrap follows the circumference on U. The diagonal
// edge meets itself after one turn, like successive overlapping wraps.
void fragment(){
	float wrap=fract(UV.y*2.+UV.x);
	float distance_to_edge=min(wrap,1.-wrap);
	float aa=max(.009,fwidth(UV.y*2.+UV.x));
	float lap=1.-smoothstep(.018,.018+aa,distance_to_edge);
	vec2 thread=UV*vec2(130.,32.);
	vec2 fade=1.-smoothstep(vec2(.15),vec2(.5),fwidth(thread));
	vec2 yarn=cos(thread*6.283185)*fade;
	ALBEDO=vec3(.79,.755,.68)*(1.-lap*.14+.025*yarn.x+.018*yarn.y);
	ROUGHNESS=.94;
	SPECULAR=.20;
	NORMAL_MAP=normalize(vec3(.075*yarn.x,.065*yarn.y+.11*lap,1.))*.5+.5;
}
