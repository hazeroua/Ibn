class_name FaunaGazelles
extends Node3D
## Troupeaux de gazelles dorcas sur les regs. Toute la simulation est dans l'extension C++ FaunaHerds (cohésion,
## fuite au galop, apaisement, pentes) ; ce nœud ne fait que la préparer et l'appeler une fois par image.
##
## Démarrage : la lecture du relief par lot (grilles de hauteurs des zones) se fait dans un fil de travail pour ne
## pas bloquer le chargement ; les gazelles apparaissent dès que la préparation est finie.
## Pires cas : 128 gazelles au plus (réglage max_animals), joueur au galop au milieu d'un troupeau ; partie de 100 h :
## positions bornées par la zone de chaque troupeau, aucune allocation par image (tampon du MultiMesh réutilisé).

const SHADER_PATH: String = "res://world/fauna/fauna_gazelle.gdshader"
const CONTEXT: String = "fauna.json > gazelles"
## Valeurs de HerdState de l'extension.
const STATE_GRAZING: int = 0
const STATE_WALKING: int = 1
const STATE_FLEEING: int = 2
const AABB_MARGIN_M: float = 40.0
const AABB_HEIGHT_M: float = 400.0

## Gardé ici : le fil de travail l'utilise pendant la préparation, puis le jeu à chaque image.
var _herds: FaunaHerds = null
var _multimesh: MultiMesh = null
var _instance: MultiMeshInstance3D = null
var _mesh: Mesh = null
var _settings: Dictionary = {}
var _zones: Array = []
var _field: DesertHeightfield = null
var _seed: int = 0
var _task_id: int = -1
var _setup_ok: bool = false
var _ready_for_steps: bool = false


## Prépare les gazelles (réglages « gazelles » de fauna.json) ; la simulation démarre quand is_running() devient vrai.
func build(settings: Dictionary, field: DesertHeightfield, world_seed: int) -> bool:
	name = "FaunaGazelles"
	var shader: Shader = load(SHADER_PATH) as Shader
	if shader == null:
		push_error("FaunaGazelles : shader %s introuvable." % SHADER_PATH)
		return false
	_settings = settings
	_field = field
	_seed = world_seed
	_zones = _parse_zones(JsonData.get_array(settings, "zones", CONTEXT))
	if _zones.is_empty():
		return false
	var animation: Dictionary = JsonData.get_dictionary(settings, "animation", CONTEXT)
	var material := ShaderMaterial.new()
	material.shader = shader
	for key: String in ["walk_swing_m", "run_swing_m", "lift_m", "bounce_m"]:
		material.set_shader_parameter(StringName(key), JsonData.get_float(animation, key, CONTEXT + " > animation"))
	var mesh: Mesh = FaunaMeshes.model_mesh(JsonData.get_string(settings, "model", CONTEXT))
	if mesh == null:
		return false
	_mesh = FaunaMeshes.with_material(mesh, material)
	_herds = FaunaHerds.new()
	return true


## Lance la préparation dans un fil de travail (à appeler une fois, quand tout le reste de la faune est valide).
func begin() -> void:
	if _task_id < 0 and not _ready_for_steps:
		_task_id = WorkerThreadPool.add_task(_prepare_herds, false, "Faune : relief des zones de gazelles")


## Vrai quand la simulation tourne (préparation terminée, MultiMesh lié).
func is_running() -> bool:
	return _ready_for_steps


## Nombre de gazelles (0 avant la fin de la préparation).
func get_animal_count() -> int:
	return _herds.get_animal_count() if _ready_for_steps else 0


## Simulation C++ (pour les tests et les captures) ; null avant la fin de la préparation.
func get_herds() -> FaunaHerds:
	return _herds if _ready_for_steps else null


## Une image : finit la préparation si besoin, puis avance la simulation. Aucune allocation.
func update(delta: float, player: Vector3) -> void:
	if _ready_for_steps:
		_herds.step(delta, player)
		return
	if _task_id < 0 or not WorkerThreadPool.is_task_completed(_task_id):
		return
	WorkerThreadPool.wait_for_task_completion(_task_id)
	_task_id = -1
	if not _setup_ok:
		push_error("FaunaGazelles : préparation impossible : %s" % _herds.get_last_error())
		return
	_attach()


## Attend la fin de la préparation (tests, fermeture du jeu).
func finish_setup() -> bool:
	if _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
		if not _setup_ok:
			push_error("FaunaGazelles : préparation impossible : %s" % _herds.get_last_error())
			return false
		_attach()
	return _ready_for_steps


func _exit_tree() -> void:
	if _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1


func _prepare_herds() -> void:
	_setup_ok = _herds.setup(_settings, _zones, _field, _seed)


func _attach() -> void:
	var count: int = _herds.get_animal_count()
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_custom_data = true
	_multimesh.mesh = _mesh
	_multimesh.instance_count = count
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for zone: int in _herds.get_zone_count():
		var bounds: PackedFloat32Array = _herds.get_zone_bounds(zone)
		low = Vector2(minf(low.x, bounds[0]), minf(low.y, bounds[1]))
		high = Vector2(maxf(high.x, bounds[2]), maxf(high.y, bounds[3]))
	_multimesh.custom_aabb = AABB(
		Vector3(low.x - AABB_MARGIN_M, -50.0, low.y - AABB_MARGIN_M),
		Vector3(high.x - low.x + 2.0 * AABB_MARGIN_M, AABB_HEIGHT_M, high.y - low.y + 2.0 * AABB_MARGIN_M)
	)
	if not _herds.bind_multimesh(_multimesh):
		push_error("FaunaGazelles : liaison du MultiMesh impossible : %s" % _herds.get_last_error())
		return
	_instance = MultiMeshInstance3D.new()
	_instance.name = "Gazelles"
	_instance.multimesh = _multimesh
	_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_instance)
	_ready_for_steps = true


## Convertit les zones de fauna.json au format attendu par FaunaHerds.
func _parse_zones(zones: Array) -> Array:
	var result: Array = []
	for entry: Variant in zones:
		if typeof(entry) != TYPE_DICTIONARY:
			push_error("FaunaGazelles : chaque zone doit être un objet (%s)." % CONTEXT)
			return []
		var zone: Dictionary = entry
		var id: String = JsonData.get_string(zone, "id", CONTEXT + " > zones")
		var context: String = "%s > zones > %s" % [CONTEXT, id]
		var shape: Dictionary = JsonData.get_dictionary(zone, "shape", context)
		var kind: String = JsonData.get_string(shape, "kind", context + " > shape")
		var parsed: Dictionary = {
			"kind": kind,
			"herds": JsonData.get_int(zone, "herds", context),
			"size_min": JsonData.get_int(zone, "size_min", context),
			"size_max": JsonData.get_int(zone, "size_max", context),
		}
		if kind == "circle":
			parsed["center"] = JsonData.get_vector2(shape, "center", context + " > shape")
			parsed["radius_m"] = JsonData.get_float(shape, "radius_m", context + " > shape")
		elif kind == "polygon":
			var points := PackedVector2Array()
			for point: Variant in JsonData.get_array(shape, "points", context + " > shape"):
				if typeof(point) != TYPE_ARRAY or (point as Array).size() != 2:
					push_error("FaunaGazelles : chaque sommet doit être [x, z] (%s)." % context)
					return []
				var pair: Array = point
				points.append(Vector2(float(pair[0]), float(pair[1])))
			parsed["points"] = points
		else:
			push_error("FaunaGazelles : forme de zone inconnue « %s » (%s)." % [kind, context])
			return []
		result.append(parsed)
	return result
