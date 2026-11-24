shader_type spatial;

render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

// Eau du point d'eau : ondulations, reflets scintillants, bord plus clair ; gelée l'hiver.
uniform vec4 deep_color : source_color = vec4(0.10, 0.34, 0.55, 0.88);
uniform vec4 shallow_color : source_color = vec4(0.30, 0.62, 0.78, 0.88);
uniform vec4 ice_color : source_color = vec4(0.78, 0.9, 0.97, 1.0);
uniform float wave_speed = 0.9;

global uniform float snow_amount;
// Pilotés par DayNightCycle : reflet du soleil + teinte de ciel réfléchissante.
global uniform vec3 sun_dir;
global uniform vec4 sun_tint : source_color;
global uniform float sun_amount;
global uniform vec4 sky_reflect : source_color;

varying vec3 v_local;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	float ice = smoothstep(0.55, 0.85, snow_amount);
	vec2 p = v_local.xz * 2.2;
	float t = TIME * wave_speed;
	// Deux couches d'ondes qui se croisent : normale perturbée et crêtes brillantes.
	float w1 = noise(p + vec2(t, t * 0.6));
	float w2 = noise(p * 1.7 - vec2(t * 0.8, t));
	float h = (w1 + w2) * 0.5;
	vec3 n = normalize(vec3((w1 - 0.5) * 0.5, 1.0, (w2 - 0.5) * 0.5));
	NORMAL = mix(normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz), NORMAL, ice);

	float radial = clamp(length(v_local.xz) / 1.5, 0.0, 1.0);
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, smoothstep(0.1, 0.9, 1.0 - radial) * 0.8);
	col += vec3(0.5, 0.6, 0.7) * smoothstep(0.62, 0.78, h) * 0.35 * (1.0 - ice);
	col = mix(col, ice_color.rgb * (0.9 + h * 0.1), ice);

	// Fresnel teinté par la couleur du ciel à l'horizon (jour chaud, nuit froide).
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	col += sky_reflect.rgb * fresnel * 0.55 * (1.0 - ice * 0.5);
	// Reflet du soleil (glint) : lobe serré dans la direction miroir des vaguelettes.
	vec3 sun_view = (VIEW_MATRIX * vec4(sun_dir / max(length(sun_dir), 1e-4), 0.0)).xyz;
	vec3 refl = reflect(-VIEW, NORMAL);
	float glint = pow(max(dot(refl, sun_view), 0.0), 160.0) * (0.7 + 0.6 * h);
	col += sun_tint.rgb * glint * 2.2 * sun_amount * (1.0 - ice);

	ALBEDO = col;
	ALPHA = mix(shallow_color.a, 1.0, ice);
	ROUGHNESS = mix(0.08, 0.3, ice);
	METALLIC = 0.0;
	SPECULAR = 0.7;
	// L'émission amplifie le reflet solaire pour le bloom (traînée de soleil).
	EMISSION = col * 0.12 + sun_tint.rgb * glint * 1.2 * sun_amount * (1.0 - ice);
}
