// Terrain de la carte « collines » : deux surfaces (sable en base, pierre en recouvrement) mélangées par une
// carte de contrôle, normales lues dans une carte du relief (identiques pour tous les niveaux de détail).
// Les coordonnées de texture viennent de la position dans le monde : le maillage n'en porte aucune.
shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform sampler2D base_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D base_normal : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D base_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D overlay_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D overlay_normal : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D overlay_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
// RG8 : composantes X et Z de la normale du relief ; R8 : poids de la pierre. Un texel par sommet de la grille.
uniform sampler2D relief_normal : filter_linear_mipmap, repeat_disable;
uniform sampler2D control_map : filter_linear_mipmap, repeat_disable;
uniform vec2 map_origin;
uniform float map_size = 1024.0;
uniform float base_uv_scale = 0.08;
uniform float overlay_uv_scale = 0.12;
uniform float detail_normal_strength = 0.6;
uniform float macro_scale = 0.011;
uniform float macro_strength = 0.35;
uniform vec3 base_tint : source_color = vec3(1.0);
uniform vec3 overlay_tint : source_color = vec3(1.0);

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Les texels de la carte sont centrés sur les sommets : la grille couvre map_size mètres pour N texels.
	vec2 texel_count = vec2(textureSize(control_map, 0));
	vec2 map_uv = (world_position.xz - map_origin) / map_size * (texel_count - 1.0) / texel_count + 0.5 / texel_count;
	float weight = smoothstep(0.3, 0.7, texture(control_map, map_uv).r);

	vec2 base_uv = world_position.xz * base_uv_scale;
	vec2 overlay_uv = world_position.xz * overlay_uv_scale;
	// Variation à grande échelle : casse la répétition visible des textures.
	float macro = texture(base_roughness, world_position.xz * macro_scale).g - 0.5;
	vec3 base_color = texture(base_albedo, base_uv).rgb * base_tint * (1.0 + macro * macro_strength * 2.0);
	vec3 overlay_color = texture(overlay_albedo, overlay_uv).rgb * overlay_tint * (1.0 - macro * macro_strength);
	ALBEDO = mix(base_color, overlay_color, weight);
	ROUGHNESS = mix(texture(base_roughness, base_uv).g, texture(overlay_roughness, overlay_uv).g, weight);

	vec2 relief_xz = texture(relief_normal, map_uv).rg * 2.0 - 1.0;
	vec3 ground_normal = vec3(relief_xz.x, sqrt(max(1.0 - dot(relief_xz, relief_xz), 0.0)), relief_xz.y);
	vec2 detail = mix(texture(base_normal, base_uv).xy, texture(overlay_normal, overlay_uv).xy, weight) * 2.0 - 1.0;
	ground_normal = normalize(ground_normal + vec3(detail.x, 0.0, -detail.y) * detail_normal_strength);
	NORMAL = normalize((VIEW_MATRIX * vec4(ground_normal, 0.0)).xyz);
}
