extends GutTest
## Test de charge des collisions sur le vrai terrain construit (generated/sahara/terrain) :
## une capsule de personnage parcourt la boucle de mesure à pied puis à 70 m/s, avec la
## physique Jolt et les collisions dynamiques de Terrain3D centrées sur elle.
## Pire cas : passage des crêtes de dunes, des berges d'oued et des éboulis à pleine vitesse,
## collisions reconstruites en continu autour du corps.

const DATA_PATH: String = "res://data/sahara/sahara.json"
const WALK_FRAMES: int = 300
const FULL_SPEED_FRAMES: int = 600
const WALK_FRACTION: float = 0.0
const FULL_SPEED_FRACTION: float = 0.99

var _terrain: Terrain3D
var _runner: RouteRunner
var _camera: Camera3D


func before_each() -> void:
	if not DirAccess.dir_exists_absolute(SaharaBuilder.TERRAIN_DIR):
		return
	var data: Dictionary = JsonData.load_dictionary(DATA_PATH)
	var scene: Dictionary = data["scene"]
	var collision: Dictionary = scene["terrain"]["collision"]
	_terrain = Terrain3D.new()
	_terrain.free_editor_textures = false
	_terrain.vertex_spacing = float(data["generation"]["vertex_spacing_meters"])
	_terrain.data_directory = SaharaBuilder.TERRAIN_DIR
	_runner = RouteRunner.new()
	var errors: PackedStringArray = PackedStringArray()
	_runner.configure(scene["measure_route"], errors, "measure_route")
	assert_true(errors.is_empty(), str(errors))
	_camera = Camera3D.new()
	add_child_autofree(_camera)
	_terrain.clipmap_target = _camera
	add_child_autofree(_terrain)
	_terrain.collision.mode = Terrain3DCollision.DYNAMIC_GAME
	_terrain.collision.radius = int(collision["radius"])
	_terrain.collision.shape_size = int(collision["shape_size"])
	_runner.terrain_data = _terrain.data
	add_child_autofree(_runner)
	_terrain.collision_target = _runner
	_runner.place_at_start()


func test_terrain_is_built() -> void:
	assert_true(DirAccess.dir_exists_absolute(SaharaBuilder.TERRAIN_DIR), "lancez outils/construire.gd avant les tests")
	if _terrain != null:
		assert_eq(_terrain.data.get_region_count(), 16)


func test_walking_never_goes_through_the_ground() -> void:
	await _run(WALK_FRAMES, WALK_FRACTION)
	assert_eq(_runner.below_ground_events, 0)
	assert_eq(_runner.stuck_events, 0)
	assert_gt(_runner.distance_meters, 1.6 * WALK_FRAMES / 60.0 * 0.8)


func test_full_speed_never_goes_through_the_ground() -> void:
	await _run(FULL_SPEED_FRAMES, FULL_SPEED_FRACTION)
	assert_eq(_runner.below_ground_events, 0)
	assert_eq(_runner.stuck_events, 0)
	assert_gt(_runner.distance_meters, 70.0 * FULL_SPEED_FRAMES / 60.0 * 0.8)


func _run(frames: int, fraction: float) -> void:
	if _runner == null:
		fail_test("terrain non construit : lancez outils/construire.gd avant les tests")
		return
	for frame: int in frames:
		await wait_physics_frames(1)
		_runner.step(get_physics_process_delta_time(), fraction)
