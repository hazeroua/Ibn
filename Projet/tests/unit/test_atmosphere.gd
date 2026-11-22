extends GutTest
## Atmosphère du Sahara : données livrées, trois moments, poussière et chaleur.
## Nécessite les textures de particules construites (outils/construire.gd).

const DATA_PATH: String = "res://data/sahara/atmosphere.json"

var _camera: Camera3D
var _atmosphere: Atmosphere
var _errors: PackedStringArray = PackedStringArray()


func before_each() -> void:
	_camera = Camera3D.new()
	add_child_autofree(_camera)
	_atmosphere = Atmosphere.new()
	add_child_autofree(_atmosphere)
	_errors = PackedStringArray()
	_atmosphere.configure(JsonData.load_dictionary(DATA_PATH), _camera, SaharaBuilder.PARTICLE_DIR, _errors)


func test_shipped_atmosphere_is_valid() -> void:
	assert_true(_errors.is_empty(), str(_errors))
	assert_eq(_atmosphere.moment_order, PackedStringArray(["matin", "midi", "fin_de_journee"]))
	assert_eq(_atmosphere.current_moment_id, _atmosphere.default_moment_id)


func test_three_moments_give_three_distinct_lights() -> void:
	var elevations: Dictionary = {}
	for moment_id: String in _atmosphere.moment_order:
		_atmosphere.apply_moment(moment_id)
		await wait_physics_frames(2)
		# Hauteur du soleil au-dessus de l'horizon, en degrés.
		elevations[moment_id] = rad_to_deg(asin(_atmosphere.sky3d.sun.global_basis.z.y))
	assert_between(float(elevations["matin"]), 8.0, 35.0, "soleil du matin")
	assert_gt(float(elevations["midi"]), 50.0, "soleil de midi")
	assert_between(float(elevations["fin_de_journee"]), 2.0, 20.0, "soleil de fin de journée")


func test_heat_haze_only_when_it_is_hot() -> void:
	var haze: MeshInstance3D = _camera.get_node("Chaleur") as MeshInstance3D
	_atmosphere.apply_moment("matin")
	assert_false(haze.visible, "pas de chaleur le matin")
	_atmosphere.apply_moment("midi")
	assert_true(haze.visible, "chaleur à midi")


func test_dust_follows_the_moment_density() -> void:
	var emitters: Array[Node] = _atmosphere.find_children("Poussiere_*", "GPUParticles3D", false, false)
	assert_eq(emitters.size(), 3)
	_atmosphere.apply_moment("matin")
	var morning: float = (emitters[0] as GPUParticles3D).amount_ratio
	_atmosphere.apply_moment("fin_de_journee")
	assert_gt((emitters[0] as GPUParticles3D).amount_ratio, morning, "plus de poussière en fin de journée")


func test_cycle_goes_through_every_moment() -> void:
	_atmosphere.apply_moment("matin")
	assert_eq(_atmosphere.cycle_moment(), "midi")
	assert_eq(_atmosphere.cycle_moment(), "fin_de_journee")
	assert_eq(_atmosphere.cycle_moment(), "matin")


func test_invalid_atmosphere_data_is_rejected() -> void:
	var data: Dictionary = JsonData.load_dictionary(DATA_PATH).duplicate(true)
	data["default_moment"] = "nuit"
	data["moment_order"] = ["matin", "matin", "midi"]
	data["moments"]["midi"]["hour"] = 25.0
	var broken: Atmosphere = Atmosphere.new()
	add_child_autofree(broken)
	var errors: PackedStringArray = PackedStringArray()
	broken.configure(data, _camera, SaharaBuilder.PARTICLE_DIR, errors)
	assert_eq(errors.size(), 3, str(errors))
