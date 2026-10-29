shader_type spatial;

render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

// Couleurs inspirées des photos de référence (assets/landscapes/models/) :
// strates sédimentaires ocre/rouge du canyon de l'Ouest américain.
uniform vec4 strata_light : source_color = vec4(0.80, 0.46, 0.22, 1.0);
uniform vec4 strata_mid : source_color = vec4(0.64, 0.33, 0.16, 1.0);
uniform vec4 strata_dark : source_color = vec4(0.44, 0.21, 0.10, 1.0);
uniform vec4 strata_accent : source_color = vec4(0.88, 0.62, 0.34, 1.0);
uniform vec4 ground_dust : source_color = vec4(0.74, 0.57, 0.38, 1.0);
uniform vec4 rock_shadow : source_color = vec4(0.25, 0.13, 0.07, 1.0);

uniform float strata_scale : hint_range(0.01, 2.0) = 0.12;
uniform float strata_thickness : hint_range(0.05, 1.0) = 0.35;
uniform float strata_roughness : hint_range(0.0, 1.0) = 0.35;
uniform float slope_rock_blend : hint_range(0.0, 1.0) = 0.75;
uniform float noise_scale : hint_range(0.001, 0.2) = 0.015;
uniform float sand_blend_height : hint_range(-50.0, 50.0) = 6.0;
uniform float ledge_dust : hint_range(0.0, 1.0) = 0.45;
uniform float grain_detail : hint_range(0.0, 1.0) = 0.5;

varying vec3 v_world_pos;
varying float v_slope;
varying float v_height;

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

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		value += amplitude * noise(p);
		p *= 2.0;
		amplitude *= 0.5;
	}
	return value;
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_slope = 1.0 - abs(dot(NORMAL, vec3(0.0, 1.0, 0.0)));
	v_height = v_world_pos.y;
}

void fragment() {
	vec2 uv_world = v_world_pos.xz * 0.5;

	// Strates sédimentaires horizontales (par hauteur) avec déformation fbm
	// pour un aspect de couches érodées irrégulières.
	float warp = fbm(uv_world * 0.18) * 4.0 - 2.0;
	float strata = sin((v_height + warp) * strata_scale * 6.2831 + fbm(uv_world * 0.3) * strata_roughness * 3.0);
	strata = smoothstep(-strata_thickness, strata_thickness, strata);

	// Grain fin haute fréquence pour casser l'aspect "plat" du procédural.
	float grain = fbm(uv_world * noise_scale * 500.0);
	float grain_fine = fbm(uv_world * noise_scale * 1500.0);
	float detail = mix(grain, grain_fine, 0.5);

	vec3 rock = mix(strata_dark.rgb, strata_mid.rgb, strata);
	rock = mix(rock, strata_light.rgb, detail * 0.5 + 0.15);
	// Veines claires occasionnelles dans certaines couches.
	float vein = smoothstep(0.92, 1.0, strata) * grain;
	rock = mix(rock, strata_accent.rgb, vein * 0.6);

	vec3 dust = ground_dust.rgb * (0.85 + detail * 0.3);

	float rock_factor = clamp(v_slope * slope_rock_blend + grain * 0.3, 0.0, 1.0);
	vec3 albedo = mix(dust, rock, rock_factor);

	// Poussière accumulée sur les replats et sommets (faces vers le haut).
	float flatness = 1.0 - clamp(v_slope * 2.0, 0.0, 1.0);
	albedo = mix(albedo, dust, flatness * ledge_dust);

	float height_mix = smoothstep(sand_blend_height - 4.0, sand_blend_height + 4.0, v_height);
	albedo = mix(albedo, dust, height_mix * 0.4);

	float ndotl = max(dot(NORMAL, vec3(0.4, 0.8, 0.3)), 0.0);
	vec3 crevice = mix(rock_shadow.rgb, albedo, ndotl);
	albedo = mix(albedo, crevice, v_slope * 0.35);

	ALBEDO = albedo;
	ROUGHNESS = 0.82 + detail * 0.15;
	METALLIC = 0.0;
}
