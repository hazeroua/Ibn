shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_lambert, specular_schlick_ggx;
#include "res://world/common/lod_fade.gdshaderinc"
// Filet d'eau des séguias et du bassin de répartition : version étroite du shader de l'oasis, sans lecture de profondeur ni
// de texture d'écran. UV.x vaut 0 à une rive et 1 à l'autre ; UV.y est la distance parcourue en mètres (l'eau s'écoule dans ce sens).

uniform vec4 shallow_color : source_color = vec4(0.2, 0.52, 0.5, 0.6);
uniform vec4 deep_color : source_color = vec4(0.05, 0.24, 0.3, 0.88);
uniform float flow_speed = 0.8;
uniform float ripple_scale = 5.0;
uniform float roughness_value = 0.1;

void fragment() {
	if (lod_fade_discard(FRAGCOORD.xy, CAMERA_POSITION_WORLD)) {
		discard;
	}
	float across = abs(UV.x * 2.0 - 1.0);
	float flow = UV.y * ripple_scale - TIME * flow_speed * ripple_scale;
	float ripple = sin(flow + UV.x * 6.0) * 0.5 + sin(flow * 1.7 - UV.x * 9.0) * 0.5;
	vec4 color = mix(deep_color, shallow_color, smoothstep(0.0, 1.0, across));
	color.rgb += vec3(0.05) * ripple;
	ALBEDO = color.rgb;
	ALPHA = color.a;
	NORMAL = normalize(NORMAL + vec3(ripple * 0.06, 0.0, 0.0));
	ROUGHNESS = roughness_value;
	SPECULAR = 0.6;
}
