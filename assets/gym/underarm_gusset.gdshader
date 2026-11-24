shader_type spatial;
render_mode cull_disabled;
uniform vec2 arm_lift;
varying vec2 bind;
varying float panel_depth;
void vertex(){
	bind=UV2;
	panel_depth=COLOR.r*.6-.3;
	float inset=mix(.004,.027,smoothstep(.17,.27,abs(bind.x)));
	float lift=bind.x>0.?arm_lift.x:arm_lift.y;
	float axilla=1.-smoothstep(1.44,1.51,bind.y);
	float extension=.021*lift*axilla*(1.-smoothstep(.23,.29,abs(bind.x)));
	VERTEX+=NORMAL*(extension-inset);
}
void fragment(){
	float side=abs(bind.x);
	float underarm=length(vec2((side-.193)/.117,(bind.y-1.418)/.132));
	if(underarm>1.) discard;
	float yarn=cos(bind.y*1450.)*(1.-smoothstep(.0006,.0025,fwidth(bind.y)));
	ALBEDO=vec3(.31,.047,.022)*(.94+.05*yarn);
	// A staggered mesh knit opens along the bias as the arm lifts.
	float lift=bind.x>0.?arm_lift.x:arm_lift.y;
	vec2 cell=vec2((panel_depth+.46*side)/.0048,(bind.y+.22*side)/.0046);
	float detail=1.-smoothstep(.22,.75,max(fwidth(cell.x),fwidth(cell.y)));
	cell.x+=.5*mod(floor(cell.y),2.);
	vec2 loop=(fract(cell)-.5)*vec2(1.24,1.13-.27*lift);
	float aperture=1.-smoothstep(.13,.34+.045*lift,length(loop));
	float lip=1.-smoothstep(.025,.115,abs(length(loop-vec2(.01,.055))-.33));
	float crease=sin((side+.42*(bind.y-1.42)+.3*panel_depth)*148.);
	ALBEDO*=.92+.08*lift*crease+detail*(.14*lip-.43*aperture);
	ROUGHNESS=.85+.07*aperture*detail;
}