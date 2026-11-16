#pragma once

#include "gdclass.h"

#include <godot_cpp/classes/multi_mesh.hpp>
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <cstdint>
#include <vector>

// Troupeaux de gazelles du désert (faune d'ambiance, sans interaction de jeu).
//
// Principes :
// - Toute la simulation est ici : cohésion autour d'un point de pâture, séparation, fuite au galop quand le
//   joueur approche, apaisement ensuite, évitement des pentes fortes. Une seule passe par image sur un
//   tampon de structures préparé une fois ; aucune allocation après setup() / bind_multimesh().
// - Le relief est lu UNE FOIS, par lot, à l'initialisation : chaque zone garde une grille de hauteurs
//   (pas fixé par les réglages) ; ensuite chaque lecture de hauteur ou de pente est une interpolation en O(1)
//   et aucun appel au moteur n'a lieu pendant le jeu.
// - Les animaux sont confinés à leur zone (cercle ou polygone) : position bornée quelle que soit la durée de
//   la partie. Le pas de simulation est découpé en sous-pas bornés (stable pour de très grands pas de temps).
// - Pire cas : max_animals animaux (512 au plus), tous dans une zone polygonale, joueur au galop au milieu d'un
//   troupeau : coût borné par la taille des troupeaux (8 au plus), pas par le nombre de troupeaux au carré.
// - Le résultat est écrit directement dans le tampon d'un MultiMesh (12 réels de transformée + 4 réels
//   personnalisés par instance : phase de la foulée, allure) ; seuls les animaux à moins de view_distance_m
//   du joueur sont rangés en tête de tampon et affichés.
class FaunaHerds : public godot::RefCounted {
	IBN_GDCLASS(FaunaHerds, godot::RefCounted)

public:
	enum HerdState {
		STATE_GRAZING = 0,
		STATE_WALKING = 1,
		STATE_FLEEING = 2,
	};

	// Prépare la simulation. p_settings : réglages des gazelles (voir fauna.json > gazelles) ; p_zones : tableau de
	// dictionnaires { kind: "circle"|"polygon", center: Vector2, radius_m: float, points: PackedVector2Array,
	// herds: int, size_min: int, size_max: int } ; p_heightfield expose height_at(x, z) -> float (appelé uniquement
	// ici). Renvoie false et renseigne get_last_error() si une donnée est invalide.
	bool setup(const godot::Dictionary &p_settings, const godot::Array &p_zones, godot::Object *p_heightfield, int64_t p_seed);

	// Associe le MultiMesh à remplir : instance_count = get_animal_count(), 3D, sans couleurs, avec données
	// personnalisées. Le MultiMesh est conservé par cet objet.
	bool bind_multimesh(const godot::Ref<godot::MultiMesh> &p_multimesh);

	// Avance la simulation de p_delta secondes (joueur en p_player, mètres du monde) et écrit le tampon.
	void step(double p_delta, const godot::Vector3 &p_player);

	int64_t get_animal_count() const;
	int64_t get_herd_count() const;
	int64_t get_visible_count() const;
	// Position d'un animal (hors limites : Vector3 nul).
	godot::Vector3 get_animal_position(int64_t p_index) const;
	// Centre d'un troupeau (moyenne de ses animaux) et son état (HerdState).
	godot::Vector3 get_herd_center(int64_t p_herd) const;
	int64_t get_herd_state(int64_t p_herd) const;
	// Indice de la zone d'un troupeau, et test d'appartenance d'un point à une zone (plan x/z).
	int64_t get_herd_zone(int64_t p_herd) const;
	bool zone_contains(int64_t p_zone, double p_x, double p_z) const;
	// Rectangle englobant d'une zone [x0, z0, x1, z1] (pour les volumes de culling).
	godot::PackedFloat32Array get_zone_bounds(int64_t p_zone) const;
	int64_t get_zone_count() const;
	// Vrai si toutes les valeurs de position et de vitesse sont finies.
	bool is_state_finite() const;

	godot::String get_last_error() const;

protected:
	static void _bind_methods();

private:
	struct Zone {
		bool circle = true;
		float cx = 0.0f;
		float cz = 0.0f;
		float radius = 0.0f;
		std::vector<float> px;
		std::vector<float> pz;
		float min_x = 0.0f;
		float min_z = 0.0f;
		float max_x = 0.0f;
		float max_z = 0.0f;
		// Point intérieur sûr (centre du cercle, ou point intérieur trouvé à l'initialisation).
		float safe_x = 0.0f;
		float safe_z = 0.0f;
		// Grille de hauteurs.
		float grid_x0 = 0.0f;
		float grid_z0 = 0.0f;
		int32_t grid_nx = 0;
		int32_t grid_nz = 0;
		std::vector<float> heights;
		int32_t herds = 0;
		int32_t size_min = 0;
		int32_t size_max = 0;
	};

	struct Animal {
		float x = 0.0f;
		float z = 0.0f;
		float y = 0.0f;
		float vx = 0.0f;
		float vz = 0.0f;
		float hx = 0.0f;
		float hz = -1.0f;
		float off_x = 0.0f;
		float off_z = 0.0f;
		float phase = 0.0f;
		float scale = 1.0f;
		float run_factor = 1.0f;
		float gait = 0.0f;
	};

	struct Herd {
		int32_t zone = 0;
		int32_t first = 0;
		int32_t count = 0;
		int32_t state = STATE_GRAZING;
		float timer = 0.0f;
		float calm_timer = 0.0f;
		float repick_timer = 0.0f;
		float anchor_x = 0.0f;
		float anchor_z = 0.0f;
		float center_x = 0.0f;
		float center_z = 0.0f;
		float nearest_player_sq = 0.0f;
	};

	struct Params {
		float view_distance = 0.0f;
		float flee_distance = 0.0f;
		float calm_distance = 0.0f;
		float calm_delay = 0.0f;
		float walk_speed = 0.0f;
		float run_speed = 0.0f;
		float run_variation = 0.0f;
		float acceleration = 0.0f;
		float turn_response = 0.0f;
		float herd_radius = 0.0f;
		float separation = 0.0f;
		float separation_strength = 0.0f;
		float graze_min = 0.0f;
		float graze_max = 0.0f;
		float relocate_max = 0.0f;
		float flee_repick = 0.0f;
		float slope_limit = 0.0f;
		float slope_soft = 0.0f;
		float scale_min = 1.0f;
		float scale_max = 1.0f;
		float height_grid = 0.0f;
		float max_substep = 0.0f;
		float walk_stride_hz = 0.0f;
		float run_stride_hz = 0.0f;
		int32_t min_herd = 0;
		int32_t max_herd = 0;
		int32_t max_animals = 0;
		int32_t flee_candidates = 0;
	};

	bool fail(const godot::String &p_message);
	bool read_params(const godot::Dictionary &p_settings);
	bool read_float(const godot::Dictionary &p_data, const char *p_key, float &r_value, float p_min, float p_max);
	bool read_int(const godot::Dictionary &p_data, const char *p_key, int32_t &r_value, int32_t p_min, int32_t p_max);
	bool build_zone(const godot::Dictionary &p_data, godot::Object *p_heightfield, Zone &r_zone);
	bool zone_has(const Zone &p_zone, float p_x, float p_z) const;
	bool pick_point(const Zone &p_zone, float &r_x, float &r_z);
	float sample_height(const Zone &p_zone, float p_x, float p_z, float &r_gx, float &r_gz) const;
	float random_unit();
	uint64_t random_next();
	void step_herd(Herd &p_herd, float p_dt, float p_player_x, float p_player_z);
	void update_state(Herd &p_herd, float p_dt, float p_player_x, float p_player_z);
	void pick_flee_anchor(Herd &p_herd, float p_player_x, float p_player_z);
	void pick_walk_anchor(Herd &p_herd);
	void write_buffer(float p_player_x, float p_player_z);

	Params params_;
	std::vector<Zone> zones_;
	std::vector<Herd> herds_;
	std::vector<Animal> animals_;
	godot::Ref<godot::MultiMesh> multimesh_;
	godot::PackedFloat32Array buffer_;
	uint64_t rng_state_ = 0;
	int64_t visible_count_ = 0;
	bool ready_ = false;
	godot::String last_error_;
};
