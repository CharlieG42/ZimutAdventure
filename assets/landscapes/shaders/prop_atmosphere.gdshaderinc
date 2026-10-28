// Brouillard atmosphérique procédural pour les props.
// Usage : inclure dans un shader spatial et appeler atmosphere_fog(ALBEDO, world_pos, camera_pos)
// Ajoute un voile de couleur atmosphérique qui augmente avec la distance,
// imitant la brume de chaleur du désert / la profondeur de champ atmosphérique.

uniform vec4 fog_color : source_color = vec4(0.75, 0.55, 0.38, 1.0);
uniform float fog_near : hint_range(0.0, 500.0) = 60.0;
uniform float fog_far : hint_range(1.0, 2000.0) = 350.0;
uniform float fog_height_falloff : hint_range(0.0, 2.0) = 0.5;

vec3 atmosphere_fog(vec3 albedo, vec3 world_pos, vec3 camera_pos) {
	float dist = distance(world_pos, camera_pos);
	float height_factor = clamp(world_pos.y * fog_height_falloff * 0.02 + 0.5, 0.3, 1.0);
	float fog_amount = smoothstep(fog_near, fog_far, dist) * height_factor;
	return mix(albedo, fog_color.rgb, fog_amount * 0.55);
}
