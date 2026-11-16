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

	// Éléments de paysage : liste de plans d'eau ({center: [x, z], radius_m, kind facultatif}) et d'oueds ({points: [[x, z], ...]}),
	// au format de desert.json. Au plus 32 plans d'eau et 16 oueds de 64 points.
	bool set_features(const godot::Array &p_water_bodies, const godot::Array &p_wadis);

	// Lit water_bodies et wadis dans un fichier de données (desert.json).
	bool load_features(const godot::String &p_path);

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
		float water_min = 0.0f;
		float water_max = 0.0f;
		// Types de plans d'eau pris en compte pour la distance (tous par défaut).
		uint8_t water_kinds = 15;
		// Courbe selon la distance normalisée au plan d'eau le plus proche.
		std::vector<CurvePoint> curve;
		float water_max_multiplier = 0.0f;
		// Courbe facultative selon la distance (mètres) à l'oued le plus proche ; vide = multiplicateur 1.
		std::vector<CurvePoint> wadi_curve;
		float wadi_max_multiplier = 1.0f;
		// Produit des deux maxima : borne de l'acceptation et du nombre d'essais.
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

	struct WaterBody {
		float x = 0.0f;
		float z = 0.0f;
		float radius = 1.0f;
		// Type du plan d'eau (bit de kind_bit) ; tous les bits si le plan d'eau n'a pas de type.
		uint8_t kinds = 15;
	};

	struct Segment {
		float ax = 0.0f;
		float az = 0.0f;
		float bx = 0.0f;
		float bz = 0.0f;
	};

	struct Point {
		float x = 0.0f;
		float z = 0.0f;
		float radius = 0.0f;
	};

	bool fail(const godot::String &p_message);
	static float curve_multiplier(const std::vector<CurvePoint> &p_curve, float p_distance);
	static bool parse_curve(const godot::Variant &p_value, std::vector<CurvePoint> &r_curve, float &r_max, godot::String &r_error);
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

	// Éléments de paysage (réservés dans set_features) et leur sélection pour la cellule en cours.
	std::vector<WaterBody> water_bodies_;
	std::vector<Segment> segments_;
	std::vector<Segment> cell_segments_;
	// Plus grande distance (mètres) d'une courbe d'oued parmi les espèces : au-delà, un oued est sans effet.
	float wadi_range_max_ = 0.0f;
	bool features_set_ = false;

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
