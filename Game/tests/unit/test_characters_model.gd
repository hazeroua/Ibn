extends GutTest
## Modèle 3D du joueur (contrat du MVP 1) : fichier GLB produit par le pipeline, squelette, bibliothèque
## d'animation « locomotion », hauteur, orientation, budgets, boucles sans à-coup, animations sur place.

const CHARACTER_ID: String = "ibn_khaldoun_jeune"
const LIBRARY: StringName = &"locomotion"
const CONTRACT_ANIMATIONS: PackedStringArray = [
	"idle",
	"walk_slow",
	"walk",
	"run",
	"stop_walk",
	"stop_run",
	"turn_left_90",
	"turn_right_90",
	"turn_180",
	"jump_start",
	"jump_air",
	"jump_land",
	"bump",
	"land_roll",
	"ride_idle",
	"ride_gallop",
	"mount",
	"dismount",
]
const HEIGHT_M: float = 1.75
const HEIGHT_TOLERANCE_M: float = 0.005
## Raccord d'une boucle : la pose de fin doit être celle du début.
const LOOP_SEAM_MAX_DEG: float = 0.5
const LOOP_SEAM_MAX_M: float = 0.001
## Continuité : écart maximal d'un os entre deux échantillons à 120 Hz (au-delà, l'œil voit un saut).
const SAMPLE_RATE_HZ: float = 120.0
const STEP_MAX_DEG: float = 20.0
const STEP_MAX_M: float = 0.06
## Sur place : écart horizontal maximal des hanches par rapport à l'origine.
const IN_PLACE_MAX_M: float = 0.25
const ROOT_MAX_OFFSET_M: float = 0.001
const TURN_TOLERANCE_DEG: float = 2.0
## Fin d'un arrêt ou d'un virage = début de « idle » (enchaînement sans saut).
const HANDOFF_MAX_DEG: float = 1.0
const HANDOFF_MAX_M: float = 0.005
## Monte : le bassin est posé sur la selle (ancré hors de l'axe) et la montée/descente déplace le corps vers
## le cheval par construction ; ces animations ne sont pas « sur place ».
const SEATED_ANIMATIONS: Array[String] = ["ride_idle", "ride_gallop", "mount", "dismount"]

var _manifest: Dictionary = {}
var _character: Dictionary = {}
var _scene: PackedScene = null


func before_all() -> void:
	_manifest = CharacterCatalog.load_manifest()
	_character = CharacterCatalog.get_character(_manifest, CHARACTER_ID)
	_scene = CharacterCatalog.load_scene(CHARACTER_ID)


func _instantiate() -> Node3D:
	var instance: Node3D = _scene.instantiate() as Node3D
	add_child_autofree(instance)
	return instance


func _entry(anim_name: String) -> Dictionary:
	for raw: Variant in JsonData.get_array(_character, "animations", "test"):
		var entry: Dictionary = raw
		if entry.get("name") == anim_name:
			return entry
	return {}


func _skeleton_bone(key: String) -> String:
	return JsonData.get_string(JsonData.get_dictionary(_character, "skeleton", "test"), key, "test")


func test_manifest_matches_contract() -> void:
	assert_false(_character.is_empty(), "le personnage du MVP 1 doit être dans le manifeste")
	assert_eq(CharacterCatalog.animation_names(_character), CONTRACT_ANIMATIONS)
	assert_eq(StringName(JsonData.get_string(_character, "animation_library", "test")), LIBRARY)
	assert_almost_eq(JsonData.get_float(_character, "height_m", "test"), HEIGHT_M, 0.0001)
	assert_eq(JsonData.get_string(_character, "forward", "test"), "-Z")
	assert_eq(JsonData.get_string(_character, "license", "test"), "CC0-1.0")
	var source_id: String = JsonData.get_string(_character, "source", "test")
	var found: bool = false
	for raw: Variant in JsonData.get_array(_manifest, "sources", "test"):
		var source: Dictionary = raw
		if source.get("id") == source_id:
			found = true
			assert_eq(JsonData.get_string(source, "license", "test"), "CC0-1.0")
			for file_raw: Variant in JsonData.get_array(source, "files", "test"):
				var sha: String = JsonData.get_string(file_raw, "sha256", "test")
				assert_eq(sha.length(), 64, "empreinte SHA-256 attendue pour chaque fichier source")
	assert_true(found, "la source du personnage doit être décrite dans le manifeste")


func test_glb_loads_with_skeleton_and_locomotion_library() -> void:
	assert_not_null(_scene, "le GLB doit être produit et importé par le pipeline")
	var instance: Node3D = _instantiate()
	var skeletons: Array[Node] = instance.find_children("*", "Skeleton3D", true, false)
	assert_eq(skeletons.size(), 1)
	var skeleton: Skeleton3D = skeletons[0]
	for key: String in ["root_bone", "hips_bone", "left_foot", "right_foot", "left_toe", "head"]:
		assert_ne(skeleton.find_bone(_skeleton_bone(key)), -1, "os « %s » attendu" % _skeleton_bone(key))
	var player: AnimationPlayer = CharacterCatalog.find_animation_player(instance)
	assert_not_null(player)
	assert_eq(player.get_animation_library_list(), [LIBRARY] as Array[StringName])
	var library: AnimationLibrary = player.get_animation_library(LIBRARY)
	assert_eq(library.get_animation_list().size(), CONTRACT_ANIMATIONS.size())
	for anim_name: String in CONTRACT_ANIMATIONS:
		assert_true(library.has_animation(anim_name), "animation « %s » attendue" % anim_name)
		if not library.has_animation(anim_name):
			continue
		var animation: Animation = library.get_animation(anim_name)
		var loop: bool = JsonData.get_bool(_entry(anim_name), "loop", "test")
		assert_eq(animation.loop_mode, Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE, "bouclage de « %s »" % anim_name)
		assert_gt(animation.length, 0.1, "durée de « %s »" % anim_name)


func test_height_feet_at_origin_and_facing_minus_z() -> void:
	var instance: Node3D = _instantiate()
	var meshes: Array[Node] = instance.find_children("*", "MeshInstance3D", true, false)
	assert_eq(meshes.size(), 1)
	var mesh_instance: MeshInstance3D = meshes[0]
	var bounds: AABB = mesh_instance.global_transform * mesh_instance.mesh.get_aabb()
	gut.p("Hauteur %.4f m, pieds à %.4f m" % [bounds.size.y, bounds.position.y])
	assert_almost_eq(bounds.size.y, HEIGHT_M, HEIGHT_TOLERANCE_M)
	assert_almost_eq(bounds.position.y, 0.0, HEIGHT_TOLERANCE_M)
	var skeleton: Skeleton3D = CharacterCatalog.find_skeleton(instance)
	var foot: Vector3 = skeleton.get_bone_global_rest(skeleton.find_bone(_skeleton_bone("left_foot"))).origin
	var toe: Vector3 = skeleton.get_bone_global_rest(skeleton.find_bone(_skeleton_bone("left_toe"))).origin
	assert_lt(toe.z, foot.z - 0.05, "les orteils doivent pointer vers -Z")
	assert_lt(foot.x, 0.0, "le pied gauche doit être du côté -X quand le regard est vers -Z")


func test_budget_triangles_bones_surfaces() -> void:
	var budget: Dictionary = JsonData.get_dictionary(_character, "budget", "test")
	var instance: Node3D = _instantiate()
	var mesh_instance: MeshInstance3D = instance.find_children("*", "MeshInstance3D", true, false)[0]
	var mesh: ArrayMesh = mesh_instance.mesh as ArrayMesh
	var triangles: int = 0
	for surface: int in mesh.get_surface_count():
		triangles += mesh.surface_get_array_index_len(surface) / 3
	var skeleton: Skeleton3D = CharacterCatalog.find_skeleton(instance)
	gut.p("Triangles %d, os %d, surfaces %d" % [triangles, skeleton.get_bone_count(), mesh.get_surface_count()])
	assert_lte(triangles, JsonData.get_int(budget, "max_triangles", "test"))
	assert_lte(skeleton.get_bone_count(), JsonData.get_int(budget, "max_bones", "test"))
	assert_lte(mesh.get_surface_count(), JsonData.get_int(budget, "max_surfaces", "test"))
	var material: BaseMaterial3D = mesh.surface_get_material(0) as BaseMaterial3D
	assert_not_null(material)
	assert_true(material.vertex_color_use_as_albedo, "la couleur vient des sommets (une seule surface)")
	assert_eq(material.cull_mode, BaseMaterial3D.CULL_BACK)
	assert_not_null(mesh_instance.skin, "le maillage doit être lié au squelette")


func test_loops_close_exactly() -> void:
	var library: AnimationLibrary = CharacterCatalog.find_animation_player(_instantiate()).get_animation_library(LIBRARY)
	for anim_name: String in CONTRACT_ANIMATIONS:
		if not JsonData.get_bool(_entry(anim_name), "loop", "test"):
			continue
		var animation: Animation = library.get_animation(anim_name)
		var worst: Vector2 = _pose_gap(animation, 0.0, animation, animation.length)
		gut.p("Raccord de « %s » : %.3f°, %.4f m" % [anim_name, worst.x, worst.y])
		assert_lt(worst.x, LOOP_SEAM_MAX_DEG, "raccord de rotation de « %s »" % anim_name)
		assert_lt(worst.y, LOOP_SEAM_MAX_M, "raccord de position de « %s »" % anim_name)


func test_animations_are_continuous() -> void:
	var library: AnimationLibrary = CharacterCatalog.find_animation_player(_instantiate()).get_animation_library(LIBRARY)
	var step: float = 1.0 / SAMPLE_RATE_HZ
	for anim_name: String in CONTRACT_ANIMATIONS:
		var animation: Animation = library.get_animation(anim_name)
		var worst := Vector2.ZERO
		var time: float = 0.0
		while time < animation.length:
			var next: float = minf(time + step, animation.length)
			var gap: Vector2 = _pose_gap(animation, time, animation, next)
			worst = Vector2(maxf(worst.x, gap.x), maxf(worst.y, gap.y))
			time = next
		gut.p("Plus grand écart entre deux échantillons de « %s » : %.2f°, %.4f m" % [anim_name, worst.x, worst.y])
		assert_lt(worst.x, STEP_MAX_DEG, "saut de rotation dans « %s »" % anim_name)
		assert_lt(worst.y, STEP_MAX_M, "saut de position dans « %s »" % anim_name)


func test_stops_and_turns_hand_off_to_idle() -> void:
	var library: AnimationLibrary = CharacterCatalog.find_animation_player(_instantiate()).get_animation_library(LIBRARY)
	var idle: Animation = library.get_animation(&"idle")
	var root_bone: String = _skeleton_bone("root_bone")
	for anim_name: String in ["stop_walk", "stop_run", "turn_left_90", "turn_right_90", "turn_180"]:
		var animation: Animation = library.get_animation(anim_name)
		# L'os racine d'un virage porte la rotation : il est exclu de la comparaison.
		var gap: Vector2 = _pose_gap(animation, animation.length, idle, 0.0, root_bone)
		gut.p("Fin de « %s » → début de « idle » : %.3f°, %.4f m" % [anim_name, gap.x, gap.y])
		assert_lt(gap.x, HANDOFF_MAX_DEG, "fin de « %s »" % anim_name)
		assert_lt(gap.y, HANDOFF_MAX_M, "fin de « %s »" % anim_name)


func test_animations_in_place_and_turn_angles() -> void:
	var instance: Node3D = _instantiate()
	var player: AnimationPlayer = CharacterCatalog.find_animation_player(instance)
	var skeleton: Skeleton3D = CharacterCatalog.find_skeleton(instance)
	var root: int = skeleton.find_bone(_skeleton_bone("root_bone"))
	var hips: int = skeleton.find_bone(_skeleton_bone("hips_bone"))
	var skeleton_to_model: Transform3D = instance.global_transform.affine_inverse() * skeleton.global_transform
	for anim_name: String in CONTRACT_ANIMATIONS:
		if anim_name in SEATED_ANIMATIONS:
			continue
		var full_name: String = "%s/%s" % [LIBRARY, anim_name]
		player.play(full_name)
		var animation: Animation = player.get_animation(full_name)
		var hips_max: float = 0.0
		var root_max: float = 0.0
		var start_yaw: float = 0.0
		var end_yaw: float = 0.0
		var samples: int = 24
		for i: int in samples + 1:
			player.seek(animation.length * float(i) / float(samples), true)
			var root_pose: Transform3D = skeleton_to_model * skeleton.get_bone_global_pose(root)
			var hips_pose: Vector3 = skeleton_to_model * skeleton.get_bone_global_pose(hips).origin
			hips_max = maxf(hips_max, Vector2(hips_pose.x, hips_pose.z).length())
			root_max = maxf(root_max, Vector2(root_pose.origin.x, root_pose.origin.z).length())
			var yaw: float = _yaw_of(root_pose.basis)
			if i == 0:
				start_yaw = yaw
			end_yaw = yaw
		var turned: float = rad_to_deg(wrapf(end_yaw - start_yaw, -PI, PI))
		var recipe: Dictionary = JsonData.get_dictionary(_entry(anim_name), "recipe", "test")
		var expected: float = JsonData.get_float(recipe, "angle_deg", "test") if recipe.get("type") == "turn" else 0.0
		gut.p("« %s » : hanches à %.3f m au plus de l'axe, racine %.4f m, rotation %.1f°" % [anim_name, hips_max, root_max, turned])
		assert_lt(hips_max, IN_PLACE_MAX_M, "« %s » doit rester sur place" % anim_name)
		assert_lt(root_max, ROOT_MAX_OFFSET_M, "la racine de « %s » ne doit pas se déplacer" % anim_name)
		assert_almost_eq(absf(wrapf(turned - expected, -180.0, 180.0)), 0.0, TURN_TOLERANCE_DEG, "rotation de « %s »" % anim_name)


## Cap (rotation autour de la verticale) d'une base : angle de son axe avant projeté au sol.
func _yaw_of(basis: Basis) -> float:
	var forward: Vector3 = basis.y if absf(basis.y.y) < 0.5 else basis.z
	return atan2(forward.x, forward.z)


## Écart maximal (degrés, mètres) entre les poses de deux animations à deux instants, piste par piste.
func _pose_gap(a: Animation, time_a: float, b: Animation, time_b: float, skip_bone: String = "") -> Vector2:
	var worst_deg: float = 0.0
	var worst_m: float = 0.0
	for track: int in a.get_track_count():
		var path: NodePath = a.track_get_path(track)
		if not skip_bone.is_empty() and path.get_concatenated_subnames() == skip_bone:
			continue
		var type: Animation.TrackType = a.track_get_type(track)
		var other: int = b.find_track(path, type)
		match type:
			Animation.TYPE_ROTATION_3D:
				var qa: Quaternion = a.rotation_track_interpolate(track, time_a)
				var qb: Quaternion = b.rotation_track_interpolate(other, time_b) if other != -1 else qa
				worst_deg = maxf(worst_deg, rad_to_deg(qa.angle_to(qb)))
			Animation.TYPE_POSITION_3D:
				var pa: Vector3 = a.position_track_interpolate(track, time_a)
				var pb: Vector3 = b.position_track_interpolate(other, time_b) if other != -1 else pa
				worst_m = maxf(worst_m, pa.distance_to(pb))
			Animation.TYPE_SCALE_3D:
				var sa: Vector3 = a.scale_track_interpolate(track, time_a)
				var sb: Vector3 = b.scale_track_interpolate(other, time_b) if other != -1 else sa
				worst_m = maxf(worst_m, sa.distance_to(sb))
	return Vector2(worst_deg, worst_m)
