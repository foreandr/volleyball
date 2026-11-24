shader_type spatial;
uniform vec3 elbow;
uniform vec3 forearm;
varying vec3 bind;
void vertex(){
	bind=vec3(UV2,COLOR.r*.6-.3)-elbow;
	VERTEX+=NORMAL*.0028;
}
void fragment(){
	float along=dot(bind,forearm)/dot(forearm,forearm);
	if(along<.095 || along>.94 || length(bind-along*forearm)>.085) discard;
	float cuff=1.-smoothstep(.028,.046,min(along-.095,.94-along));
	float phase=along*510.+bind.z*410.;
	float ribs=cos(phase)*(1.-smoothstep(.65,2.6,fwidth(phase)));
	ALBEDO=mix(vec3(.021,.030,.036),vec3(.042,.051,.055),cuff)*(.96+.09*ribs);
	// Jacquard compression bands follow the circumference of the tapered forearm.
	vec3 radial=bind-along*forearm;
	float chevron=along+.64*abs(radial.z);
	float distance_to_band=min(abs(chevron-.44),abs(chevron-.52));
	float band=1.-smoothstep(.012,.016+fwidth(chevron),distance_to_band);
	float edge=1.-smoothstep(.002,.005+fwidth(chevron),abs(distance_to_band-.012));
	ALBEDO=mix(ALBEDO,vec3(.057,.071,.078)*(.94+.12*ribs),band);
	ALBEDO*=1.-.16*edge;
	ROUGHNESS=.81+.08*cuff-.12*band;
}
