shader_type canvas_item;
render_mode unshaded;
uniform bool hero = true;
uniform vec2 viewport_size = vec2(1280.,720.);
uniform vec4 accent : source_color = vec4(0.12,0.81,0.75,1.);
float stroke(float d,float w){return 1.-smoothstep(w,w+0.002,abs(d));}
void fragment(){
	vec2 p = (UV-vec2(.75,.49))*vec2(viewport_size.x/viewport_size.y,1.);
	float r=length(p);
	vec3 base=mix(vec3(.026,.055,.096),vec3(.044,.175,.205),smoothstep(.25,1.,UV.x));
	float line=stroke(r-.51,.0008)+stroke(r-.55,.0006)+stroke(r-.73,.0007);
	float stripe=step(.86,fract((p.x+p.y*.34)*18.));
	base+=vec3(.015,.055,.055)*stripe*smoothstep(.38,.72,UV.x);
	base+=accent.rgb*.17*line;
	if(hero && r<.32){
		vec2 xy=p/.32;
		vec3 n=vec3(xy.x,-xy.y,sqrt(max(0.,1.-dot(xy,xy))));
		float a=.60+TIME*.60;
		vec3 q=n;
		q.xz=mat2(vec2(cos(a),sin(a)),vec2(-sin(a),cos(a)))*q.xz;
		q.xy=mat2(vec2(.906,.423),vec2(-.423,.906))*q.xy;
		vec3 m=abs(q);
		vec2 patch;
		float family;
		if(m.x>=max(m.y,m.z)){patch=q.yz/m.x;family=0.;}
		else if(m.y>=m.z){patch=q.zx/m.y;family=1.;}
		else{patch=q.xy/m.z;family=2.;}
		float band=patch.x+.12*(1.-patch.y*patch.y);
		float seam=min(min(abs(abs(band)-.34),1.-abs(patch.y)),1.-abs(patch.x));
		vec3 leather=vec3(.90,.91,.84);
		if(family==1. && band<.34 || family==2. && band>.34){leather=vec3(.10,.65,.65);}
		if(family==0. && band<-.34 || family==2. && band<-.34){leather=vec3(.99,.35,.115);}
		float light=.32+.72*max(0.,dot(n,normalize(vec3(-.55,.76,.7))));
		float grain=fract(sin(dot(floor(FRAGCOORD.xy),vec2(12.9898,78.233)))*43758.5453);
		base=mix(vec3(.045,.085,.102),leather,smoothstep(.001,.022,seam))*light + (grain-.5)*.025;
	}
	float sweep=exp(-70.*abs(p.x+p.y*.26-mod(TIME*.11,2.4)+.65));
	base+=vec3(.012,.043,.038)*sweep;
	COLOR=vec4(base,COLOR.a);
}
