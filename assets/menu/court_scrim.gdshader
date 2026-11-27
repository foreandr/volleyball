shader_type canvas_item;
render_mode unshaded;

void fragment() {
	float left_panel = 1.0 - smoothstep(0.27, 0.76, UV.x);
	float lower_edge = smoothstep(0.71, 1.04, UV.y);
	COLOR = vec4(0.025, 0.052, 0.085, 0.06 + 0.81 * left_panel + 0.1 * lower_edge);
}
