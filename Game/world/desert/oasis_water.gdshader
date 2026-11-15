shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_lambert, specular_schlick_ggx;
// Eau de l'oasis : un seul maillage, aucune lecture de profondeur ni de texture d'écran
// (coûteuses sur puce intégrée). Le bord est lu dans l'attribut UV (0 au centre, 1 au bord).

uniform vec4 shallow_color : source_color;
uniform vec4 deep_color : source_color;
uniform vec4 foam_color : source_color;
uniform float wave_speed;
uniform float wave_scale;
uniform float wave_height;
uniform float normal_strength;
uniform float edge_width;
uniform float roughness_value;

float wave(vec2 p, float t) {
	return sin(p.x * 1.7 + t) * 0.5 + sin(p.y * 2.3 - t * 1.3) * 0.3 + sin((p.x + p.y) * 3.1 + t * 0.7) * 0.2;
}

varying vec2 world_xz;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	vec2 p = world_xz * wave_scale;
	VERTEX.y += wave(p, TIME * wave_speed) * wave_height;
}

void fragment() {
	vec2 p = world_xz * wave_scale;
	float t = TIME * wave_speed;
	float dx = wave(p + vec2(0.05, 0.0), t) - wave(p, t);
	float dz = wave(p + vec2(0.0, 0.05), t) - wave(p, t);
	NORMAL = normalize(NORMAL + vec3(dx, 0.0, dz) * normal_strength * 20.0);
	float edge = smoothstep(1.0 - edge_width, 1.0, UV.x);
	float depth = 1.0 - smoothstep(0.0, 0.85, UV.x);
	vec4 color = mix(shallow_color, deep_color, depth);
	color = mix(color, foam_color, edge * 0.8);
	ALBEDO = color.rgb;
	ALPHA = mix(color.a, 0.0, smoothstep(0.985, 1.0, UV.x));
	ROUGHNESS = roughness_value;
	SPECULAR = 0.6;
}
