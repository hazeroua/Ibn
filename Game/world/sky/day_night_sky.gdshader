shader_type sky;
render_mode use_debanding;
// Ciel du cycle jour/nuit : dégradé horizon/zénith, halo et disque du soleil, disque de la lune avec
// phase, étoiles procédurales. Tous les paramètres sont fournis par DayNight (courbes JSON).
// Étoiles ignorées dans la passe cubemap (éclairage ambiant et reflets) : inutile et coûteux.

uniform vec3 sky_top : source_color = vec3(0.2, 0.4, 0.8);
uniform vec3 sky_horizon : source_color = vec3(0.8, 0.8, 0.7);
uniform vec3 ground_horizon : source_color = vec3(0.7, 0.6, 0.4);
uniform vec3 ground_bottom : source_color = vec3(0.4, 0.3, 0.2);
uniform vec3 sun_color : source_color = vec3(1.0, 0.9, 0.7);
uniform vec3 moon_color : source_color = vec3(0.8, 0.85, 1.0);
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_direction = vec3(0.0, -1.0, 0.0);
uniform float sun_glow = 0.2;
uniform float sun_visibility = 1.0;
uniform float moon_visibility = 0.0;
uniform float moon_phase = 0.5;
uniform float star_alpha = 0.0;
uniform float horizon_curve = 0.45;
uniform float ground_curve = 0.35;
uniform float glow_power = 6.0;
uniform float sun_cos_size = 0.9996;
uniform float moon_cos_size = 0.9984;
uniform float star_density = 0.02;
uniform float star_scale = 90.0;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float height = dir.y;
	vec3 color;
	if (height >= 0.0) {
		color = mix(sky_horizon, sky_top, pow(clamp(height, 0.0, 1.0), horizon_curve));
	} else {
		color = mix(ground_horizon, ground_bottom, pow(clamp(-height, 0.0, 1.0), ground_curve));
	}

	float sun_dot = dot(dir, normalize(sun_direction));
	float glow = pow(max(sun_dot, 0.0), glow_power) * sun_glow;
	color += sun_color * glow * (1.0 - clamp(-height * 4.0, 0.0, 1.0));
	float sun_disk = smoothstep(sun_cos_size, mix(sun_cos_size, 1.0, 0.35), sun_dot);
	color = mix(color, sun_color * 6.0, sun_disk * step(0.0, height + 0.02) * clamp(sun_visibility, 0.0, 1.0));

	if (!AT_CUBEMAP_PASS) {
		vec3 moon_dir = normalize(moon_direction);
		float night = clamp(star_alpha, 0.0, 1.0);
		if (height > 0.0 && night > 0.0) {
			vec3 cell = floor(dir * star_scale);
			float h = hash13(cell);
			vec3 offset = fract(dir * star_scale) - 0.5;
			float star = step(1.0 - star_density, h) * smoothstep(0.3, 0.0, length(offset));
			color += vec3(0.85, 0.9, 1.0) * star * (0.4 + 0.6 * fract(h * 37.0)) * night * smoothstep(0.0, 0.15, height) * 2.0;
		}
		float moon_dot = dot(dir, moon_dir);
		if (moon_dot > moon_cos_size && height > -0.02) {
			// Repère du disque : x vers la droite, y vers le haut, z vers la lune.
			vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), moon_dir));
			vec3 up = cross(moon_dir, right);
			float radius = sqrt(max(1.0 - moon_cos_size * moon_cos_size, 1e-9));
			vec2 disk = vec2(dot(dir, right), dot(dir, up)) / radius;
			float rim = length(disk);
			float terminator = -cos(moon_phase * 6.2831853) * sqrt(max(1.0 - disk.y * disk.y, 0.0));
			float lit = smoothstep(terminator - 0.08, terminator + 0.08, disk.x);
			float edge = 1.0 - smoothstep(0.92, 1.0, rim);
			color = mix(color, moon_color * (0.15 + 1.6 * lit), edge * clamp(moon_visibility * 8.0, 0.0, 1.0));
		}
	}
	COLOR = color;
}
