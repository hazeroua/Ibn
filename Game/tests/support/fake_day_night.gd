extends Node
## Doublure de DayNight : heure, vitesse, set_time et signal time_changed.

signal time_changed(hours: float)

var time_of_day: float = 12.0
var time_scale: float = 1.0


func set_time(hours: float) -> void:
	time_of_day = fposmod(hours, 24.0)
	time_changed.emit(time_of_day)
