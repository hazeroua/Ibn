shader_type spatial;
// Terre de la palmeraie (murets en pisé, berges des séguias, rebords des bassins) : la même texture et la même teinte
// que la terre du terrain (desert_terrain.gdshader), projetées sur les trois axes du monde (les faces verticales des
// murets ne sont pas étirées). Les pieds des ouvrages, enfouis dans le sol, se confondent donc avec le terrain.
// COULEUR du sommet : r = part de pisé séché (plus clair), g = part de terre humide (plus sombre), b = nuance (0,5 neutre).
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D earth_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D earth_normal : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D earth_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float earth_uv_scale = 0.19;
uniform vec3 earth_tint : source_color = vec3(0.55, 0.42, 0.27);
uniform vec3 pise_tint : source_color = vec3(0.72, 0.58, 0.40);
uniform vec3 wet_tint : source_color = vec3(0.30, 0.22, 0.15);
uniform float shade_strength = 0.25;
uniform float detail_normal_strength = 0.5;
uniform float wet_roughness = 0.55;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

vec3 triplanar_weights(vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	return w / max(w.x + w.y + w.z, 0.0001);
}

void fragment() {
	vec3 w = triplanar_weights(world_normal);
	vec3 p = world_position * earth_uv_scale;
	vec3 albedo = texture(earth_albedo, p.zy).rgb * w.x + texture(earth_albedo, p.xz).rgb * w.y + texture(earth_albedo, p.xy).rgb * w.z;
	float rough = texture(earth_roughness, p.zy).g * w.x + texture(earth_roughness, p.xz).g * w.y + texture(earth_roughness, p.xy).g * w.z;
	vec2 nx = texture(earth_normal, p.zy).xy * 2.0 - 1.0;
	vec2 ny = texture(earth_normal, p.xz).xy * 2.0 - 1.0;
	vec2 nz = texture(earth_normal, p.xy).xy * 2.0 - 1.0;
	// Détail du relief : perturbation de la normale du monde dans le plan de chaque projection.
	vec3 detail = vec3(0.0, nx.y, nx.x) * w.x + vec3(ny.x, 0.0, -ny.y) * w.y + vec3(nz.x, nz.y, 0.0) * w.z;
	vec3 n = normalize(world_normal + detail * detail_normal_strength);
	float pise = clamp(COLOR.r, 0.0, 1.0);
	float wet = clamp(COLOR.g, 0.0, 1.0);
	float shade = 1.0 + (COLOR.b - 0.5) * 2.0 * shade_strength;
	vec3 tint = mix(mix(earth_tint, pise_tint, pise), wet_tint, wet);
	ALBEDO = albedo * tint * shade;
	ROUGHNESS = mix(rough, wet_roughness, wet);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
