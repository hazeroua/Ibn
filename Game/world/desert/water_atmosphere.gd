class_name WaterAtmosphere
extends Node
## Publie l'uniforme global « water_midday » (0 à 1) : vaut 1 quand le soleil est haut (mirage du chott), 0 sinon.
## Recalculé seulement quand l'heure ou la saison change (signaux), jamais par image : une lecture de la direction
## du soleil et une écriture d'uniforme.

var _uniform: StringName = &""
var _low: float = 0.0
var _high: float = 1.0
var _day_night: DayNightSystem = null


func _ready() -> void:
	var settings: Dictionary = JsonData.get_dictionary(WaterBody.settings(), "midday", WaterBody.SETTINGS_PATH)
	_uniform = StringName(JsonData.get_string(settings, "uniform", WaterBody.SETTINGS_PATH))
	_low = JsonData.get_float(settings, "sun_height_low", WaterBody.SETTINGS_PATH)
	_high = JsonData.get_float(settings, "sun_height_high", WaterBody.SETTINGS_PATH)
	_day_night = get_node_or_null("/root/DayNight") as DayNightSystem
	if _day_night == null:
		push_error("WaterAtmosphere : le système DayNight est absent.")
		return
	@warning_ignore("return_value_discarded")
	_day_night.time_changed.connect(_on_time_changed)
	var seasons: Node = get_node_or_null("/root/Seasons")
	if seasons != null:
		@warning_ignore("return_value_discarded")
		seasons.connect(&"season_changed", _on_season_changed)
	_publish(_day_night.get_time())


func _on_time_changed(hours: float) -> void:
	_publish(hours)


func _on_season_changed(_id: StringName) -> void:
	_publish(_day_night.get_time())


func _publish(hours: float) -> void:
	var sun_height: float = _day_night.get_sun_direction(hours).y
	RenderingServer.global_shader_parameter_set(_uniform, smoothstep(_low, _high, sun_height))
