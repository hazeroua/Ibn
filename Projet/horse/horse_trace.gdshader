shader_type spatial;
render_mode cull_back;
// Empreinte de sabot dans le sable : sol assombri au creux, bords nets ; opaque, effacée par tramage en fin de vie
// (INSTANCE_CUSTOM.x = heure de pose, now_s = horloge des traces). Aucune transparence triée.

uniform vec4 imprint_color : source_color = vec4(0.36, 0.26, 0.16, 1.0);
uniform float lifetime_s = 45.0;
uniform float fade_s = 8.0;
uniform float now_s = 0.0;

varying float age_fraction;
varying vec2 local_uv;

void vertex() {
	float age = now_s - INSTANCE_CUSTOM.x;
	age_fraction = clamp((lifetime_s - age) / max(fade_s, 0.001), 0.0, 1.0);
	local_uv = UV * 2.0 - 1.0;
}

void fragment() {
	// Forme de sabot : ellipse ouverte vers l'arrière (fourchette).
	vec2 p = local_uv;
	float shape = 1.0 - smoothstep(0.82, 1.0, length(vec2(p.x * 1.05, p.y)));
	float frog = smoothstep(0.18, 0.32, length(vec2(p.x * 2.2, p.y - 0.55)));
	float mask = shape * mix(1.0, frog, step(0.0, p.y));
	ivec2 cell = ivec2(mod(FRAGCOORD.xy, 4.0));
	int index = cell.x + cell.y * 4;
	float bayer[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	if (mask < 0.5 || age_fraction <= (bayer[index] + 0.5) / 16.0) {
		discard;
	}
	float depth = smoothstep(0.5, 1.0, mask);
	ALBEDO = imprint_color.rgb * mix(1.0, 0.82, depth);
	ROUGHNESS = 1.0;
	SPECULAR = 0.2;
}
