shader_type spatial;

render_mode diffuse_lambert, specular_disabled, cull_back;

// Mesas lointaines : strates horizontales, sommets plus clairs (neige l'hiver), plaine sableuse.
// Couleur de sommet : R = teinte propre, G = 1 sur les plateaux, B = 1 pour la plaine.
uniform vec4 rock_red : source_color = vec4(0.70, 0.34, 0.20, 1.0);
uniform vec4 rock_pale : source_color = vec4(0.82, 0.58, 0.40, 1.0);
uniform vec4 rock_dark : source_color = vec4(0.52, 0.24, 0.15, 1.0);
uniform vec4 ground_color : source_color = vec4(0.80, 0.62, 0.42, 1.0);
uniform vec4 snow_color : source_color = vec4(0.93, 0.95, 0.98, 1.0);

global uniform float snow_amount;

varying vec3 v_world;
varying vec4 v_col;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_col = COLOR;
}

void fragment() {
	float y = v_world.y;
	float band = sin(y * 0.55 + v_col.r * 6.0) * 0.5 + 0.5;
	float band2 = sin(y * 1.7 + 1.3) * 0.5 + 0.5;
	vec3 rock = mix(rock_red.rgb, rock_pale.rgb, smoothstep(0.55, 0.9, band) * 0.7);
	rock = mix(rock, rock_dark.rgb, smoothstep(0.75, 1.0, band2) * 0.35);
	rock *= 0.9 + 0.2 * v_col.r;
	vec3 col = mix(rock, rock_pale.rgb * 1.05, v_col.g * 0.6);
	col = mix(col, snow_color.rgb, v_col.g * smoothstep(0.3, 0.8, snow_amount));
	col = mix(col, mix(ground_color.rgb, snow_color.rgb, smoothstep(0.4, 0.9, snow_amount) * 0.8), v_col.b);
	ALBEDO = col;
	ROUGHNESS = 1.0;
}
