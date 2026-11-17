class_name LodFadeMesh
extends MeshInstance3D
## Maillage opaque à fondu tramé de niveau de détail, sans payer le discard hors transition : il porte deux
## matériaux partagés, la variante opaque (test de profondeur précoce conservé, utilisée presque tout le temps)
## et la variante de fondu (lod_fade.gdshaderinc, discard). LodFadeMesh.update_all() choisit la variante d'après
## la distance de la caméra au centre (même mesure que le shader et que la plage de visibilité de Godot).
##
## Registre statique tenu par l'entrée et la sortie de l'arbre (fil principal) ; mise à jour par minuteur
## (LodFadeMesh.update_all, désert : 10 fois par seconde), jamais par image. Pire cas : 3 maillages par cellule
## chargée (16 × 16 cellules au plus) : quelques centaines de distances par mise à jour, aucune allocation
## (tableau réservé, retrait par échange avec le dernier).

const RESERVE: int = 1024

## Tableau de capacité fixe (RESERVE, agrandi par blocs s'il le faut, jamais réduit) et nombre d'entrées utiles.
static var _members: Array[LodFadeMesh] = []
static var _count: int = 0

var base_material: Material
var fade_material: Material
## Centre de mesure (repère du monde) et bornes de distance : début du fondu d'entrée, fin du fondu d'entrée,
## début du fondu de sortie, fin du fondu de sortie (comme l'uniforme lod_fade du shader).
var center := Vector3.ZERO
var fade := Vector4(-2.0, -1.0, 1.0e9, 2.0e9)
var _fading: bool = false
var _slot: int = -1


## Prépare le maillage (avant son entrée dans l'arbre, fil de travail possible) : plage de visibilité, uniformes
## d'instance du fondu et variante opaque.
func setup(
	base: Material, fading: Material, center_value: Vector3, begin: float, begin_margin: float, end: float, end_margin: float
) -> void:
	base_material = base
	fade_material = fading
	center = center_value
	fade = LodFade.apply(self, center_value, begin, begin_margin, end, end_margin)
	material_override = base
	_fading = false


func _enter_tree() -> void:
	if _count >= _members.size():
		_members.resize(_members.size() + RESERVE)
	_slot = _count
	_members[_slot] = self
	_count += 1


func _exit_tree() -> void:
	if _slot < 0:
		return
	_count -= 1
	var last: LodFadeMesh = _members[_count]
	_members[_slot] = last
	last._slot = _slot
	_members[_count] = null
	_slot = -1


## Variante de fondu seulement dans les bandes de transition (plus une marge de sécurité, la caméra bougeant
## entre deux mises à jour), variante opaque partout ailleurs.
func update_for(camera_position: Vector3, guard: float) -> void:
	var distance: float = camera_position.distance_to(center)
	var fading: bool = distance < fade.y + guard or distance > fade.z - guard
	if fading != _fading:
		_fading = fading
		material_override = fade_material if fading else base_material


## Met à jour tous les maillages enregistrés ; guard = distance que la caméra peut parcourir avant la mise à
## jour suivante (vitesse maximale × intervalle).
static func update_all(camera_position: Vector3, guard: float) -> void:
	for index: int in _count:
		_members[index].update_for(camera_position, guard)


static func member_count() -> int:
	return _count
