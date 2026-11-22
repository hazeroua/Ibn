// Particule de poussière : panneau face à la caméra, couleur et opacité venant des particules,
// fondu selon la distance à la caméra (rien de collé à l'écran, rien au loin). Aucune lecture
// de l'écran ni de la profondeur : coût d'un simple quadrilatère transparent.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_disable;
// Distance (m) à partir de laquelle la particule est entièrement visible.
uniform float fade_near = 2.0;
// Distance (m) au-delà de laquelle la particule a disparu.
uniform float fade_far = 30.0;

void vertex() {
	// Panneau orienté vers la caméra, tourné selon l'angle de la particule (INSTANCE_CUSTOM.x).
	mat4 world = mat4(
			normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	float angle = INSTANCE_CUSTOM.x;
	world = world * mat4(vec4(cos(angle), -sin(angle), 0.0, 0.0), vec4(sin(angle), cos(angle), 0.0, 0.0),
							vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * world;
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
										  vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
										  vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec4 texel = texture(albedo_texture, UV);
	float distance_to_camera = length(VERTEX);
	float near_fade = smoothstep(fade_near * 0.25, fade_near, distance_to_camera);
	float far_fade = 1.0 - smoothstep(fade_far * 0.6, fade_far, distance_to_camera);
	ALBEDO = texel.rgb * COLOR.rgb;
	ALPHA = texel.a * COLOR.a * near_fade * far_fade;
}
