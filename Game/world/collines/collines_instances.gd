class_name CollinesInstances
extends MultiMeshInstance3D
## MultiMeshInstance3D dont les transformations sont enregistrées dans la scène sous forme d'un tableau de réels
## (12 réels par instance, rangés comme le tampon du moteur) et appliquées une seule fois au chargement.
##
## Le moteur sans fenêtre (construction des scènes par le pipeline) ne conserve pas les transformations d'un
## MultiMesh : les garder dans la scène rend la construction identique avec ou sans affichage.

const FLOATS_PER_INSTANCE: int = 12

@export var transform_buffer: PackedFloat32Array = PackedFloat32Array()


## Écrit une transformation dans un tampon de transformations 3D (ordre ligne par ligne de la matrice 3 × 4).
static func write_transform(buffer: PackedFloat32Array, index: int, value: Transform3D) -> void:
	var cursor: int = index * FLOATS_PER_INSTANCE
	var basis: Basis = value.basis
	var origin: Vector3 = value.origin
	buffer[cursor] = basis.x.x
	buffer[cursor + 1] = basis.y.x
	buffer[cursor + 2] = basis.z.x
	buffer[cursor + 3] = origin.x
	buffer[cursor + 4] = basis.x.y
	buffer[cursor + 5] = basis.y.y
	buffer[cursor + 6] = basis.z.y
	buffer[cursor + 7] = origin.y
	buffer[cursor + 8] = basis.x.z
	buffer[cursor + 9] = basis.y.z
	buffer[cursor + 10] = basis.z.z
	buffer[cursor + 11] = origin.z


func _ready() -> void:
	if multimesh == null or transform_buffer.is_empty():
		return
	multimesh.instance_count = transform_buffer.size() / FLOATS_PER_INSTANCE
	multimesh.buffer = transform_buffer
