shader_type spatial;

render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_disabled;

uniform vec4 albedo : source_color = vec4(0.2, 0.35, 0.12, 1.0);
uniform vec4 albedo_light : source_color = vec4(0.35, 0.5, 0.18, 1.0);
uniform float variation_scale : hint_range(0.1, 10.0) = 2.0;
uniform float light_boost : hint_range(0.0, 1.0) = 0.4;
uniform float wind_strength : hint_range(0.0, 1.0) = 0.12;
uniform float wind_speed : hint_range(0.0, 10.0) = 1.6;
uniform float wind_scale : hint_range(0.01, 2.0) = 0.35;

varying vec3 v_world_pos;
varying vec3 v_normal;
varying float v_y;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453123);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash(i);
	float n100 = hash(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash(i + vec3(1.0, 1.0, 1.0));
	float nx00 = mix(n000, n100, f.x);
	float nx10 = mix(n010, n110, f.x);
	float nx01 = mix(n001, n101, f.x);
	float nx11 = mix(n011, n111, f.x);
	return mix(mix(nx00, nx10, f.y), mix(nx01, nx11, f.y), f.z);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_y = VERTEX.y;

	// Balancement au vent : déformation horizontale croissante avec la
	// hauteur locale, animée par une onde qui parcourt le monde.
	float sway_phase = TIME * wind_speed + v_world_pos.x * wind_scale + v_world_pos.z * wind_scale * 0.7;
	float sway = sin(sway_phase) * wind_strength * max(VERTEX.y, 0.0);
	VERTEX.x += sway;
	VERTEX.z += cos(sway_phase * 0.8) * wind_strength * 0.6 * max(VERTEX.y, 0.0);
}

void fragment() {
	float variation = noise3(v_world_pos * variation_scale);
	vec3 col = mix(albedo.rgb, albedo_light.rgb, variation);

	vec3 n = normalize(v_normal);
	float up = max(n.y, 0.0);
	float light_dir = max(dot(n, normalize(vec3(0.4, 0.8, 0.3))), 0.0);
	col = mix(col, albedo_light.rgb, up * light_boost);
	col *= 0.75 + light_dir * 0.25;

	ALBEDO = col;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
