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
// Aurores boréales (région Canada) : 0 ailleurs, ~1 la nuit au Grand Nord.
uniform float aurora_amount : hint_range(0.0, 1.0) = 0.0;

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
	// Aurores boréales : rideaux ondulants (deux sinus déphasés), dégradé vert -> violet,
	// visibles seulement la nuit et selon la région (aurora_amount).
	if (aurora_amount > 0.001 && up > 0.03 && day_factor < 0.6) {
		float a1 = sin(dir.x * 2.2 + TIME * 0.10 + sin(dir.z * 1.7 + TIME * 0.07) * 2.0);
		float a2 = sin(dir.x * 5.1 - TIME * 0.06 + dir.z * 2.3);
		float curtain = pow(max(a1 * 0.62 + a2 * 0.38, 0.0), 2.0);
		curtain *= smoothstep(0.03, 0.3, up) * (1.0 - smoothstep(0.5, 0.95, up));
		vec3 aurora_col = mix(vec3(0.1, 0.95, 0.45), vec3(0.5, 0.25, 0.95), 0.5 + 0.5 * sin(TIME * 0.05 + dir.x * 1.3));
		col += aurora_col * curtain * aurora_amount * 0.5 * (1.0 - day_factor);
	}
	// Étoiles filantes : une fenêtre toutes les ~8 s, traînée qui traverse le ciel la nuit.
	if (star_amount > 0.3 && up > 0.1) {
		float mslot = floor(TIME * 0.12);
		float mh = hash13(vec3(mslot, 7.0, 3.0));
		if (mh > 0.8) {
			float mt = fract(TIME * 0.12);
			vec3 mdir = normalize(vec3(hash13(vec3(mslot, 1.0, 2.0)) - 0.5,
				0.55 + hash13(vec3(mslot, 3.0, 4.0)) * 0.35,
				hash13(vec3(mslot, 5.0, 6.0)) - 0.5));
			vec3 mpos = mdir * (1.6 - mt * 2.2);
			float md = length(dir - mpos);
			float tail = smoothstep(0.014, 0.0, md) * smoothstep(0.0, 0.3, mt) * (1.0 - smoothstep(0.7, 1.0, mt));
			col += vec3(1.0, 0.95, 0.85) * tail * 2.5 * star_amount;
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
