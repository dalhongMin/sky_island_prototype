shader_type spatial;
render_mode cull_disabled, diffuse_lambert;

// Shared material for grass blades, leaves and flowers.
// The sway is a vertex offset (no extra draw calls, no transparency) and the
// phase comes from the node position so every plant moves a little differently.

uniform vec4 albedo : source_color = vec4(0.45, 0.68, 0.33, 1.0);
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec3 emission_color : source_color = vec3(0.3, 0.8, 0.6);
uniform float emission_strength = 0.0;
uniform float sway_strength = 0.12;
uniform float sway_speed = 1.1;

void vertex() {
	float phase = NODE_POSITION_WORLD.x * 1.9 + NODE_POSITION_WORLD.z * 1.3;
	float height = max(VERTEX.y, 0.0);
	float s = sin(TIME * sway_speed + phase) * sway_strength * height;
	float c = cos(TIME * sway_speed * 0.8 + phase) * sway_strength * 0.6 * height;
	VERTEX.x += s;
	VERTEX.z += c;
}

void fragment() {
	ALBEDO = albedo.rgb * tint.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	EMISSION = emission_color * emission_strength;
}
