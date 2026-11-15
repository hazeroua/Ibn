#include "register_types.h"

#include "perf_recorder.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

void initialize_ibn_module(godot::ModuleInitializationLevel p_level) {
	if (p_level != godot::MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(PerfRecorder);
}

void uninitialize_ibn_module(godot::ModuleInitializationLevel p_level) {
	// Aucune ressource globale à libérer : les classes sont désenregistrées par Godot.
	(void)p_level;
}

extern "C" {

GDExtensionBool GDE_EXPORT ibn_library_init(
		GDExtensionInterfaceGetProcAddress p_get_proc_address,
		GDExtensionClassLibraryPtr p_library,
		GDExtensionInitialization *r_initialization) {
	godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_ibn_module);
	init_obj.register_terminator(uninitialize_ibn_module);
	init_obj.set_minimum_library_initialization_level(godot::MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}

} // extern "C"
