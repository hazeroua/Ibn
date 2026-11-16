shader_type spatial;
render_mode diffuse_burley, specular_disabled;
// Sol cultivé de la palmeraie : un seul maillage par cellule, aucun coût par image côté processeur. La couleur de sommet porte
// la teinte de la culture (rgb) et sa croissance minimale (alpha : les cultures qui restent vertes toute l'année) ; UV est le
// repère local en mètres ; UV2 donne le style de semis (0 couvert plein, 1 semis dense, 2 rangs, 3 rangs larges) et l'écart
// des rangs. La saison arrive par les uniformes globaux : sol nu quand la croissance est nulle, doré à la moisson.

global uniform float season_crop_growth; // 0 : sol nu ; 1 : pleine végétation
global uniform float season_crop_ripe; // 0 : vert ; 1 : doré (moisson)

uniform vec3 soil_color : source_color = vec3(0.36, 0.27, 0.18);
uniform vec3 soil_wet_color : source_color = vec3(0.25, 0.18, 0.12);
uniform vec3 ripe_color : source_color = vec3(0.8, 0.66, 0.28);

varying vec4 v_tint;
varying vec2 v_local;
varying vec2 v_style;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	v_tint = COLOR;
	v_local = UV;
	v_style = UV2;
}

void fragment() {
	float growth = clamp(max(season_crop_growth, v_tint.a), 0.0, 1.0);
	float style = v_style.x;
	float spacing = max(v_style.y, 0.01);
	float patch = value_noise(v_local * 0.45);
	float fine = value_noise(v_local * 3.1);
	// Rangs parallèles à l'axe local u : sillons entre les rangs de plants.
	float row = abs(fract(v_local.y / spacing) - 0.5) * 2.0;
	float furrow = smoothstep(0.55, 0.95, row);
	float coverage = growth;
	if (style > 1.5) {
		coverage *= 1.0 - furrow * (style > 2.5 ? 0.85 : 0.65);
	} else if (style > 0.5) {
		coverage *= 1.0 - furrow * 0.25;
	}
	coverage = clamp(coverage * (0.75 + 0.5 * patch) + (fine - 0.5) * 0.15, 0.0, 1.0);
	coverage = smoothstep(0.05, 0.55, coverage) * step(0.01, growth);
	vec3 soil = mix(soil_color, soil_wet_color, furrow * 0.7 + patch * 0.2);
	vec3 green = v_tint.rgb * (0.8 + 0.4 * fine);
	vec3 plant = mix(green, ripe_color * (0.8 + 0.35 * fine), clamp(season_crop_ripe, 0.0, 1.0));
	ALBEDO = mix(soil, plant, coverage);
	ROUGHNESS = 0.97;
}
