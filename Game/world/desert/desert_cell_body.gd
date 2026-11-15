class_name DesertCellBody
extends StaticBody3D
## Corps statique d'une cellule du désert (couche 1) : porte la collision et les niveaux de détail, et expose
## surface_at() au système de pas (lecture O(1) dans le champ de hauteurs partagé).

## Coordonnées de la cellule dans la grille de streaming.
var cell: Vector2i = Vector2i.ZERO
var heightfield: DesertHeightfield


## Surface du sol à la position du monde (« sable », « pierre » ou « terre »).
func surface_at(world_position: Vector3) -> StringName:
	return heightfield.surface_at(world_position)
