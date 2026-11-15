#pragma once

#include "gdclass.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>

#include <cstdint>
#include <vector>

// Enregistreur de mesures de performance, une entrée par image.
//
// Conçu pour le chemin chaud : toute la mémoire est réservée une fois par reserve(), puis
// add_frame() n'alloue jamais. Quand la capacité est atteinte, add_frame() refuse la mesure
// et renvoie false : la scène de mesure dimensionne la capacité d'après la durée et un
// plafond d'images par seconde, et traite ce refus comme une erreur.
class PerfRecorder : public godot::RefCounted {
	IBN_GDCLASS(PerfRecorder, godot::RefCounted)

public:
	// Réserve la mémoire pour p_capacity images et efface les mesures existantes.
	// Renvoie false (sans rien modifier) si p_capacity est nulle, négative ou au-delà du plafond de sécurité.
	bool reserve(int64_t p_capacity);

	// Ajoute les mesures d'une image. Renvoie false si la capacité est atteinte ou si une valeur est invalide.
	bool add_frame(double p_frame_ms, double p_cpu_ms, double p_gpu_ms, int64_t p_draw_calls, int64_t p_primitives);

	// Efface les mesures sans libérer la mémoire réservée.
	void clear();

	int64_t get_count() const;
	int64_t get_capacity() const;

	godot::PackedFloat32Array get_frame_ms() const;
	godot::PackedFloat32Array get_cpu_ms() const;
	godot::PackedFloat32Array get_gpu_ms() const;
	godot::PackedInt64Array get_draw_calls() const;
	godot::PackedInt64Array get_primitives() const;

	// Statistiques sur les images enregistrées (moyennes, centiles par rang, maximums).
	// Renvoie un dictionnaire vide si aucune image n'a été enregistrée.
	godot::Dictionary compute_summary() const;

protected:
	static void _bind_methods();

private:
	struct SeriesStats {
		double average = 0.0;
		double p50 = 0.0;
		double p95 = 0.0;
		double p99 = 0.0;
		double maximum = 0.0;
		double worst_percent_average = 0.0;
	};

	// Calcule les statistiques d'une série à partir d'une copie dans le tampon de travail (déjà réservé).
	SeriesStats compute_series_stats(const std::vector<float> &p_series) const;

	static godot::PackedFloat32Array to_packed(const std::vector<float> &p_series, size_t p_count);
	static godot::PackedInt64Array to_packed(const std::vector<int64_t> &p_series, size_t p_count);

	std::vector<float> frame_ms_;
	std::vector<float> cpu_ms_;
	std::vector<float> gpu_ms_;
	std::vector<int64_t> draw_calls_;
	std::vector<int64_t> primitives_;
	mutable std::vector<float> scratch_;
	size_t count_ = 0;
	size_t capacity_ = 0;
};
