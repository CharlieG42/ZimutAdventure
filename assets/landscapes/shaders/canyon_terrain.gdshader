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

// Sol : sable pâle des lits asséchés, terre rouge, gravier sombre.
uniform vec4 ground_pale : source_color = vec4(0.86, 0.71, 0.50, 1.0);
uniform vec4 ground_red : source_color = vec4(0.62, 0.34, 0.18, 1.0);
uniform vec4 pebble_dark : source_color = vec4(0.30, 0.19, 0.12, 1.0);

uniform float strata_scale : hint_range(0.01, 2.0) = 0.12;
uniform float strata_thickness : hint_range(0.05, 1.0) = 0.35;
uniform float strata_roughness : hint_range(0.0, 1.0) = 0.35;
uniform float slope_rock_blend : hint_range(0.0, 1.0) = 0.75;
uniform float noise_scale : hint_range(0.001, 0.2) = 0.015;
uniform float sand_blend_height : hint_range(-50.0, 50.0) = 6.0;
uniform float ledge_dust : hint_range(0.0, 1.0) = 0.45;
uniform float grain_detail : hint_range(0.0, 1.0) = 0.5;

// Détail du sol proche (fondu avec la distance : pas de scintillement au loin).
uniform float ground_detail : hint_range(0.0, 1.0) = 0.85;
uniform float detail_fade_start = 35.0;
uniform float detail_fade_end = 110.0;
uniform float bump_strength : hint_range(0.0, 1.0) = 0.35;

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

// fbm à 3 octaves : suffisant pour les grandes taches du sol, moins coûteux.
float fbm3(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 3; i++) {
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
	vec2 w = v_world_pos.xz;
	vec2 uv_world = w * 0.5;
	float view_dist = length(VERTEX);
	float near = (1.0 - smoothstep(detail_fade_start, detail_fade_end, view_dist)) * ground_detail;

	// --- Sol : grandes taches (≈ 50 m), mouchetures (≈ 3 m), gravier (≈ 0,3 m) ---
	float macro = fbm3(w * 0.02);
	float patch_red = fbm3(w * 0.035 + vec2(17.0, 9.0));
	float meso = noise(w * 0.35);
	float micro = noise(w * 3.0);
	float pebble_cell = noise(w * 4.5 + vec2(3.0, 11.0));

	vec3 dust = mix(ground_dust.rgb, ground_pale.rgb, smoothstep(0.35, 0.75, macro) * 0.65);
	dust = mix(dust, ground_red.rgb, smoothstep(0.52, 0.85, patch_red) * 0.6);
	dust *= 0.86 + meso * 0.28;
	dust *= 1.0 + (micro - 0.5) * 0.2 * near;
	// Rides de sable étirées par le vent.
	float ripple = noise(vec2(w.x * 0.9 + w.y * 0.25, w.y * 6.0));
	dust *= 1.0 + (ripple - 0.5) * 0.12 * near;
	// Cailloux épars.
	dust = mix(dust, pebble_dark.rgb, smoothstep(0.76, 0.9, pebble_cell) * 0.6 * near);

	// --- Falaises : strates sédimentaires (calculées seulement sur les pentes) ---
	float rock_factor = smoothstep(0.1, 0.45, v_slope * (0.5 + slope_rock_blend));
	vec3 albedo = dust;
	if (rock_factor > 0.001) {
		// Strates horizontales (par hauteur) avec déformation fbm
		// pour un aspect de couches érodées irrégulières.
		float warp = fbm(uv_world * 0.18) * 4.0 - 2.0;
		float strata = sin((v_height + warp) * strata_scale * 6.2831 + fbm(uv_world * 0.3) * strata_roughness * 3.0);
		strata = smoothstep(-strata_thickness, strata_thickness, strata);

		float grain = noise(w * 2.2) * 0.6 + noise(w * 7.0) * 0.4;
		vec3 rock = mix(strata_dark.rgb, strata_mid.rgb, strata);
		rock = mix(rock, strata_light.rgb, grain * 0.5 + 0.15);
		// Veines claires occasionnelles dans certaines couches.
		float vein = smoothstep(0.92, 1.0, strata) * grain;
		rock = mix(rock, strata_accent.rgb, vein * 0.6);
		albedo = mix(dust, rock, rock_factor);
	}

	// Poussière accumulée sur les replats et sommets (faces vers le haut).
	float flatness = 1.0 - clamp(v_slope * 2.0, 0.0, 1.0);
	albedo = mix(albedo, dust, flatness * ledge_dust);

	float height_mix = smoothstep(sand_blend_height - 4.0, sand_blend_height + 4.0, v_height);
	albedo = mix(albedo, dust, height_mix * 0.4);

	float ndotl = max(dot(NORMAL, vec3(0.4, 0.8, 0.3)), 0.0);
	vec3 crevice = mix(rock_shadow.rgb, albedo, ndotl);
	albedo = mix(albedo, crevice, v_slope * 0.35);

	// Micro-relief : accroche la lumière rasante du soir sur le sol proche.
	if (near > 0.01 && bump_strength > 0.0) {
		vec2 bp = w * 2.4;
		float h0 = noise(bp);
		float hx = noise(bp + vec2(0.1, 0.0));
		float hz = noise(bp + vec2(0.0, 0.1));
		vec3 n_world = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		n_world = normalize(n_world + vec3(h0 - hx, 0.0, h0 - hz) * bump_strength * 6.0 * near);
		NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	}

	ALBEDO = albedo;
	ROUGHNESS = 0.85 + micro * 0.1;
	METALLIC = 0.0;
}
