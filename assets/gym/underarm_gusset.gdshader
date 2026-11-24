shader_type spatial;
render_mode cull_disabled;
varying vec2 bind;
void vertex(){
	bind=UV2;
	float inset=mix(.004,.027,smoothstep(.17,.27,abs(bind.x)));
	VERTEX-=NORMAL*inset;
}
void fragment(){
	float side=abs(bind.x);
	float underarm=length(vec2((side-.193)/.117,(bind.y-1.418)/.132));
	if(underarm>1.) discard;
	float yarn=cos(bind.y*1450.)*(1.-smoothstep(.0006,.0025,fwidth(bind.y)));
	ALBEDO=vec3(.31,.047,.022)*(.94+.05*yarn);
	ROUGHNESS=.87;
}