shader_type spatial;
uniform sampler2D crest : source_color,filter_linear_mipmap_anisotropic,repeat_disable;
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
	// Screen-printed school crest and perimeter paint sit beneath the varnish.
	vec2 mark_uv=vec2(.5-p.x/3.6,.5+(p.y-6.25)/3.6);
	if(all(greaterThanEqual(mark_uv,vec2(0.))) && all(lessThanEqual(mark_uv,vec2(1.)))){
		vec4 mark=texture(crest,mark_uv);
		ALBEDO=mix(ALBEDO,mark.rgb,mark.a*.91);
	}
	vec2 bounds=abs(p-vec2(0.,4.))-vec2(4.5,9.);
	float outer=max(bounds.x,bounds.y);
	float band=smoothstep(.04,.06,outer)*(1.-smoothstep(.43,.45,outer));
	ALBEDO=mix(ALBEDO,vec3(.038,.128,.10)*(1.+grain*.1),band);
	float scuff=noise2(p*vec2(8.,85.))*noise2(p*1.8);
	// Dust collects along the bleacher bases; pivoting shoes leave broken rubber arcs.
	float dust=smoothstep(5.6,8.0,abs(p.x))*smoothstep(.26,.73,noise2(p*1.7))*(.45+.55*noise2(p*42.));
	vec2 tile=floor(p/.67);
	vec2 d=fract(p/.67)-vec2(.32+.32*hash(tile),.48);
	float spin=hash(tile+9.)*6.283;
	d=mat2(vec2(cos(spin),sin(spin)),vec2(-sin(spin),cos(spin)))*d;
	float rub=(1.-smoothstep(.007,.027,abs(length(d*vec2(1.,1.65))-.23)))*smoothstep(.02,.13,d.x)*step(.85,hash(tile+3.))*noise2(p*95.);
	ALBEDO=mix(ALBEDO,vec3(.17,.14,.10),dust*.32+rub*.46);
	ROUGHNESS=dust*.26+rub*.30+.28+grain*.05+.17*smoothstep(.49,.72,scuff);
	SPECULAR=.63;
	CLEARCOAT=.38;
	CLEARCOAT_ROUGHNESS=.2;
}
