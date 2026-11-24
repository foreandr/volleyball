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
	float fiber=sin(UV.x*33.+UV.y*4.);
	ALBEDO=tone.rgb*(.80+.17*fiber+.46*UV.y);
	ROUGHNESS=.52+.18*UV.y;
	SPECULAR=.45;
}
