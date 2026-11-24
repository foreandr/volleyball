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
	VERTEX+=tips*motion*(COLOR.g*1.6);
}
void fragment(){
	// Vary fiber spacing and tip splits per lock, keeping the pattern attached during motion.
	float lock_seed=fract(COLOR.r*63.71);
	float lock_phase=phase+6.283*lock_seed;
	float strand=UV.x*mix(33.,51.,lock_seed)+sin(UV.y*7.+lock_phase)*.65;
	float fiber=sin(strand)*(1.-smoothstep(.55,2.8,fwidth(strand)));
	float edge=min(UV.x,1.-UV.x);
	// Split the outer portion of each lock into staggered, tapered wisps.
	float lane=UV.x*mix(4.,6.,lock_seed)+.12*sin(5.*UV.y+lock_phase);
	float seed=fract(sin(floor(lane)*19.13+lock_phase)*314.17);
	float tip_end=.82+.18*seed;
	float taper=smoothstep(.48+.15*seed,tip_end,UV.y);
	float separation=abs(fract(lane)-.5);
	if(edge<.035+.08*taper || separation>.5*(1.-taper)) discard;
	RIM=.23*UV.y;
	RIM_TINT=.6;
	ALBEDO=tone.rgb*(.53+.11*fiber+.36*UV.y)*(.68+.32*COLOR.r);
	// Individual fibers share a broader highlight once a lock falls below a pixel.
	float footprint=max(fwidth(UV.x),.35*fwidth(UV.y));
	float unresolved=smoothstep(.075,.70,footprint);
	float normal_spread=clamp(dot(dFdx(NORMAL),dFdx(NORMAL))+dot(dFdy(NORMAL),dFdy(NORMAL)),0.,1.);
	ANISOTROPY=mix(.68,.38,unresolved);
	ANISOTROPY_FLOW=vec2(1.,0.);
	float rough=.48+.16*UV.y+.06*(1.-COLOR.r);
	ROUGHNESS=sqrt(min(1.,rough*rough+.24*unresolved+.14*normal_spread));
	SPECULAR=mix(.45,.31,unresolved);
}
