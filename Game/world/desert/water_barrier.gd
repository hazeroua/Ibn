class_name WaterBarrier
extends RefCounted
## Limite invisible autour d'un plan d'eau profond : un anneau de boîtes de collision (couche 1) posé au cercle où la
## profondeur atteint la profondeur maximale de gué. Le joueur ne peut pas aller plus loin (pas de nage).
##
## Une seule forme de boîte partagée par tout l'anneau, un seul corps statique, un propriétaire de forme par boîte
## (au plus max_segments). Construit une fois par plan d'eau, aucun coût par image.

const CONTEXT: String = "water_kinds.json > barrier"


## Corps statique centré sur le plan d'eau (origine à la hauteur de la surface). ring_radius_m : rayon du cercle de
## profondeur maximale ; depth_m : profondeur au centre. Les boîtes occupent l'intérieur du cercle, joueur dehors.
static func build(ring_radius_m: float, depth_m: float, settings: Dictionary, layer: int) -> StaticBody3D:
	var thickness: float = JsonData.get_float(settings, "thickness_m", CONTEXT)
	var above: float = JsonData.get_float(settings, "height_above_surface_m", CONTEXT)
	var max_chord: float = JsonData.get_float(settings, "max_chord_m", CONTEXT)
	var max_segments: int = JsonData.get_int(settings, "max_segments", CONTEXT)
	var below: float = JsonData.get_float(settings, "depth_below_floor_m", CONTEXT)
	if thickness <= 0.0 or above <= 0.0 or max_chord <= 0.0 or max_segments < 8 or below < 0.0 or ring_radius_m <= thickness:
		push_error("WaterBarrier : réglages ou rayon incohérents (%s)." % CONTEXT)
		return null
	var count: int = clampi(ceili(TAU * ring_radius_m / max_chord), 8, max_segments)
	var chord: float = 2.0 * ring_radius_m * sin(PI / float(count)) + thickness * 0.5
	var bottom: float = -depth_m - below
	var height: float = above - bottom
	var box := BoxShape3D.new()
	box.size = Vector3(chord, height, thickness)
	var body := StaticBody3D.new()
	body.name = "WaterBarrier"
	body.collision_layer = layer
	body.collision_mask = 0
	var centre_radius: float = ring_radius_m - thickness * 0.5
	for i: int in count:
		var angle: float = TAU * float(i) / float(count)
		var basis := Basis(Vector3.UP, -(angle + PI * 0.5))
		var origin := Vector3(cos(angle) * centre_radius, bottom + height * 0.5, sin(angle) * centre_radius)
		var owner_id: int = body.create_shape_owner(body)
		body.shape_owner_add_shape(owner_id, box)
		body.shape_owner_set_transform(owner_id, Transform3D(basis, origin))
	return body
