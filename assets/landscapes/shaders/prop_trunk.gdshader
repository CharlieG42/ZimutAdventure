shader_type spatial;

render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(0.24, 0.14, 0.07, 1.0);
uniform vec4 albedo_light : source_color = vec4(0.38, 0.22, 0.10, 1.0);
uniform float bark_scale : hint_range(0.5, 20.0) = 6.0;
uniform float bark_depth : hint_range(0.0, 1.0) = 0.4;

varying vec3 v_world_pos;
varying vec3 v_normal;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = vec2(atan(v_world_pos.z, v_world_pos.x) * 1.5, v_world_pos.y * bark_scale);
	float bark = noise(uv * 3.0) * 0.6 + noise(uv * 8.0) * 0.4;
	vec3 col = mix(albedo.rgb, albedo_light.rgb, bark * bark_depth);

	float ndotl = max(dot(normalize(v_normal), vec3(0.4, 0.8, 0.3)), 0.0);
	col = mix(albedo.rgb * 0.5, col, ndotl * 0.5 + 0.5);

	ALBEDO = col;
	ROUGHNESS = 0.95;
	METALLIC = 0.0;
}
