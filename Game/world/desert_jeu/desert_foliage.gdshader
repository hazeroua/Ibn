shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;
// Végétation du désert : balancement par le vent (uniformes globaux du ticket vent) et teinte de saison
// (uniformes globaux du ticket saisons). Aucun coût par image côté processeur.

global uniform vec2 wind_direction;
global uniform float wind_strength;
global uniform float wind_time;
global uniform vec3 season_grass_color;
global uniform vec3 season_palm_color;
global uniform float season_bloom; // 1 au printemps, 0 hors saison : les fleurs poussent et disparaissent
global uniform float season_flowering; // floraison des arbustes (0 à 1)
global uniform float season_fruit; // maturité des fruits des arbres fruitiers (0 : verts ou absents, 1 : mûrs)
global uniform float season_crop_growth; // croissance des cultures basses (0 : sol nu, 1 : pleine végétation)
global uniform float season_crop_ripe; // maturité des cultures (0 : vert, 1 : doré)

uniform int tint_kind = 0; // 0 : aucune, 1 : herbe et buissons, 2 : palmes, 3 : fleurs éphémères (sommets réduits à zéro hors saison), 4 : arbustes fleuris, 5 : arbres fruitiers (fruits repérés par le rouge de sommet > 0,8), 6 : cultures basses
uniform vec3 bloom_leaf_color = vec3(0.2, 0.34, 0.17); // mode 4 : couleur des fleurs hors floraison (feuillage)
uniform vec3 fruit_leaf_color = vec3(0.2, 0.3, 0.12); // mode 5 : couleur des fruits verts (feuillage)
uniform vec3 fruit_ripe_color = vec3(0.7, 0.15, 0.1); // mode 5 : couleur des fruits mûrs
uniform float crop_min_growth = 0.0; // mode 6 : croissance minimale (cultures qui restent vertes)
uniform vec3 crop_ripe_color = vec3(0.8, 0.66, 0.28); // mode 6 : couleur à maturité
uniform float sway_height_m = 1.0;
uniform float sway_amount_m = 0.25;

varying vec3 v_color;

void vertex() {
	if (tint_kind == 3) {
		// Hors saison tous les sommets se confondent au pied : triangles dégénérés, aucun pixel dessiné.
		VERTEX *= season_bloom;
	}
	if (tint_kind == 6) {
		// Cultures : la touffe pousse et rétrécit avec la saison ; sol nu = triangles dégénérés, aucun pixel dessiné.
		float growth = clamp(max(season_crop_growth, crop_min_growth), 0.0, 1.0);
		VERTEX *= vec3(mix(0.6, 1.0, growth), growth, mix(0.6, 1.0, growth)) * step(0.02, growth);
	}
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float weight = clamp(VERTEX.y / max(sway_height_m, 0.001), 0.0, 1.0);
	weight *= weight;
	float phase = wind_time * 1.6 + dot(world.xz, vec2(0.11, 0.07));
	float push = (0.55 + 0.45 * sin(phase)) * wind_strength * sway_amount_m * weight;
	vec2 dir = normalize(wind_direction + vec2(0.0001));
	VERTEX.x += dir.x * push;
	VERTEX.z += dir.y * push;
	v_color = COLOR.rgb;
}

void fragment() {
	vec3 tint = vec3(1.0);
	if (tint_kind == 1) {
		tint = season_grass_color;
	} else if (tint_kind == 2) {
		tint = mix(vec3(1.0), season_palm_color * 2.0, step(0.25, v_color.g - v_color.r));
	}
	vec3 albedo = v_color * tint;
	if (tint_kind == 3) {
		// Fleurs : rouge de sommet réservé (> 0,8), posé par Blender. Hors floraison elles prennent la couleur du feuillage.
		float flower = step(0.8, v_color.r);
		albedo = mix(v_color, mix(bloom_leaf_color, v_color, clamp(season_bloom, 0.0, 1.0)), flower);
	}
	if (tint_kind == 5) {
		float flag = step(0.8, v_color.r);
		float ripe = smoothstep(0.15, 0.7, season_fruit);
		albedo = mix(v_color, mix(fruit_leaf_color, fruit_ripe_color, ripe), flag);
	} else if (tint_kind == 6) {
		albedo = mix(v_color, crop_ripe_color * (0.55 + 0.9 * v_color.g), clamp(season_crop_ripe, 0.0, 1.0));
	}
	ALBEDO = albedo;
	ROUGHNESS = 0.95;
}
