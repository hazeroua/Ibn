class_name VitrinePersonnage
extends Node3D
## Racine de la vitrine du personnage : au chargement, lance l'animation de chaque personnage de « Characters »
## (métadonnées « animation » et « time_offset_s » posées par VitrinePersonnageBuilder). Aucun traitement par image.


func _ready() -> void:
	var characters: Node = get_node_or_null("Characters")
	if characters == null:
		push_error("VitrinePersonnage : nœud « Characters » absent.")
		return
	for child: Node in characters.get_children():
		var player: AnimationPlayer = CharacterCatalog.find_animation_player(child)
		if player == null:
			push_error("VitrinePersonnage : aucun AnimationPlayer dans « %s »." % child.name)
			continue
		var animation_name := StringName(str(child.get_meta(&"animation", "")))
		if not player.has_animation(animation_name):
			push_error("VitrinePersonnage : animation « %s » absente pour « %s »." % [animation_name, child.name])
			continue
		player.play(animation_name)
		player.seek(float(child.get_meta(&"time_offset_s", 0.0)), true)
