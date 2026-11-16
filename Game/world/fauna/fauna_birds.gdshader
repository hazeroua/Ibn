shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;
// Vols d'oiseaux : un seul MultiMesh par espèce, posé à l'origine du monde (le repère du modèle est celui du monde).
// Le processeur ne fournit que deux vecteurs par groupe et par image (group_a, group_b) ; la position de chaque oiseau
// autour du centre de son groupe, son battement d'ailes (sommets repérés par l'alpha de la couleur : 0 corps, 1 bout
// d'aile) et son virage penché sont calculés ici. INSTANCE_CUSTOM : x phase, y indice du groupe, z et w tirages.
//   group_a = (centre x, centre y, centre z, étalement en vol)
//   group_b = (cap, envol 0..1, visible 0/1, inclinaison)

const int MAX_GROUPS = 16;

uniform vec4 group_a[MAX_GROUPS];
uniform vec4 group_b[MAX_GROUPS];
uniform float flap_hz = 6.0;
uniform float flap_amount = 0.6;
uniform float fold = 0.75;
uniform float perched_spread_m = 3.0;
uniform float height_variation_m = 3.0;

varying vec3 v_color;

void vertex() {
	int group = clamp(int(INSTANCE_CUSTOM.y + 0.5), 0, MAX_GROUPS - 1);
	vec4 a = group_a[group];
	vec4 b = group_b[group];
	if (b.z < 0.5) {
		VERTEX = vec3(0.0);
	} else {
		float phase = INSTANCE_CUSTOM.x;
		float flight = b.y;
		vec3 v = VERTEX;
		float wing = COLOR.a;
		// Ailes : repliées au repos, battantes en vol (déplacement proportionnel à la distance au corps).
		float spread_wing = mix(1.0 - fold, 1.0, flight);
		v.x *= mix(1.0, spread_wing, clamp(wing * 4.0, 0.0, 1.0));
		float flap = sin(TIME * flap_hz * 6.2831853 + phase) * flap_amount * flight;
		v.y += flap * wing * abs(v.x);
		// Inclinaison dans le virage : l'aile intérieure descend.
		float roll = b.w;
		float cr = cos(roll);
		float sr = sin(roll);
		v.xy = vec2(v.x * cr + v.y * sr, -v.x * sr + v.y * cr);
		// Cap : le modèle regarde vers -Z.
		float cy = cos(b.x);
		float sy = sin(b.x);
		v = vec3(v.x * cy + v.z * sy, v.y, -v.x * sy + v.z * cy);
		vec3 n = NORMAL;
		NORMAL = vec3(n.x * cy + n.z * sy, n.y, -n.x * sy + n.z * cy);
		// Position de l'oiseau dans son groupe : au sol serré, en vol étalé et ondulant.
		float spread = mix(perched_spread_m, a.w, flight);
		vec2 around = (vec2(INSTANCE_CUSTOM.z, INSTANCE_CUSTOM.w) - 0.5) * 2.0 * spread;
		vec2 wobble = vec2(sin(TIME * 0.7 + phase), cos(TIME * 0.9 + phase * 1.3)) * 0.8 * flight;
		float lift = (fract(INSTANCE_CUSTOM.z * 7.31 + INSTANCE_CUSTOM.w * 3.7) - 0.5) * height_variation_m * flight;
		float peck = (1.0 - flight) * max(0.0, sin(TIME * 2.3 + phase * 2.0)) * 0.02;
		VERTEX = v + vec3(a.x + around.x + wobble.x, a.y + lift + peck, a.z + around.y + wobble.y);
	}
	v_color = COLOR.rgb;
}

void fragment() {
	ALBEDO = v_color;
	ROUGHNESS = 0.9;
}
