extends SceneTree
## Captures reproductibles de la médina générée (Scripts/Pipeline/capturer-medina.ps1).
##
## La ville est construite à partir des cellules versionnées (TunisCellProvider, comme en jeu), toutes
## cellules chargées, sous une lumière neutre de fin d'après-midi : ce sont des captures de contrôle de
## la composition (silhouette, coude de la rue, ombre du passage, place), pas de l'ambiance (#58).
## Points de vue tirés du plan généré (medina_layout.json) : aucun point codé en dur.
## Argument après « -- » : --out=<dossier absolu>.

const OUT_PREFIX: String = "--out="
const SETTLE_FRAMES: int = 12
const EYE_HEIGHT_M: float = 1.7
const MOUNTED_EYE_HEIGHT_M: float = 2.6
const FOV_DEG: float = 70.0
const SUN_ELEVATION_DEG: float = 24.0
const SUN_AZIMUTH_DEG: float = 235.0
const GROUND_SIZE_M: float = 600.0
const GROUND_COLOR: Color = Color(0.71, 0.6, 0.43)
const TOP_VIEW_HEIGHT_M: float = 150.0

var _out: String = ""
var _camera: Camera3D = null


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(OUT_PREFIX):
			_out = argument.substr(OUT_PREFIX.length())
	if _out.is_empty():
		push_error("capture_medina : --out=<dossier> est requis.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _run() -> void:
	var provider: TunisCellProvider = TunisCellProvider.create()
	if provider == null:
		quit(1)
		return
	var world := Node3D.new()
	get_root().add_child(world)
	var grid: int = int(sqrt(float(provider.cell_count())))
	for x: int in grid:
		for z: int in grid:
			var cell: Node3D = provider.build_cell(Vector2i(x, z))
			if cell == null:
				quit(1)
				return
			world.add_child(cell)
	_add_environment(world)
	_camera = Camera3D.new()
	_camera.fov = FOV_DEG
	_camera.far = 2000.0
	world.add_child(_camera)
	_camera.make_current()
	var layout: Dictionary = JsonData.load_dictionary(MedinaStore.LAYOUT_PATH)
	for shot: Dictionary in _shots(layout):
		_camera.global_transform = Transform3D.IDENTITY.looking_at(shot["target"] - shot["eye"], Vector3.UP).translated(shot["eye"])
		for frame: int in SETTLE_FRAMES:
			await process_frame
		var image: Image = get_root().get_texture().get_image()
		var path: String = _out.path_join(String(shot["name"]) + ".png")
		if image == null or image.save_png(path) != OK:
			push_error("capture_medina : capture impossible : %s." % path)
			quit(1)
			return
		print("Capture : " + path)
	world.queue_free()
	await process_frame
	quit(0)


func _add_environment(world: Node3D) -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-SUN_ELEVATION_DEG, SUN_AZIMUTH_DEG, 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 220.0
	world.add_child(sun)
	var sky_material := ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var holder := WorldEnvironment.new()
	holder.environment = environment
	world.add_child(holder)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(GROUND_SIZE_M, GROUND_SIZE_M)
	var material := StandardMaterial3D.new()
	material.albedo_color = GROUND_COLOR
	material.roughness = 1.0
	plane.material = material
	ground.mesh = plane
	world.add_child(ground)


func _v3(point: Array, height: float) -> Vector3:
	return Vector3(float(point[0]), height, float(point[1]))


func _shots(layout: Dictionary) -> Array[Dictionary]:
	var shots: Array[Dictionary] = []
	var gate: Dictionary = layout["gate"]
	var gate_point: Vector3 = _v3(gate["position"], 0.0)
	var inward: Array = gate["inward"]
	var into := Vector3(float(inward[0]), 0.0, float(inward[1]))
	var description: Dictionary = JsonData.load_dictionary(MedinaStore.DESCRIPTION_PATH)
	var viewpoints: Dictionary = description["viewpoints"]
	for distance: Variant in viewpoints["desert_distances_m"]:
		var eye: Vector3 = gate_point - into * float(distance) + Vector3.UP * MOUNTED_EYE_HEIGHT_M
		shots.append({"name": "desert_%dm" % int(distance), "eye": eye, "target": gate_point + Vector3.UP * 4.0})
	shots.append(
		{
			"name": "porte_interieur",
			"eye": gate_point + into * 2.0 + Vector3.UP * EYE_HEIGHT_M,
			"target": gate_point + into * 30.0 + Vector3.UP * EYE_HEIGHT_M
		}
	)
	var plaza: Dictionary = layout["plaza"]
	var fountain: Vector3 = _v3(plaza["fountain"], 0.0)
	var rect: Array = plaza["rect"]
	var corner := Vector3(float(rect[0]) + 1.5, EYE_HEIGHT_M, float(rect[3]) - 1.5)
	shots.append({"name": "place_fontaine", "eye": corner, "target": fountain + Vector3.UP * 1.0})
	for span: Variant in layout["spans"]:
		var entry: Dictionary = span
		if String(entry["prefab"]) != MedinaBuilder.PREFAB_PASSAGE:
			continue
		var from: Vector3 = _v3(entry["from"], EYE_HEIGHT_M)
		var to: Vector3 = _v3(entry["to"], EYE_HEIGHT_M)
		var along: Vector3 = (to - from).normalized()
		shots.append({"name": "passage_couvert", "eye": from - along * 6.0, "target": to})
	var narrow: String = String((layout["narrowest_way"] as Dictionary)["id"])
	for way: Variant in layout["ways"]:
		var data: Dictionary = way
		if String(data["id"]) != narrow:
			continue
		var points: Array = data["points"]
		var a: Vector3 = _v3(points[1], EYE_HEIGHT_M)
		var b: Vector3 = _v3(points[2], EYE_HEIGHT_M)
		shots.append({"name": "ruelle_etroite", "eye": a + (b - a).normalized() * 2.0, "target": b})
	var center: Vector3 = (gate_point + fountain) / 2.0
	shots.append({"name": "vue_dessus", "eye": center + Vector3(0.0, TOP_VIEW_HEIGHT_M, 0.01), "target": center})
	return shots
