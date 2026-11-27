shader_type spatial;
varying vec3 pos;
varying vec3 local;
void vertex(){pos=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;local=VERTEX;}
float hash(vec2 p){return fract(sin(dot(p,vec2(37.41,81.63)))*438.74);}
float noise2(vec2 p){
	vec2 i=floor(p), f=fract(p); f=f*f*(3.-2.*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+1.),f.x),f.y);
}
void fragment(){
	float slat=floor((local.x+.325)/.1625);
	float seed=hash(vec2(slat,floor(abs(pos.x)*1.48)));
	float warp=noise2(vec2(pos.z*.8,seed*43.));
	float grain=noise2(vec2(pos.z*2.,pos.x*113.+warp*4.));
	float seam=abs(fract((local.x+.325)/.1625)-.5);
	float groove=smoothstep(.477,.498,seam);
	float joint=smoothstep(.495,.499,abs(fract((pos.z+seed)/3.75)-.5));
	float worn=smoothstep(.27,.325,abs(local.x))*noise2(pos.xz*34.);
	vec3 oak=mix(vec3(.010,.011,.013),vec3(.034,.035,.039),.25*seed+.75*grain);
	ALBEDO=mix(oak,vec3(.065,.063,.061),worn*.57)*(1.-.38*max(groove,joint));
	vec2 hole=vec2(abs(local.x)-.246,mod(pos.z+1.,2.)-1.);
	float bolt=1.-smoothstep(.009,.016,length(hole));
	ALBEDO=mix(ALBEDO,vec3(.18,.19,.175),bolt);
	METALLIC=bolt*.8;
	CLEARCOAT=.33*(1.-worn)*(1.-bolt);
	CLEARCOAT_ROUGHNESS=.19+.28*worn;
	ROUGHNESS=.43+.19*grain+.25*worn;
}
