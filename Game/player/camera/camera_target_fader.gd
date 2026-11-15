class_name CameraTargetFader
extends RefCounted
## Fondu de la cible quand la caméra s'en approche trop (recoin, plafond bas).
##
## Agit sur la propriété « transparency » des GeometryInstance3D descendants de la cible : l'ombre
## reste portée pendant le fondu. Une fois la cible entièrement effacée, les géométries qui portaient
## une ombre passent en « ombre seule » et quittent le rendu transparent (plus rien à dessiner pour
## l'image). Aucun clignotement possible : la valeur suit l'objectif par un lissage exponentiel.
##
## Coût par image : nul tant que la caméra est loin (aucune écriture). La liste des géométries n'est
## parcourue qu'au début d'un fondu ; pendant le fondu, les géométries ajoutées à la cible (équipement)
## sont reprises grâce au signal SceneTree.node_added, connecté seulement pendant le fondu.

## En dessous de cette valeur, la cible est considérée comme entièrement visible.
const VISIBLE_EPSILON: float = 0.001
## Au-dessus de cette valeur, la cible est considérée comme entièrement effacée.
const HIDDEN_THRESHOLD: float = 0.999

var _target: Node3D = null
var _tree: SceneTree = null
var _fade: float = 0.0
var _hidden_mode: bool = false
## Identifiants des géométries suivies (un objet libéré entre-temps est simplement ignoré).
var _instance_ids: PackedInt64Array = PackedInt64Array()
var _base_transparency: PackedFloat32Array = PackedFloat32Array()
var _base_shadow: PackedInt32Array = PackedInt32Array()


## Valeur courante du fondu (0 : cible visible, 1 : cible effacée).
func get_fade() -> float:
	return _fade


## Vrai quand la cible est entièrement effacée.
func is_hidden() -> bool:
	return _hidden_mode


## Nombre de géométries de la cible actuellement prises en charge.
func get_instance_count() -> int:
	return _instance_ids.size()


## Change de cible : l'ancienne retrouve exactement son apparence d'origine.
func set_target(target: Node3D) -> void:
	if target == _target:
		return
	reset()
	_target = target


## Rend à la cible son apparence d'origine et oublie le fondu en cours.
func reset() -> void:
	_restore_all()
	_fade = 0.0


## Avance le fondu vers « goal » (0 à 1) avec le taux de lissage « rate » (par seconde).
func update(goal: float, rate: float, delta: float) -> void:
	var next: float = goal + (_fade - goal) * exp(-rate * delta)
	if goal <= 0.0 and next < VISIBLE_EPSILON:
		next = 0.0
	elif goal >= 1.0 and next > HIDDEN_THRESHOLD:
		next = 1.0
	if next == _fade:
		return
	if _fade == 0.0:
		_begin()
	_fade = next
	if _fade == 0.0:
		_restore_all()
		return
	_apply()


func _begin() -> void:
	_instance_ids.resize(0)
	_base_transparency.resize(0)
	_base_shadow.resize(0)
	_hidden_mode = false
	if _target == null or not is_instance_valid(_target):
		return
	_collect(_target)
	if _target.is_inside_tree():
		_tree = _target.get_tree()
		if not _tree.node_added.is_connected(_on_node_added):
			_tree.node_added.connect(_on_node_added)


func _collect(node: Node) -> void:
	var geometry: GeometryInstance3D = node as GeometryInstance3D
	if geometry != null:
		_track(geometry)
	for child: Node in node.get_children():
		_collect(child)


func _track(geometry: GeometryInstance3D) -> void:
	_instance_ids.append(geometry.get_instance_id())
	_base_transparency.append(geometry.transparency)
	_base_shadow.append(geometry.cast_shadow)


func _on_node_added(node: Node) -> void:
	var geometry: GeometryInstance3D = node as GeometryInstance3D
	if geometry == null or _target == null or not is_instance_valid(_target) or not _target.is_ancestor_of(geometry):
		return
	if _instance_ids.has(geometry.get_instance_id()):
		return
	_track(geometry)
	_apply_to(_instance_ids.size() - 1, _hidden_mode)


func _apply() -> void:
	var hidden: bool = _fade >= 1.0
	_hidden_mode = hidden
	for i: int in _instance_ids.size():
		_apply_to(i, hidden)


func _apply_to(index: int, hidden: bool) -> void:
	var geometry: GeometryInstance3D = instance_from_id(_instance_ids[index]) as GeometryInstance3D
	if geometry == null:
		return
	var base_transparency: float = _base_transparency[index]
	var base_shadow: int = _base_shadow[index]
	if hidden and base_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		# Effacée et porteuse d'ombre : ombre seule, sans passer par le rendu transparent.
		geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		geometry.transparency = base_transparency
		return
	geometry.cast_shadow = base_shadow as GeometryInstance3D.ShadowCastingSetting
	geometry.transparency = 1.0 - (1.0 - base_transparency) * (1.0 - _fade)


func _restore_all() -> void:
	for i: int in _instance_ids.size():
		var geometry: GeometryInstance3D = instance_from_id(_instance_ids[i]) as GeometryInstance3D
		if geometry != null:
			geometry.transparency = _base_transparency[i]
			geometry.cast_shadow = _base_shadow[i] as GeometryInstance3D.ShadowCastingSetting
	_instance_ids.resize(0)
	_base_transparency.resize(0)
	_base_shadow.resize(0)
	_hidden_mode = false
	if _tree != null and _tree.node_added.is_connected(_on_node_added):
		_tree.node_added.disconnect(_on_node_added)
	_tree = null
