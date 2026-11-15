extends GutTest
## Eau de l'oasis : maillage unique léger et coût de construction mesuré.

const SETTINGS_PATH: String = "res://data/assets/oasis_water.json"
const BUILD_COUNT: int = 200
## Construire une oasis doit rester négligeable (budget moyen par construction, en ms).
const BUILD_BUDGET_MS: float = 2.0


func test_build_returns_single_surface_within_budget() -> void:
	var settings: Dictionary = JsonData.load_dictionary(SETTINGS_PATH)
	var budget: Dictionary = JsonData.get_dictionary(settings, "budget", SETTINGS_PATH)
	var node: Node3D = OasisWater.build(Vector2(120.0, -340.0), 60.0)
	assert_not_null(node)
	var instance: MeshInstance3D = node as MeshInstance3D
	assert_not_null(instance)
	assert_eq(instance.mesh.get_surface_count(), 1, "un seul appel de dessin")
	var indices: PackedInt32Array = instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	assert_lte(indices.size() / 3, int(JsonData.get_float(budget, "max_triangles", SETTINGS_PATH)))
	assert_almost_eq(node.position.x, 120.0, 0.001)
	assert_almost_eq(node.position.z, -340.0, 0.001)
	node.free()


func test_water_covers_the_requested_radius() -> void:
	var node: MeshInstance3D = OasisWater.build(Vector2.ZERO, 45.0) as MeshInstance3D
	var box: AABB = node.mesh.get_aabb()
	assert_almost_eq(box.size.x, 90.0, 0.5)
	assert_almost_eq(box.size.z, 90.0, 0.5)
	node.free()


func test_material_uses_the_light_shader_without_screen_reads() -> void:
	var node: MeshInstance3D = OasisWater.build(Vector2.ZERO, 30.0) as MeshInstance3D
	var material: ShaderMaterial = node.mesh.surface_get_material(0) as ShaderMaterial
	assert_not_null(material)
	assert_false(material.shader.code.contains("hint_screen_texture"))
	assert_false(material.shader.code.contains("hint_depth_texture"))
	node.free()


func test_build_cost_worst_case() -> void:
	var start: int = Time.get_ticks_usec()
	for i: int in BUILD_COUNT:
		var node: Node3D = OasisWater.build(Vector2(float(i), 0.0), 80.0)
		node.free()
	var per_build_ms: float = float(Time.get_ticks_usec() - start) / 1000.0 / float(BUILD_COUNT)
	gut.p(
		(
			"Construction de l'eau : %.3f ms en moyenne (%d constructions)"
			% [per_build_ms, BUILD_COUNT]
		)
	)
	assert_lt(per_build_ms, BUILD_BUDGET_MS)


func test_mesh_and_material_are_shared() -> void:
	var a: MeshInstance3D = OasisWater.build(Vector2.ZERO, 70.0) as MeshInstance3D
	var b: MeshInstance3D = OasisWater.build(Vector2(500.0, 0.0), 70.0) as MeshInstance3D
	var c: MeshInstance3D = OasisWater.build(Vector2.ZERO, 35.0) as MeshInstance3D
	assert_same(a.mesh, b.mesh, "même rayon : même maillage")
	assert_ne(a.mesh, c.mesh, "autre rayon : autre maillage")
	assert_same(a.mesh.surface_get_material(0), c.mesh.surface_get_material(0), "matériau unique")
	a.free()
	b.free()
	c.free()
