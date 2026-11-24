shader_type spatial;
uniform sampler2D shoe_atlas : source_color,filter_linear_mipmap_anisotropic;
uniform vec4 tint : source_color = vec4(1.);
uniform vec4 counter_color : source_color;
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
	// The heel counter hugs the cup and tapers into two lower side wings.
	float wing=smoothstep(-.123,.012,shoe.z);
	float lip=mix(.076,.033,wing);
	float counter=smoothstep(.025,.030,height)*(1.-smoothstep(lip-.002,lip+.002,height))
		*(1.-smoothstep(-.024,.012,shoe.z));
	float edge=1.-smoothstep(.0006,.002+fwidth(height),abs(height-lip+.003));
	ALBEDO=mix(ALBEDO,counter_color.rgb*(.88+.12*edge),counter*.87);
	float bead=1.-smoothstep(.0004,.0014+fwidth(height),abs(height-.022));
	ALBEDO*=1.-foam*.15*bead;
	ROUGHNESS=mix(mix(.74,.88,foam),.84,rubber);
	ROUGHNESS=mix(ROUGHNESS,.44,counter);
	SPECULAR=mix(mix(.26,.34,rubber),.46,counter);
}
