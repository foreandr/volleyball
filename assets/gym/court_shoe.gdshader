shader_type spatial;
uniform sampler2D shoe_atlas : source_color,filter_linear_mipmap_anisotropic;
uniform vec4 tint : source_color = vec4(1.);
varying vec3 shoe;

void vertex(){
	shoe=VERTEX;
}

void fragment(){
	vec3 upper=texture(shoe_atlas,UV).rgb*tint.rgb;
	// Follow the toe rocker as the sole turns up under the forefoot.
	float height=shoe.y-.011*smoothstep(.09,.18,shoe.z);
	float rubber=1.-smoothstep(.012,.016,height);
	float foam=(1.-rubber)*(1.-smoothstep(.026,.035,height));
	float chevron=(shoe.z+abs(shoe.x)*.68)*960.;
	float resolution=1.-smoothstep(.8,3.1,fwidth(chevron));
	float groove=smoothstep(.38,.9,cos(chevron))*resolution;
	vec3 outsole=mix(vec3(.115,.101,.085),vec3(.055,.048,.040),groove);
	ALBEDO=mix(upper,outsole,rubber*.78);
	float bead=1.-smoothstep(.0004,.0014+fwidth(height),abs(height-.022));
	ALBEDO*=1.-foam*.15*bead;
	ROUGHNESS=mix(mix(.74,.88,foam),.84,rubber);
	SPECULAR=mix(.26,.34,rubber);
}
