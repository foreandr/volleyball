shader_type spatial;
render_mode unshaded, cull_disabled;

uniform float remaining : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	ALBEDO = UV.x < remaining ? vec3(1.0) : vec3(0.012);
}
