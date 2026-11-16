class_name LodFade
extends RefCounted
## Plages de visibilité avec fondu tramé (lod_fade.gdshaderinc) au lieu du fondu transparent de Godot.
## Godot n'affiche l'instance qu'entre begin - begin_margin et end + end_margin (sans fondu) ; le shader trame
## l'apparition et la disparition dans les marges. Réglage une fois à la création de l'instance ; rien par image.


## center : centre de l'objet dans le repère du monde (celui que Godot utilise pour les plages de visibilité).
## begin = 0 : visible dès la caméra. end = 0 : jamais masqué au loin.
static func apply(instance: GeometryInstance3D, center: Vector3, begin: float, begin_margin: float, end: float, end_margin: float) -> void:
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	var fade := Vector4(-2.0, -1.0, 1.0e9, 2.0e9)
	if begin > 0.0:
		instance.visibility_range_begin = maxf(begin - begin_margin, 0.0)
		instance.visibility_range_begin_margin = 0.0
		fade.x = begin - begin_margin
		fade.y = begin
	if end > 0.0:
		instance.visibility_range_end = end + end_margin
		instance.visibility_range_end_margin = 0.0
		fade.z = end
		fade.w = end + end_margin
	instance.set_instance_shader_parameter(&"lod_fade", fade)
	instance.set_instance_shader_parameter(&"lod_center", center)
