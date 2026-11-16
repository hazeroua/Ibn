// Terrain du désert : sable, pierre et terre mélangés par le poids porté par les sommets (couleur : R = pierre,
// V = terre, B = galets du lit d'oued, A = proximité du lit). Textures lues en coordonnées du monde (le maillage n'en porte aucune). Répétition cachée par deux
// lectures à échelles et orientations différentes, fondues par un bruit lent, et par une variation de teinte à
// grande échelle. Les normales viennent des sommets : identiques pour tous les niveaux de détail.
shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform sampler2D sand_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_normal : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D galets_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D galets_normal : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D galets_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float galets_uv_scale = 0.22;
uniform float bed_far_start_m = 150.0;
uniform float bed_far_end_m = 500.0;
uniform float bed_far_strength = 0.6;
uniform vec3 galets_tint : source_color = vec3(1.0);
uniform vec3 bed_far_tint : source_color = vec3(1.0);
uniform float sand_uv_scale = 0.08;
uniform float rock_uv_scale = 0.12;
uniform float earth_uv_scale = 0.19;
uniform float detail_normal_strength = 0.5;
uniform float macro_scale = 0.0045;
uniform float macro_strength = 0.3;
uniform float tiling_scale = 0.0021;
uniform vec3 sand_tint : source_color = vec3(1.0);
uniform vec3 rock_tint : source_color = vec3(1.0);
uniform vec3 earth_tint : source_color = vec3(1.0);

varying vec3 world_position;
varying vec3 world_normal;

float hash12(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(cell), hash12(cell + vec2(1.0, 0.0)), f.x), mix(hash12(cell + vec2(0.0, 1.0)), hash12(cell + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

// Deux lectures : la seconde, tournée et à une autre échelle, remplace la première là où le bruit lent l'indique.
vec4 sample_untiled(sampler2D tex, vec2 uv, float blend) {
	vec2 turned = vec2(uv.x * 0.8 - uv.y * 0.6, uv.x * 0.6 + uv.y * 0.8) * 0.37 + vec2(0.31, 0.77);
	return mix(texture(tex, uv), texture(tex, turned), blend);
}

void fragment() {
	float pierre = clamp(COLOR.r, 0.0, 1.0);
	float terre = clamp(COLOR.g, 0.0, 1.0);
	vec2 xz = world_position.xz;
	float blend = smoothstep(0.25, 0.75, value_noise(xz * tiling_scale));
	float macro = value_noise(xz * macro_scale) - 0.5;

	vec2 sand_uv = xz * sand_uv_scale;
	vec2 rock_uv = xz * rock_uv_scale;
	vec3 sand_color = sample_untiled(sand_albedo, sand_uv, blend).rgb * sand_tint * (1.0 + macro * macro_strength * 2.0);
	vec3 color = sand_color;
	float roughness = sample_untiled(sand_roughness, sand_uv, blend).g;
	vec2 detail = sample_untiled(sand_normal, sand_uv, blend).xy;
	if (terre > 0.001) {
		vec2 earth_uv = xz * earth_uv_scale;
		vec3 earth_color = texture(sand_albedo, earth_uv).rgb * earth_tint;
		color = mix(color, earth_color, terre);
		roughness = mix(roughness, texture(sand_roughness, earth_uv).g, terre);
	}
	if (pierre > 0.001) {
		vec3 rock_color = texture(rock_albedo, rock_uv).rgb * rock_tint * (1.0 - macro * macro_strength);
		color = mix(color, rock_color, pierre);
		roughness = mix(roughness, texture(rock_roughness, rock_uv).g, pierre);
		detail = mix(detail, texture(rock_normal, rock_uv).xy, pierre);
	}
	float galets = clamp(COLOR.b, 0.0, 1.0);
	if (galets > 0.001) {
		vec2 pebble_uv = xz * galets_uv_scale;
		color = mix(color, texture(galets_albedo, pebble_uv).rgb * galets_tint, galets);
		roughness = mix(roughness, texture(galets_roughness, pebble_uv).g, galets);
		detail = mix(detail, texture(galets_normal, pebble_uv).xy, galets);
	}
	// Vu de loin, le lit d'oued est teinté par le poids de proximité (alpha) : il reste visible aux niveaux de détail grossiers.
	float far_bed = clamp(COLOR.a, 0.0, 1.0) * smoothstep(bed_far_start_m, bed_far_end_m, length(VERTEX));
	color = mix(color, bed_far_tint, far_bed * bed_far_strength);
	ALBEDO = color;
	ROUGHNESS = roughness;
	detail = detail * 2.0 - 1.0;
	vec3 ground_normal = normalize(normalize(world_normal) + vec3(detail.x, 0.0, -detail.y) * detail_normal_strength);
	NORMAL = normalize((VIEW_MATRIX * vec4(ground_normal, 0.0)).xyz);
}
