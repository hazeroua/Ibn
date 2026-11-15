class_name InputBindings
extends RefCounted
## Touches du joueur : valeurs par défaut du catalogue, surcharge enregistrée dans un fichier
## utilisateur (user://controles.json par défaut), reconfiguration par code et détection des conflits.
##
## Ne touche pas à l'InputMap : chaque changement émet bindings_changed, et le singleton GameInput
## déclare alors l'action modifiée (voir InputActions.apply_binding).
##
## Pires cas traités : fichier absent, vide, illisible, tronqué, énorme, d'une version plus récente
## ou plus ancienne (actions renommées ou disparues), partiellement faux (seules les parties
## invalides sont ignorées) ; arrêt brutal pendant l'écriture (écriture dans un fichier intermédiaire
## puis renommage, relu au démarrage si le fichier principal manque). Un problème du fichier
## utilisateur n'est jamais une erreur du jeu : il est signalé par push_warning.

## Émis après chaque changement des touches d'une action (action vide : toutes les actions).
signal bindings_changed(action: StringName)

enum LoadStatus { NO_FILE, LOADED, LOADED_WITH_REJECTIONS, CORRUPTED, NEWER_VERSION }
enum RebindResult { OK, UNKNOWN_ACTION, INVALID_EVENT, INVALID_SLOT, CONFLICT }

const CONTEXT: String = "fichier des touches"
const TEMP_SUFFIX: String = ".tmp"
const BACKUP_SUFFIX: String = ".illisible"

var last_load_status: LoadStatus = LoadStatus.NO_FILE
## Raisons des parties ignorées lors du dernier chargement.
var last_load_warnings: Array[String] = []
## Faux : les avertissements de lecture restent dans last_load_warnings mais ne sont pas écrits dans la console
## (utile aux mesures, car l'écriture dans la console Windows coûte plus que la lecture elle-même).
var log_warnings: bool = true

var _order: Array[StringName] = []
var _defaults: Dictionary[StringName, InputActionBinding] = {}
var _current: Dictionary[StringName, InputActionBinding] = {}
var _renamed: Dictionary[String, String] = {}
var _user_path: String = ""
var _user_version: int = 1
var _max_bytes: int = 65536
var _max_per_family: int = 3
var _axis_activation: float = 0.5
var _backup_before_save: bool = false


## Lit le catalogue (res://data/input/actions.json) ; user_path vide = chemin du catalogue.
## Toutes les touches reviennent aux valeurs par défaut.
func configure(catalog: Dictionary, user_path: String = "") -> void:
	var user_file: Dictionary = JsonData.get_dictionary(catalog, "user_file", InputActions.CONTEXT)
	_user_path = user_path if not user_path.is_empty() else JsonData.get_string(user_file, "path", InputActions.CONTEXT)
	_user_version = JsonData.get_int(user_file, "version", InputActions.CONTEXT)
	_max_bytes = JsonData.get_int(user_file, "max_bytes", InputActions.CONTEXT)
	_max_per_family = JsonData.get_int(catalog, "max_events_per_family", InputActions.CONTEXT)
	_axis_activation = JsonData.get_float(catalog, "joy_axis_activation", InputActions.CONTEXT)
	if _user_version < 1 or _max_bytes < 1 or _max_per_family < 1 or _axis_activation <= 0.0 or _axis_activation > 1.0:
		push_error("InputBindings : réglages du fichier utilisateur invalides dans le catalogue.")
	_renamed.clear()
	var renamed: Dictionary = JsonData.get_dictionary(catalog, "renamed_actions", InputActions.CONTEXT)
	for old_name: Variant in renamed:
		if typeof(old_name) != TYPE_STRING or typeof(renamed[old_name]) != TYPE_STRING:
			push_error("InputBindings : « renamed_actions » doit associer des noms à des noms.")
			continue
		var old_text: String = old_name
		var new_text: String = renamed[old_name]
		_renamed[old_text] = new_text
	_order.clear()
	_defaults.clear()
	for binding: InputActionBinding in InputActions.parse(catalog):
		_order.append(binding.action)
		_defaults[binding.action] = binding
		if binding.family_count(InputEventCodec.Family.KEYBOARD_MOUSE) > _max_per_family:
			push_error("InputBindings : « %s » dépasse max_events_per_family." % binding.action)
		if binding.family_count(InputEventCodec.Family.GAMEPAD) > _max_per_family:
			push_error("InputBindings : « %s » dépasse max_events_per_family." % binding.action)
	_reset_current()
	last_load_status = LoadStatus.NO_FILE
	last_load_warnings.clear()
	_backup_before_save = false


func get_user_path() -> String:
	return _user_path


func get_axis_activation() -> float:
	return _axis_activation


func has_action(action: StringName) -> bool:
	return _current.has(action)


## Noms des actions dans l'ordre du catalogue.
func get_action_names() -> Array[StringName]:
	return _order.duplicate()


## Touches actuelles de l'action (copie indépendante), ou null si l'action est inconnue.
func get_binding(action: StringName) -> InputActionBinding:
	if not _current.has(action):
		return null
	return _current[action].copy()


## Vrai si le joueur a changé les touches ou la zone morte de l'action.
func is_customized(action: StringName) -> bool:
	return _current.has(action) and not _current[action].same_as(_defaults[action])


## Charge la surcharge du joueur et la fusionne avec les valeurs par défaut ; résultat dans
## last_load_status et last_load_warnings.
func load_user_file() -> void:
	var path: String = _user_path
	if not FileAccess.file_exists(path):
		path = _user_path + TEMP_SUFFIX
		if not FileAccess.file_exists(path):
			_begin_load()
			last_load_status = LoadStatus.NO_FILE
			bindings_changed.emit(&"")
			return
	_begin_load()
	_finish_load(_parse_json(_read_text(path)), path)


## Même traitement que load_user_file, sur un texte déjà lu (sans accès au disque).
func load_user_text(text: String, source: String = "") -> void:
	_begin_load()
	var checked: Variant = null
	var length: int = text.to_utf8_buffer().size()
	if length > _max_bytes:
		last_load_warnings.append("fichier trop gros (%d octets, maximum %d)" % [length, _max_bytes])
	else:
		checked = text
	_finish_load(_parse_json(checked), source if not source.is_empty() else _user_path)


func _begin_load() -> void:
	_reset_current()
	last_load_warnings.clear()
	_backup_before_save = false


func _finish_load(root: Variant, path: String) -> void:
	if typeof(root) != TYPE_DICTIONARY:
		last_load_status = LoadStatus.CORRUPTED
	else:
		var root_data: Dictionary = root
		last_load_status = _merge(root_data)
	if last_load_status == LoadStatus.CORRUPTED or last_load_status == LoadStatus.NEWER_VERSION:
		_reset_current()
		_backup_before_save = true
	for warning: String in last_load_warnings:
		if not log_warnings:
			break
		push_warning("InputBindings : %s : %s." % [path, warning])
	bindings_changed.emit(&"")


## Enregistre les touches modifiées par le joueur (les autres restent aux valeurs par défaut du jeu,
## qui peuvent ainsi évoluer d'une version à l'autre). Un fichier illisible ou plus récent est
## d'abord conservé à côté (suffixe BACKUP_SUFFIX).
func save_user_file() -> Error:
	var text: String = user_text()
	var directory: String = _user_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(directory):
		var made: Error = DirAccess.make_dir_recursive_absolute(directory)
		if made != OK:
			return made
	if _backup_before_save and FileAccess.file_exists(_user_path):
		var copied: Error = DirAccess.copy_absolute(_user_path, _user_path + BACKUP_SUFFIX)
		if copied != OK:
			return copied
	var temp_path: String = _user_path + TEMP_SUFFIX
	var file: FileAccess = FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var stored: bool = file.store_string(text)
	file.close()
	if not stored:
		return ERR_FILE_CANT_WRITE
	var renamed: Error = DirAccess.rename_absolute(temp_path, _user_path)
	if renamed == OK:
		_backup_before_save = false
	return renamed


## Texte du fichier utilisateur (touches modifiées seulement), sans accès au disque.
func user_text() -> String:
	var overrides: Dictionary = {}
	for action: StringName in _order:
		if is_customized(action):
			var binding: InputActionBinding = _current[action]
			var events: Array[Dictionary] = []
			for event: InputEvent in binding.events:
				events.append(InputEventCodec.to_data(event))
			overrides[String(action)] = {"deadzone": binding.deadzone, "events": events}
	return JSON.stringify({"version": _user_version, "actions": overrides}, "\t")


## Lie event (capturé tel quel, il est d'abord mis sous forme canonique) à l'action, à la place
## de sa n-ième touche (slot) de la même famille d'appareil ; slot égal au nombre de touches de
## cette famille ajoute une touche. Si la touche sert déjà à une action active dans le même
## contexte : refus (CONFLICT) sauf si replace_conflicts, qui la retire de ces actions.
func rebind(action: StringName, event: InputEvent, slot: int = 0, replace_conflicts: bool = false) -> RebindResult:
	if not _current.has(action):
		return RebindResult.UNKNOWN_ACTION
	var canonical: InputEvent = InputEventCodec.normalize(event, _axis_activation)
	if canonical == null:
		return RebindResult.INVALID_EVENT
	var binding: InputActionBinding = _current[action]
	var family: InputEventCodec.Family = InputEventCodec.family_of(canonical)
	var count: int = binding.family_count(family)
	if slot < 0 or slot > count or (slot == count and count >= _max_per_family):
		return RebindResult.INVALID_SLOT
	var conflicts: Array[StringName] = find_conflicts(action, canonical)
	if not conflicts.is_empty() and not replace_conflicts:
		return RebindResult.CONFLICT
	var key: int = InputEventCodec.binding_key(canonical)
	for other: StringName in conflicts:
		var other_binding: InputActionBinding = _current[other]
		other_binding.events.remove_at(other_binding.find_key(key))
		bindings_changed.emit(other)
	var index: int = binding.find_slot(family, slot)
	if index < 0:
		binding.events.append(canonical)
	else:
		binding.events[index] = canonical
	# La même touche à une autre place de la même action ferait double emploi.
	for i: int in range(binding.events.size() - 1, -1, -1):
		if binding.events[i] != canonical and InputEventCodec.binding_key(binding.events[i]) == key:
			binding.events.remove_at(i)
	bindings_changed.emit(action)
	return RebindResult.OK


## Retire la n-ième touche (slot) de la famille donnée ; faux si elle n'existe pas.
func unbind(action: StringName, family: InputEventCodec.Family, slot: int) -> bool:
	if not _current.has(action):
		return false
	var binding: InputActionBinding = _current[action]
	var index: int = binding.find_slot(family, slot)
	if index < 0:
		return false
	binding.events.remove_at(index)
	bindings_changed.emit(action)
	return true


## Change la zone morte de l'action (entre 0 et 1) ; faux si l'action ou la valeur est invalide.
func set_deadzone(action: StringName, deadzone: float) -> bool:
	if not _current.has(action) or is_nan(deadzone) or deadzone < 0.0 or deadzone > 1.0:
		return false
	_current[action].deadzone = deadzone
	bindings_changed.emit(action)
	return true


## Remet l'action à ses valeurs par défaut ; les conflits éventuels sont donnés par get_all_conflicts.
func reset(action: StringName) -> bool:
	if not _defaults.has(action):
		return false
	_current[action] = _defaults[action].copy()
	bindings_changed.emit(action)
	return true


## Remet toutes les actions à leurs valeurs par défaut.
func reset_all() -> void:
	_reset_current()
	bindings_changed.emit(&"")


## Actions (autres que action) actives dans un contexte commun avec action et déjà liées à event.
func find_conflicts(action: StringName, event: InputEvent) -> Array[StringName]:
	var result: Array[StringName] = []
	var key: int = InputEventCodec.binding_key(event)
	var mask: int = _current[action].context_mask if _current.has(action) else -1
	if key < 0:
		return result
	for other: StringName in _order:
		var binding: InputActionBinding = _current[other]
		if other != action and (binding.context_mask & mask) != 0 and binding.find_key(key) >= 0:
			result.append(other)
	return result


## Tous les conflits actuels : liste de { "event": InputEvent, "actions": Array[StringName] }, une
## entrée par touche partagée par des actions actives dans un contexte commun.
func get_all_conflicts() -> Array[Dictionary]:
	var users: Dictionary[int, Array] = {}
	for action: StringName in _order:
		for event: InputEvent in _current[action].events:
			var key: int = InputEventCodec.binding_key(event)
			if not users.has(key):
				users[key] = []
			users[key].append(action)
	var result: Array[Dictionary] = []
	for key: int in users:
		var actions: Array = users[key]
		if actions.size() < 2:
			continue
		var involved: Array[StringName] = []
		for i: int in actions.size():
			for j: int in range(i + 1, actions.size()):
				var first: StringName = actions[i]
				var second: StringName = actions[j]
				if (_current[first].context_mask & _current[second].context_mask) == 0:
					continue
				if not involved.has(first):
					involved.append(first)
				if not involved.has(second):
					involved.append(second)
		if not involved.is_empty():
			var first_binding: InputActionBinding = _current[involved[0]]
			result.append({"event": first_binding.events[first_binding.find_key(key)].duplicate(), "actions": involved})
	return result


func _reset_current() -> void:
	_current.clear()
	for action: StringName in _order:
		_current[action] = _defaults[action].copy()


## Texte du fichier, ou null s'il est trop gros ou illisible.
func _read_text(path: String) -> Variant:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_load_warnings.append("ouverture impossible (%s)" % error_string(FileAccess.get_open_error()))
		return null
	var length: int = file.get_length()
	if length > _max_bytes:
		last_load_warnings.append("fichier trop gros (%d octets, maximum %d)" % [length, _max_bytes])
		return null
	var text: String = file.get_as_text()
	file.close()
	return text


## Contenu JSON du texte, ou null s'il est absent ou illisible.
func _parse_json(text: Variant) -> Variant:
	if typeof(text) != TYPE_STRING:
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		last_load_warnings.append("JSON illisible, ligne %d : %s" % [json.get_error_line(), json.get_error_message()])
		return null
	if typeof(json.data) != TYPE_DICTIONARY:
		last_load_warnings.append("la racine doit être un objet")
	return json.data


func _merge(root: Dictionary) -> LoadStatus:
	var version: Variant = root.get("version")
	if (typeof(version) != TYPE_FLOAT and typeof(version) != TYPE_INT) or float(version) != roundf(float(version)):
		last_load_warnings.append("« version » manquante ou invalide")
		return LoadStatus.CORRUPTED
	if int(version) > _user_version:
		last_load_warnings.append("version %d plus récente que celle du jeu (%d)" % [int(version), _user_version])
		return LoadStatus.NEWER_VERSION
	if int(version) < 1:
		last_load_warnings.append("version %d invalide" % int(version))
		return LoadStatus.CORRUPTED
	if typeof(root.get("actions")) != TYPE_DICTIONARY:
		last_load_warnings.append("« actions » doit être un objet")
		return LoadStatus.CORRUPTED
	var actions: Dictionary = root["actions"]
	var rejected: int = 0
	for raw_name: Variant in actions:
		var action_name: String = str(raw_name)
		action_name = _renamed.get(action_name, action_name)
		var action := StringName(action_name)
		if not _current.has(action):
			last_load_warnings.append("action inconnue « %s » ignorée" % action_name)
			rejected += 1
			continue
		if typeof(actions[raw_name]) != TYPE_DICTIONARY:
			last_load_warnings.append("« %s » doit être un objet" % action_name)
			rejected += 1
			continue
		var entry: Dictionary = actions[raw_name]
		rejected += _merge_action(_current[action], entry)
	return LoadStatus.LOADED if rejected == 0 else LoadStatus.LOADED_WITH_REJECTIONS


## Applique la surcharge d'une action ; renvoie le nombre de parties ignorées (0 à 2).
func _merge_action(binding: InputActionBinding, entry: Dictionary) -> int:
	var rejected: int = 0
	if entry.has("deadzone"):
		var deadzone: Variant = entry["deadzone"]
		if (typeof(deadzone) == TYPE_FLOAT or typeof(deadzone) == TYPE_INT) and float(deadzone) >= 0.0 and float(deadzone) <= 1.0:
			binding.deadzone = float(deadzone)
		else:
			last_load_warnings.append("zone morte de « %s » invalide, valeur par défaut gardée" % binding.action)
			rejected += 1
	if entry.has("events"):
		var events: Array[InputEvent] = []
		if _parse_events(entry["events"], binding.action, events):
			binding.events = events
		else:
			rejected += 1
	return rejected


## Remplit result avec les touches d'une surcharge ; faux si la liste est invalide (elle est alors
## entièrement ignorée, pour ne jamais garder une moitié de reconfiguration).
func _parse_events(raw: Variant, action: StringName, result: Array[InputEvent]) -> bool:
	if typeof(raw) != TYPE_ARRAY:
		last_load_warnings.append("touches de « %s » : un tableau est attendu" % action)
		return false
	var list: Array = raw
	if list.size() > 2 * _max_per_family:
		last_load_warnings.append("touches de « %s » : trop nombreuses" % action)
		return false
	var keys: Dictionary[int, bool] = {}
	var errors: Array[String] = []
	for event_data: Variant in list:
		var event: InputEvent = InputEventCodec.from_data(event_data, errors)
		if event == null:
			last_load_warnings.append("touches de « %s » : %s" % [action, ", ".join(errors)])
			return false
		var key: int = InputEventCodec.binding_key(event)
		if not keys.has(key):
			keys[key] = true
			result.append(event)
	var probe := InputActionBinding.new()
	probe.events = result
	if (
		probe.family_count(InputEventCodec.Family.KEYBOARD_MOUSE) > _max_per_family
		or probe.family_count(InputEventCodec.Family.GAMEPAD) > _max_per_family
	):
		last_load_warnings.append("touches de « %s » : trop nombreuses pour un appareil" % action)
		return false
	return true
