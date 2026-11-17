class_name TunisGateTransition
extends Node3D
## Raccord spatial de la médina dans le désert et règle de la porte : on entre à pied, Barq attend dehors.
##
## Barq reste l'entité unique de DesertSession ; ce nœud ne crée pas de second cheval, il pose trois règles
## sur le contrôleur existant (data/tunis/transition.json) :
## - vitesse : quel que soit son cap, Barq ne peut pas aller plus vite que ce qui lui permet de s'arrêter à
##   stop_before_wall_m de l'enceinte en freinant à brake_deceleration_mps2 (v = √(2·a·d), d le long du cap) :
##   le freinage est progressif et le cavalier garde la direction pour repartir ;
## - déplacement : aucun pas n'entre dans l'enceinte élargie de cette marge (garde-fou, jamais atteint en
##   conduite normale) ;
## - saut : interdit à moins de no_jump_m de l'enceinte (pas de saut contre un rempart).
## Une fois le cavalier descendu près de la porte, Barq va au point d'attache versionné et y attend. Un sifflet
## lancé depuis la ville ne le fait pas entrer : il hennit et reste (ou retourne) au point d'attache.
## Coût par image : une intersection rayon-rectangle et quelques comparaisons ; aucune allocation.

const CONTEXT: String = "tunis/transition.json"
## Groupe des scènes qui chargent le monde autour du point de vue des captures et mesures (PipelineRunner).
const PIPELINE_FOCUS_GROUP: StringName = &"pipeline_focus"

var _player: PlayerCharacter
var _mount: HorseMountSystem
var _city: TunisRuntime
var _gate_local: Vector2 = Vector2.ZERO
var _inward: Vector2 = Vector2.ZERO
var _hitch_local: Vector2 = Vector2.ZERO
var _enclosure: Rect2 = Rect2()
var _keep_out: Rect2 = Rect2()
var _no_jump: Rect2 = Rect2()
var _brake: float = 0.0
var _warning: float = 0.0
var _hitch_radius: float = 0.0
var _message_duration: float = 0.0
var _message_remaining: float = 0.0
var _timed_message: String = ""
var _message_approach: String = ""
var _message_blocked: String = ""
var _message_whistle: String = ""
var _message_ready: String = ""
var _hint: Label
var _last_hint: String = ""
var _previous_riding: bool = false
var _redirecting: bool = false
var _pipeline_focused: bool = false
var _pipeline_focus: Vector3 = Vector3.ZERO
var _view_distance: float = 0.0
var _call_edge: float = 0.0
var _city_shown: bool = false


func configure(config: Dictionary, player: PlayerCharacter, mount: HorseMountSystem, city: TunisRuntime) -> bool:
	if player == null or mount == null or mount.horse == null:
		push_error("%s : joueur ou Barq absent." % CONTEXT)
		return false
	if JsonData.get_int(config, "schema_version", CONTEXT) != 1:
		push_error("%s : version de schéma inconnue." % CONTEXT)
		return false
	var origin: Array = JsonData.get_array(config, "world_origin_xz_m", CONTEXT)
	var horse_data: Dictionary = JsonData.get_dictionary(config, "horse", CONTEXT)
	var hitch: Array = JsonData.get_array(horse_data, "hitch_local_xz_m", CONTEXT)
	var layout: Dictionary = JsonData.load_dictionary(JsonData.get_string(config, "layout_path", CONTEXT))
	var gate: Dictionary = JsonData.get_dictionary(layout, "gate", CONTEXT)
	var raw_gate: Array = JsonData.get_array(gate, "position", CONTEXT)
	var raw_inward: Array = JsonData.get_array(gate, "inward", CONTEXT)
	var raw_enclosure: Array = JsonData.get_array(layout, "enclosure", CONTEXT)
	if origin.size() != 2 or hitch.size() != 2 or raw_gate.size() != 2 or raw_inward.size() != 2 or raw_enclosure.size() != 4:
		push_error("%s : origine, point d'attache, porte ou enceinte invalides." % CONTEXT)
		return false
	_gate_local = Vector2(float(raw_gate[0]), float(raw_gate[1]))
	_inward = Vector2(float(raw_inward[0]), float(raw_inward[1])).normalized()
	_hitch_local = Vector2(float(hitch[0]), float(hitch[1]))
	_enclosure = Rect2(
		Vector2(float(raw_enclosure[0]), float(raw_enclosure[1])),
		Vector2(float(raw_enclosure[2]) - float(raw_enclosure[0]), float(raw_enclosure[3]) - float(raw_enclosure[1]))
	)
	_brake = JsonData.get_float(horse_data, "brake_deceleration_mps2", CONTEXT)
	var stop_before: float = JsonData.get_float(horse_data, "stop_before_wall_m", CONTEXT)
	var no_jump: float = JsonData.get_float(horse_data, "no_jump_m", CONTEXT)
	_warning = JsonData.get_float(horse_data, "warning_m", CONTEXT)
	_hitch_radius = JsonData.get_float(horse_data, "hitch_arrival_radius_m", CONTEXT)
	_message_duration = JsonData.get_float(horse_data, "message_duration_s", CONTEXT)
	_call_edge = JsonData.get_float(horse_data, "call_stop_at_edge_m", CONTEXT)
	var sprint_speed: float = _gait_speed(mount.horse, "sprint")
	_keep_out = _enclosure.grow(stop_before)
	_no_jump = _enclosure.grow(no_jump)
	var stopping: float = sprint_speed * sprint_speed / (2.0 * maxf(_brake, 0.001))
	if (
		_brake <= 0.0
		or stop_before <= 0.0
		or no_jump <= stop_before
		or _hitch_radius <= 0.0
		or _message_duration <= 0.0
		or _warning < stop_before + stopping
		or _keep_out.has_point(_hitch_local)
		or _call_edge <= 0.0
	):
		push_error("%s : freinage, distances ou point d'attache incohérents (arrêt au galop : %.1f m)." % [CONTEXT, stopping])
		return false
	var messages: Dictionary = JsonData.get_dictionary(config, "messages", CONTEXT)
	_message_approach = JsonData.get_string(messages, "approach", CONTEXT)
	_message_blocked = JsonData.get_string(messages, "dismount_blocked", CONTEXT)
	_message_whistle = JsonData.get_string(messages, "whistle_inside", CONTEXT)
	_message_ready = JsonData.get_string(messages, "ready", CONTEXT)
	if not _build_hint(JsonData.get_dictionary(config, "hint", CONTEXT)):
		return false
	_view_distance = JsonData.get_float(config, "view_distance_m", CONTEXT)
	if _view_distance <= _warning:
		push_error("%s : view_distance_m doit dépasser la zone d'avertissement." % CONTEXT)
		return false
	_player = player
	_mount = mount
	_city = city
	var level: float = 0.0
	if mount.heightfield != null:
		level = mount.heightfield.city_ground_level()
	global_position = Vector3(float(origin[0]), level, float(origin[1]))
	var horse: HorseController = mount.horse
	horse.speed_guard = _horse_speed_limit
	horse.guard_deceleration = _brake
	horse.block_call_area(Rect2(_keep_out.position + Vector2(global_position.x, global_position.z), _keep_out.size))
	horse.movement_guard = _horse_motion_allowed
	horse.jump_guard = _horse_jump_allowed
	horse.called.connect(_on_horse_called)
	mount.dismount_blocked.connect(_on_dismount_blocked)
	add_to_group(PIPELINE_FOCUS_GROUP)
	return true


static func _gait_speed(horse: HorseController, gait: String) -> float:
	var gaits: Dictionary = JsonData.get_dictionary(horse.settings, "gaits", "horse.json")
	return JsonData.get_float(JsonData.get_dictionary(gaits, gait, "horse.json > gaits"), "speed_mps", "horse.json > " + gait)


func gate_world_position() -> Vector3:
	return global_position + Vector3(_gate_local.x, 0.0, _gate_local.y)


## Direction (monde, horizontale) qui entre dans la ville par la porte.
func inward_direction() -> Vector3:
	return Vector3(_inward.x, 0.0, _inward.y)


func hitch_world_position() -> Vector3:
	return global_position + Vector3(_hitch_local.x, 0.0, _hitch_local.y)


## Rectangle (local, mètres) où Barq ne peut pas entrer.
func keep_out_rect() -> Rect2:
	return _keep_out


func is_city_side(world_position: Vector3) -> bool:
	return _is_city_side(_local(world_position))


func current_hint() -> String:
	return _last_hint


## Captures et mesures : la ville se charge autour du point de vue imposé, pas autour du joueur.
func pipeline_focus_at(world_position: Vector3) -> void:
	_pipeline_focused = true
	_pipeline_focus = world_position
	_update_city(world_position, Vector3.ZERO)


## Réglé quand aucune cellule de la ville n'attend son chargement.
func pipeline_is_settled() -> bool:
	return _city == null or not _pipeline_focused or _city.pending_cell_count() == 0


## La ville est un repère du désert : dans view_distance_m, toutes ses cellules restent chargées (elle se
## voit de loin, sans apparition brusque à l'approche) ; au-delà, le streaming de #50 la décharge.
func _update_city(world_position: Vector3, velocity: Vector3) -> void:
	if _city == null:
		return
	_city.set_focus(world_position - global_position, velocity)
	var shown: bool = _distance_to_wall(_local(world_position)) <= _view_distance
	if shown != _city_shown:
		_city_shown = shown
		_city.force_all_cells_loaded(shown)


func _physics_process(delta: float) -> void:
	if _player == null or _mount == null or _mount.horse == null:
		return
	var horse: HorseController = _mount.horse
	_message_remaining = maxf(_message_remaining - delta, 0.0)
	var riding: bool = _mount.is_riding()
	if not _pipeline_focused:
		var carrier: Vector3 = horse.global_position if riding else _player.global_position
		_update_city(carrier, horse.velocity if riding else _player.velocity)
	var local_horse: Vector2 = _local(horse.global_position)
	var local_player: Vector2 = _local(_player.global_position)
	# Appelé vers un point de la zone interdite (seuil de la porte) : l'appel s'arrête au bord de la zone.
	if horse.is_called and _keep_out.has_point(_local(horse.called_target)) and _distance_to_rect(local_horse, _keep_out) < _call_edge:
		horse.cancel_call()
	if riding:
		_previous_riding = true
	elif _previous_riding:
		_previous_riding = false
		if _distance_to_wall(local_horse) < _warning and horse.global_position.distance_to(hitch_world_position()) > _hitch_radius:
			horse.call_to(hitch_world_position())
	if _message_remaining > 0.0:
		_show_hint(_timed_message)
	elif riding and _distance_to_wall(local_horse) < _warning:
		_show_hint(_message_approach)
	elif not riding and not _is_city_side(local_player) and _distance_to_wall(local_player) < _warning:
		_show_hint(_message_ready if _player.global_position.distance_to(horse.global_position) < _warning else "")
	else:
		_show_hint("")


func _local(world_position: Vector3) -> Vector2:
	return Vector2(world_position.x - global_position.x, world_position.z - global_position.z)


## Distance horizontale (m) entre un point local et l'enceinte (0 dedans).
func _distance_to_wall(local: Vector2) -> float:
	return _distance_to_rect(local, _enclosure)


static func _distance_to_rect(local: Vector2, rect: Rect2) -> float:
	var dx: float = maxf(maxf(rect.position.x - local.x, local.x - rect.end.x), 0.0)
	var dz: float = maxf(maxf(rect.position.y - local.y, local.y - rect.end.y), 0.0)
	return sqrt(dx * dx + dz * dz)


## Vitesse maximale (m/s) qui laisse Barq s'arrêter avant la zone interdite le long de son cap.
func _horse_speed_limit(world_position: Vector3, facing: Vector3) -> float:
	var origin: Vector2 = _local(world_position)
	var direction := Vector2(facing.x, facing.z)
	if _keep_out.has_point(origin):
		return 0.0
	var t_near: float = -INF
	var t_far: float = INF
	for axis: int in 2:
		var o: float = origin[axis]
		var d: float = direction[axis]
		var low: float = _keep_out.position[axis]
		var high: float = _keep_out.end[axis]
		if absf(d) < 0.000001:
			if o < low or o > high:
				return INF
			continue
		var t1: float = (low - o) / d
		var t2: float = (high - o) / d
		t_near = maxf(t_near, minf(t1, t2))
		t_far = minf(t_far, maxf(t1, t2))
	if t_near > t_far or t_far < 0.0:
		return INF
	return sqrt(2.0 * _brake * maxf(t_near, 0.0))


func _horse_motion_allowed(world_position: Vector3, motion: Vector3) -> bool:
	return not _keep_out.has_point(_local(world_position + motion))


func _horse_jump_allowed(world_position: Vector3) -> bool:
	return not _no_jump.has_point(_local(world_position))


func _is_city_side(local: Vector2) -> bool:
	return _enclosure.has_point(local)


## Sifflet : depuis la ville, Barq ne vient pas ; il hennit et attend (ou retourne) au point d'attache.
func _on_horse_called() -> void:
	if _redirecting or not _is_city_side(_local(_player.global_position)):
		return
	var horse: HorseController = _mount.horse
	_redirecting = true
	horse.cancel_call()
	if horse.global_position.distance_to(hitch_world_position()) > _hitch_radius:
		horse.call_to(hitch_world_position())
	_redirecting = false
	if _mount.audio != null:
		_mount.audio.neigh(horse.global_position)
	_show_timed(_message_whistle)


## Descente refusée près de la ville seulement : ailleurs dans le désert, le comportement du MVP 3 est inchangé.
func _on_dismount_blocked() -> void:
	if _distance_to_wall(_local(_mount.horse.global_position)) < _warning:
		_show_timed(_message_blocked)


func _show_timed(message: String) -> void:
	_timed_message = message
	_message_remaining = _message_duration
	_show_hint(message)


func _build_hint(style: Dictionary) -> bool:
	var context: String = CONTEXT + " > hint"
	var shadow_offset: Array = JsonData.get_array(style, "shadow_offset_px", context)
	var font_color: String = JsonData.get_string(style, "font_color", context)
	var shadow_color: String = JsonData.get_string(style, "shadow_color", context)
	if shadow_offset.size() != 2 or not Color.html_is_valid(font_color) or not Color.html_is_valid(shadow_color):
		push_error("%s : couleurs ou décalage d'ombre invalides." % context)
		return false
	var layer := CanvasLayer.new()
	layer.name = "GateHint"
	layer.layer = JsonData.get_int(style, "canvas_layer", context)
	add_child(layer)
	_hint = Label.new()
	_hint.name = "Message"
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	var bottom: float = JsonData.get_float(style, "bottom_margin_px", context)
	_hint.offset_bottom = -bottom
	_hint.offset_top = -bottom - JsonData.get_float(style, "height_px", context)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_color_override("font_color", Color.html(font_color))
	_hint.add_theme_color_override("font_shadow_color", Color.html(shadow_color))
	_hint.add_theme_constant_override("shadow_offset_x", int(shadow_offset[0]))
	_hint.add_theme_constant_override("shadow_offset_y", int(shadow_offset[1]))
	_hint.visible = false
	layer.add_child(_hint)
	return true


func _show_hint(message: String) -> void:
	if _hint == null or message == _last_hint:
		return
	_last_hint = message
	_hint.text = message
	_hint.visible = not message.is_empty()
