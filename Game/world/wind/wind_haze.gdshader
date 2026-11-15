shader_type spatial;
// Brume de chaleur et poussière à l'horizon : anneau translucide autour de la caméra.
// Sans lecture de l'écran ni texture : bruit procédural 3D périodique (aucune couture), coût par pixel borné.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, fog_disabled;

global uniform vec2 wind_direction;
global uniform float wind_strength;
global uniform float wind_time;

uniform vec4 heat_color : source_color = vec4(1.0, 0.95, 0.8, 1.0);
uniform vec4 dust_color : source_color = vec4(0.8, 0.65, 0.4, 1.0);
uniform float heat_alpha = 0.16;
uniform float dust_alpha = 0.55;
uniform float noise_scale = 9.0;
uniform float shimmer_speed = 0.35;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x), mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x), mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}

void fragment() {
	float v = UV.y;
	float angle = UV.x * 6.28318530718;
	vec2 ring = vec2(cos(angle), sin(angle)) * noise_scale;
	float drift = wind_time * (0.15 + wind_strength);
	float n = value_noise(vec3(ring + wind_direction * drift * 0.2, v * noise_scale * 0.5 + wind_time * shimmer_speed));
	float low_edge = smoothstep(0.0, 0.05, v);
	float heat = heat_alpha * low_edge * pow(1.0 - v, 2.5) * (0.6 + 0.8 * n);
	float dust = dust_alpha * pow(wind_strength, 1.5) * low_edge * pow(1.0 - v, 1.2) * (0.4 + 0.6 * n);
	float total = heat + dust;
	ALBEDO = mix(heat_color.rgb, dust_color.rgb, dust / max(total, 0.0001));
	ALPHA = clamp(total, 0.0, 1.0);
}
