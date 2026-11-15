#pragma once

#include "gdclass.h"

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <atomic>
#include <cstdint>
#include <vector>

// Streaming du monde : charge et décharge les cellules (grille carrée) autour du joueur.
//
// Pires cas retenus : grille 16 x 16 (256 cellules), galop à 15 m/s en ligne droite ou en zigzag,
// puce graphique intégrée, partie de 100 heures (aucune dérive : tout est dimensionné une fois pour toutes).
//
// Principe :
//  - la construction d'une cellule (fournisseur.build_cell) se fait en tâche de fond (WorkerThreadPool) ;
//  - le fil principal ne fait que l'insertion dans l'arbre et le retrait, dans la limite d'un budget par image ;
//  - l'ensemble voulu est recalculé uniquement quand la cellule du joueur ou celle de sa position anticipée change ;
//  - tous les tampons sont réservés à la configuration : aucune allocation dans update().
class WorldStreamer : public godot::Node {
	IBN_GDCLASS(WorldStreamer, godot::Node)

public:
	WorldStreamer();
	~WorldStreamer() override;

	// Lit un fichier JSON de réglages (res://data/streaming/streaming.json). Renvoie false (et signale l'erreur) si invalide.
	bool load_config(const godot::String &p_path);
	// Applique un dictionnaire de réglages (mêmes clés que le fichier). Renvoie false si invalide, sans rien modifier.
	bool configure(const godot::Dictionary &p_config);

	// Le fournisseur doit exposer build_cell(cell: Vector2i) -> Node3D (appelée depuis un fil de travail).
	bool register_provider(godot::Object *p_provider);

	// Position et vitesse du joueur (m, m/s). Peu coûteux : à appeler à chaque image.
	void set_focus(const godot::Vector3 &p_position, const godot::Vector3 &p_velocity);

	// Avance le streaming d'une image. Appelée par _process quand l'autotraitement est actif.
	void update(double p_delta);

	// Décharge toutes les cellules et attend les tâches en cours.
	void clear();

	bool is_cell_loaded(const godot::Vector2i &p_cell) const;
	godot::Node3D *get_cell_node(const godot::Vector2i &p_cell) const;
	int64_t get_loaded_count() const;
	int64_t get_pending_count() const;
	godot::PackedVector2Array get_loaded_cells() const;
	godot::Vector2i world_to_cell(const godot::Vector3 &p_position) const;

	// Statistiques cumulées : coût maximal d'update (ms), images au-delà du budget, chargements, déchargements.
	godot::Dictionary get_stats() const;
	void reset_stats();

	void set_auto_update(bool p_enabled);
	bool get_auto_update() const;

protected:
	static void _bind_methods();
	void _notification(int p_what);

private:
	enum SlotState : int {
		STATE_ABSENT = 0,
		STATE_BUILDING = 1,
		STATE_READY = 2,
		STATE_FAILED = 3,
		STATE_LOADED = 4,
		STATE_DEAD = 5, // échec déjà signalé : la cellule n'est plus jamais demandée
	};

	struct Slot {
		std::atomic<int> state{ STATE_ABSENT };
		godot::Node3D *node = nullptr; // écrit par le fil de travail avant le passage à READY
		int64_t task_id = -1;
		uint8_t want = 0; // dans le rayon de chargement
		uint8_t keep = 0; // dans le rayon de déchargement (chargement + hystérésis)
		float priority = 0.0F;
	};

	void build_task(int64_t p_index);
	void recompute_desired();
	void dispatch_builds();
	void integrate_ready(int64_t p_deadline_us);
	void unload_stale(int64_t p_deadline_us);
	// p_immediate : libération immédiate (clear), sinon différée à la fin de l'image (queue_free).
	void release_slot(size_t p_index, bool p_emit, bool p_immediate);
	void wait_all_tasks();
	int64_t cell_index_at(float p_x, float p_z) const;
	godot::Vector2i index_to_cell(size_t p_index) const;
	void cell_center(size_t p_index, float &r_x, float &r_z) const;

	bool configured_ = false;
	float cell_size_ = 250.0F;
	int grid_size_ = 16;
	float origin_x_ = -2000.0F;
	float origin_z_ = -2000.0F;
	float load_radius_ = 600.0F;
	float unload_radius_ = 850.0F;
	float lookahead_s_ = 6.0F;
	double budget_ms_ = 2.0;
	int max_concurrent_ = 4;

	godot::Object *provider_ = nullptr;
	std::vector<Slot> slots_;
	std::vector<godot::Callable> build_callables_;
	std::vector<uint32_t> queue_; // indices triés par priorité (réservé à la configuration)
	std::vector<uint32_t> loaded_; // cellules chargées (réservé à la configuration)
	size_t queue_head_ = 0;
	int in_flight_ = 0;
	bool unload_pending_ = false;

	float focus_x_ = 0.0F;
	float focus_z_ = 0.0F;
	float velocity_x_ = 0.0F;
	float velocity_z_ = 0.0F;
	bool focus_set_ = false;
	bool dirty_ = true;
	int64_t last_focus_index_ = -2;
	int64_t last_predicted_index_ = -2;

	bool auto_update_ = true;
	double max_update_ms_ = 0.0;
	int64_t over_budget_frames_ = 0;
	int64_t load_count_ = 0;
	int64_t unload_count_ = 0;
	int64_t failed_count_ = 0;
	int64_t update_count_ = 0;
};
