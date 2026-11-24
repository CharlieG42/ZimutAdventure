shader_type sky;
// Ciel custom : dégradé jour/crépuscule/nuit, disque solaire + halo, lune, étoiles
// procédurales scintillantes la nuit, couverture nuageuse animée (défilement via TIME).
// Piloté par DayNightCycle (uniforms top/horizon/ground/day_factor/energy/sun/moon/stars/clouds).

uniform vec4 top_color : source_color = vec4(0.2, 0.45, 0.86, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.98, 0.8, 0.58, 1.0);
uniform vec4 ground_color : source_color = vec4(0.35, 0.22, 0.14, 1.0);
uniform float day_factor : hint_range(0.0, 1.0) = 1.0;
uniform float energy : hint_range(0.0, 3.0) = 1.0;

uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
uniform vec4 sun_color : source_color = vec4(1.0, 0.9, 0.7, 1.0);
uniform float sun_disc_size : hint_range(0.001, 0.2) = 0.035;
uniform float sun_halo : hint_range(0.0, 1.0) = 0.35;

uniform vec3 moon_direction = vec3(0.0, -1.0, 0.0);
uniform vec4 moon_color : source_color = vec4(0.85, 0.9, 1.0, 1.0);
uniform float moon_disc_size : hint_range(0.001, 0.2) = 0.045;

uniform float star_amount : hint_range(0.0, 1.0) = 0.0; // 1 = pleine nuit
uniform float twinkle_speed : hint_range(0.0, 20.0) = 6.0;

uniform sampler2D cloud_texture;
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.0; // 0 = ciel dégagé
uniform vec4 cloud_day : source_color = vec4(0.95, 0.93, 0.9, 1.0);
uniform vec4 cloud_night : source_color = vec4(0.1, 0.12, 0.22, 1.0);
uniform float cloud_scale : hint_range(0.1, 10.0) = 2.0;
uniform float cloud_speed : hint_range(0.0, 0.05) = 0.004;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float up = clamp(dir.y, -1.0, 1.0);
	// Dégradé : horizon -> zénith au-dessus, teinte de sol sous l'horizon.
	float t = pow(clamp(up, 0.0, 1.0), 0.45);
	vec3 col = mix(horizon_color.rgb, top_color.rgb, t);
	if (up < 0.0) {
		col = mix(horizon_color.rgb, ground_color.rgb, clamp(-up * 2.5, 0.0, 1.0));
	}
	// Soleil : disque + halo (jour).
	float sun_dot = dot(dir, normalize(sun_direction));
	float disc = smoothstep(cos(sun_disc_size), cos(sun_disc_size * 0.6), sun_dot);
	float halo = pow(max(sun_dot, 0.0), 350.0) * sun_halo;
	col += sun_color.rgb * (disc * 4.0 + halo) * day_factor;
	// Lune : disque + halo (nuit).
	float moon_amount = 1.0 - day_factor;
	float moon_dot = dot(dir, normalize(moon_direction));
	float mdisc = smoothstep(cos(moon_disc_size), cos(moon_disc_size * 0.7), moon_dot);
	float mhalo = pow(max(moon_dot, 0.0), 220.0) * 0.25;
	col += moon_color.rgb * (mdisc * 2.2 + mhalo) * moon_amount;
	// Étoiles : grille 3D hashée + scintillement, hémisphère supérieur, la nuit.
	if (star_amount > 0.001 && up > 0.02) {
		vec3 cell = floor(dir * 220.0);
		float h = hash13(cell);
		if (h > 0.992) {
			float tw = 0.6 + 0.4 * sin(TIME * twinkle_speed * (0.5 + h) + h * 40.0);
			vec3 star_pos = normalize((cell + 0.5) / 220.0);
			float d = length(dir - star_pos);
			float star = smoothstep(0.004, 0.0, d) * tw;
			col += vec3(0.9, 0.95, 1.0) * star * star_amount * smoothstep(0.02, 0.25, up);
		}
	}
	// Nuages : masque alpha de cloud_cover.png, défilement lent, teinte jour/nuit.
	if (cloud_cover > 0.001 && up > -0.05) {
		vec2 cuv = dir.xz / max(up + 0.25, 0.05) * cloud_scale + vec2(TIME * cloud_speed, TIME * cloud_speed * 0.35);
		float ca = texture(cloud_texture, cuv).a * cloud_cover;
		vec3 cloud_col = mix(cloud_night.rgb, cloud_day.rgb, day_factor);
		col = mix(col, cloud_col, clamp(ca, 0.0, 0.9));
	}
	COLOR = col * energy;
}
