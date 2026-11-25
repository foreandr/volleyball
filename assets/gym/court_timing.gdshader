shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec2 contact;
uniform vec2 perfect;
uniform float cursor;
uniform bool highlight;
uniform vec4 miss : source_color;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float t = atan(-p.y, p.x) / PI;
	float r = length(p);
	if (t < 0.0 || r < 0.87 || r > 0.99) discard;
	float progress = 1.0 - t;
	vec3 tint = miss.rgb;
	float start = 0.0;
	if (progress >= contact.x) { tint=vec3(.94,.54,.07); start=contact.x; }
	if (progress >= perfect.x) { tint=vec3(.12,.78,.28); start=perfect.x; }
	if (progress > perfect.y) { tint=vec3(.94,.12,.10); start=perfect.y; }
	if (progress > contact.y) { tint=miss.rgb; start=contact.y; }
	ALBEDO=tint*((progress<=cursor || (highlight && start<=cursor)) ? 1.0 : .68);
	if (abs(progress-cursor) < .012) ALBEDO=vec3(1.0);
}
