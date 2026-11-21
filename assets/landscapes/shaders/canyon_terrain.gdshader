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

// Zones (couleur de sommet : R berges, V pinède, B mesas, A rive mouillée).
uniform vec4 bank_grass : source_color = vec4(0.40, 0.46, 0.20, 1.0);
uniform vec4 bank_grass_dry : source_color = vec4(0.58, 0.55, 0.28, 1.0);
uniform vec4 forest_floor : source_color = vec4(0.40, 0.31, 0.19, 1.0);
uniform vec4 badlands_red : source_color = vec4(0.66, 0.30, 0.15, 1.0);
uniform float zone_tint : hint_range(0.0, 1.0) = 1.0;

uniform float strata_scale : hint_range(0.01, 2.0) = 0.12;
uniform float strata_thickness : hint_range(0.05, 1.0) = 0.35;
uniform float strata_roughness : hint_range(0.0, 1.0) = 0.35;
uniform float slope_rock_blend : hint_range(0.0, 1.0) = 0.75;
uniform float noise_scale : hint_range(0.001, 0.2) = 0.015;
uniform float sand_blend_height : hint_range(-50.0, 50.0) = 6.0;
uniform float ledge_dust : hint_range(0.0, 1.0) = 0.45;
uniform float grain_detail : hint_range(0.0, 1.0) = 0.5;

// Détail du sol proche (fondu avec la distance : pas de scintillement au loin).
uniform float ground_detail : hint_range(0.0, 1.0) = 0.4;
uniform float detail_fade_start = 35.0;
uniform float detail_fade_end = 110.0;
// Variation par facette (voir fragment) : valeur, teinte chaude/froide, taille de cellule (m).
uniform float facet_contrast : hint_range(0.0, 0.5) = 0.3;
uniform float facet_tint : hint_range(0.0, 1.0) = 0.5;
uniform float facet_cell_inv = 0.5;
uniform float bump_strength : hint_range(0.0, 1.0) = 0.1;

// Réglés par Weather : couverture de neige et sol détrempé (0 à 1).
global uniform float snow_amount;
global uniform float wetness;

varying vec3 v_world_pos;
varying float v_height;
varying vec4 v_zone;

// Bruits lus dans une texture précalculée et raccordable (tools/generate_noise_texture.py) :
// une lecture au lieu de 4 hachages à base de sinus par bruit, bien moins cher sur mobile.
//   R : bruit de valeur (32 cellules)  G : fbm 4 octaves (8 cellules)
//   B : bruit indépendant (32 cellules) A : bruit fin (64 cellules)
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable, hint_default_white;

// Même échelle que l'ancien noise(p) : une cellule par unité de p.
float noise(vec2 p) {
	return texture(noise_tex, p * (1.0 / 32.0)).r;
}

float noise_b(vec2 p) {
	return texture(noise_tex, p * (1.0 / 32.0)).b;
}

float noise_fine(vec2 p) {
	return texture(noise_tex, p * (1.0 / 64.0)).a;
}

// fbm 4 octaves précalculé (cellule de base d'une unité de p).
float fbm(vec2 p) {
	return texture(noise_tex, p * (1.0 / 8.0)).g;
}

// Micro-relief : deux lectures au lieu de deux bruits procéduraux.
float bump_height(vec2 p) {
	return noise(p) + 0.5 * noise_fine(p * 2.3);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_height = v_world_pos.y;
	v_zone = COLOR * zone_tint;
}

void fragment() {
	// Style « low-poly » : chaque triangle du relief a sa propre normale (ombrage facetté),
	// et c'est cette pente par facette qui décide du roc, de la poussière et des strates.
	NORMAL = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	vec3 face_world = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float v_slope = 1.0 - abs(face_world.y);
	vec2 w = v_world_pos.xz;
	vec2 uv_world = w * 0.5;
	float view_dist = length(VERTEX);
	float near = (1.0 - smoothstep(detail_fade_start, detail_fade_end, view_dist)) * ground_detail;

	// --- Sol : grandes taches (≈ 50 m), mouchetures (≈ 3 m), gravier (≈ 0,3 m) ---
	float macro = fbm(w * 0.02);
	float patch_red = fbm(w * 0.035 + vec2(17.0, 9.0));
	float meso = noise(w * 0.35);
	float micro = noise_fine(w * 3.0);
	float pebble_cell = noise_b(w * 4.5 + vec2(3.0, 11.0));

	vec3 dust = mix(ground_dust.rgb, ground_pale.rgb, smoothstep(0.35, 0.75, macro) * 0.65);
	dust = mix(dust, ground_red.rgb, smoothstep(0.52, 0.85, patch_red) * 0.6);
	dust *= 0.86 + meso * 0.28;
	dust *= 1.0 + (micro - 0.5) * 0.2 * near;
	// Zones : herbe des berges (par touffes), humus sombre de la pinède, terre rouge des mesas.
	float tuft = smoothstep(0.25, 0.6, meso * 0.6 + macro * 0.5);
	vec3 grass = mix(bank_grass_dry.rgb, bank_grass.rgb, tuft) * (0.9 + micro * 0.2 * near);
	dust = mix(dust, grass, clamp(v_zone.r * 1.25, 0.0, 1.0) * (0.55 + 0.4 * tuft));
	dust = mix(dust, forest_floor.rgb * (0.85 + meso * 0.3), v_zone.g * 0.7);
	dust = mix(dust, badlands_red.rgb * (0.85 + meso * 0.3), v_zone.b * 0.55);
	// Rive : sable mouillé, plus sombre, jusque sous l'eau.
	dust = mix(dust, dust * vec3(0.55, 0.52, 0.5), v_zone.a);
	// Rides de sable étirées par le vent.
	float ripple = noise_b(vec2(w.x * 0.9 + w.y * 0.25, w.y * 6.0));
	dust *= 1.0 + (ripple - 0.5) * 0.12 * near;
	// Cailloux épars.
	dust = mix(dust, pebble_dark.rgb, smoothstep(0.76, 0.9, pebble_cell) * 0.3 * near);

	// --- Falaises : strates sédimentaires (calculées seulement sur les pentes) ---
	float rock_factor = smoothstep(0.1, 0.45, v_slope * (0.5 + slope_rock_blend));
	vec3 albedo = dust;
	if (rock_factor > 0.001) {
		// Strates horizontales (par hauteur) avec déformation fbm
		// pour un aspect de couches érodées irrégulières.
		float warp = fbm(uv_world * 0.18) * 4.0 - 2.0;
		float strata = sin((v_height + warp) * strata_scale * 6.2831 + fbm(uv_world * 0.3) * strata_roughness * 3.0);
		strata = smoothstep(-strata_thickness, strata_thickness, strata);

		float grain = noise_b(w * 2.2) * 0.6 + noise_fine(w * 7.0) * 0.4;
		vec3 rock = mix(strata_dark.rgb, strata_mid.rgb, strata);
		rock = mix(rock, strata_light.rgb, grain * 0.5 + 0.15);
		// Veines claires occasionnelles dans certaines couches.
		float vein = smoothstep(0.92, 1.0, strata) * grain;
		rock = mix(rock, strata_accent.rgb, vein * 0.6);
		albedo = mix(dust, rock, rock_factor);
	}

	// Facettes : chaque triangle (cellules de 2 m, deux triangles par cellule) reçoit une
	// légère variation de valeur et de teinte, pour que le relief lise « low-poly » même
	// sur le plat. S'estompe au loin (facettes sous le pixel : scintillement).
	vec2 cell = v_world_pos.xz * facet_cell_inv;
	vec2 cell_id = floor(cell);
	vec2 cell_f = fract(cell);
	float tri = step(1.0, cell_f.x + cell_f.y);
	// Hasard de facette : un texel de la texture de bruit (deux bruits indépendants R et B).
	ivec2 facet_id = (ivec2(cell_id) + ivec2(int(tri) * 37, int(tri) * 61)) & ivec2(255);
	vec4 facet_rand = texelFetch(noise_tex, facet_id, 0);
	float h1 = facet_rand.r;
	float h2 = facet_rand.b;
	float facet_fade = 1.0 - smoothstep(70.0, 260.0, view_dist);
	albedo *= 1.0 + (h1 - 0.5) * facet_contrast * facet_fade;
	albedo = mix(albedo, albedo * vec3(1.07, 0.98, 0.9), (h2 - 0.5) * facet_tint * facet_fade + 0.0);

	// Poussière accumulée sur les replats et sommets (faces vers le haut).
	float flatness = 1.0 - clamp(v_slope * 2.0, 0.0, 1.0);
	albedo = mix(albedo, dust, flatness * ledge_dust);

	float height_mix = smoothstep(sand_blend_height - 4.0, sand_blend_height + 4.0, v_height);
	albedo = mix(albedo, dust, height_mix * 0.4);

	float ndotl = max(dot(NORMAL, vec3(0.4, 0.8, 0.3)), 0.0);
	vec3 crevice = mix(rock_shadow.rgb, albedo, ndotl);
	albedo = mix(albedo, crevice, v_slope * 0.35);

	// Micro-relief du sol proche + grain des falaises : accrochent la lumière rasante du soir.
	float bump_amount = near * bump_strength + rock_factor * bump_strength * 1.4 * (1.0 - smoothstep(60.0, 160.0, view_dist));
	if (bump_amount > 0.01) {
		vec2 bp = w * 2.4 + vec2(v_height * 0.9, -v_height * 0.4) * rock_factor;
		float h0 = bump_height(bp);
		float hx = bump_height(bp + vec2(0.1, 0.0));
		float hz = bump_height(bp + vec2(0.0, 0.1));
		vec3 n_world = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		n_world = normalize(n_world + vec3(h0 - hx, 0.0, h0 - hz) * bump_amount * 6.0);
		NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	}

	// Éclat discret du sable au soleil (grains quartz) sur le sol proche.
	float sparkle = step(0.97, noise_fine(w * 38.0)) * near * (1.0 - rock_factor);
	albedo += vec3(0.5, 0.45, 0.35) * sparkle * 0.6;

	// Pluie : le sol s'assombrit et devient brillant.
	albedo *= 1.0 - 0.28 * wetness * (1.0 - rock_factor * 0.4);

	// Neige : se dépose d'abord sur les replats, un peu moins sur les pentes raides ; bords irréguliers.
	float snow_edge = noise(w * 0.8) * 0.5 + noise_b(w * 3.1) * 0.5;
	float snow_cover = snow_amount * (1.0 - smoothstep(0.18, 0.7, v_slope)) ;
	snow_cover = smoothstep(0.35, 0.6, snow_cover + (snow_edge - 0.5) * 0.45 * snow_amount);
	vec3 snow_color = vec3(0.92, 0.95, 1.0) * (0.94 + micro * 0.06);
	albedo = mix(albedo, snow_color, snow_cover);
	sparkle *= 1.0 - snow_cover;

	ALBEDO = albedo;
	ROUGHNESS = mix(0.85 + micro * 0.1 - sparkle * 0.5, 0.35, wetness * 0.6) * (1.0 - snow_cover * 0.1);
	RIM = 0.15 * (1.0 - rock_factor);
	RIM_TINT = 0.6;
	METALLIC = 0.0;
}
