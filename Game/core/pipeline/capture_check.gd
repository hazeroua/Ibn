class_name CaptureCheck
extends RefCounted
## Contrôle automatique des captures d'écran : détecte une image noire, une image uniforme (rien n'est
## rendu) ou des pixels magenta (couleur de Godot pour une texture ou un matériau manquant).
##
## L'image est échantillonnée sur une grille régulière (environ 8 000 points en 1080p) : le coût reste
## constant quelle que soit la scène.

const SAMPLE_STEP: int = 16
const SAMPLE_OFFSET: int = 8
const MIN_MEAN_LUMINANCE: float = 0.03
const MIN_LUMINANCE_DEVIATION: float = 0.01
const MAX_MAGENTA_RATIO: float = 0.002


static func analyze(image: Image) -> Dictionary:
	var width: int = image.get_width()
	var height: int = image.get_height()
	var count: int = 0
	var sum: float = 0.0
	var sum_squares: float = 0.0
	var magenta: int = 0
	var y: int = SAMPLE_OFFSET
	while y < height:
		var x: int = SAMPLE_OFFSET
		while x < width:
			var color: Color = image.get_pixel(x, y)
			var luminance: float = color.get_luminance()
			sum += luminance
			sum_squares += luminance * luminance
			if color.r > 0.85 and color.g < 0.15 and color.b > 0.85:
				magenta += 1
			count += 1
			x += SAMPLE_STEP
		y += SAMPLE_STEP
	if count == 0:
		return {"samples": 0, "mean_luminance": 0.0, "luminance_deviation": 0.0, "magenta_ratio": 0.0}
	var mean: float = sum / float(count)
	var variance: float = maxf(sum_squares / float(count) - mean * mean, 0.0)
	return {
		"samples": count,
		"mean_luminance": mean,
		"luminance_deviation": sqrt(variance),
		"magenta_ratio": float(magenta) / float(count),
	}


static func problems(stats: Dictionary) -> PackedStringArray:
	var found := PackedStringArray()
	if int(stats["samples"]) == 0:
		found.append("image vide")
		return found
	if float(stats["mean_luminance"]) < MIN_MEAN_LUMINANCE:
		found.append("image presque noire (luminance moyenne %.4f)" % float(stats["mean_luminance"]))
	if float(stats["luminance_deviation"]) < MIN_LUMINANCE_DEVIATION:
		found.append("image uniforme : rien ne semble rendu (écart de luminance %.4f)" % float(stats["luminance_deviation"]))
	if float(stats["magenta_ratio"]) > MAX_MAGENTA_RATIO:
		found.append("%.1f %% de pixels magenta : texture ou matériau manquant" % (float(stats["magenta_ratio"]) * 100.0))
	return found
