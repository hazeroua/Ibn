class_name FaunaWater
extends RefCounted
## Plans d'eau utiles à la faune (libellules, ancrage des sons et des oiseaux), lus dans desert.json :
## liste « water_bodies » ({ id, kind, center, radius_m, surface_height_m }). Chaque plan d'eau est un dictionnaire
## { id: String, kind: String, center: Vector2, radius: float, surface: float }.

const CONTEXT: String = "desert.json"


## Plans d'eau du désert ; tableau vide (et erreur) si les données sont invalides.
static func load_bodies(data: Dictionary, _field: DesertHeightfield) -> Array[Dictionary]:
	var bodies: Array[Dictionary] = []
	if data.has("water_bodies"):
		for entry: Variant in JsonData.get_array(data, "water_bodies", CONTEXT):
			if typeof(entry) != TYPE_DICTIONARY:
				push_error("FaunaWater : chaque plan d'eau doit être un objet (%s)." % CONTEXT)
				return []
			var body: Dictionary = entry
			var id: String = JsonData.get_string(body, "id", CONTEXT + " > water_bodies")
			var context: String = "%s > water_bodies > %s" % [CONTEXT, id]
			(
				bodies
				. append(
					{
						"id": id,
						"kind": str(body.get("kind", "eau")),
						"center": JsonData.get_vector2(body, "center", context),
						"radius": JsonData.get_float(body, "radius_m", context),
						"surface": JsonData.get_float(body, "surface_height_m", context),
					}
				)
			)
		return bodies
	push_error("FaunaWater : la liste water_bodies est absente (%s)." % CONTEXT)
	return bodies


## Plan d'eau d'ancrage « oasis » : le premier de type oasis, sinon le premier ; dictionnaire vide s'il n'y en a aucun.
static func oasis_anchor(bodies: Array[Dictionary]) -> Dictionary:
	for body: Dictionary in bodies:
		if body["kind"] == "oasis":
			return body
	if bodies.is_empty():
		return {}
	return bodies[0]
