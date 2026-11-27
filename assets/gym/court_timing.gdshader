shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec2 contact;
uniform vec2 perfect;
uniform float cursor;
uniform bool highlight;
uniform bool black_cursor;
uniform vec4 miss : source_color;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float t = atan(-p.y, p.x) / PI;
	float r = length(p);
	if (t < 0.0 || r < 0.70 || r > 0.99) discard;
	float progress = 1.0 - t;
	vec3 tint = miss.rgb;
	float start = 0.0;
	if (progress >= contact.x) { tint=vec3(.94,.54,.07); start=contact.x; }
	if (progress >= perfect.x) { tint=vec3(.12,.78,.28); start=perfect.x; }
	if (progress > perfect.y) { tint=vec3(.94,.12,.10); start=perfect.y; }
	if (progress > contact.y) { tint=miss.rgb; start=contact.y; }
	ALBEDO=tint*((progress<=cursor || (highlight && start<=cursor)) ? 1.0 : .68);
	if (r < .722 || r > .965) ALBEDO=vec3(.025);
	float cursor_distance=abs(progress-cursor);
	if (cursor_distance < .040) ALBEDO=black_cursor ? vec3(.94) : vec3(.025);
	if (cursor_distance < .029) ALBEDO=black_cursor ? vec3(.015) : vec3(1.0);
}
