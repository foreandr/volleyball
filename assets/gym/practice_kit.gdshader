shader_type spatial;
render_mode cull_disabled;
uniform vec4 fabric : source_color;
uniform vec4 trim : source_color;
uniform bool captain = false;
uniform sampler2D lettering : source_color,filter_linear_mipmap_anisotropic;
uniform bool mirror_print = false;
uniform sampler2D team_crest : source_color,filter_linear_mipmap_anisotropic;
uniform vec3 hem_particles[12];
uniform vec3 strap_offsets[4];
uniform float hem_shift;
uniform float signal_lift = 0.;
uniform bool tucked;
uniform vec4 waist_color : source_color;
uniform bool jacket = false;

uniform vec3 inertia;
uniform vec2 arm_lift;
uniform sampler2D knit_surface : repeat_enable,filter_linear_mipmap_anisotropic;
float tension_fold(vec3 bind){
	float x=abs(bind.x);
	float tension=bind.x>0.?arm_lift.x:arm_lift.y;
	float diagonal=bind.y-1.27-x*.75;
	float panel=smoothstep(.035,.12,x)*(1.-smoothstep(.22,.31,x));
	return tension*panel*exp(-diagonal*diagonal/.011)*sin(diagonal*86.);
}
// Shallow compression pleats fan down from the rear armhole.
float armhole_pleat(vec3 p){
	float side=abs(p.x);
	float lift=p.x>0.?arm_lift.x:arm_lift.y;
	float line=p.y-1.37-(side-.15)*1.35;
	float patch=smoothstep(.09,.17,side)*(1.-smoothstep(.22,.28,side))*(1.-smoothstep(-.04,.025,p.z));
	return .004*lift*patch*exp(-line*line/.004)*(.5+.5*cos(138.*line));
}
// The loose lower panel buckles above the hem when the near arm lifts.
float waist_fold(vec3 p){
	float side=abs(p.x);
	float reach=mix(arm_lift.y,arm_lift.x,smoothstep(-.06,.06,p.x));
	float line=p.y-1.107-side*.29-p.z*.14;
	float envelope=exp(-line*line/.003)*smoothstep(.045,.16,side);
	return .0065*reach*envelope*sin(line*98.);
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
	vec3 body_point=VERTEX;
	vec3 body_normal=normalize(NORMAL);
	if(!jacket){
		float lower=1.-smoothstep(1.02,1.29,rest.y);
		float section=fract(atan(rest.x,rest.z+.018)/6.2831853+1.)*12.;
		int i=int(floor(section))%12;
		VERTEX+=lower*(tucked?.12:1.)*mix(hem_particles[i],hem_particles[(i+1)%12],fract(section));
		VERTEX.y+=lower*((tucked?0.:hem_shift)+.13*signal_lift*smoothstep(-.03,.12,rest.z)*(1.-smoothstep(.08,.24,abs(rest.x))));
		if(tucked) VERTEX-=NORMAL*.043*(1.-smoothstep(1.04,1.14,rest.y));
	}
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
		// Moist fabric near the spine carries more weight and flutters less.
		float back=1.-smoothstep(-.065,.015,rest.z);
		float cling=back*dampness*exp(-pow(abs(rest.x)/(.054+.10*dampness),2.))
			*smoothstep(1.015,1.15,rest.y)*(1.-smoothstep(1.40,1.52,rest.y));
		float flutter=motion*(1.-.68*cling);
		float drape=mix(.016,.012,arm)+.014*pleat+flutter*(.023+.044*wave+.013*ripple);
		drape=mix(drape,.003+.006*pleat+motion*(.008+.019*wave),facing);
		VERTEX+=NORMAL*(free_edge*drape*(1.-arm)*(1.-.55*cling)+.0035*tension_fold(rest)+waist_fold(rest)+armhole_pleat(rest));
		{
			// Carry the reach down the side seam into the loose hem.
			// Interpolate across the torso so opposite arm heights stay continuous.
			float reach=mix(arm_lift.y,arm_lift.x,smoothstep(-.10,.10,rest.x));
			float side_pull=smoothstep(.035,.175,abs(rest.x));
			float seam_lift=.038*reach*side_pull*(1.-smoothstep(1.03,1.38,rest.y));
			VERTEX.y+=seam_lift+(1.-arm)*free_edge*(-.018-.014*facing-.014*cling+flutter*(.023*wave+.012*ripple)*(1.-.48*facing));
		}
	}
	{
		float folds=.0018*sin(rest.x*115.0+rest.z*38.0);
		float ease=jacket ? (1.-smoothstep(1.19,1.49,rest.y))*(1.-smoothstep(.2,.32,abs(rest.x))) : 0.;
		// Gather the loose shell into the narrower elastic at the wrist.
		float cuff=smoothstep(.625,.65,abs(rest.x));
		float gather=sin(rest.x*168.+rest.z*51.)*exp(-pow(abs(abs(rest.x)-.616)/.031,2.));
		float strap=smoothstep(1.455,1.55,rest.y)*(1.-smoothstep(.18,.22,abs(rest.x)));
		float shell_clearance=jacket ? (.009-.012*cuff+.0045*gather+.006*back_flap(rest)) : mix(.022,.004,strap);
		VERTEX+=NORMAL*(shell_clearance+folds+.022*ease+(jacket ? motion*(.006+.012*ease)*sin(rest.x*24.+rest.y*15.-TIME*12.) : 0.));
	}
	if(!jacket){
		// Both layers use the same body vertices and bone weights. Resolve inward
		// displacement against the animated skin after gravity, drag and tailoring.
		// The shorts are a second layer beneath an untucked hem.
		float waist=1.-smoothstep(1.055,1.19,rest.y);
		float rear_waist=(1.-smoothstep(-.07,.01,rest.z))*(1.-smoothstep(1.06,1.24,rest.y));
		float clearance=.0035+(tucked?.009:mix(.045,.014,rear_waist))*waist;
		// Anchor the back panel to the animated waist. Bound the combined hem,
		// flutter and inertia offsets while retaining the selected shirt length.
		vec3 travel=VERTEX-body_point;
		vec3 fitted=body_point+body_normal*clamp(dot(travel,body_normal),clearance,clearance+.006);
		fitted.y+=(tucked?0.:hem_shift)*(1.-smoothstep(1.02,1.29,rest.y));
		VERTEX=mix(VERTEX,fitted,rear_waist);
		if(tucked) VERTEX=mix(body_point+body_normal*clearance,VERTEX,smoothstep(1.064,1.115,rest.y));
		float shoulder=smoothstep(1.405,1.505,rest.y)*smoothstep(.058,.105,abs(rest.x));
		int strap=rest.x>0.?0:2;
		vec3 slide=mix(strap_offsets[strap+1],strap_offsets[strap],smoothstep(-.065,.045,rest.z));
		vec3 free_strap=VERTEX-body_point+slide;
		// Let the fabric slide along the skin; keep only a thin layer of ease over the trap.
		vec3 resting=body_point+free_strap-body_normal*dot(free_strap,body_normal)+body_normal*.0038;
		VERTEX=mix(VERTEX,resting,shoulder);
		float gap=dot(VERTEX-body_point,body_normal);
		VERTEX+=body_normal*max(0.,clearance-gap);
	}
}
void fragment(){
	float x=abs(rest.x), y=rest.y;
	float hemline=tucked?1.033:.997;
	if(!jacket && (y<hemline || x>.249)) discard;
	float neckline=1.572-.041*(1.-smoothstep(.022,.108,x))*smoothstep(-.085,.09,rest.z);
	{
		if(!jacket && y>neckline-.009) discard;
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
		base=mix(vec3(.144,.024,.038),vec3(.207,.034,.047),smoothstep(seam_y-.003,seam_y+.003,y));
		base*=1.-.24*seam-.28*hem;
		float flap=back_flap(rest);
		float underlap=max(0.,back_flap(rest+vec3(0.,.006,0.))-flap);
		base*=1.+.12*flap-.38*underlap;
		// The coach windbreaker has contrasting woven shoulder inserts.
		float yoke_edge=1.49-.075*smoothstep(.10,.39,x);
		float sleeve_span=smoothstep(.07,.15,x)*(1.-smoothstep(.52,.59,x));
		float insert=smoothstep(yoke_edge-.002,yoke_edge+.002,y)*sleeve_span;
		float piping=(1.-smoothstep(.0014,.0032+fwidth(y),abs(y-yoke_edge)))*sleeve_span;
		base=mix(base,vec3(.25,.045,.066),insert*.87);
		base=mix(base,vec3(.36,.16,.18),piping*.68);
		// Reinforcing yarns cross the shoulder panel in a small ripstop grid.
		vec2 ripstop=vec2(rest.x+.17*rest.z,rest.z-.36*y)/.006;
		vec2 thread_dist=abs(fract(ripstop+.5)-.5);
		vec2 footprint=max(fwidth(ripstop),vec2(.015));
		vec2 yarns=(1.-smoothstep(vec2(.035),vec2(.035)+footprint,thread_dist))
			*(1.-smoothstep(vec2(.16),vec2(.65),footprint));
		base*=1.+insert*(.15*max(yarns.x,yarns.y)+.06*yarns.x*yarns.y);
		float neck_binding=smoothstep(neckline-.013,neckline-.010,y)*(1.-smoothstep(.092,.122,x));
		float neck_stitch=1.-smoothstep(.0007,.0025,abs(y-neckline+.010));
		base=mix(base,vec3(.085,.015,.024)*(.91+.19*neck_stitch),neck_binding);
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
		// A brushed metal slider and open pull tab finish the center zipper.
		vec2 slider=vec2(rest.x,y-1.507);
		float aa=max(.00045,fwidth(rest.x)+fwidth(y));
		float body=1.-smoothstep(-aa,aa,length(slider/vec2(.0045,.006))*.0045-.0045);
		vec2 tab=vec2(rest.x-.20*(1.504-y),y-1.495);
		float tab_edge=length(vec2(tab.x,max(abs(tab.y)-.005,0.)));
		float loop=1.-smoothstep(.0007,.0007+aa,abs(tab_edge-.0031));
		float metal=max(body,loop)*front;
		base=mix(base,vec3(.37,.40,.38)*(.73+.45*smoothstep(-.003,.003,-tab.x)),metal);
		// Slanted welt pocket openings sit in the lower front panels.
		float pocket_x=.103+.39*(y-1.14);
		float pocket=abs(x-pocket_x);
		float length_mask=smoothstep(1.085,1.10,y)*(1.-smoothstep(1.235,1.25,y))*front;
		float welt=(1.-smoothstep(.006,.010,pocket))*length_mask;
		float opening=(1.-smoothstep(.001,.0035,pocket))*length_mask;
		base*=1.+.15*welt-.64*opening;
		// Embroider the school insignia on the left breast above the pocket.
		vec2 badge_uv=vec2(.5+(rest.x-.094)/.088,(1.453-y)/.088);
		if(rest.z>.008 && all(greaterThanEqual(badge_uv,vec2(0.))) && all(lessThanEqual(badge_uv,vec2(1.)))){
			vec4 badge=texture(team_crest,badge_uv);
			float stitch_phase=(rest.x*.68+y)*2500.;
			float thread=cos(stitch_phase)*(1.-smoothstep(.8,2.8,fwidth(stitch_phase)));
			base=mix(base,badge.rgb*(.93+.13*thread),badge.a);
		}
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
		// A tapered contrast stripe follows the front seam of each ventilated panel.
		float stripe_span=smoothstep(1.025,1.10,y)*(1.-smoothstep(1.30,1.39,y));
		float stripe_width=.008*stripe_span;
		float stripe_edge=rest.z+.023-insert_width;
		float stripe_aa=max(.0005,fwidth(stripe_edge));
		float stripe=smoothstep(-stripe_width-stripe_aa,-stripe_width,stripe_edge)
			*(1.-smoothstep(-stripe_aa,0.,stripe_edge));
		base=mix(base,mix(trim.rgb,vec3(.74,.65,.52),.58),insert*stripe*stripe_span);
		// The bound opening curves inward over the shoulder and down into the axilla.
		float armhole=x-(.165-.026*smoothstep(1.39,1.54,y)+.17*abs(rest.z));
		float cut=min(armhole,y-1.342+.22*(x-.16));
		if(cut>0.) discard;
		float binding_width=1.-smoothstep(.005,.009,-cut);
		base=mix(base,trim.rgb,binding_width*.82);
		// Distance to the fitted neckline follows its asymmetric front and back.
		float neck_band=1.-smoothstep(.007,.014,neckline-.009-y);
		float seam=1.-smoothstep(.028,.082,abs((neckline-.009-y-.012)*32.));
		float ribs=cos(atan(rest.z+.018,rest.x)*112.);
		float resolved_ribs=1.-smoothstep(.001,.004,fwidth(rest.x)+fwidth(rest.z));
		base=mix(base,trim.rgb*(1.+.085*ribs*resolved_ribs),neck_band);
		base*=1.-.22*seam;
		// Print only the torso panels. Blending mirrored UVs collapses the
		// number onto the side of the jersey as the depth passes through zero.
		// A small transfer below the back collar repeats the gym's falcon insignia.
		vec2 crest_uv=vec2(.5-rest.x/.062,(1.493-y)/.044);
		if(rest.z<-.04 && all(greaterThanEqual(crest_uv,vec2(0.))) && all(lessThanEqual(crest_uv,vec2(1.)))){
			vec4 crest=texture(team_crest,crest_uv);
			base=mix(base,crest.rgb,crest.a);
			print_coverage=crest.a;
		}
		float rear=1.-step(0.,rest.z);
		vec2 uv=vec2(.5+mix(rest.x,-rest.x,rear)/mix(.205,.262,rear),(1.425-y)/mix(.115,.144,rear));
		if(mirror_print) uv.x=1.-uv.x;
		if(captain && abs(rest.z)>.035 && abs(uv.x-.5)<.39 && uv.y>1.03 && uv.y<1.10){
			base=vec3(.95,.90,.77);
			print_coverage=1.;
		}
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
		float from_edge=y-hemline;
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
	if(!jacket) crease+=.52*waist_fold(rest)+armhole_pleat(rest);
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
	// As exertion builds, perspiration spreads sideways where the back meets the waistband.
	vec2 lumbar=vec2(rest.x/(.048+.105*dampness),(y-1.105-.018*cos(rest.x*18.))/.064);
	float waist_wet=rear*exp(-dot(lumbar,lumbar))*smoothstep(.28,.83,dampness);
	spread=max(spread,waist_wet);
	float wet=dampness*smoothstep(.16,.56,spread+wick)*(1.-.91*print_coverage);
	ALBEDO*=1.-.47*wet;
	ROUGHNESS=mix(ROUGHNESS,.52,wet);
	if(!jacket){
		vec3 yarn=texture(knit_surface,UV*31.).rgb;
		float cuff=0.;
		float stitches=0.;
		ALBEDO*=mix(.97,1.03,yarn.b)*(1.-.12*cuff-.18*stitches);
		NORMAL_MAP.xy+=(yarn.rg-.5)*.28;
		ROUGHNESS=clamp(ROUGHNESS+.08*(yarn.b-.5)-.025*cuff,0.,1.);
	}
	// Transfer film bridges the yarn valleys while retaining broad folds.
	NORMAL_MAP.xy=mix(NORMAL_MAP.xy,vec2(.5),.39*print_coverage);
	ROUGHNESS=mix(ROUGHNESS,.53,print_coverage);
	// The elastic waistband is the outer layer when the shirt is tucked.
	if(!jacket && tucked && y<1.073){
		float band_aa=max(.0005,fwidth(y));
		float edge=1.-smoothstep(.0008,.0008+band_aa,abs(y-1.069));
		ALBEDO=waist_color.rgb*(.87+.18*edge+.045*weave*fade);
		ROUGHNESS=.87;
	}
	RIM=.16;
	RIM_TINT=.32;
	SPECULAR=.28;
}
