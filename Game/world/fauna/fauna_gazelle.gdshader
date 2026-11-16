shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;
// Gazelles dorcas : la simulation (C++, FaunaHerds) fournit la transformée et, dans INSTANCE_CUSTOM, la phase de la
// foulée (x) et l'allure (y : 0 arrêt, 0,3 marche, 1 galop). Les pattes sont repérées par l'alpha de la couleur de
// sommet (0 corps, 0,5 genou, 1 sabot) : elles se balancent d'avant en arrière et se lèvent ; au pas les pattes
// vont par paires diagonales, au galop par paires avant et arrière. Le corps rebondit au galop.

uniform float walk_swing_m = 0.1;
uniform float run_swing_m = 0.26;
uniform float lift_m = 0.1;
uniform float bounce_m = 0.06;

varying vec3 v_color;

void vertex() {
	float phase = INSTANCE_CUSTOM.x;
	float gait = INSTANCE_CUSTOM.y;
	float run = smoothstep(0.35, 0.8, gait);
	float moving = smoothstep(0.0, 0.2, gait);
	float leg = COLOR.a;
	vec3 v = VERTEX;
	// Décalage de phase de la patte : côté (droite/gauche) et position (avant = -Z du modèle).
	float side = step(0.0, VERTEX.x);
	float front = step(VERTEX.z, 0.0);
	float walk_offset = 3.14159265 * (side + (1.0 - front));
	float run_offset = (1.0 - front) * 1.2;
	float angle = phase + mix(walk_offset, run_offset, run);
	float swing = sin(angle) * mix(walk_swing_m, run_swing_m, run) * moving;
	float lift = max(0.0, cos(angle)) * lift_m * moving;
	v.z += swing * leg;
	v.y += lift * leg;
	v.y += abs(sin(phase * 0.5)) * bounce_m * run;
	VERTEX = v;
	v_color = COLOR.rgb;
}

void fragment() {
	ALBEDO = v_color;
	ROUGHNESS = 0.95;
}
