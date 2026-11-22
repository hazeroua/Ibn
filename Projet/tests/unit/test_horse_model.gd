extends GutTest
## Cheval du ticket #106 dans le jeu : modèle préparé par Blender (generated/chevaux/), squelette et animations
## du cheval de Quaternius, taille réelle, tête vers l'avant de Godot, point de selle sur la selle.

const SETTINGS_PATH: String = "res://data/horse/horse.json"


func _settings() -> Dictionary:
	return JsonData.load_dictionary(SETTINGS_PATH)


func test_model_has_skeleton_and_every_clip() -> void:
	var visual: HorseVisual = HorseVisual.build(_settings())
	assert_not_null(visual, "modèle préparé par valider.bat")
	if visual == null:
		return
	add_child_autofree(visual)
	assert_not_null(visual.skeleton)
	assert_not_null(visual.animation_player)
	for clip: StringName in [&"Idle", &"WalkSlow", &"Walk", &"Run", &"Jump"]:
		assert_true(visual.animation_player.has_animation(clip), "animation %s" % clip)
	assert_almost_eq(visual.model_scale, 1.0, 0.02, "le modèle est déjà en mètres")


func test_head_faces_godot_forward_and_ears_reach_real_height() -> void:
	var visual: HorseVisual = HorseVisual.build(_settings())
	if visual == null:
		fail_test("modèle absent")
		return
	add_child_autofree(visual)
	var head: int = visual.skeleton.find_bone("Head")
	var tail: int = visual.skeleton.find_bone("Tail1")
	var head_position: Vector3 = (visual.skeleton.global_transform * visual.skeleton.get_bone_global_rest(head)).origin
	var tail_position: Vector3 = (visual.skeleton.global_transform * visual.skeleton.get_bone_global_rest(tail)).origin
	assert_lt(head_position.z, -0.5, "tête vers -Z")
	assert_gt(tail_position.z, 0.5, "queue vers +Z")
	assert_gt(head_position.y, 2.0, "tête haute")
	var top: float = 0.0
	for node: Node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		top = maxf(top, (mesh_instance.global_transform * mesh_instance.get_aabb()).end.y)
	assert_almost_eq(top, float(_settings()["model"]["height_m"]), 0.05)


func test_seat_is_on_the_saddle() -> void:
	var horse := HorseController.new(null)
	add_child_autofree(horse)
	var seat: Vector3 = horse.saddle_position()
	assert_between(seat.y, 1.70, 1.90, "bassin du cavalier au-dessus de la selle")
	assert_lt(absf(seat.x), 0.01)
	assert_lt(absf(seat.z), 0.25)


func test_ground_surfaces_match_footstep_surfaces() -> void:
	var settings: Dictionary = JsonData.load_dictionary(FootstepSystem.SETTINGS_PATH)
	for surface: StringName in HorseGround.SURFACES:
		assert_true((settings["surfaces"] as Dictionary).has(String(surface)), "sons de pas pour %s" % surface)
	assert_eq(HorseGround.SURFACES.size(), SaharaSurface.GROUND_NAMES.size(), "une surface sonore par sol du Sahara")
