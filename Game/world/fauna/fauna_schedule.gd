class_name FaunaSchedule
extends RefCounted
## Plages horaires d'activité de la faune. Une plage est un Vector3 (début, fin, durée du fondu) en heures ;
## une fin qui précède le début traverse minuit. Calcul pur, sans allocation.


## Lit une plage { start, end, fade } dans les données.
static func parse(hours: Dictionary, context: String) -> Vector3:
	return Vector3(
		JsonData.get_float(hours, "start", context), JsonData.get_float(hours, "end", context), JsonData.get_float(hours, "fade", context)
	)


## Poids d'activité de 0 (inactif) à 1 (pleinement actif) à l'heure donnée, avec fondu de part et d'autre.
static func weight(hour: float, window: Vector3) -> float:
	var length: float = fposmod(window.y - window.x, 24.0)
	if length <= 0.0:
		length = 24.0
	var elapsed: float = fposmod(hour - window.x, 24.0)
	if elapsed >= length:
		return 0.0
	var fade: float = maxf(window.z, 0.001)
	return smoothstep(0.0, 1.0, minf(elapsed / fade, (length - elapsed) / fade))
