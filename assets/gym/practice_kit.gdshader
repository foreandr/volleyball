shader_type spatial;
render_mode cull_disabled;
uniform vec4 fabric : source_color;
uniform vec4 trim : source_color;
uniform sampler2D lettering : source_color,filter_linear_mipmap_anisotropic;
uniform bool jacket = false;

uniform vec3 inertia;
uniform float motion=0.;
uniform float phase=0.;
varying vec3 rest;
void vertex(){
	// Capture the undistorted garment coordinates from UV2 for animated tailoring.
	rest=vec3(UV2, COLOR.r*0.6-0.3);
	float freedom=1.-smoothstep(1.04,1.48,rest.y);
	VERTEX+=freedom*(inertia*.38+NORMAL*max(0.,dot(inertia,NORMAL))*.85)*(jacket?.65:1.);
	if(!jacket){
		float arm=smoothstep(.16,.27,abs(rest.x));
		float free_edge=mix(1.-smoothstep(1.02,1.54,rest.y),.56*smoothstep(.19,.39,abs(rest.x)),arm);
		float angle=atan(rest.x,rest.z+.02);
		float pleat=sin(angle*8.+rest.y*8.+phase);
		float wave=sin(angle*4.+rest.y*12.-TIME*10.+phase);
		float ripple=sin(angle*7.-TIME*15.+phase*.7);
		float drape=.062+.014*pleat+motion*(.023+.044*wave+.013*ripple);
		VERTEX+=NORMAL*free_edge*drape;
		{
			VERTEX.y+=(1.-arm)*free_edge*(-.095+motion*(.023*wave+.012*ripple));
		}
	}
	{
		float folds=.0018*sin(rest.x*115.0+rest.z*38.0);
		float ease=jacket ? (1.-smoothstep(1.19,1.49,rest.y))*(1.-smoothstep(.2,.32,abs(rest.x))) : 0.;
		VERTEX+=NORMAL*(.009+folds+.022*ease+(jacket ? motion*(.006+.012*ease)*sin(rest.x*24.+rest.y*15.-TIME*12.) : 0.));
	}
}
void fragment(){
	float x=abs(rest.x), y=rest.y;
	{
		if(jacket){
			if(x>.69 || y<1.012 || y>1.57 || (x<.072 && y>1.538)) discard;
		}else if(x>.394 || y<1.045 || y>1.563-.055*(1.-smoothstep(.045,.109,x))*smoothstep(-.075,.075,rest.z)) discard;
	}

	float side=smoothstep(.18,.24,x)*(1.-smoothstep(1.29,1.43,y));
	vec3 base=mix(fabric.rgb,trim.rgb,side*.23);
	if(jacket){

		float seam_y=1.404+.022*smoothstep(.05,.24,x);
		float seam=1.-smoothstep(.0008,.0035,abs(y-seam_y));
		float hem=1.-smoothstep(1.025,1.04,y);
		base=mix(vec3(.052,.099,.080),vec3(.070,.128,.101),smoothstep(seam_y-.003,seam_y+.003,y));
		base*=1.-.24*seam-.28*hem;
		float zipper=(1.-smoothstep(.0015,.003,abs(rest.x)))*step(.065,rest.z);
		base=mix(base,vec3(.50,.53,.50),zipper);
	}else{
		float cuff=1.-smoothstep(.002,.005,abs(x-.386));
		base*=1.-.12*cuff;
		float collar=1.563-.055*(1.-smoothstep(.045,.109,x))*smoothstep(-.075,.075,rest.z);
		base=mix(base,trim.rgb,1.-smoothstep(.008,.012,collar-y));
		float rear=1.-smoothstep(-.05,.02,rest.z);
		vec2 uv=vec2(.5+mix(rest.x,-rest.x,rear)/mix(.205,.262,rear),(1.425-y)/mix(.115,.144,rear));
		if(all(greaterThanEqual(uv,vec2(0.))) && all(lessThanEqual(uv,vec2(1.)))){
			vec4 ink=texture(lettering,uv);
			base=mix(base,vec3(.95,.90,.77),ink.a);
		}
	}
	float weave=sin(rest.x*2100.)*sin(y*2500.);
	float fade=1.-smoothstep(.0001,.0015,max(fwidth(rest.x),fwidth(y)));
	ALBEDO=base*(1.+.04*weave*fade);
	float knit=sin(rest.x*1650.+sin(y*1300.))*cos(y*1300.);
	if(!jacket){
		float seam=1.-smoothstep(.0008,.0028,abs(y-1.054));
		ALBEDO*=1.-.18*seam;
	}
	ROUGHNESS=.79+.075*knit*fade;
	if(!jacket){
		vec3 grain=vec3(.10*knit*fade,.07*weave*fade,1.);
		NORMAL_MAP=normalize(grain)*.5+.5;
	}
	SPECULAR=.28;
}
