#pragma once

#include <godot_cpp/core/class_db.hpp>

// GDCLASS de godot-cpp, sans l'avertissement C4189 (« variable locale initialisée mais non utilisée »)
// que MSVC émet sur le code généré par la macro. Nos sources sont compilées avec les avertissements
// traités comme des erreurs : seul cet avertissement, et seulement dans le code de la macro, est neutralisé.
#if defined(_MSC_VER)
#define IBN_GDCLASS(m_class, m_inherits) \
	__pragma(warning(push)) \
	__pragma(warning(disable : 4189)) \
	GDCLASS(m_class, m_inherits) \
	__pragma(warning(pop))
#else
#define IBN_GDCLASS(m_class, m_inherits) GDCLASS(m_class, m_inherits)
#endif
