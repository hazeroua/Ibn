#pragma once

#include "gdclass.h"

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <cstdint>
#include <vector>

// Placement de la végétation du désert (palmiers, buissons, herbe sèche), cellule par cellule.
//
// Principes :
// - Déterministe : le résultat ne dépend que de (graine, cellule, règles, champ de hauteurs).
// - Sans chevauchement : tirage de points avec rejet sur grilles d'occupation (une grille par espèce,
//   au plus un point par case), donc un test de conflit en O(1) par candidat. Les points sont gardés à
//   l'écart des bords de la cellule d'une distance égale à leur rayon : deux cellules voisines ne
//   peuvent jamais produire deux plantes qui se touchent.
// - Pire cas borné : le champ de hauteurs n'est interrogé que sur une grille fixe par cellule
//   (hauteur + surface à chaque nœud), jamais par candidat. Le coût d'appel ne dépend donc pas de la
//   densité ; le nombre de candidats est plafonné par les règles.
// - Toute la mémoire de travail est réservée dans load_rules() ; scatter() n'alloue que le résultat.
class VegetationScatter : public godot::RefCounted {
	IBN_GDCLASS(VegetationScatter, godot::RefCounted)

public:
	// Charge les règles (vegetation.json). Renvoie false et renseigne get_last_error() si invalide.
	bool load_rules(const godot::String &p_path);

	// Zone de l'oasis (centre en mètres sur le plan x/z, rayon en mètres).
	bool set_oasis(const godot::Vector2 &p_center, double p_radius);

	// Lit oasis_center et oasis_radius dans un fichier de données (desert.json).
	bool load_oasis(const godot::String &p_path);

	// Placement d'une cellule. Le champ de hauteurs expose height_at(x, z) -> float et
	// surface_at(Vector3) -> StringName. Renvoie, par espèce, les transformées au format d'un
	// MultiMesh (12 réels par instance, coordonnées du monde). Dictionnaire vide si une erreur
	// survient (voir get_last_error()).
	godot::Dictionary scatter(const godot::Vector2i &p_cell, godot::Object *p_heightfield, int64_t p_seed);

	// Réglages d'affichage par espèce (distance d'affichage, fondu, ombres, instances maximales).
	godot::Dictionary get_species_settings() const;
	godot::PackedStringArray get_species_ids() const;

	godot::String get_last_error() const;
	// Mesures du dernier scatter() : instances, candidats, appels au champ de hauteurs, durée.
	godot::Dictionary get_last_stats() const;

protected:
	static void _bind_methods();

private:
	struct CurvePoint {
		float distance = 0.0f;
		float multiplier = 0.0f;
	};

	struct Species {
		godot::StringName id;
		float radius = 0.0f;
		float density_per_hectare = 0.0f;
		int32_t max_instances = 0;
		float min_normal_y = 0.0f;
		float altitude_min = 0.0f;
		float altitude_max = 0.0f;
		float oasis_min = 0.0f;
		float oasis_max = 0.0f;
		std::vector<CurvePoint> curve;
		float max_multiplier = 0.0f;
		uint8_t surface_mask = 0;
		float scale_min = 1.0f;
		float scale_max = 1.0f;
		float height_scale_variation = 0.0f;
		float align_to_normal = 0.0f;
		float ground_offset = 0.0f;
		float visibility_range_end = 0.0f;
		float visibility_fade_margin = 0.0f;
		bool cast_shadows = false;
		// Grille d'occupation : côté de case = rayon * racine(2), une case = au plus un point.
		float grid_cell = 0.0f;
		int32_t grid_dim = 0;
		std::vector<int32_t> grid;
	};

	struct Point {
		float x = 0.0f;
		float z = 0.0f;
		float radius = 0.0f;
	};

	bool fail(const godot::String &p_message);
	float oasis_multiplier(const Species &p_species, float p_normalized_distance) const;
	bool conflicts(float p_x, float p_z, float p_radius, float p_cell_x0, float p_cell_z0) const;
	void scatter_species(size_t p_index, float p_x0, float p_z0, uint64_t p_hash);

	// Règles
	float world_origin_x_ = 0.0f;
	float world_origin_z_ = 0.0f;
	float cell_size_ = 0.0f;
	int32_t cells_per_side_ = 0;
	float height_step_ = 0.0f;
	int32_t height_segments_ = 0;
	float attempt_factor_ = 0.0f;
	int32_t max_attempts_ = 0;
	bool need_surface_ = false;
	std::vector<Species> species_;
	bool rules_loaded_ = false;

	// Oasis
	float oasis_x_ = 0.0f;
	float oasis_z_ = 0.0f;
	float oasis_radius_ = 0.0f;
	bool oasis_set_ = false;

	// Tampons de travail (réservés dans load_rules).
	std::vector<float> heights_;
	std::vector<uint8_t> surfaces_;
	std::vector<Point> points_;
	std::vector<std::vector<float>> outputs_;

	// Mesures du dernier scatter().
	int64_t stat_instances_ = 0;
	int64_t stat_attempts_ = 0;
	int64_t stat_heightfield_calls_ = 0;
	double stat_duration_ms_ = 0.0;

	godot::String last_error_;
};
