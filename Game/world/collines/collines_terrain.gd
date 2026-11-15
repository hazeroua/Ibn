class_name CollinesTerrain
extends StaticBody3D
## Corps statique du terrain de la carte « collines » (couche 1) : porte la forme de collision en carte de hauteurs,
## les tuiles visibles, et la méthode du contrat des surfaces du sol.
##
## surface_at() lit la carte de contrôle de la carte : la pierre domine quand son poids atteint 0,5, sinon c'est
## le sable. Lecture en O(1), sans allocation (le tableau d'octets est extrait une seule fois).

## Surface de chaque couche (indice 0 : texture de base, indice 1 : texture de recouvrement).
@export var layer_surfaces: PackedStringArray = PackedStringArray()
## Poids de la texture de recouvrement par sommet (R8, une ligne après l'autre).
@export var control_image: Image
## Coin (x, z) du monde du premier sommet de la grille.
@export var grid_origin: Vector2 = Vector2.ZERO
## Distance entre deux sommets, en mètres.
@export var grid_spacing: float = 1.0

var _control := PackedByteArray()


## Surface du sol à la position du monde (« sable », « pierre »…). Hors de la grille : surface de la couche de base.
func surface_at(world_position: Vector3) -> StringName:
	var default_surface: StringName = &"sable" if layer_surfaces.is_empty() else StringName(layer_surfaces[0])
	if control_image == null or layer_surfaces.size() < 2:
		return default_surface
	if _control.is_empty():
		_control = control_image.get_data()
	var side: int = control_image.get_width()
	var column: int = roundi((world_position.x - grid_origin.x) / grid_spacing)
	var row: int = roundi((world_position.z - grid_origin.y) / grid_spacing)
	if column < 0 or row < 0 or column >= side or row >= side:
		return default_surface
	# 128 sur 255 : premier poids de pierre supérieur ou égal à 0,5.
	return StringName(layer_surfaces[1] if _control[row * side + column] >= 128 else layer_surfaces[0])
