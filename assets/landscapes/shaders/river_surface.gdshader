shader_type spatial;

render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_schlick_ggx;

// Eau de la rivière : UV.x = 0 sur la berge, 1 au milieu du lit ; UV.y = distance le long
// du courant (mètres). Vaguelettes qui descendent le courant, bord transparent, gel l'hiver.
uniform vec4 deep_color : source_color = vec4(0.09, 0.33, 0.46, 0.9);
uniform vec4 shallow_color : source_color = vec4(0.36, 0.66, 0.68, 0.55);
uniform vec4 ice_color : source_color = vec4(0.78, 0.9, 0.97, 1.0);
uniform float flow_speed = 1.1;

global uniform float snow_amount;
// Pilotés par DayNightCycle : reflet du soleil + teinte de ciel réfléchissante.
global uniform vec3 sun_dir;
global uniform vec4 sun_tint : source_color;
global uniform float sun_amount;
global uniform vec4 sky_reflect : source_color;

varying vec3 v_world;

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
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float ice = smoothstep(0.55, 0.85, snow_amount);
	float t = TIME * flow_speed * (1.0 - ice);
	vec2 p = v_world.xz * 0.9;
	float w1 = noise(vec2(p.x - t, p.y * 1.6));
	float w2 = noise(vec2(p.x * 1.9 - t * 1.5, p.y * 2.4 + t * 0.2));
	float h = (w1 + w2) * 0.5;
	vec3 n = normalize(vec3((w1 - 0.5) * 0.45, 1.0, (w2 - 0.5) * 0.45));
	NORMAL = mix(normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz), NORMAL, ice);

	float depth = smoothstep(0.12, 0.85, UV.x);
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, depth);
	// Crêtes claires et filets d'écume le long des berges.
	col += vec3(0.55, 0.65, 0.7) * smoothstep(0.64, 0.8, h) * 0.3 * (1.0 - ice);
	float foam = smoothstep(0.30, 0.16, UV.x) * smoothstep(0.45, 0.7, noise(vec2(p.x * 2.0 - t * 0.7, p.y * 3.0)));
	col = mix(col, vec3(0.9, 0.95, 0.96), foam * 0.45 * (1.0 - ice));
	col = mix(col, ice_color.rgb * (0.9 + h * 0.1), ice);

	// Fresnel teinté par la couleur du ciel à l'horizon (jour chaud, nuit froide).
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	col += sky_reflect.rgb * fresnel * 0.5 * (1.0 - ice * 0.5);
	// Reflet du soleil (glint) : lobe serré dans la direction miroir des vaguelettes.
	vec3 sun_view = (VIEW_MATRIX * vec4(sun_dir / max(length(sun_dir), 1e-4), 0.0)).xyz;
	vec3 refl = reflect(-VIEW, NORMAL);
	float glint = pow(max(dot(refl, sun_view), 0.0), 160.0) * (0.7 + 0.6 * h);
	col += sun_tint.rgb * glint * 2.0 * sun_amount * (1.0 - ice);

	ALBEDO = col;
	ALPHA = mix(mix(shallow_color.a, deep_color.a, depth) * smoothstep(0.0, 0.1, UV.x), 1.0, ice);
	ROUGHNESS = mix(0.08, 0.3, ice);
	METALLIC = 0.0;
	SPECULAR = 0.7;
	// L'émission amplifie le reflet solaire pour le bloom (traînée de soleil).
	EMISSION = col * 0.1 + sun_tint.rgb * glint * 1.0 * sun_amount * (1.0 - ice);
}
