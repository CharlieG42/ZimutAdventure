shader_type spatial;
// Vent sur la végétation basse (herbes, buissons, fleurs) :
// - balancement sinusoïdal selon la position monde (rafales douces),
// - pliure locale autour du joueur (uniforme global player_pos).
// La partie haute du maillage bouge plus que la base (h = VERTEX.y / top_y).

render_mode cull_disabled, depth_draw_opaque, diffuse_lambert, specular_disabled;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform vec4 albedo_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform bool has_texture = false;
uniform bool use_vertex_color = false;
uniform float roughness : hint_range(0.0, 1.0) = 0.9;
uniform float wind_strength = 0.05;      // amplitude du balancement (m)
uniform float top_y = 1.0;                // hauteur du maillage (pour pondérer le sway)
uniform float bend_radius = 1.3;          // rayon de pliure autour du joueur
uniform float bend_strength = 0.3;        // amplitude de la pliure (m)
global uniform vec3 player_pos;

void vertex() {
	float h = clamp(VERTEX.y / max(top_y, 0.01), 0.0, 1.0);
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Rafale : deux sinus déphasés selon la position monde.
	float sway = sin(TIME * 1.25 + wp.x * 0.9 + wp.z * 0.7) * 0.7
	           + sin(TIME * 2.1 + wp.z * 1.7 - wp.x * 0.4) * 0.3;
	VERTEX.x += sway * wind_strength * h;
	VERTEX.z += cos(TIME * 0.9 + wp.x * 1.3) * wind_strength * 0.6 * h;
	// Pliure au passage du joueur.
	vec2 to_player = wp.xz - player_pos.xz;
	float dist = length(to_player);
	float bend = bend_strength * h * smoothstep(bend_radius, 0.0, dist);
	if (dist > 0.001) {
		VERTEX.xz -= (to_player / dist) * bend;
	}
}

void fragment() {
	vec4 tex = has_texture ? texture(albedo_texture, UV) : vec4(1.0);
	ALBEDO = albedo_color.rgb * tex.rgb * (use_vertex_color ? COLOR.rgb : vec3(1.0));
	ALPHA = albedo_color.a * tex.a * (use_vertex_color ? COLOR.a : 1.0);
	ROUGHNESS = roughness;
	if (ALPHA < 0.01) {
		discard;
	}
}
