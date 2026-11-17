// Corps commun des variantes de palmeraie_culture.gdshader (sans discard, hors transition) et palmeraie_culture_fade.gdshader
// (avec le fondu tramé, seulement pendant une transition de niveau de détail : LodFadeSwitch).
render_mode diffuse_burley, specular_disabled;
#ifdef LOD_FADE
#include "res://world/common/lod_fade.gdshaderinc"
#endif
// Sol cultivé de la palmeraie : un seul maillage par cellule, aucun coût par image côté processeur. La couleur de sommet porte
// la teinte de la culture (rgb) et sa croissance minimale (alpha : les cultures qui restent vertes toute l'année) ; UV est le
// repère local en mètres ; UV2 donne le style de semis (0 couvert plein, 1 semis dense, 2 rangs, 3 rangs larges) et l'écart
// des rangs. La saison arrive par les uniformes globaux : sol nu quand la croissance est nulle, doré à la moisson.

global uniform float season_crop_growth; // 0 : sol nu ; 1 : pleine végétation
global uniform float season_crop_ripe; // 0 : vert ; 1 : doré (moisson)

// Terre : même texture que la terre du terrain (desert_terrain.gdshader), projetée sur le plan du monde.
uniform sampler2D earth_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D earth_normal : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float earth_uv_scale = 0.19;
uniform float detail_normal_strength = 0.5;
uniform vec3 soil_color : source_color = vec3(0.36, 0.27, 0.18);
uniform vec3 soil_wet_color : source_color = vec3(0.25, 0.18, 0.12);
uniform vec3 ripe_color : source_color = vec3(0.8, 0.66, 0.28);

varying vec4 v_tint;
varying vec2 v_local;
varying vec2 v_style;
varying vec3 v_world;

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
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
#ifdef LOD_FADE
	if (lod_fade_discard(FRAGCOORD.xy, CAMERA_POSITION_WORLD)) {
		discard;
	}
#endif
	vec2 earth_uv = v_world.xz * earth_uv_scale;
	vec3 earth = texture(earth_albedo, earth_uv).rgb;
	float grain = dot(earth, vec3(0.333));
	// Le grain de l'albédo sert aussi au micro-relief : une lecture au lieu de deux par fragment.
	vec2 bump = vec2(earth.r - earth.g, earth.g - earth.b) * 2.0;
	float growth = clamp(max(season_crop_growth, v_tint.a), 0.0, 1.0);
	float style = v_style.x;
	float spacing = max(v_style.y, 0.01);
	float patch = value_noise(v_local * 0.35);
	float fine = value_noise(v_local * 2.3);
	float tiny = value_noise(v_local * 9.0);
	// Rangs parallèles à l'axe local u : sillons entre les rangs de plants.
	float row = abs(fract(v_local.y / spacing) - 0.5) * 2.0;
	float furrow = smoothstep(0.55, 0.95, row);
	float coverage = growth;
	if (style > 1.5) {
		coverage *= 1.0 - furrow * (style > 2.5 ? 0.85 : 0.65);
	} else if (style > 0.5) {
		coverage *= 1.0 - furrow * 0.25;
	} else {
		// Couvert plein (herbe sous les arbres, luzerne) : touffes et clairières, jamais un tapis uniforme.
		coverage *= 0.45 + 0.75 * patch;
	}
	coverage = clamp(coverage * (0.8 + 0.4 * fine) + (tiny - 0.5) * 0.12 + (grain - 0.5) * 0.25, 0.0, 1.0);
	coverage = smoothstep(0.2, 0.75, coverage) * step(0.01, growth);
	// La terre garde la texture du terrain (même grain qu'autour de la palmeraie), plus sombre dans les sillons arrosés.
	vec3 soil = earth * mix(soil_color, soil_wet_color, furrow * 0.7 + patch * 0.25);
	vec3 green = v_tint.rgb * (0.7 + 0.45 * fine) * (0.8 + 0.4 * grain);
	// Seules les cultures annuelles (sans croissance minimale) dorent à la moisson.
	float ripe = clamp(season_crop_ripe, 0.0, 1.0) * (1.0 - step(0.01, v_tint.a));
	vec3 plant = mix(green, ripe_color * (0.75 + 0.4 * fine), ripe);
	ALBEDO = mix(soil, plant, coverage);
	ROUGHNESS = 0.97;
	vec3 n = normalize(vec3(bump.x, 1.0 / max(detail_normal_strength * (1.0 - coverage * 0.6), 0.05), -bump.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
