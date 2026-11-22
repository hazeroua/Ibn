// Chaleur qui fait trembler l'air : déformation de l'image limitée au lointain
// (au-delà de start_distance) et à une bande autour de l'horizon, pour ne jamais
// gêner la lecture du premier plan. Dessinée avant les autres objets transparents
// (priorité minimale) : la poussière et la brume restent nettes par-dessus.
shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, skip_vertex_transform, fog_disabled, shadows_disabled;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
// Carte de normales issue d'un bruit : ses composantes RG donnent un décalage signé.
uniform sampler2D noise_texture : filter_linear_mipmap, repeat_enable;
uniform float strength : hint_range(0.0, 0.02) = 0.0;
uniform float start_distance = 180.0;
uniform float full_distance = 1400.0;
uniform float horizon_band : hint_range(0.01, 1.0) = 0.1;
uniform float speed = 0.25;
uniform float noise_scale = 7.0;

void vertex() {
	// Quadrilatère plein écran (QuadMesh de 2 × 2).
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	view.xyz /= view.w;
	vec3 world_direction = normalize((INV_VIEW_MATRIX * vec4(view.xyz, 0.0)).xyz);
	float amount = smoothstep(start_distance, full_distance, length(view.xyz));
	amount *= 1.0 - smoothstep(0.0, horizon_band, abs(world_direction.y));
	vec2 drift = vec2(0.0, -TIME * speed);
	vec2 offset = texture(noise_texture, SCREEN_UV * vec2(noise_scale, noise_scale * 1.6) + drift).rg - 0.5;
	ALBEDO = textureLod(screen_texture, SCREEN_UV + offset * strength * amount, 0.0).rgb;
}
