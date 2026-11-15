#include "perf_recorder.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>

#include <algorithm>
#include <cmath>
#include <numeric>

using godot::ClassDB;
using godot::D_METHOD;
using godot::Dictionary;
using godot::PackedFloat32Array;
using godot::PackedInt64Array;

namespace {

// Plafond de sécurité : 4 heures à 1000 images par seconde.
constexpr int64_t MAX_CAPACITY = 4LL * 3600LL * 1000LL;

// Indice du centile p (0 < p <= 100) selon la méthode du rang le plus proche.
size_t nearest_rank_index(size_t p_count, double p_percentile) {
	const double rank = std::ceil(p_percentile / 100.0 * static_cast<double>(p_count));
	const size_t index = rank < 1.0 ? 0 : static_cast<size_t>(rank) - 1;
	return std::min(index, p_count - 1);
}

} // namespace

bool PerfRecorder::reserve(int64_t p_capacity) {
	ERR_FAIL_COND_V_MSG(p_capacity <= 0 || p_capacity > MAX_CAPACITY, false, "PerfRecorder.reserve : capacité hors limites.");
	const size_t capacity = static_cast<size_t>(p_capacity);
	frame_ms_.assign(capacity, 0.0f);
	cpu_ms_.assign(capacity, 0.0f);
	gpu_ms_.assign(capacity, 0.0f);
	draw_calls_.assign(capacity, 0);
	primitives_.assign(capacity, 0);
	scratch_.assign(capacity, 0.0f);
	capacity_ = capacity;
	count_ = 0;
	return true;
}

bool PerfRecorder::add_frame(double p_frame_ms, double p_cpu_ms, double p_gpu_ms, int64_t p_draw_calls, int64_t p_primitives) {
	if (count_ >= capacity_) {
		return false;
	}
	if (!std::isfinite(p_frame_ms) || !std::isfinite(p_cpu_ms) || !std::isfinite(p_gpu_ms) ||
			p_frame_ms < 0.0 || p_cpu_ms < 0.0 || p_gpu_ms < 0.0 || p_draw_calls < 0 || p_primitives < 0) {
		return false;
	}
	frame_ms_[count_] = static_cast<float>(p_frame_ms);
	cpu_ms_[count_] = static_cast<float>(p_cpu_ms);
	gpu_ms_[count_] = static_cast<float>(p_gpu_ms);
	draw_calls_[count_] = p_draw_calls;
	primitives_[count_] = p_primitives;
	++count_;
	return true;
}

void PerfRecorder::clear() {
	count_ = 0;
}

int64_t PerfRecorder::get_count() const {
	return static_cast<int64_t>(count_);
}

int64_t PerfRecorder::get_capacity() const {
	return static_cast<int64_t>(capacity_);
}

PackedFloat32Array PerfRecorder::to_packed(const std::vector<float> &p_series, size_t p_count) {
	PackedFloat32Array packed;
	packed.resize(static_cast<int64_t>(p_count));
	if (p_count > 0) {
		std::copy_n(p_series.data(), p_count, packed.ptrw());
	}
	return packed;
}

PackedInt64Array PerfRecorder::to_packed(const std::vector<int64_t> &p_series, size_t p_count) {
	PackedInt64Array packed;
	packed.resize(static_cast<int64_t>(p_count));
	if (p_count > 0) {
		std::copy_n(p_series.data(), p_count, packed.ptrw());
	}
	return packed;
}

PackedFloat32Array PerfRecorder::get_frame_ms() const {
	return to_packed(frame_ms_, count_);
}

PackedFloat32Array PerfRecorder::get_cpu_ms() const {
	return to_packed(cpu_ms_, count_);
}

PackedFloat32Array PerfRecorder::get_gpu_ms() const {
	return to_packed(gpu_ms_, count_);
}

PackedInt64Array PerfRecorder::get_draw_calls() const {
	return to_packed(draw_calls_, count_);
}

PackedInt64Array PerfRecorder::get_primitives() const {
	return to_packed(primitives_, count_);
}

PerfRecorder::SeriesStats PerfRecorder::compute_series_stats(const std::vector<float> &p_series) const {
	SeriesStats stats;
	const size_t n = count_;
	float *values = scratch_.data();
	std::copy_n(p_series.data(), n, values);

	double sum = 0.0;
	for (size_t i = 0; i < n; ++i) {
		sum += static_cast<double>(values[i]);
	}
	stats.average = sum / static_cast<double>(n);

	// Centiles par sélection (O(n) en moyenne par centile), dans l'ordre croissant des rangs :
	// chaque nth_element ne réordonne que la partie droite déjà délimitée.
	const size_t i50 = nearest_rank_index(n, 50.0);
	const size_t i95 = nearest_rank_index(n, 95.0);
	const size_t i99 = nearest_rank_index(n, 99.0);
	std::nth_element(values, values + i50, values + n);
	stats.p50 = static_cast<double>(values[i50]);
	std::nth_element(values + i50, values + i95, values + n);
	stats.p95 = static_cast<double>(values[i95]);
	std::nth_element(values + i95, values + i99, values + n);
	stats.p99 = static_cast<double>(values[i99]);
	stats.maximum = static_cast<double>(*std::max_element(values + i99, values + n));

	// Moyenne du pire 1 % (au moins une image) : les k plus grandes valeurs.
	const size_t worst_count = std::max<size_t>(1, n / 100);
	const size_t worst_begin = n - worst_count;
	std::nth_element(values, values + worst_begin, values + n);
	double worst_sum = 0.0;
	for (size_t i = worst_begin; i < n; ++i) {
		worst_sum += static_cast<double>(values[i]);
	}
	stats.worst_percent_average = worst_sum / static_cast<double>(worst_count);
	return stats;
}

Dictionary PerfRecorder::compute_summary() const {
	Dictionary summary;
	if (count_ == 0) {
		return summary;
	}
	const SeriesStats frame = compute_series_stats(frame_ms_);
	const SeriesStats cpu = compute_series_stats(cpu_ms_);
	const SeriesStats gpu = compute_series_stats(gpu_ms_);

	int64_t draw_calls_max = 0;
	int64_t primitives_max = 0;
	double draw_calls_sum = 0.0;
	for (size_t i = 0; i < count_; ++i) {
		draw_calls_max = std::max(draw_calls_max, draw_calls_[i]);
		primitives_max = std::max(primitives_max, primitives_[i]);
		draw_calls_sum += static_cast<double>(draw_calls_[i]);
	}

	summary["frames"] = static_cast<int64_t>(count_);
	summary["frame_avg_ms"] = frame.average;
	summary["frame_p50_ms"] = frame.p50;
	summary["frame_p95_ms"] = frame.p95;
	summary["frame_p99_ms"] = frame.p99;
	summary["frame_max_ms"] = frame.maximum;
	summary["fps_avg"] = frame.average > 0.0 ? 1000.0 / frame.average : 0.0;
	summary["fps_1pct_low"] = frame.worst_percent_average > 0.0 ? 1000.0 / frame.worst_percent_average : 0.0;
	summary["cpu_avg_ms"] = cpu.average;
	summary["cpu_p99_ms"] = cpu.p99;
	summary["gpu_avg_ms"] = gpu.average;
	summary["gpu_p99_ms"] = gpu.p99;
	summary["draw_calls_avg"] = draw_calls_sum / static_cast<double>(count_);
	summary["draw_calls_max"] = draw_calls_max;
	summary["primitives_max"] = primitives_max;
	return summary;
}

void PerfRecorder::_bind_methods() {
	ClassDB::bind_method(D_METHOD("reserve", "capacity"), &PerfRecorder::reserve);
	ClassDB::bind_method(D_METHOD("add_frame", "frame_ms", "cpu_ms", "gpu_ms", "draw_calls", "primitives"), &PerfRecorder::add_frame);
	ClassDB::bind_method(D_METHOD("clear"), &PerfRecorder::clear);
	ClassDB::bind_method(D_METHOD("get_count"), &PerfRecorder::get_count);
	ClassDB::bind_method(D_METHOD("get_capacity"), &PerfRecorder::get_capacity);
	ClassDB::bind_method(D_METHOD("get_frame_ms"), &PerfRecorder::get_frame_ms);
	ClassDB::bind_method(D_METHOD("get_cpu_ms"), &PerfRecorder::get_cpu_ms);
	ClassDB::bind_method(D_METHOD("get_gpu_ms"), &PerfRecorder::get_gpu_ms);
	ClassDB::bind_method(D_METHOD("get_draw_calls"), &PerfRecorder::get_draw_calls);
	ClassDB::bind_method(D_METHOD("get_primitives"), &PerfRecorder::get_primitives);
	ClassDB::bind_method(D_METHOD("compute_summary"), &PerfRecorder::compute_summary);
}
