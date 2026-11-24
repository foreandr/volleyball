shader_type spatial;
render_mode cull_disabled;
uniform vec4 fabric : source_color;
uniform vec4 trim : source_color;
uniform sampler2D lettering : source_color,filter_linear_mipmap_anisotropic;
uniform bool jacket = false;

uniform vec3 inertia;
uniform vec2 arm_lift;
uniform sampler2D knit_surface : repeat_enable,filter_linear_mipmap_anisotropic;
uniform vec3 sleeve_offset[160];
vec3 sleeve_motion(vec3 bind){
	float ring=clamp((abs(bind.x)-.195)/.039,0.,3.999);
	int row=int(floor(ring));
	float phase_angle=fract(atan(bind.z+.035,bind.y-1.48)/6.2831853+1.)*16.;
	int j=int(floor(phase_angle))%16;
	int base=(bind.x>0.?0:80)+row*16;
	vec3 a=mix(sleeve_offset[base+j],sleeve_offset[base+(j+1)%16],fract(phase_angle));
	vec3 b=mix(sleeve_offset[base+16+j],sleeve_offset[base+16+(j+1)%16],fract(phase_angle));
	return mix(a,b,fract(ring));
}
float tension_fold(vec3 bind){
	float x=abs(bind.x);
	float tension=bind.x>0.?arm_lift.x:arm_lift.y;
	float diagonal=bind.y-1.27-x*.75;
	float panel=smoothstep(.035,.12,x)*(1.-smoothstep(.22,.31,x));
	return tension*panel*exp(-diagonal*diagonal/.011)*sin(diagonal*86.);
}
// Short compression folds form on the underside of a raised sleeve.
float sleeve_crease(vec3 bind){
	float x=abs(bind.x);
	float lift=bind.x>0.?arm_lift.x:arm_lift.y;
	float underside=1.-smoothstep(1.46,1.53,bind.y);
	float envelope=smoothstep(.195,.235,x)*(1.-smoothstep(.305,.354,x));
	float line=x+.32*(bind.y-1.46)+.25*bind.z;
	float fold=sin((line-.23)*132.);
	return .0038*lift*smoothstep(1.37,1.42,bind.y)*underside*envelope*fold;
}
uniform float motion=0.;
uniform float dampness;
uniform float phase=0.;
varying vec3 rest;
// A shallow overlapping storm flap spans the back between the armholes.
float back_flap(vec3 p){
	float edge=1.386+.030*smoothstep(.025,.19,abs(p.x));
	return (1.-smoothstep(.155,.205,abs(p.x)))*(1.-smoothstep(-.055,-.016,p.z))
		*smoothstep(edge-.003,edge+.002,p.y)*(1.-smoothstep(edge+.006,edge+.052,p.y));
}
void vertex(){
	// Capture the undistorted garment coordinates from UV2 for animated tailoring.
	rest=vec3(UV2, COLOR.r*0.6-0.3);
	float freedom=1.-smoothstep(1.04,1.48,rest.y);
	VERTEX+=freedom*(inertia*.38+NORMAL*max(0.,dot(inertia,NORMAL))*.85)*(jacket?.65:1.);
	if(!jacket){
		float arm=smoothstep(.16,.27,abs(rest.x))*smoothstep(1.27,1.38,rest.y);
		float free_edge=mix(1.-smoothstep(1.02,1.54,rest.y),.56*smoothstep(.19,.39,abs(rest.x)),arm);
		float angle=atan(rest.x,rest.z+.02);
		float pleat=sin(angle*8.+rest.y*8.+phase);
		float wave=sin(angle*4.+rest.y*12.-TIME*10.+phase);
		float ripple=sin(angle*7.-TIME*15.+phase*.7);
		// A doubled hem hangs under its own weight. Keep the broader fold
		// above it and damp the small ripples at the stitched edge.
		float facing=max(1.-smoothstep(.16,.89,COLOR.a),1.-smoothstep(1.05,1.14,rest.y))*(1.-arm);
		float drape=mix(.016,.012,arm)+.014*pleat+motion*(.023+.044*wave+.013*ripple);
		drape=mix(drape,.003+.006*pleat+motion*(.008+.019*wave),facing);
		VERTEX+=NORMAL*(free_edge*drape*(1.-arm)+.0035*tension_fold(rest)+sleeve_crease(rest))+sleeve_motion(rest)*arm;
		{
			VERTEX.y+=(1.-arm)*free_edge*(-.018-.014*facing+motion*(.023*wave+.012*ripple)*(1.-.48*facing));
		}
	}
	{
		float folds=.0018*sin(rest.x*115.0+rest.z*38.0);
		float ease=jacket ? (1.-smoothstep(1.19,1.49,rest.y))*(1.-smoothstep(.2,.32,abs(rest.x))) : 0.;
		// Gather the loose shell into the narrower elastic at the wrist.
		float cuff=smoothstep(.625,.65,abs(rest.x));
		float gather=sin(rest.x*168.+rest.z*51.)*exp(-pow(abs(abs(rest.x)-.616)/.031,2.));
		float shell_clearance=jacket ? (.009-.012*cuff+.0045*gather+.006*back_flap(rest)) : mix(.0015,.009,smoothstep(.12,.95,COLOR.g));
		VERTEX+=NORMAL*(shell_clearance+folds+.022*ease+(jacket ? motion*(.006+.012*ease)*sin(rest.x*24.+rest.y*15.-TIME*12.) : 0.));
	}
}
void fragment(){
	float x=abs(rest.x), y=rest.y;
	float neckline=1.572-.041*(1.-smoothstep(.022,.108,x))*smoothstep(-.085,.09,rest.z);
	{
		if(jacket){
			if(x>.69 || y<1.012 || y>neckline) discard;
		}
	}

	float side=smoothstep(.18,.24,x)*(1.-smoothstep(1.29,1.43,y));
	vec3 base=mix(fabric.rgb,trim.rgb,side*.23);
	float print_coverage=0.;
	if(jacket){

		float seam_y=1.404+.022*smoothstep(.05,.24,x);
		float seam=1.-smoothstep(.0008,.0035,abs(y-seam_y));
		float hem=1.-smoothstep(1.025,1.04,y);
		base=mix(vec3(.052,.099,.080),vec3(.070,.128,.101),smoothstep(seam_y-.003,seam_y+.003,y));
		base*=1.-.24*seam-.28*hem;
		float flap=back_flap(rest);
		float underlap=max(0.,back_flap(rest+vec3(0.,.006,0.))-flap);
		base*=1.+.12*flap-.38*underlap;
		// The coach windbreaker has contrasting woven shoulder inserts.
		float yoke_edge=1.49-.075*smoothstep(.10,.39,x);
		float sleeve_span=smoothstep(.07,.15,x)*(1.-smoothstep(.52,.59,x));
		float insert=smoothstep(yoke_edge-.002,yoke_edge+.002,y)*sleeve_span;
		float piping=(1.-smoothstep(.0014,.0032+fwidth(y),abs(y-yoke_edge)))*sleeve_span;
		base=mix(base,vec3(.081,.164,.129),insert*.87);
		base=mix(base,vec3(.22,.30,.25),piping*.68);
		float neck_binding=smoothstep(neckline-.013,neckline-.010,y)*(1.-smoothstep(.092,.122,x));
		float neck_stitch=1.-smoothstep(.0007,.0025,abs(y-neckline+.010));
		base=mix(base,vec3(.032,.066,.050)*(.91+.19*neck_stitch),neck_binding);
		float wrist=smoothstep(.637,.641,x);
		float cuff_join=1.-smoothstep(.001,.0035,abs(x-.639));
		float ribs=cos(y*1020.+rest.z*610.)*(1.-smoothstep(.0008,.003,fwidth(y)+fwidth(rest.z)));
		base*=1.-wrist*(.34-.10*ribs)-.25*cuff_join;
		float zipper=(1.-smoothstep(.0015,.003,abs(rest.x)))*step(.065,rest.z);
		float front=smoothstep(.015,.075,rest.z);
		float tape=(1.-smoothstep(.005,.008,abs(rest.x)))*front;
		base=mix(base,base*.46,tape);
		float teeth=.62+.28*cos(y*2400.)*(1.-smoothstep(.0005,.002,fwidth(y)));
		base=mix(base,vec3(.50,.53,.50)*teeth,zipper);
		// Slanted welt pocket openings sit in the lower front panels.
		float pocket_x=.103+.39*(y-1.14);
		float pocket=abs(x-pocket_x);
		float length_mask=smoothstep(1.085,1.10,y)*(1.-smoothstep(1.235,1.25,y))*front;
		float welt=(1.-smoothstep(.006,.010,pocket))*length_mask;
		float opening=(1.-smoothstep(.001,.0035,pocket))*length_mask;
		base*=1.+.15*welt-.64*opening;
	}else{
		// Across the back the raglan seam runs from neckline to underarm.
		// Use bind coordinates so the seam bends with the panel and printing.
		float seam_x=.071+.61*(1.55-y)+.7*(1.55-y)*(1.55-y);
		float span=smoothstep(1.32,1.36,y)*(1.-smoothstep(1.542,1.56,y));
		float dist=abs(x-seam_x);
		float aa=max(.00065,fwidth(dist));
		float join=(1.-smoothstep(.0007,.0007+aa,dist))*span;
		float stitch_line=(1.-smoothstep(.00055,.00055+aa,abs(dist-.0026)))*span;
		float loops=.70+.30*cos(y*1150.)*(1.-smoothstep(.001,.004,fwidth(y)));
		base*=1.-.26*join+.095*stitch_line*loops;
		float shoulder_panel=smoothstep(seam_x-aa,seam_x+aa,x)*span;
		base*=1.-.065*shoulder_panel;
		// The breathable side insert follows the torso depth on either side.
		float insert_width=mix(.048,.084,smoothstep(1.04,1.38,y));
		float border=abs(rest.z+.023)-insert_width;
		float insert=smoothstep(.115,.17,x)*(1.-smoothstep(1.36,1.42,y));
		float panel=insert*(1.-smoothstep(-.002,.002,border));
		vec2 knit_cell=vec2(rest.z/.0034,y/.004);
		float resolved=1.-smoothstep(.2,.7,max(fwidth(knit_cell.x),fwidth(knit_cell.y)));
		knit_cell.x+=.5*mod(floor(knit_cell.y),2.);
		float eyelet=1.-smoothstep(.12,.31,length(fract(knit_cell)-.5));
		base=mix(base,base*.74, panel);
		base*=1.-panel*(.035+.20*(eyelet-.15)*resolved);
		float binding=1.-smoothstep(.001,.003+fwidth(border),abs(border));
		base*=1.-.18*insert*binding;
		float cuff=1.-smoothstep(.18,.40,COLOR.g);
		// The sleeve opening carries a narrow contrast welt inside a rib-knit band.
		float cuff_mm=COLOR.g*35.;
		float cuff_aa=max(.32,fwidth(cuff_mm));
		float welt=1.-smoothstep(2.3,2.3+cuff_aa,abs(cuff_mm-8.0));
		float knit_phase=atan(rest.z+.035,rest.y-1.46)*96.;
		float cuff_rib=cos(knit_phase)*(1.-smoothstep(.55,2.8,fwidth(knit_phase)));
		base=mix(base,trim.rgb*(.90+.10*cuff_rib),.75*cuff);
		base=mix(base,mix(vec3(.78,.73,.63),base,.32),welt*.88);
		// Distance to the fitted neckline follows its asymmetric front and back.
		float neck_band=1.-smoothstep(.31,.41,COLOR.b);
		float seam=1.-smoothstep(.028,.082,abs(COLOR.b-.37));
		float ribs=cos(atan(rest.z+.018,rest.x)*112.);
		float resolved_ribs=1.-smoothstep(.001,.004,fwidth(rest.x)+fwidth(rest.z));
		base=mix(base,trim.rgb*(1.+.085*ribs*resolved_ribs),neck_band);
		base*=1.-.22*seam;
		// Print only the torso panels. Blending mirrored UVs collapses the
		// number onto the side of the jersey as the depth passes through zero.
		float rear=1.-step(0.,rest.z);
		vec2 uv=vec2(.5+mix(rest.x,-rest.x,rear)/mix(.205,.262,rear),(1.425-y)/mix(.115,.144,rear));
		if(x<.136 && abs(rest.z)>.035 && all(greaterThanEqual(uv,vec2(0.))) && all(lessThanEqual(uv,vec2(1.)))){
			vec4 ink=texture(lettering,uv);
			// A narrow backing print holds the number outline over bright folds.
			vec2 inset=vec2(.009,.014);
			float border=max(max(texture(lettering,uv+vec2(inset.x,0.)).a,texture(lettering,uv-vec2(inset.x,0.)).a),
				max(texture(lettering,uv+vec2(0.,inset.y)).a,texture(lettering,uv-vec2(0.,inset.y)).a));
			base=mix(base,trim.rgb*.58,border);
			base=mix(base,vec3(.95,.90,.77),ink.a);
			print_coverage=max(ink.a,border);
		}
	}
	float weave=sin(rest.x*2100.)*sin(y*2500.);
	float fade=1.-smoothstep(.0001,.0015,max(fwidth(rest.x),fwidth(y)));
	ALBEDO=base*(1.+.04*weave*fade);
	float knit=sin(rest.x*1650.+sin(y*1300.))*cos(y*1300.);
	if(!jacket){
		float from_edge=COLOR.a*.040;
		float twin=min(abs(from_edge-.010),abs(from_edge-.014));
		float seam=1.-smoothstep(.00055,.0014+fwidth(from_edge),twin);
		float facing=1.-smoothstep(.013,.018,from_edge);
		ALBEDO*=1.-.095*facing-.21*seam;
	}
	ROUGHNESS=.79+.075*knit*fade;
	if(!jacket){
		vec3 grain=vec3(.10*knit*fade,.07*weave*fade,1.);
		NORMAL_MAP=normalize(grain)*.5+.5;
	}
	// A raised arm pulls diagonal folds towards the armhole. Loose flank
	// folds settle lower and trail changes in the direction of travel.
	float flank=smoothstep(.065,.17,x)*(1.-smoothstep(.22,.34,x));
	float diagonal=y-1.27-x*.75;
	float lift=rest.x>0.?arm_lift.x:arm_lift.y;
	float ridge=sin(diagonal*91.+rest.z*12.);
	float crease=flank*lift*exp(-diagonal*diagonal/.009)*ridge*.0028;
	if(!jacket) crease+=sleeve_crease(rest);
	float loose=(1.-smoothstep(1.04,1.32,y))*flank;
	crease+=loose*.0032*sin(y*58.+x*35.+rest.z*18.+inertia.x*32.);
	vec3 dx=dFdx(VERTEX),dy=dFdy(VERTEX);
	vec3 u=cross(dy,NORMAL),v=cross(NORMAL,dx);
	float det=dot(dx,u);
	vec3 slope=u*dFdx(crease)+v*dFdy(crease);
	if(abs(det)>1e-10) NORMAL=normalize(NORMAL-slope/det);
	float pull=tension_fold(rest);
	float shoulder=smoothstep(1.34,1.48,y)*smoothstep(.07,.20,x);
	float fold=sin(x*72.+y*43.+sin(y*21.+phase)*.8);
	float stitch=1.-smoothstep(.001,.003,abs(y-(1.48-.16*x)));
	float thread=.55+.45*cos(x*720.)*(1.-smoothstep(.001,.004,fwidth(x)));
	ALBEDO*=1.-.1*shoulder*stitch*thread;
	NORMAL_MAP=normalize(vec3(.09*knit*fade+.09*shoulder*fold-.09*pull,.06*weave*fade+.13*pull,1.))*.5+.5;
	vec2 back_uv=vec2(rest.x/(.045+.14*dampness),(y-1.37)/(.095+.20*dampness));
	vec2 axilla=vec2((x-.208)/(.025+.095*dampness),(y-1.403)/(.045+.13*dampness));
	float spread=max(exp(-dot(back_uv,back_uv))*(1.-smoothstep(-.065,.0,rest.z)),exp(-dot(axilla,axilla)));
	float wick=.035*sin(y*99.+rest.x*83.)+.022*sin(y*181.-rest.x*119.);
	// Sweat follows the spine and wicks down from the front neckline.
	float rear=1.-smoothstep(-.055,.018,rest.z);
	vec2 spine=vec2(rest.x/(.024+.042*dampness),(y-1.27)/(.095+.19*dampness));
	vec2 sternum=vec2(rest.x/(.033+.079*dampness),(y-1.47)/(.048+.14*dampness));
	spread=max(spread,max(rear*exp(-dot(spine,spine)),(1.-rear)*exp(-dot(sternum,sternum))*.85));
	float wet=dampness*smoothstep(.16,.56,spread+wick)*(1.-.91*print_coverage);
	ALBEDO*=1.-.47*wet;
	ROUGHNESS=mix(ROUGHNESS,.52,wet);
	if(!jacket){
		vec3 yarn=texture(knit_surface,UV*31.).rgb;
		float cuff=1.-smoothstep(.20,.42,COLOR.g);
		float stitches=(1.-smoothstep(.035,.11,abs(COLOR.g-.28)))*(.6+.4*yarn.b);
		ALBEDO*=mix(.97,1.03,yarn.b)*(1.-.12*cuff-.18*stitches);
		NORMAL_MAP.xy+=(yarn.rg-.5)*.28;
		ROUGHNESS=clamp(ROUGHNESS+.08*(yarn.b-.5)-.025*cuff,0.,1.);
	}
	// Transfer film bridges the yarn valleys while retaining broad folds.
	NORMAL_MAP.xy=mix(NORMAL_MAP.xy,vec2(.5),.39*print_coverage);
	ROUGHNESS=mix(ROUGHNESS,.53,print_coverage);
	RIM=.16;
	RIM_TINT=.32;
	SPECULAR=.28;
}
