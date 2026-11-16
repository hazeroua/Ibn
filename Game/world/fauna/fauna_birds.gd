class_name FaunaBirds
extends Node3D
## Vols d'oiseaux du désert (tourterelles, moineaux, corbeaux bruns, vautours percnoptères).
##
## Rendu : un MultiMeshInstance3D par espèce ; la position de chaque oiseau, son battement d'ailes et son virage sont
## calculés par le vertex shader (fauna_birds.gdshader). Le processeur ne met à jour qu'une position de groupe par
## image : deux vecteurs (centre et étalement, cap et envol) par groupe, jamais d'oiseau par oiseau.
## Comportement d'un groupe : il tourne autour de son centre d'orbite ; s'il a un perchoir, il s'y pose quand le
## joueur reste loin assez longtemps et s'envole quand le joueur approche. Hors des heures d'activité, le groupe
## s'éloigne en spirale puis disparaît (et revient de même).
##
## Pires cas : 16 groupes par espèce au plus ; 4 espèces ; chaque groupe lit la distance du joueur une seule fois par
## image (carré de distance, sans racine) ; aucun tableau n'est alloué par image (deux jeux de vecteurs alternés,
## un seul appel set_shader_parameter par uniforme et par espèce) ; une espèce entièrement absente n'est ni
## mise à jour ni dessinée. 100 h de jeu : tous les angles sont ramenés dans [0, 2π[ et les états sont bornés.

const SHADER_PATH: String = "res://world/fauna/fauna_birds.gdshader"
const CONTEXT: String = "fauna.json > birds"
## Taille des tableaux du shader (MAX_GROUPS dans fauna_birds.gdshader).
const SHADER_GROUPS: int = 16
const ORBIT_SAMPLES: int = 16
const TAU_F: float = TAU


## État d'un groupe d'oiseaux.
class Flock:
	extends RefCounted
	var id: String = ""
	var shader_index: int = 0
	var orbit_center: Vector2 = Vector2.ZERO
	var orbit_radius: float = 1.0
	var flight_y: float = 0.0
	var omega: float = 0.0
	var angle: float = 0.0
	var has_perch: bool = false
	var perch: Vector3 = Vector3.ZERO
	var perch_heading: float = 0.0
	var flight: float = 0.0
	var target_flight: float = 0.0
	var presence: float = 0.0
	var settle_timer: float = 0.0
	var spread: float = 0.0


## Réglages et rendu d'une espèce.
class Species:
	extends RefCounted
	var id: StringName = &""
	var window: Vector3 = Vector3.ZERO
	var flee_distance_sq: float = 0.0
	var settle_distance_sq: float = 0.0
	var settle_delay: float = 0.0
	var transition: float = 1.0
	var leave_radius: float = 0.0
	var leave_seconds: float = 1.0
	var flocks: Array[Flock] = []
	var material: ShaderMaterial = null
	var multimesh: MultiMesh = null
	var node: MultiMeshInstance3D = null
	var buffers_a: Array[PackedVector4Array] = []
	var buffers_b: Array[PackedVector4Array] = []
	var buffer_index: int = 0


var _species: Array[Species] = []
var _flip: int = 0
var _active_bird_count: int = 0


## Construit toutes les espèces depuis fauna.json (clé « birds »). anchors : plans d'eau (FaunaWater). Renvoie false
## (avec erreur) si une donnée est invalide.
func build(birds: Dictionary, field: DesertHeightfield, anchors: Array[Dictionary], hour: float, aabb: AABB) -> bool:
	name = "FaunaBirds"
	var shader: Shader = load(SHADER_PATH) as Shader
	if shader == null:
		push_error("FaunaBirds : shader %s introuvable." % SHADER_PATH)
		return false
	var max_groups: int = JsonData.get_int(birds, "max_groups_per_species", CONTEXT)
	if max_groups < 1 or max_groups > SHADER_GROUPS:
		push_error("FaunaBirds : max_groups_per_species doit être entre 1 et %d (%s)." % [SHADER_GROUPS, CONTEXT])
		return false
	var all: Dictionary = JsonData.get_dictionary(birds, "species", CONTEXT)
	for id: Variant in all.keys():
		var species_id := StringName(str(id))
		var spec: Dictionary = JsonData.get_dictionary(all, str(id), CONTEXT + " > species")
		var species: Species = _build_species(species_id, spec, shader, field, anchors, max_groups, hour, aabb)
		if species == null:
			return false
		_species.append(species)
		add_child(species.node)
	return true


## Nombre total d'oiseaux (toutes espèces) : c'est ce qui compte pour le budget d'animaux affichés.
func get_bird_count() -> int:
	return _active_bird_count


## Nombre de groupes de toutes les espèces.
func get_flock_count() -> int:
	var total: int = 0
	for species: Species in _species:
		total += species.flocks.size()
	return total


## Groupe par identifiant (pour les tests et les captures) ; null s'il n'existe pas.
func find_flock(id: String) -> Flock:
	for species: Species in _species:
		for flock: Flock in species.flocks:
			if flock.id == id:
				return flock
	return null


## Met à jour tous les groupes : delta en secondes, heure du jour, position du joueur. Aucune allocation.
func update(delta: float, hour: float, player: Vector3) -> void:
	_flip = 1 - _flip
	for species: Species in _species:
		var present: bool = FaunaSchedule.weight(hour, species.window) > 0.0
		var any_visible: bool = false
		var group_a: PackedVector4Array = species.buffers_a[_flip]
		var group_b: PackedVector4Array = species.buffers_b[_flip]
		for flock: Flock in species.flocks:
			_update_flock(species, flock, delta, present, player)
			var index: int = flock.shader_index
			if flock.presence <= 0.0:
				group_b[index] = Vector4.ZERO
				continue
			any_visible = true
			_write_flock(species, flock, group_a, group_b)
		species.node.visible = any_visible
		if any_visible:
			species.material.set_shader_parameter(&"group_a", group_a)
			species.material.set_shader_parameter(&"group_b", group_b)


func _build_species(
	id: StringName,
	spec: Dictionary,
	shader: Shader,
	field: DesertHeightfield,
	anchors: Array[Dictionary],
	max_groups: int,
	hour: float,
	aabb: AABB
) -> Species:
	var context: String = "%s > species > %s" % [CONTEXT, id]
	var species := Species.new()
	species.id = id
	species.window = FaunaSchedule.parse(JsonData.get_dictionary(spec, "hours", context), context + " > hours")
	var flee: float = JsonData.get_float(spec, "flee_distance_m", context)
	var settle: float = JsonData.get_float(spec, "settle_distance_m", context)
	species.flee_distance_sq = flee * flee
	species.settle_distance_sq = settle * settle
	species.settle_delay = JsonData.get_float(spec, "settle_delay_s", context)
	species.transition = JsonData.get_float(spec, "transition_s", context)
	species.leave_radius = JsonData.get_float(spec, "leave_radius_m", context)
	species.leave_seconds = JsonData.get_float(spec, "leave_s", context)
	if flee <= 0.0 or settle <= flee or species.transition <= 0.0 or species.leave_seconds <= 0.0 or species.leave_radius <= 0.0:
		push_error("FaunaBirds : distances ou durées incohérentes (%s)." % context)
		return null
	var groups: Array = JsonData.get_array(spec, "groups", context)
	if groups.is_empty() or groups.size() > max_groups:
		push_error("FaunaBirds : entre 1 et %d groupes attendus (%s)." % [max_groups, context])
		return null
	var anchor: Dictionary = FaunaWater.oasis_anchor(anchors)
	var counts: PackedInt32Array = PackedInt32Array()
	var total: int = 0
	var spread: float = JsonData.get_float(spec, "airborne_spread_m", context)
	for index: int in groups.size():
		var group_value: Variant = groups[index]
		if typeof(group_value) != TYPE_DICTIONARY:
			push_error("FaunaBirds : chaque groupe doit être un objet (%s)." % context)
			return null
		var flock: Flock = _build_flock(group_value as Dictionary, index, field, anchor, species, spread, hour, context)
		if flock == null:
			return null
		species.flocks.append(flock)
		var count: int = JsonData.get_int(group_value as Dictionary, "count", context + " > groups")
		if count < 1 or count > 64:
			push_error("FaunaBirds : « count » doit être entre 1 et 64 (%s > %s)." % [context, flock.id])
			return null
		counts.append(count)
		total += count
	_active_bird_count += total
	var mesh: Mesh = FaunaMeshes.model_mesh(JsonData.get_string(spec, "model", context))
	if mesh == null:
		return null
	species.material = ShaderMaterial.new()
	species.material.shader = shader
	species.material.set_shader_parameter(&"flap_hz", JsonData.get_float(spec, "flap_hz", context))
	species.material.set_shader_parameter(&"flap_amount", JsonData.get_float(spec, "flap_amount", context))
	species.material.set_shader_parameter(&"fold", JsonData.get_float(spec, "fold", context))
	species.material.set_shader_parameter(&"perched_spread_m", JsonData.get_float(spec, "perched_spread_m", context))
	species.material.set_shader_parameter(&"height_variation_m", JsonData.get_float(spec, "height_variation_m", context))
	species.multimesh = MultiMesh.new()
	species.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	species.multimesh.use_custom_data = true
	species.multimesh.mesh = FaunaMeshes.with_material(mesh, species.material)
	species.multimesh.instance_count = total
	species.multimesh.custom_aabb = aabb
	species.multimesh.buffer = _instance_buffer(counts, int(id.hash()))
	species.node = MultiMeshInstance3D.new()
	species.node.name = String(id)
	species.node.multimesh = species.multimesh
	species.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	species.node.visible = false
	for _buffer_index: int in 2:
		var buffer_a := PackedVector4Array()
		buffer_a.resize(SHADER_GROUPS)
		var buffer_b := PackedVector4Array()
		buffer_b.resize(SHADER_GROUPS)
		species.buffers_a.append(buffer_a)
		species.buffers_b.append(buffer_b)
	return species


func _build_flock(
	group: Dictionary,
	index: int,
	field: DesertHeightfield,
	anchor: Dictionary,
	species: Species,
	spread: float,
	hour: float,
	context: String
) -> Flock:
	var flock := Flock.new()
	flock.id = JsonData.get_string(group, "id", context + " > groups")
	flock.shader_index = index
	var group_context: String = "%s > groups > %s" % [context, flock.id]
	if anchor.is_empty():
		push_error("FaunaBirds : aucun plan d'eau pour l'ancrage « oasis » (%s)." % group_context)
		return null
	var base: Vector2 = anchor["center"]
	flock.orbit_center = base + JsonData.get_vector2(group, "offset_m", group_context)
	flock.orbit_radius = JsonData.get_float(group, "orbit_radius_m", group_context)
	if flock.orbit_radius <= 0.0:
		push_error("FaunaBirds : orbit_radius_m doit être positif (%s)." % group_context)
		return null
	flock.spread = spread
	flock.omega = deg_to_rad(JsonData.get_float(group, "angular_speed_deg_s", group_context))
	if is_zero_approx(flock.omega):
		push_error("FaunaBirds : angular_speed_deg_s ne doit pas être nul (%s)." % group_context)
		return null
	# Altitude de croisière au-dessus du point le plus haut de l'orbite (les dunes ne doivent jamais couper le vol).
	var highest: float = -1.0e9
	for sample: int in ORBIT_SAMPLES:
		var angle: float = TAU_F * float(sample) / float(ORBIT_SAMPLES)
		var x: float = flock.orbit_center.x + cos(angle) * flock.orbit_radius
		var z: float = flock.orbit_center.y + sin(angle) * flock.orbit_radius
		highest = maxf(highest, field.height_at(x, z))
	highest = maxf(highest, field.height_at(flock.orbit_center.x, flock.orbit_center.y))
	flock.flight_y = highest + JsonData.get_float(group, "altitude_m", group_context)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(flock.id)
	flock.angle = rng.randf() * TAU_F
	flock.perch_heading = rng.randf() * TAU_F
	flock.has_perch = group.has("perch_offset_m")
	if flock.has_perch:
		var perch_xz: Vector2 = flock.orbit_center + JsonData.get_vector2(group, "perch_offset_m", group_context)
		flock.perch = Vector3(perch_xz.x, field.height_at(perch_xz.x, perch_xz.y) + 0.05, perch_xz.y)
	var start: String = JsonData.get_string(group, "start", group_context)
	if start != "perched" and start != "flying":
		push_error("FaunaBirds : start doit valoir perched ou flying (%s)." % group_context)
		return null
	if start == "perched" and not flock.has_perch:
		push_error("FaunaBirds : un groupe sans perchoir ne peut pas démarrer posé (%s)." % group_context)
		return null
	flock.flight = 1.0 if start == "flying" else 0.0
	flock.target_flight = flock.flight
	flock.presence = 1.0 if FaunaSchedule.weight(hour, species.window) > 0.0 else 0.0
	return flock


## Tampon initial des instances : transformée identité (le shader place tout) et données personnalisées
## (phase de battement, indice du groupe, deux tirages de position).
static func _instance_buffer(counts: PackedInt32Array, seed_value: int) -> PackedFloat32Array:
	var total: int = 0
	for count: int in counts:
		total += count
	var buffer := PackedFloat32Array()
	buffer.resize(total * 16)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var offset: int = 0
	for group: int in counts.size():
		for _bird: int in counts[group]:
			buffer[offset] = 1.0
			buffer[offset + 5] = 1.0
			buffer[offset + 10] = 1.0
			buffer[offset + 12] = rng.randf() * TAU_F
			buffer[offset + 13] = float(group)
			buffer[offset + 14] = rng.randf()
			buffer[offset + 15] = rng.randf()
			offset += 16
	return buffer


func _update_flock(species: Species, flock: Flock, delta: float, present: bool, player: Vector3) -> void:
	flock.presence = move_toward(flock.presence, 1.0 if present else 0.0, delta / species.leave_seconds)
	if flock.presence <= 0.0:
		return
	# Distance du joueur lue une seule fois par groupe et par image (au perchoir s'il y en a un).
	var dx: float = player.x - (flock.perch.x if flock.has_perch else flock.orbit_center.x)
	var dz: float = player.z - (flock.perch.z if flock.has_perch else flock.orbit_center.y)
	var distance_sq: float = dx * dx + dz * dz
	if not flock.has_perch or not present or flock.presence < 1.0:
		flock.target_flight = 1.0
		flock.settle_timer = 0.0
	elif flock.target_flight > 0.5:
		# En vol : se pose si le joueur reste loin assez longtemps.
		if distance_sq > species.settle_distance_sq:
			flock.settle_timer += delta
			if flock.settle_timer >= species.settle_delay:
				flock.target_flight = 0.0
		else:
			flock.settle_timer = 0.0
	elif distance_sq < species.flee_distance_sq:
		# Posé : s'envole quand le joueur approche.
		flock.target_flight = 1.0
		flock.settle_timer = 0.0
	flock.flight = move_toward(flock.flight, flock.target_flight, delta / species.transition)
	if flock.flight > 0.0:
		flock.angle = fposmod(flock.angle + flock.omega * delta, TAU_F)


func _write_flock(species: Species, flock: Flock, group_a: PackedVector4Array, group_b: PackedVector4Array) -> void:
	var arrival: float = smoothstep(0.0, 1.0, flock.presence)
	var radius: float = lerpf(species.leave_radius, flock.orbit_radius, arrival)
	var orbit_x: float = flock.orbit_center.x + cos(flock.angle) * radius
	var orbit_z: float = flock.orbit_center.y + sin(flock.angle) * radius
	var orbit_y: float = flock.flight_y + (1.0 - arrival) * 80.0
	var blend: float = smoothstep(0.0, 1.0, flock.flight)
	var x: float = orbit_x
	var y: float = orbit_y
	var z: float = orbit_z
	if flock.has_perch:
		x = lerpf(flock.perch.x, orbit_x, blend)
		y = lerpf(flock.perch.y, orbit_y, blend)
		z = lerpf(flock.perch.z, orbit_z, blend)
	# Tangente de l'orbite : le sens de rotation donne le cap (le modèle regarde vers -Z).
	var turn: float = signf(flock.omega)
	var tangent_x: float = -sin(flock.angle) * turn
	var tangent_z: float = cos(flock.angle) * turn
	var heading: float = lerp_angle(flock.perch_heading, atan2(-tangent_x, -tangent_z), blend)
	var index: int = flock.shader_index
	group_a[index] = Vector4(x, y, z, flock.spread)
	group_b[index] = Vector4(heading, flock.flight, 1.0, 0.3 * turn * blend)
