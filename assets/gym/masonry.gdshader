shader_type spatial;
varying vec3 pos;
varying vec3 axis;
void vertex(){pos=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;axis=MODEL_NORMAL_MATRIX*NORMAL;}
void fragment(){
	vec2 p=vec2(abs(axis.x)>.5?pos.z:pos.x,pos.y);
	float row=floor(p.y/.2);
	vec2 tile=vec2(p.x/.405+mod(row,2.)*.5,p.y/.2);
	vec2 q=fract(tile);
	float d=min(min(q.x,1.-q.x)*.405,min(q.y,1.-q.y)*.2);
	float mortar=1.-smoothstep(.0005,.003+fwidth(d),d);
	float v=fract(sin(dot(floor(tile),vec2(32.5,12.4)))*4321.6);
	ALBEDO=mix(vec3(.58,.56,.49)*(.95+.05*v),vec3(.39,.38,.34),mortar*.58);
	ROUGHNESS=.87;
}
