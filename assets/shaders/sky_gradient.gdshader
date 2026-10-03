shader_type sky;

// Sky gradient + sun/moon glow + procedural star field.
// Driven from scripts/world/sky_cycle.gd; no screen-space passes involved.

uniform vec3 top_color : source_color = vec3(0.33, 0.62, 0.86);
uniform vec3 horizon_color : source_color = vec3(0.76, 0.87, 0.93);
uniform vec3 glow_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float glow_strength = 0.3;
uniform float glow_tightness = 18.0;
uniform float star_amount = 0.0;
uniform vec3 sun_direction = vec3(0.4, 0.5, -0.6);

// Moon disc. It is only a sky colour: it casts no light and the directional
// light is aimed independently, so moving it never changes how the island
// is lit.
uniform vec3 moon_color : source_color = vec3(0.95, 0.95, 0.90);
uniform vec3 moon_direction = vec3(-0.272, 0.268, -0.924);
uniform float moon_radius = 0.042;
uniform float moon_amount = 0.0;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

void sky() {
	float h = clamp(EYEDIR.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 col = mix(horizon_color, top_color, pow(h, 0.75));

	float toward = max(dot(normalize(EYEDIR), normalize(sun_direction)), 0.0);
	col += glow_color * pow(toward, glow_tightness) * glow_strength;

	if (star_amount > 0.002 && EYEDIR.y > 0.0) {
		vec3 e = EYEDIR * 130.0;
		vec3 cell = floor(e);
		vec3 f = fract(e);
		float pick = hash13(cell + 11.0);
		vec3 center = vec3(hash13(cell + 1.0), hash13(cell + 2.0), hash13(cell + 3.0));
		float d = length(f - center);
		float dot_mask = smoothstep(0.26, 0.0, d) * step(0.955, pick);
		float twinkle = 0.65 + 0.35 * sin(TIME * 1.7 + pick * 90.0);
		float fade = smoothstep(0.02, 0.3, EYEDIR.y);
		col += vec3(0.88, 0.92, 1.0) * dot_mask * twinkle * fade * star_amount;
	}

	// After the stars, so the disc stays a clean flat shape.
	if (moon_amount > 0.002) {
		float d = length(normalize(EYEDIR) - normalize(moon_direction));
		float halo = pow(max(1.0 - d / (moon_radius * 3.2), 0.0), 3.0);
		col += moon_color * halo * 0.14 * moon_amount;
		float disc = smoothstep(moon_radius, moon_radius * 0.88, d);
		col = mix(col, moon_color, disc * moon_amount);
	}

	COLOR = col;
}
