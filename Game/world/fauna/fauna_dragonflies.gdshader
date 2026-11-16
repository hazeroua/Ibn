shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;
// Libellules au-dessus de l'eau : tout est calculé ici, aucun travail du processeur par image. INSTANCE_CUSTOM : x phase,
// y indice du plan d'eau, z et w tirages. Chaque libellule suit une courbe de Lissajous bornée par le rayon de son plan
// d'eau (jamais plus de 0,85 rayon du centre), à hauteur variable ; son cap est la dérivée de la courbe ; ses quatre
// ailes (alpha de la couleur de sommet : 1 en bout d'aile) battent très vite.
//   waters[i] = (centre x, hauteur de la surface, centre z, rayon)

const int MAX_WATERS = 16;

uniform vec4 waters[MAX_WATERS];
uniform float speed = 1.0;
uniform float body_scale = 2.0;
uniform float flap_hz = 38.0;
uniform float flap_amount = 0.5;
uniform float hover_min_m = 0.5;
uniform float hover_max_m = 1.9;

varying vec3 v_color;

void vertex() {
	int site = clamp(int(INSTANCE_CUSTOM.y + 0.5), 0, MAX_WATERS - 1);
	vec4 water = waters[site];
	float phase = INSTANCE_CUSTOM.x;
	float s1 = INSTANCE_CUSTOM.z * 6.2831853;
	float s2 = INSTANCE_CUSTOM.w * 6.2831853;
	float t = TIME * speed + phase * 3.0;
	float reach = water.w * 0.6;
	vec2 p = vec2(sin(t * 0.37 + s1) * 0.9 + sin(t * 0.91 + s2) * 0.35, cos(t * 0.43 + s2) * 0.9 + cos(t * 0.77 + s1) * 0.3) * reach;
	vec2 d = vec2(cos(t * 0.37 + s1) * 0.9 * 0.37 + cos(t * 0.91 + s2) * 0.35 * 0.91, -sin(t * 0.43 + s2) * 0.9 * 0.43 - sin(t * 0.77 + s1) * 0.3 * 0.77);
	float hover = mix(hover_min_m, hover_max_m, 0.5 + 0.5 * sin(t * 0.6 + s1 * 2.0));
	float heading = atan(-d.x, -d.y);
	float ch = cos(heading);
	float sh = sin(heading);
	vec3 v = VERTEX * body_scale;
	float wing = COLOR.a;
	v.y += sin(TIME * flap_hz * 6.2831853 + phase * 7.0) * flap_amount * wing * abs(v.x);
	vec3 rotated = vec3(v.x * ch + v.z * sh, v.y, -v.x * sh + v.z * ch);
	vec3 n = NORMAL;
	NORMAL = vec3(n.x * ch + n.z * sh, n.y, -n.x * sh + n.z * ch);
	VERTEX = rotated + vec3(water.x + p.x, water.y + hover, water.z + p.y);
	v_color = COLOR.rgb;
}

void fragment() {
	ALBEDO = v_color;
	ROUGHNESS = 0.6;
}
