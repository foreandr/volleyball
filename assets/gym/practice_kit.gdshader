shader_type spatial;
render_mode cull_disabled;
uniform vec4 fabric : source_color;
uniform vec4 trim : source_color;
uniform sampler2D lettering : source_color,filter_linear_mipmap_anisotropic;
uniform bool jacket = false;
uniform bool sleeves = false;
uniform float motion=0.;
uniform float phase=0.;
varying vec3 rest;
void vertex(){
	// Capture the undistorted garment coordinates from UV2 for animated tailoring.
	rest=vec3(UV2, COLOR.r*0.6-0.3);
	if(!jacket){
		float free_edge=sleeves ? smoothstep(.22,.33,abs(rest.x)) : 1.-smoothstep(1.02,1.46,rest.y);
		float folds=sin(rest.x*45.+rest.y*17.+rest.z*19.+phase);
		float wave=sin(rest.y*26.+rest.x*32.-TIME*13.+phase);
		VERTEX+=NORMAL*free_edge*(.008+.005*folds+motion*(.012+.017*wave));
		VERTEX.y+=free_edge*motion*.008*wave;
	}
	if(sleeves){
		float folds=.0018*sin(rest.x*115.0+rest.z*38.0);
		VERTEX+=NORMAL*(.009+folds);
	}
}
void fragment(){
	float x=abs(rest.x), y=rest.y;
	if(sleeves){
		if(jacket){
			if((x<.185 && y<1.50) || x>.69 || y<.98 || y>1.565 || (x<.069 && y>1.52)) discard;
		}else if(x>.333 || y<1.15 || y>1.565 || (x<.14 && y<1.48)) discard;
	}
	if(!sleeves && !jacket && y<1.045)discard;
	float side=smoothstep(.142,.154,x);
	vec3 base=mix(fabric.rgb,trim.rgb,side*.54);
	if(jacket){
		float shoulder=smoothstep(1.41,1.42,y);
		base=mix(vec3(.056,.107,.085),vec3(.064,.117,.094),shoulder);
		float zipper=(1.-smoothstep(.0015,.003,abs(rest.x)))*step(.065,rest.z);
		base=mix(base,vec3(.50,.53,.50),zipper);
	}else{
		float piping=1.-smoothstep(.0015,.004,abs(x-.145));
		base=mix(base,trim.rgb,piping);
		vec2 uv=vec2(.5+rest.x/.247,(1.425-y)/.135);
		if(all(greaterThanEqual(uv,vec2(0.))) && all(lessThanEqual(uv,vec2(1.)))){
			vec4 ink=texture(lettering,uv);
			base=mix(base,vec3(.95,.90,.77),ink.a);
		}
	}
	float weave=sin(rest.x*2100.)*sin(y*2500.);
	float fade=1.-smoothstep(.0001,.0015,max(fwidth(rest.x),fwidth(y)));
	ALBEDO=base*(1.+.04*weave*fade);
	float knit=sin(rest.x*1650.+sin(y*1300.))*cos(y*1300.);
	if(!jacket && !sleeves){
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
