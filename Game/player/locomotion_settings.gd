class_name LocomotionSettings
extends RefCounted
## Réglages du déplacement du personnage joueur, lus dans res://data/player/locomotion.json.
##
## Toutes les valeurs sont vérifiées au chargement : une valeur absente, mal typée ou hors de
## son domaine est signalée par push_error (ce qui fait échouer le pipeline). Les valeurs par
## allure sont rangées dans des tableaux indexés par Gait pour une lecture sans recherche ni
## allocation pendant le jeu.

enum Gait { IDLE, WALK_SLOW, WALK, RUN }

const PATH: String = "res://data/player/locomotion.json"
const CONTEXT: String = "locomotion.json"
## Noms des allures (contrat du MVP 1), indexés par Gait.
const GAIT_NAMES: Array[StringName] = [&"idle", &"walk_slow", &"walk", &"run"]
const MAX_LAYER: int = 32

# Corps
var body_radius: float = 0.0
var body_height: float = 0.0
var collision_layer: int = 0
var collision_mask: int = 0
var safe_margin: float = 0.0

# Physique
var gravity: float = 0.0
var terminal_fall_speed: float = 0.0
var floor_max_angle: float = 0.0
var floor_snap_base_length: float = 0.0
var wall_min_slide_angle: float = 0.0
var max_slides: int = 0
var air_control: float = 0.0
var teleport_distance: float = 0.0

# Marches
var step_max_height: float = 0.0
var step_min_height: float = 0.0
var step_clearance: float = 0.0
var step_surface_inset: float = 0.0
var step_headroom_probe_distance: float = 0.0
var climb_retry_delay: float = 0.0

# Entrées
var input_smoothing_time: float = 0.0
var move_threshold: float = 0.0
var analog_walk_slow_max: float = 0.0
var analog_hysteresis: float = 0.0
var analog_min_speed_fraction: float = 0.0
var idle_confirm_time: float = 0.0

# Allures (indexées par Gait ; la case IDLE vaut 0)
var gait_speed := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var gait_acceleration := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var gait_deceleration := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var gait_turn_rate := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var gait_stride_length := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var gait_animation_reference_speed := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])

# Virages
var turn_90_min_angle: float = 0.0
var turn_180_min_angle: float = 0.0
var turn_90_duration: float = 0.0
var turn_180_duration: float = 0.0
var turn_90_speed_factor: float = 0.0
var turn_180_speed_factor: float = 0.0
var turn_deceleration: float = 0.0
var turn_cooldown: float = 0.0
var turn_confirm_time: float = 0.0
var turn_stable_angle: float = 0.0

# Arrêts
var stop_min_speed_fraction: float = 0.0
var stop_min_duration: float = 0.0
var stop_max_duration: float = 0.0

# Pas
var first_step_fraction: float = 0.0
var foot_lateral_offset: float = 0.0
var foot_ray_start_height: float = 0.0
var foot_ray_depth: float = 0.0
var foot_ray_mask: int = 0
var rest_speed: float = 0.0
var stop_step_min_fraction: float = 0.0
## Os des pieds (gauche, droit) dont les appuis, lus dans les animations, déclenchent les pas quand un modèle est branché.
var foot_bone_names := PackedStringArray()
var contact_height: float = 0.0
var contact_lift: float = 0.0
var contact_samples_per_second: float = 0.0
var contact_min_gap: float = 0.0
var contact_min_travel: float = 0.0
## Réactions au monde (section « impact ») : choc contre un mur, roulade, franchissement d'obstacles bas.
var bump_min_speed: float = 0.0
var bump_min_facing: float = 0.0
var blocked_speed: float = 0.0
var roll_min_air: float = 0.0
var roll_min_speed: float = 0.0
var vault_min_speed: float = 0.0
var vault_min_facing: float = 0.0
var vault_min_height: float = 0.0
var vault_max_height: float = 0.0
var vault_max_depth: float = 0.0
var vault_max_drop: float = 0.0
var vault_clearance: float = 0.0
var vault_min_gap: float = 0.0
var vault_look_ahead: float = 0.0
var vault_min_duration: float = 0.0
var vault_max_duration: float = 0.0
var vault_samples: int = 0
## Saut (section « jump »).
var jump_speed: float = 0.0
var jump_coyote: float = 0.0
var jump_buffer: float = 0.0
var jump_landing_min_air: float = 0.0
var jump_blend: float = 0.0

# Animation
var blend_time: float = 0.0
var one_shot_blend_time: float = 0.0
var speed_scale_min: float = 0.0
var speed_scale_max: float = 0.0

# Marche dans l'eau peu profonde
var wading_max_depth: float = 0.0
var wading_enter_depth: float = 0.0
var wading_speed_multiplier: float = 1.0
var wading_smoothing: float = 0.0
var splash: Dictionary = {}

# Budgets du test de charge
var budget_step_average_ms: float = 0.0
var budget_step_p95_ms: float = 0.0

## Nombre d'erreurs relevées pendant la lecture (0 si les données sont valides).
var error_count: int = 0


static func load_file(path: String = PATH) -> LocomotionSettings:
	return from_dictionary(JsonData.load_dictionary(path))


static func from_dictionary(data: Dictionary) -> LocomotionSettings:
	var settings := LocomotionSettings.new()
	settings._read_body(JsonData.get_dictionary(data, "body", CONTEXT))
	settings._read_physics(JsonData.get_dictionary(data, "physics", CONTEXT))
	settings._read_steps(JsonData.get_dictionary(data, "steps", CONTEXT))
	settings._read_input(JsonData.get_dictionary(data, "input", CONTEXT))
	settings._read_gaits(JsonData.get_dictionary(data, "gaits", CONTEXT))
	settings._read_turns(JsonData.get_dictionary(data, "turns", CONTEXT))
	settings._read_stops(JsonData.get_dictionary(data, "stops", CONTEXT))
	settings._read_jump(JsonData.get_dictionary(data, "jump", CONTEXT))
	settings._read_impact(JsonData.get_dictionary(data, "impact", CONTEXT))
	settings._read_footsteps(JsonData.get_dictionary(data, "footsteps", CONTEXT))
	settings._read_animation(JsonData.get_dictionary(data, "animation", CONTEXT))
	settings._read_wading(JsonData.get_dictionary(data, "wading", CONTEXT))
	settings._read_budgets(JsonData.get_dictionary(data, "budgets", CONTEXT))
	settings._check_consistency()
	return settings


## Longueur de foulée de l'allure (la case IDLE renvoie celle de la marche).
func stride_for(gait: int) -> float:
	return gait_stride_length[Gait.WALK if gait == Gait.IDLE else gait]


func _read_body(section: Dictionary) -> void:
	var context: String = CONTEXT + " > body"
	body_radius = _positive(section, "radius", context)
	body_height = _positive(section, "height", context)
	collision_layer = _layers(section, "collision_layers", context)
	collision_mask = _layers(section, "collision_mask_layers", context)
	safe_margin = _positive(section, "safe_margin", context)
	_check(body_height > 2.0 * body_radius, "la hauteur doit dépasser le diamètre de la capsule", context)


func _read_physics(section: Dictionary) -> void:
	var context: String = CONTEXT + " > physics"
	gravity = _positive(section, "gravity", context)
	terminal_fall_speed = _positive(section, "terminal_fall_speed", context)
	floor_max_angle = deg_to_rad(_ranged(section, "floor_max_angle_degrees", 1.0, 89.0, context))
	floor_snap_base_length = _positive(section, "floor_snap_base_length", context)
	wall_min_slide_angle = deg_to_rad(_ranged(section, "wall_min_slide_angle_degrees", 0.0, 89.0, context))
	max_slides = int(_ranged(section, "max_slides", 1.0, 16.0, context))
	air_control = _ranged(section, "air_control", 0.0, 1.0, context)
	teleport_distance = _positive(section, "teleport_distance", context)


func _read_steps(section: Dictionary) -> void:
	var context: String = CONTEXT + " > steps"
	step_max_height = _positive(section, "max_height", context)
	step_min_height = _positive(section, "min_height", context)
	step_clearance = _positive(section, "clearance", context)
	step_surface_inset = _positive(section, "surface_inset", context)
	step_headroom_probe_distance = _positive(section, "headroom_probe_distance", context)
	climb_retry_delay = _ranged(section, "retry_delay", 0.0, 5.0, context)
	_check(step_min_height < step_max_height, "min_height doit être inférieure à max_height", context)


func _read_input(section: Dictionary) -> void:
	var context: String = CONTEXT + " > input"
	input_smoothing_time = _ranged(section, "smoothing_time", 0.0, 1.0, context)
	move_threshold = _ranged(section, "move_threshold", 0.01, 0.9, context)
	analog_walk_slow_max = _ranged(section, "analog_walk_slow_max", 0.05, 0.95, context)
	analog_hysteresis = _ranged(section, "analog_hysteresis", 0.0, 0.3, context)
	analog_min_speed_fraction = _ranged(section, "analog_min_speed_fraction", 0.0, 1.0, context)
	idle_confirm_time = _ranged(section, "idle_confirm_time", 0.0, 1.0, context)
	_check(
		move_threshold < analog_walk_slow_max - analog_hysteresis and analog_walk_slow_max + analog_hysteresis < 1.0,
		"move_threshold < analog_walk_slow_max ± analog_hysteresis < 1 attendu",
		context
	)


func _read_gaits(section: Dictionary) -> void:
	for gait: int in [Gait.WALK_SLOW, Gait.WALK, Gait.RUN]:
		var gait_name: String = GAIT_NAMES[gait]
		var context: String = CONTEXT + " > gaits > " + gait_name
		var gait_data: Dictionary = JsonData.get_dictionary(section, gait_name, context)
		gait_speed[gait] = _positive(gait_data, "speed", context)
		gait_acceleration[gait] = _positive(gait_data, "acceleration", context)
		gait_deceleration[gait] = _positive(gait_data, "deceleration", context)
		gait_turn_rate[gait] = deg_to_rad(_positive(gait_data, "turn_rate_degrees", context))
		gait_stride_length[gait] = _ranged(gait_data, "stride_length", 0.1, 3.0, context)
		gait_animation_reference_speed[gait] = _positive(gait_data, "animation_reference_speed", context)
	_check(
		gait_speed[Gait.WALK_SLOW] < gait_speed[Gait.WALK] and gait_speed[Gait.WALK] < gait_speed[Gait.RUN],
		"les vitesses doivent croître : walk_slow < walk < run",
		CONTEXT + " > gaits"
	)


func _read_turns(section: Dictionary) -> void:
	var context: String = CONTEXT + " > turns"
	turn_90_min_angle = deg_to_rad(_ranged(section, "turn_90_min_angle_degrees", 10.0, 180.0, context))
	turn_180_min_angle = deg_to_rad(_ranged(section, "turn_180_min_angle_degrees", 10.0, 180.0, context))
	turn_90_duration = _positive(section, "turn_90_duration", context)
	turn_180_duration = _positive(section, "turn_180_duration", context)
	turn_90_speed_factor = _ranged(section, "turn_90_speed_factor", 0.0, 1.0, context)
	turn_180_speed_factor = _ranged(section, "turn_180_speed_factor", 0.0, 1.0, context)
	turn_deceleration = _positive(section, "deceleration", context)
	turn_cooldown = _ranged(section, "cooldown", 0.0, 2.0, context)
	turn_confirm_time = _ranged(section, "confirm_time", 0.0, 1.0, context)
	turn_stable_angle = deg_to_rad(_ranged(section, "stable_angle_degrees", 1.0, 90.0, context))
	_check(turn_90_min_angle < turn_180_min_angle, "l'angle du quart de tour doit être inférieur à celui du demi-tour", context)


func _read_stops(section: Dictionary) -> void:
	var context: String = CONTEXT + " > stops"
	stop_min_speed_fraction = _ranged(section, "min_speed_fraction", 0.0, 1.0, context)
	stop_min_duration = _positive(section, "min_duration", context)
	stop_max_duration = _positive(section, "max_duration", context)
	_check(stop_min_duration <= stop_max_duration, "min_duration doit être inférieure ou égale à max_duration", context)


func _read_footsteps(section: Dictionary) -> void:
	var context: String = CONTEXT + " > footsteps"
	first_step_fraction = _ranged(section, "first_step_fraction", 0.0, 1.0, context)
	foot_lateral_offset = _ranged(section, "foot_lateral_offset", 0.0, 1.0, context)
	foot_ray_start_height = _positive(section, "ray_start_height", context)
	foot_ray_depth = _positive(section, "ray_depth", context)
	foot_ray_mask = _layers(section, "ray_collision_mask_layers", context)
	rest_speed = _positive(section, "rest_speed", context)
	stop_step_min_fraction = _ranged(section, "stop_step_min_fraction", 0.0, 1.0, context)
	var contacts: Dictionary = JsonData.get_dictionary(section, "animation_contacts", context)
	var contacts_context: String = context + " > animation_contacts"
	foot_bone_names = PackedStringArray()
	for bone: Variant in JsonData.get_array(contacts, "foot_bones", contacts_context):
		foot_bone_names.append(str(bone))
	_check(foot_bone_names.size() == 2, "foot_bones doit nommer deux os (gauche, droit)", contacts_context)
	contact_height = _ranged(contacts, "height_m", 0.001, 0.5, contacts_context)
	contact_lift = _ranged(contacts, "lift_m", 0.001, 0.5, contacts_context)
	contact_samples_per_second = _ranged(contacts, "samples_per_second", 10.0, 1000.0, contacts_context)
	contact_min_gap = _ranged(contacts, "min_gap_s", 0.0, 1.0, contacts_context)
	contact_min_travel = _ranged(contacts, "min_travel_m", 0.0, 2.0, contacts_context)


func _read_animation(section: Dictionary) -> void:
	var context: String = CONTEXT + " > animation"
	blend_time = _ranged(section, "blend_time", 0.0, 2.0, context)
	one_shot_blend_time = _ranged(section, "one_shot_blend_time", 0.0, 2.0, context)
	speed_scale_min = _positive(section, "speed_scale_min", context)
	speed_scale_max = _positive(section, "speed_scale_max", context)
	_check(speed_scale_min <= speed_scale_max, "speed_scale_min doit être inférieure ou égale à speed_scale_max", context)


func _read_wading(section: Dictionary) -> void:
	var context: String = CONTEXT + " > wading"
	wading_max_depth = _positive(section, "max_depth_m", context)
	wading_enter_depth = _ranged(section, "enter_depth_m", 0.0, wading_max_depth, context)
	wading_speed_multiplier = _ranged(section, "speed_multiplier_at_max_depth", 0.05, 1.0, context)
	wading_smoothing = _positive(section, "smoothing_per_second", context)
	splash = JsonData.get_dictionary(section, "splash", context)


func _read_budgets(section: Dictionary) -> void:
	var context: String = CONTEXT + " > budgets"
	budget_step_average_ms = _positive(section, "step_average_ms", context)
	budget_step_p95_ms = _positive(section, "step_p95_ms", context)


func _check_consistency() -> void:
	_check(
		vault_min_height > step_max_height,
		"impact > vault_min_height_m doit dépasser steps > max_height (sinon une marche serait sautée)",
		CONTEXT
	)
	# Une marche franchissable reste sous la moitié du corps ; un déplacement normal d'une image
	# de 100 ms à la course ne doit jamais être pris pour une téléportation.
	_check(step_max_height < body_height * 0.5, "steps > max_height doit rester sous la moitié de la hauteur du corps", CONTEXT)
	_check(teleport_distance > gait_speed[Gait.RUN] * 0.1, "teleport_distance doit dépasser le déplacement d'une image de 100 ms", CONTEXT)


func _positive(section: Dictionary, key: String, context: String) -> float:
	var value: float = JsonData.get_float(section, key, context)
	_check(value > 0.0, "« %s » doit être strictement positif" % key, context)
	return value


func _ranged(section: Dictionary, key: String, minimum: float, maximum: float, context: String) -> float:
	var value: float = JsonData.get_float(section, key, context)
	_check(value >= minimum and value <= maximum, "« %s » doit être compris entre %s et %s" % [key, minimum, maximum], context)
	return clampf(value, minimum, maximum)


func _layers(section: Dictionary, key: String, context: String) -> int:
	var mask: int = 0
	var values: Array = JsonData.get_array(section, key, context)
	_check(not values.is_empty(), "« %s » doit contenir au moins une couche" % key, context)
	for raw: Variant in values:
		var is_number: bool = typeof(raw) == TYPE_INT or typeof(raw) == TYPE_FLOAT
		var layer: int = int(raw) if is_number else 0
		if is_number and layer >= 1 and layer <= MAX_LAYER:
			mask |= 1 << (layer - 1)
		else:
			_check(false, "« %s » : couches de 1 à %d" % [key, MAX_LAYER], context)
	return mask


func _check(condition: bool, message: String, context: String) -> void:
	if not condition:
		error_count += 1
		push_error("LocomotionSettings : %s (%s)." % [message, context])


func _read_impact(impact: Dictionary) -> void:
	var context: String = CONTEXT + " > impact"
	bump_min_speed = _ranged(impact, "bump_min_speed_mps", 0.5, 20.0, context)
	bump_min_facing = cos(deg_to_rad(_ranged(impact, "bump_max_angle_deg", 0.0, 89.0, context)))
	blocked_speed = _ranged(impact, "blocked_speed_mps", 0.0, 2.0, context)
	roll_min_air = _ranged(impact, "roll_min_air_s", 0.1, 10.0, context)
	roll_min_speed = _ranged(impact, "roll_min_speed_mps", 0.0, 20.0, context)
	vault_min_speed = _ranged(impact, "vault_min_speed_mps", 0.0, 20.0, context)
	vault_min_facing = cos(deg_to_rad(_ranged(impact, "vault_max_angle_deg", 0.0, 89.0, context)))
	vault_min_height = _ranged(impact, "vault_min_height_m", 0.05, 3.0, context)
	vault_max_height = _ranged(impact, "vault_max_height_m", 0.05, 3.0, context)
	vault_max_depth = _ranged(impact, "vault_max_depth_m", 0.05, 5.0, context)
	vault_max_drop = _ranged(impact, "vault_max_drop_m", 0.0, 5.0, context)
	vault_clearance = _ranged(impact, "vault_clearance_m", 0.0, 1.0, context)
	vault_min_gap = _ranged(impact, "vault_min_gap_m", 0.0, 3.0, context)
	vault_look_ahead = _ranged(impact, "vault_look_ahead_s", 0.05, 2.0, context)
	vault_min_duration = _ranged(impact, "vault_min_duration_s", 0.1, 3.0, context)
	vault_max_duration = _ranged(impact, "vault_max_duration_s", 0.1, 3.0, context)
	vault_samples = int(_ranged(impact, "vault_samples", 2.0, 64.0, context))
	_check(vault_min_height < vault_max_height, "vault_min_height_m doit être inférieure à vault_max_height_m", context)


func _read_jump(jump: Dictionary) -> void:
	var jump_context: String = CONTEXT + " > jump"
	jump_speed = _ranged(jump, "speed_mps", 0.5, 20.0, jump_context)
	jump_coyote = _ranged(jump, "coyote_s", 0.0, 1.0, jump_context)
	jump_buffer = _ranged(jump, "buffer_s", 0.0, 1.0, jump_context)
	jump_landing_min_air = _ranged(jump, "landing_min_air_s", 0.0, 5.0, jump_context)
	jump_blend = _ranged(jump, "blend_s", 0.0, 1.0, jump_context)
