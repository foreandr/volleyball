shader_type spatial;
render_mode cull_disabled;
uniform vec4 tone:source_color;
uniform vec3 guide_0;
uniform vec3 guide_1;
uniform vec3 guide_2;
uniform vec3 guide_3;
uniform float phase;
void vertex(){
	vec2 radial=UV2*2.-1.;
	vec4 weights=vec4(max(-radial.x,0.),max(radial.x,0.),max(radial.y,0.),max(-radial.y,0.))+vec4(.06);
	weights/=dot(weights,vec4(1.));
	vec3 lag=guide_0*weights.x+guide_1*weights.y+guide_2*weights.z+guide_3*weights.w;
	float tips=UV.y*UV.y*(3.-2.*UV.y);
	float wind=sin(TIME*2.6+phase+VERTEX.x*28.)+.35*sin(TIME*5.+VERTEX.z*31.);
	vec3 motion=lag+vec3(.003*wind,0.,.0015*wind);
	// Slide loose ends along the scalp when a head turn drives them inward.
	vec3 outward=normalize(vec3(radial.x,sqrt(max(0.,1.-dot(radial,radial))),radial.y));
	motion-=outward*min(dot(outward,motion),0.);
	VERTEX+=tips*motion;
}
void fragment(){
	float strand=UV.x*42.+sin(UV.y*7.+phase)*.65;
	float fiber=sin(strand)*(1.-smoothstep(.55,2.8,fwidth(strand)));
	float edge=min(UV.x,1.-UV.x);
	// Split the outer portion of each lock into staggered, tapered wisps.
	float lane=UV.x*5.+.09*sin(5.*UV.y+phase);
	float seed=fract(sin(floor(lane)*19.13+phase)*314.17);
	float tip_end=.82+.18*seed;
	float taper=smoothstep(.48+.15*seed,tip_end,UV.y);
	float separation=abs(fract(lane)-.5);
	if(edge<.035+.08*taper || separation>.5*(1.-taper)) discard;
	RIM=.23*UV.y;
	RIM_TINT=.6;
	ALBEDO=tone.rgb*(.53+.11*fiber+.36*UV.y)*(.68+.32*COLOR.r);
	ANISOTROPY=.68;
	ANISOTROPY_FLOW=vec2(1.,0.);
	ROUGHNESS=.48+.16*UV.y+.06*(1.-COLOR.r);
	SPECULAR=.45;
}
