class_name DesertFoliageInstance
extends MultiMeshInstance3D
## Végétation d'une cellule du désert. La cellule est construite sur un fil de fond (WorldStreamer) :
## le serveur de rendu refuse d'y remplir le tampon d'un MultiMesh. Les transformées calculées sur
## ce fil sont donc gardées ici et copiées dans le MultiMesh à l'entrée dans l'arbre (fil principal).

const FLOATS_PER_INSTANCE: int = 12

var transform_buffer: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	if multimesh == null or transform_buffer.is_empty():
		return
	multimesh.instance_count = transform_buffer.size() / FLOATS_PER_INSTANCE
	multimesh.buffer = transform_buffer
	# Le MultiMesh garde sa copie : inutile de conserver celle-ci.
	transform_buffer = PackedFloat32Array()
