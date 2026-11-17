extends GutTest

const SCENE_PATH: String = "res://world/tunis/tunis.tscn"


func test_generated_scene_contains_runtime_root() -> void:
	var scene: PackedScene = load(SCENE_PATH) as PackedScene
	assert_not_null(scene)
	var root: Node = scene.instantiate()
	assert_true(root is TunisRuntime)
	root.free()
