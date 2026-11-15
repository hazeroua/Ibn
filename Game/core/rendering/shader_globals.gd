class_name ShaderGlobals
extends RefCounted
## Déclaration unique des uniformes globaux de shader créés par le jeu. Godot interdit de relire la
## liste des uniformes hors de l'éditeur (RenderingServer.global_shader_parameter_get_list), d'où ce
## registre : tous les uniformes globaux du jeu passent par declare().

static var _declared: Dictionary[StringName, bool] = {}


## Déclare l'uniforme s'il ne l'est pas encore ; sans effet ensuite.
static func declare(uniform: StringName, type: RenderingServer.GlobalShaderParameterType, default_value: Variant) -> void:
	if _declared.has(uniform):
		return
	RenderingServer.global_shader_parameter_add(uniform, type, default_value)
	_declared[uniform] = true
