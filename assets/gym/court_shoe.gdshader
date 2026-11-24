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
	// Low-profile abrasion overlay wraps around the toe and rises at the sides.
	float toe=smoothstep(.074,.146,shoe.z);
	float guard_height=.028+toe*.015+smoothstep(.021,.049,abs(shoe.x))*.007;
	float guard=toe*smoothstep(.024,.029,height)*(1.-smoothstep(guard_height-.001,guard_height+.001,height));
	float weld=1.-smoothstep(.0005,.0016+fwidth(height),abs(height-guard_height+.002));
	ALBEDO=mix(ALBEDO,mix(upper*.68,counter_color.rgb,.40)*(.91+.15*weld),guard);
	// Woven quarter panels sit between the heel counter and bonded toe guard.
	float quarter=smoothstep(-.052,-.027,shoe.z)*(1.-smoothstep(.087,.111,shoe.z))
		*smoothstep(.031,.042,height)*(1.-smoothstep(.067,.080,height))
		*smoothstep(.021,.035,abs(shoe.x));
	vec2 cell=vec2(shoe.z/.0038,height/.0031);
	float detail=1.-smoothstep(.25,.82,max(fwidth(cell.x),fwidth(cell.y)));
	cell.x+=.5*mod(floor(cell.y),2.);
	float hole=1.-smoothstep(.15,.39,length(fract(cell)-.5));
	vec3 mesh_color=mix(upper,vec3(.076,.081,.083),.58)*(.97-.52*hole*detail);
	ALBEDO=mix(ALBEDO,mesh_color,quarter*(1.-guard)*(1.-counter));
	// Two bonded supports fan out from the lace row into the midsole.
	float rise=clamp((height-.027)/.052,0.,1.);
	float forward_band=abs(shoe.z-mix(.085,.042,rise));
	float rear_band=abs(shoe.z-mix(-.008,.031,rise));
	float band_distance=min(forward_band,rear_band);
	float band_width=mix(.006,.0038,rise);
	float support=(1.-smoothstep(band_width-.001,band_width+fwidth(band_distance),band_distance))
		*smoothstep(.023,.034,abs(shoe.x))*smoothstep(.024,.029,height)*(1.-smoothstep(.075,.082,height));
	float bevel=smoothstep(band_width-.0025,band_width,band_distance);
	ALBEDO=mix(ALBEDO,mix(counter_color.rgb,upper,.38)*(.79+.23*bevel),support);
	float bead=1.-smoothstep(.0004,.0014+fwidth(height),abs(height-.022));
	// Compression-molded foam forms a continuous sidewall above the rubber tread.
	float sculpt=sin(height*1380.+3.*smoothstep(-.09,.11,shoe.z));
	float resolved=1.-smoothstep(.7,2.6,fwidth(height)*1380.);
	vec3 midsole=mix(vec3(.51,.49,.45),tint.rgb,.14)*(.96+.055*sculpt*resolved);
	ALBEDO=mix(ALBEDO,midsole,foam*.91);
	ALBEDO*=1.-foam*.19*bead;
	ROUGHNESS=mix(mix(.74,.88,foam),.84,rubber);
	ROUGHNESS=mix(ROUGHNESS,.44,counter);
	ROUGHNESS=mix(ROUGHNESS,.49,guard);
	ROUGHNESS=mix(ROUGHNESS,.51,support*(1.-foam));
	SPECULAR=mix(mix(.26,.34,rubber),.46,counter);
}
