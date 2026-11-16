shader_type spatial;
// Robe de Barq : couleur de robe, crins et extrémités (bas des jambes) plus sombres, légère variation du poil.
// Le modèle source n'a ni texture ni couleurs de sommets : tout est ici, réglé par horse.json > model > coat.
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

uniform vec3 coat_color : source_color = vec3(0.42, 0.24, 0.13);
uniform vec3 points_color : source_color = vec3(0.08, 0.06, 0.05);
uniform float points_height_m = 0.45;
uniform float points_blend_m = 0.12;
uniform float hair_variation = 0.12;
uniform float roughness_value = 0.75;
// Surface de crins (crinière, queue) : toute la surface prend la couleur des extrémités.
uniform bool is_hair = false;

varying vec3 local_position;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void vertex() {
	// Hauteur au-dessus des sabots, en mètres réels (repère du cheval, après l'échelle du modèle).
	local_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - NODE_POSITION_WORLD;
}

void fragment() {
	float points = is_hair ? 1.0 : 1.0 - smoothstep(points_height_m - points_blend_m, points_height_m + points_blend_m, local_position.y);
	vec3 color = mix(coat_color, points_color, points);
	float grain = hash(floor(local_position * 40.0)) - 0.5;
	ALBEDO = color * (1.0 + grain * hair_variation);
	ROUGHNESS = roughness_value;
	SPECULAR = 0.35;
}
