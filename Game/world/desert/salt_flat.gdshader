shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;
// Chott : croûte de sel craquelée (motif cellulaire procédural) qui se couvre d'une pellicule d'eau miroir selon
// l'humidité de saison (uniforme global season_wetness), avec un mirage au loin à midi (water_midday). Aucun accès à
// la profondeur ni à l'écran. Le maillage suit le sol ; rouge de sommet : 1 au fond de la cuvette, 0 à la rive.

global uniform float season_wetness;
global uniform float water_midday;
global uniform float wind_time;

uniform vec3 salt_color : source_color;
uniform vec3 crack_color : source_color;
uniform vec3 mud_color : source_color;
uniform vec3 water_color : source_color;
uniform float crack_scale;
uniform float crack_width;
uniform float crack_fade_start;
uniform float crack_fade_end;
uniform float wet_roughness;
uniform float dry_roughness;
uniform float mirror_metallic;
uniform float far_lift_per_m;
uniform float mirage_start;
uniform float mirage_end;
uniform float mirage_horizon;
uniform vec3 mirage_color : source_color;
uniform float mirage_wobble;
uniform float edge_fade;

varying vec3 world_pos;
varying float bowl;
varying float view_distance;

vec2 hash22(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	q += dot(q, q.yzx + 33.33);
	return fract((q.xx + q.yz) * q.zy);
}

// Distance au bord de la cellule de Voronoï la plus proche (0 sur une craquelure).
float crack_distance(vec2 p) {
	vec2 cell = floor(p);
	vec2 local = fract(p);
	float nearest = 8.0;
	float second = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 offset = vec2(float(i), float(j));
			vec2 point = offset + hash22(cell + offset) - local;
			float d = dot(point, point);
			if (d < nearest) {
				second = nearest;
				nearest = d;
			} else if (d < second) {
				second = d;
			}
		}
	}
	return sqrt(second) - sqrt(nearest);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash22(i).x;
	float b = hash22(i + vec2(1.0, 0.0)).x;
	float c = hash22(i + vec2(0.0, 1.0)).x;
	float d = hash22(i + vec2(1.0, 1.0)).x;
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	bowl = COLOR.r;
	view_distance = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	// Légère remontée avec la distance : évite le scintillement avec le terrain lointain (grille plus grossière).
	VERTEX.y += view_distance * far_lift_per_m * clamp(bowl * 8.0, 0.0, 1.0);
}

void fragment() {
	// L'eau gagne d'abord le fond de la cuvette : plus la saison est humide, plus la pellicule s'étend vers la rive.
	float wet = clamp(season_wetness * 1.5 - (1.0 - bowl) * 0.9, 0.0, 1.0);
	wet = smoothstep(0.0, 0.35, wet);
	float near_detail = 1.0 - smoothstep(crack_fade_start, crack_fade_end, view_distance);
	float crack = 0.0;
	if (near_detail > 0.0) {
		float d = crack_distance(world_pos.xz * crack_scale);
		crack = (1.0 - smoothstep(0.0, crack_width * 4.0, d)) * near_detail;
	}
	vec3 dry = mix(salt_color, crack_color, crack * 0.8);
	vec3 damp = mix(dry, mud_color, wet * 0.5);
	vec3 albedo = mix(damp, water_color, wet);

	// Mirage : bande de reflet du ciel près de l'horizon, seulement de loin et à midi, surtout quand c'est sec.
	vec3 view_world = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float wobble = sin(world_pos.x * 0.05 + wind_time * mirage_wobble) * 0.5 + 0.5;
	float band = 1.0 - smoothstep(0.0, mirage_horizon * (0.7 + 0.6 * wobble), abs(view_world.y));
	float far = smoothstep(mirage_start, mirage_end, view_distance);
	float mirage = band * far * water_midday * (1.0 - 0.5 * wet);
	albedo = mix(albedo, mirage_color, mirage);

	ALBEDO = albedo;
	ROUGHNESS = mix(dry_roughness, wet_roughness, max(wet, mirage));
	METALLIC = mirror_metallic * max(wet, mirage);
	SPECULAR = 0.5;
	// Rive irrégulière : le bord du sel avance et recule (bruit à grande échelle) et se salit de sable avant de
	// disparaître, au lieu d'un cercle net.
	float lobes = value_noise(world_pos.xz * 0.012) * 0.6 + value_noise(world_pos.xz * 0.045) * 0.4;
	float rim = UV.x + (lobes - 0.5) * 0.35;
	float fade = 1.0 - smoothstep(edge_fade - 0.25, 1.0, rim);
	ALBEDO = mix(mud_color * 1.35, ALBEDO, smoothstep(0.0, 0.6, fade));
	ALPHA = fade;
}
