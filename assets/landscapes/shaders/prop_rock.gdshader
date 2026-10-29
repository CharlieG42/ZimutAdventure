shader_type spatial;

render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(0.6, 0.35, 0.18, 1.0);
uniform vec4 albedo_dark : source_color = vec4(0.35, 0.18, 0.09, 1.0);
uniform float grain_scale : hint_range(0.1, 20.0) = 4.0;
uniform float grain_strength : hint_range(0.0, 1.0) = 0.35;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.9;

varying vec3 v_world_pos;
varying vec3 v_normal;

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

float fbm3(vec3 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 3; i++) {
		value += amplitude * noise3(p);
		p *= 2.0;
		amplitude *= 0.5;
	}
	return value;
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float grain = fbm3(v_world_pos * grain_scale);
	vec3 col = mix(albedo_dark.rgb, albedo.rgb, grain * grain_strength + (1.0 - grain_strength) * 0.5);

	// Strates sédimentaires horizontales : bandes de teinte par hauteur monde,
	// déformées par le grain pour une érosion irrégulière.
	float band = sin(v_world_pos.y * 1.4 + grain * 2.5);
	float strata = smoothstep(-0.35, 0.35, band);
	col = mix(col * 0.82, col * 1.12, strata);

	// Poudre claire sur les faces vers le haut (poussière déposée).
	vec3 n = normalize(v_normal);
	float up = max(n.y, 0.0);
	col = mix(col, col * 1.18 + vec3(0.06, 0.05, 0.03), up * 0.4 * grain);
	// Ombre renforcée dans les creux orientés vers le bas.
	float under = max(-n.y, 0.0);
	col = mix(col, col * 0.7, under * 0.5);

	float ndotl = max(dot(n, vec3(0.4, 0.8, 0.3)), 0.0);
	vec3 shaded = mix(albedo_dark.rgb * 0.6, col, ndotl * 0.5 + 0.5);

	ALBEDO = shaded;
	ROUGHNESS = roughness_base;
	METALLIC = 0.0;
}
