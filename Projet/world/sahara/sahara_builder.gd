class_name SaharaBuilder
extends RefCounted
## Constructeur du Sahara, lancé par outils/construire.gd (pipeline) :
## 1. empaquette les textures téléchargées au format Terrain3D
##    (albédo + hauteur, normale OpenGL + rugosité) dans generated/sahara/textures/ ;
## 2. génère relief, sols et teintes en pleine résolution ;
## 3. enregistre les régions Terrain3D dans generated/sahara/terrain/.
## Rien n'est refait si les données, les ressources et le code du générateur n'ont pas changé.

const DATA_PATH: String = "res://data/sahara/sahara.json"
const OUTPUT_DIR: String = "res://generated/sahara"
const TERRAIN_DIR: String = "res://generated/sahara/terrain"
const TEXTURE_DIR: String = "res://generated/sahara/textures"
const STAMP_PATH: String = "res://generated/sahara/empreinte.txt"
const LOG_CATEGORY: String = "construction"
const TEXTURE_SIZE: int = 2048
## Fichiers dont dépend le résultat : toute modification relance la construction.
const SOURCES: PackedStringArray = [
	"res://data/sahara/sahara.json",
	"res://data/ressources.json",
	"res://data/ressources.lock.json",
	"res://world/sahara/sahara_settings.gd",
	"res://world/sahara/sahara_heightfield.gd",
	"res://world/sahara/sahara_surface.gd",
	"res://world/sahara/sahara_builder.gd",
]
const IMPORT_SETTINGS: String = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.7
compress/normal_map=2
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
process/fix_alpha_border=false
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/size_limit=0
detect_3d/compress_to=0
"""


## Chemins des textures empaquetées d'un sol (utilisés aussi par la scène).
static func albedo_path(ground: String) -> String:
	return TEXTURE_DIR.path_join(ground + "_albedo_hauteur.png")


static func normal_path(ground: String) -> String:
	return TEXTURE_DIR.path_join(ground + "_normale_rugosite.png")


static func build(tree: SceneTree) -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	var data: Dictionary = JsonData.load_dictionary(DATA_PATH)
	var settings: SaharaSettings = SaharaSettings.from_dictionary(JsonData.read_dictionary(data, "generation", errors, "sahara.json"))
	errors.append_array(settings.errors)
	var manifest: ResourceManifest = ResourceManifest.load_shipped()
	errors.append_array(manifest.errors)
	var textures: Array = JsonData.read_dictionary(data, "scene", errors, "sahara.json").get("textures", [])
	if not errors.is_empty():
		return errors

	var stamp: String = _compute_stamp()
	if FileAccess.file_exists(STAMP_PATH) and FileAccess.get_file_as_string(STAMP_PATH).strip_edges() == stamp:
		GameLog.info(LOG_CATEGORY, "Sahara déjà à jour.")
		return errors
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TERRAIN_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEXTURE_DIR))

	var start_msec: int = Time.get_ticks_msec()
	for texture: Variant in textures:
		var entry: Dictionary = texture
		errors.append_array(_pack_texture(String(entry.get("ground", "")), String(entry.get("resource", "")), manifest))
	if not errors.is_empty():
		return errors
	GameLog.info(LOG_CATEGORY, "Textures empaquetées en %d ms." % (Time.get_ticks_msec() - start_msec))

	start_msec = Time.get_ticks_msec()
	var pixels: int = int(settings.map_size_meters / settings.vertex_spacing_meters)
	var field: SaharaHeightfield = SaharaHeightfield.generate(settings, pixels)
	var surface: SaharaSurface = SaharaSurface.generate(field, settings)
	GameLog.info(LOG_CATEGORY, "Relief et sols %d × %d générés en %d ms." % [pixels, pixels, Time.get_ticks_msec() - start_msec])
	var twist: PackedFloat32Array = field.max_walkable_twist(settings.walkable_slope_degrees)
	GameLog.info(LOG_CATEGORY, "Torsion maximale praticable : %.2f m en (%.0f, %.0f)." % [twist[0], twist[1], twist[2]])
	if twist[0] > settings.max_walkable_twist_meters:
		errors.append(
			(
				"Relief trop irrégulier pour une grille de %.0f m : torsion %.2f m en (%.0f, %.0f), maximum %.2f m."
				% [settings.vertex_spacing_meters, twist[0], twist[1], twist[2], settings.max_walkable_twist_meters]
			)
		)
		return errors

	errors.append_array(await _save_terrain(tree, settings, field, surface))
	if not errors.is_empty():
		return errors
	var stamp_file: FileAccess = FileAccess.open(STAMP_PATH, FileAccess.WRITE)
	if stamp_file == null:
		errors.append("Impossible d'écrire " + STAMP_PATH)
		return errors
	stamp_file.store_line(stamp)
	stamp_file.close()
	for landmark: Dictionary in field.landmarks:
		GameLog.info(LOG_CATEGORY, "Repère « %s » : sommet à %s." % [landmark["name"], str(landmark["position"])])
	return errors


static func _compute_stamp() -> String:
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	for path: String in SOURCES:
		context.update(path.to_utf8_buffer())
		context.update(FileAccess.get_file_as_bytes(path))
	return context.finish().hex_encode()


static func _pack_texture(ground: String, resource_key: String, manifest: ResourceManifest) -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if ground not in SaharaSurface.GROUND_NAMES or not manifest.has_texture(resource_key):
		errors.append("sahara.json › textures : sol « %s » ou ressource « %s » inconnus." % [ground, resource_key])
		return errors
	var images: Dictionary = {}
	for map_name: String in ResourceManifest.TEXTURE_MAPS:
		var path: String = ProjectSettings.globalize_path(manifest.local_path(resource_key, map_name))
		var image: Image = Image.load_from_file(path)
		if image == null or image.is_empty():
			errors.append("Texture absente ou illisible : %s (lancez valider.bat pour la télécharger)." % path)
			continue
		if image.is_compressed():
			image.decompress()
		if image.get_size() != Vector2i(TEXTURE_SIZE, TEXTURE_SIZE):
			image.resize(TEXTURE_SIZE, TEXTURE_SIZE, Image.INTERPOLATE_LANCZOS)
		images[map_name] = image
	if not errors.is_empty():
		return errors
	var albedo_height: Image = Terrain3DUtil.pack_image(images["albedo"], images["height"], null, false, false, true, 0, 0)
	var normal_roughness: Image = Terrain3DUtil.pack_image(images["normal"], images["roughness"], null, false, false, false, 0, 0)
	for pair: Array in [[albedo_height, albedo_path(ground)], [normal_roughness, normal_path(ground)]]:
		var packed: Image = pair[0]
		var target: String = pair[1]
		if packed == null or packed.get_format() != Image.FORMAT_RGBA8:
			errors.append("Empaquetage Terrain3D impossible pour " + target)
			continue
		var save_error: Error = packed.save_png(ProjectSettings.globalize_path(target))
		if save_error != OK:
			errors.append("Impossible d'écrire %s : %s" % [target, error_string(save_error)])
			continue
		var import_file: FileAccess = FileAccess.open(target + ".import", FileAccess.WRITE)
		if import_file == null:
			errors.append("Impossible d'écrire %s.import" % target)
			continue
		import_file.store_string(IMPORT_SETTINGS)
		import_file.close()
	return errors


static func _save_terrain(tree: SceneTree, settings: SaharaSettings, field: SaharaHeightfield, surface: SaharaSurface) -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	var directory: DirAccess = DirAccess.open(TERRAIN_DIR)
	if directory == null:
		errors.append("Dossier inaccessible : " + TERRAIN_DIR)
		return errors
	for file_name: String in directory.get_files():
		if file_name.begins_with("terrain3d"):
			directory.remove(file_name)

	# Terrain3D cherche une caméra pour ses niveaux de détail : une caméra fixe suffit ici.
	var camera: Camera3D = Camera3D.new()
	tree.root.add_child(camera)
	camera.current = true
	var terrain: Terrain3D = Terrain3D.new()
	terrain.free_editor_textures = false
	terrain.vertex_spacing = settings.vertex_spacing_meters
	terrain.clipmap_target = camera
	tree.root.add_child(terrain)
	await tree.process_frame
	# La taille de région n'est prise en compte qu'une fois le terrain dans l'arbre.
	terrain.change_region_size(settings.region_size as Terrain3D.RegionSize)

	var images: Array[Image] = [field.to_height_image(), surface.to_control_image(), surface.to_color_image()]
	var corner: Vector3 = Vector3(field.origin.x, 0.0, field.origin.y)
	terrain.data.import_images(images, corner, 0.0, 1.0)
	var expected_regions: int = int(pow(settings.map_size_meters / (settings.vertex_spacing_meters * settings.region_size), 2.0))
	if terrain.data.get_region_count() != expected_regions:
		errors.append("Terrain3D : %d régions au lieu de %d." % [terrain.data.get_region_count(), expected_regions])
	terrain.data.save_directory(TERRAIN_DIR)
	var saved: int = 0
	for file_name: String in DirAccess.get_files_at(TERRAIN_DIR):
		if file_name.begins_with("terrain3d") and file_name.ends_with(".res"):
			saved += 1
	if saved != expected_regions:
		errors.append("Terrain3D : %d régions enregistrées au lieu de %d." % [saved, expected_regions])
	GameLog.info(LOG_CATEGORY, "%d régions Terrain3D enregistrées dans %s." % [saved, TERRAIN_DIR])
	terrain.queue_free()
	camera.queue_free()
	await tree.process_frame
	return errors
