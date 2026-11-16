shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_lambert, specular_schlick_ggx;
// Eau libre (oasis, lac, guelta) : aucun accès à la profondeur ni à la texture de l'écran (trop coûteux sur puce
// intégrée). La profondeur lisible vient de la couleur de sommet (rouge : 0 à la rive, 1 au point le plus profond,
// calculée à la construction du maillage). Vagues pilotées par le vent (uniformes globaux du ticket vent) ; le reflet
// du ciel vient du reflet de l'environnement (rugosité basse, réflexion métallique réglable).

global uniform vec2 wind_direction;
global uniform float wind_strength;
global uniform float wind_time;

uniform vec4 shallow_color : source_color;
uniform vec4 deep_color : source_color;
uniform vec4 foam_color : source_color;
uniform float wave_speed;
uniform float wave_scale;
uniform float wave_height;
uniform float normal_strength;
uniform float edge_width;
uniform float roughness_value;
uniform float reflection;
uniform float wind_gain;

varying vec2 world_xz;
varying float depth_fraction;
varying float wave_amount;

float wave(vec2 p, vec2 dir, float t) {
	float along = dot(p, dir);
	float across = dot(p, vec2(-dir.y, dir.x));
	return sin(along * 1.7 - t) * 0.5 + sin(across * 2.3 - t * 1.3 + along * 0.6) * 0.3 + sin((along + across) * 3.1 - t * 0.7) * 0.2;
}

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	depth_fraction = COLOR.r;
	wave_amount = (0.35 + wind_strength * wind_gain) * clamp(depth_fraction * 4.0, 0.0, 1.0);
	vec2 dir = normalize(wind_direction + vec2(0.0001));
	VERTEX.y += wave(world_xz * wave_scale, dir, wind_time * wave_speed * 3.0) * wave_height * wave_amount;
}

// Petites rides irrégulières : deux trains de vagues croisés et une modulation lente, pour ne jamais voir de motif répété.
vec2 ripple_slope(vec2 p, vec2 dir, float t) {
	vec2 side = vec2(-dir.y, dir.x);
	float e = 0.05;
	float b1 = wave(p, dir, t);
	float b2 = wave(p * 2.63 + vec2(3.1, 7.7), normalize(dir + side * 0.6), t * 1.37);
	float m = 0.6 + 0.4 * sin(dot(p, vec2(0.21, 0.17)) + t * 0.11);
	float h = b1 * m + b2 * 0.45;
	float hx = wave(p + vec2(e, 0.0), dir, t) * m + wave((p + vec2(e, 0.0)) * 2.63 + vec2(3.1, 7.7), normalize(dir + side * 0.6), t * 1.37) * 0.45;
	float hz = wave(p + vec2(0.0, e), dir, t) * m + wave((p + vec2(0.0, e)) * 2.63 + vec2(3.1, 7.7), normalize(dir + side * 0.6), t * 1.37) * 0.45;
	return vec2(hx - h, hz - h) / e;
}

void fragment() {
	vec2 dir = normalize(wind_direction + vec2(0.0001));
	vec2 p = world_xz * wave_scale;
	float t = wind_time * wave_speed * 3.0;
	vec2 slope = ripple_slope(p, dir, t);
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(slope.x, 0.0, slope.y, 0.0)).xyz * normal_strength * 0.35 * wave_amount);
	float edge = smoothstep(1.0 - edge_width, 1.0, UV.x);
	vec4 color = mix(shallow_color, deep_color, smoothstep(0.0, 1.0, depth_fraction));
	// Écume discrète au bord, l'eau devient transparente sur la dernière bande de rive (le fond se voit).
	color.rgb = mix(color.rgb, foam_color.rgb, edge * 0.25);
	ALBEDO = color.rgb;
	ALPHA = color.a * (1.0 - smoothstep(1.0 - edge_width * 0.6, 1.0, UV.x));
	ROUGHNESS = roughness_value;
	METALLIC = reflection;
	SPECULAR = 0.6;
}
