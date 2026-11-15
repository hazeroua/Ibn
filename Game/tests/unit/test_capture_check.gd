extends GutTest
## Contrôle automatique des captures d'écran.


func _uniform(color: Color) -> Image:
	var image := Image.create_empty(320, 180, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return image


func test_black_image_is_rejected() -> void:
	var problems: PackedStringArray = CaptureCheck.problems(CaptureCheck.analyze(_uniform(Color.BLACK)))
	assert_eq(problems.size(), 2, "noire et uniforme")


func test_magenta_image_is_rejected() -> void:
	var image: Image = _uniform(Color(0.4, 0.5, 0.6))
	image.fill_rect(Rect2i(0, 0, 160, 180), Color.MAGENTA)
	var stats: Dictionary = CaptureCheck.analyze(image)
	assert_gt(float(stats["magenta_ratio"]), 0.4)
	assert_true(CaptureCheck.problems(stats).size() >= 1)


func test_varied_image_is_accepted() -> void:
	var image: Image = _uniform(Color(0.8, 0.7, 0.5))
	image.fill_rect(Rect2i(0, 0, 320, 90), Color(0.35, 0.5, 0.75))
	assert_eq(CaptureCheck.problems(CaptureCheck.analyze(image)).size(), 0)


func test_worst_case_full_hd_analysis_is_fast() -> void:
	var image: Image = Image.create_empty(1920, 1080, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.5, 0.5, 0.5))
	var start: int = Time.get_ticks_usec()
	var stats: Dictionary = CaptureCheck.analyze(image)
	var elapsed_ms: float = float(Time.get_ticks_usec() - start) / 1000.0
	# Grille de 16 pixels décalée de 8 : 120 colonnes (8 à 1912) et 67 lignes (8 à 1064).
	assert_eq(int(stats["samples"]), 120 * 67)
	gut.p("Analyse d'une capture 1080p en %.2f ms" % elapsed_ms)
	PerfCheck.under(self, elapsed_ms, 200.0)
