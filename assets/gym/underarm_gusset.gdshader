shader_type spatial;
render_mode cull_disabled;
uniform vec2 arm_lift;
varying vec2 bind;
void vertex(){
	bind=UV2;
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
	ROUGHNESS=.87;
}