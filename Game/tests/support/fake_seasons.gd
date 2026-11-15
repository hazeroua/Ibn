extends Node
## Doublure de Seasons : saison courante, set_season et signal season_changed.

signal season_changed(id: StringName)

var season: StringName = &"ete"


func set_season(id: StringName) -> void:
	season = id
	season_changed.emit(id)
