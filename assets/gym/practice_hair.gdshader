shader_type spatial;
render_mode cull_disabled;
uniform vec4 tone:source_color;
uniform vec3 lag;
uniform float phase;
void vertex(){
	float tips=UV.y*UV.y;
	float wind=sin(TIME*2.6+phase+VERTEX.x*28.)+.35*sin(TIME*5.+VERTEX.z*31.);
	VERTEX+=tips*(lag+vec3(.003*wind,0.,.0015*wind));
}
void fragment(){
	float strand=UV.x*42.+sin(UV.y*7.+phase)*.65;
	float fiber=sin(strand)*(1.-smoothstep(.55,2.8,fwidth(strand)));
	float edge=min(UV.x,1.-UV.x);
	if(edge<.045+.018*sin(UV.y*19.+phase)) discard;
	RIM=.23*UV.y;
	RIM_TINT=.6;
	ALBEDO=tone.rgb*(.80+.17*fiber+.46*UV.y);
	ROUGHNESS=.52+.18*UV.y;
	SPECULAR=.45;
}
