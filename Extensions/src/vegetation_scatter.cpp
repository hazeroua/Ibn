#include "vegetation_scatter.h"

#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/json.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>
#include <limits>

using godot::Array;
using godot::Dictionary;
using godot::String;
using godot::StringName;
using godot::Variant;

namespace {

constexpr float kPi = 3.14159265358979323846f;
constexpr uint8_t kSurfaceSand = 1;
constexpr uint8_t kSurfaceStone = 2;
constexpr uint8_t kSurfaceEarth = 4;
constexpr uint8_t kSurfaceAll = kSurfaceSand | kSurfaceStone | kSurfaceEarth;
constexpr int64_t kMaxInstancesLimit = 200000;
constexpr int32_t kMaxGridCells = 4000000;
constexpr int32_t kMaxHeightSegments = 256;

// Générateur pseudo-aléatoire SplitMix64 : portable (même suite sur toutes les plateformes).
struct Rng {
	uint64_t state = 0;

	static uint64_t mix(uint64_t p_value) {
		uint64_t z = p_value + 0x9E3779B97F4A7C15ULL;
		z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
		z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
		return z ^ (z >> 31);
	}

	uint64_t next() {
		state += 0x9E3779B97F4A7C15ULL;
		uint64_t z = state;
		z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
		z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
		return z ^ (z >> 31);
	}

	// Réel dans [0, 1).
	float unit() {
		return static_cast<float>(next() >> 40) * (1.0f / 16777216.0f);
	}
};

bool read_number(const Dictionary &p_data, const char *p_key, double &r_value) {
	const StringName key(p_key);
	if (!p_data.has(key)) {
		return false;
	}
	const Variant value = p_data[key];
	if (value.get_type() != Variant::FLOAT && value.get_type() != Variant::INT) {
		return false;
	}
	r_value = static_cast<double>(value);
	return std::isfinite(r_value);
}

} // namespace

bool VegetationScatter::fail(const String &p_message) {
	last_error_ = p_message;
	return false;
}

bool VegetationScatter::load_rules(const String &p_path) {
	rules_loaded_ = false;
	species_.clear();
	wadi_range_max_ = 0.0f;
	if (!godot::FileAccess::file_exists(p_path)) {
		return fail("Fichier de règles introuvable : " + p_path);
	}
	const String text = godot::FileAccess::get_file_as_string(p_path);
	godot::Ref<godot::JSON> json;
	json.instantiate();
	if (json->parse(text) != godot::OK || json->get_data().get_type() != Variant::DICTIONARY) {
		return fail("JSON invalide : " + p_path);
	}
	const Dictionary root = json->get_data();
	const String where = " (" + p_path + ")";

	if (!root.has("world") || !root.has("sampling") || !root.has("species")) {
		return fail("Sections world, sampling et species obligatoires" + where);
	}
	const Dictionary world = root["world"];
	const Dictionary sampling = root["sampling"];
	const Array species_list = root["species"];

	double origin_x = 0.0;
	double origin_z = 0.0;
	double cell_size = 0.0;
	double cells = 0.0;
	if (!read_number(world, "origin_x", origin_x) || !read_number(world, "origin_z", origin_z) ||
			!read_number(world, "cell_size", cell_size) || !read_number(world, "cells_per_side", cells)) {
		return fail("world : origin_x, origin_z, cell_size et cells_per_side obligatoires" + where);
	}
	if (cell_size < 1.0 || cell_size > 10000.0 || cells < 1.0 || cells > 4096.0) {
		return fail("world : cell_size ou cells_per_side hors limites" + where);
	}
	double step = 0.0;
	double attempt_factor = 0.0;
	double max_attempts = 0.0;
	if (!read_number(sampling, "height_grid_step", step) || !read_number(sampling, "attempt_factor", attempt_factor) ||
			!read_number(sampling, "max_attempts_per_species", max_attempts)) {
		return fail("sampling : height_grid_step, attempt_factor et max_attempts_per_species obligatoires" + where);
	}
	if (step <= 0.0 || step > cell_size || attempt_factor < 1.0 || max_attempts < 1.0 || max_attempts > 1.0e7) {
		return fail("sampling : valeurs hors limites" + where);
	}
	const double segments = std::max(1.0, std::round(cell_size / step));
	if (segments > static_cast<double>(kMaxHeightSegments)) {
		return fail("sampling : grille de hauteurs trop fine" + where);
	}
	if (species_list.is_empty() || species_list.size() > 16) {
		return fail("species : entre 1 et 16 espèces attendues" + where);
	}

	std::vector<Species> parsed;
	parsed.reserve(static_cast<size_t>(species_list.size()));
	int64_t total_instances = 0;
	bool all_surfaces = true;
	for (int64_t i = 0; i < species_list.size(); i++) {
		const Variant entry = species_list[i];
		if (entry.get_type() != Variant::DICTIONARY) {
			return fail("species : entrée non valide" + where);
		}
		const Dictionary d = entry;
		Species s;
		if (!d.has("id") || d["id"].get_type() != Variant::STRING) {
			return fail("species : id obligatoire" + where);
		}
		s.id = StringName(String(d["id"]));
		const String ctx = " espèce " + String(s.id) + where;
		double radius = 0.0;
		double density = 0.0;
		double max_inst = 0.0;
		double slope = 0.0;
		double alt_min = 0.0;
		double alt_max = 0.0;
		double water_min = 0.0;
		double water_max = 0.0;
		double scale_min = 0.0;
		double scale_max = 0.0;
		double hvar = 0.0;
		double align = 0.0;
		double offset = 0.0;
		double vis_end = 0.0;
		double vis_fade = 0.0;
		if (!read_number(d, "radius", radius) || !read_number(d, "density_per_hectare", density) ||
				!read_number(d, "max_instances", max_inst) || !read_number(d, "max_slope_deg", slope) ||
				!read_number(d, "altitude_min", alt_min) || !read_number(d, "altitude_max", alt_max) ||
				!read_number(d, "water_distance_min", water_min) || !read_number(d, "water_distance_max", water_max) ||
				!read_number(d, "scale_min", scale_min) || !read_number(d, "scale_max", scale_max) ||
				!read_number(d, "height_scale_variation", hvar) || !read_number(d, "align_to_normal", align) ||
				!read_number(d, "ground_offset", offset) || !read_number(d, "visibility_range_end", vis_end) ||
				!read_number(d, "visibility_fade_margin", vis_fade)) {
			return fail("Champ numérique manquant ou invalide," + ctx);
		}
		if (radius < 0.05 || radius > 50.0 || density <= 0.0 || max_inst < 1.0 || static_cast<int64_t>(max_inst) > kMaxInstancesLimit ||
				slope <= 0.0 || slope > 90.0 || alt_min > alt_max || water_min > water_max || scale_min <= 0.0 ||
				scale_max < scale_min || hvar < 0.0 || hvar >= 1.0 || align < 0.0 || align > 1.0 || vis_end <= 0.0 || vis_fade < 0.0 ||
				vis_fade >= vis_end) {
			return fail("Valeur hors limites," + ctx);
		}
		if (!d.has("cast_shadows") || d["cast_shadows"].get_type() != Variant::BOOL) {
			return fail("cast_shadows obligatoire," + ctx);
		}
		s.cast_shadows = static_cast<bool>(d["cast_shadows"]);
		if (!d.has("surfaces") || d["surfaces"].get_type() != Variant::ARRAY || Array(d["surfaces"]).is_empty()) {
			return fail("surfaces obligatoire," + ctx);
		}
		const Array surfaces = d["surfaces"];
		for (int64_t k = 0; k < surfaces.size(); k++) {
			const String name = String(surfaces[k]);
			if (name == "sable") {
				s.surface_mask |= kSurfaceSand;
			} else if (name == "pierre") {
				s.surface_mask |= kSurfaceStone;
			} else if (name == "terre") {
				s.surface_mask |= kSurfaceEarth;
			} else {
				return fail("Surface inconnue « " + name + " »," + ctx);
			}
		}
		String curve_error;
		if (!d.has("water_density_curve") || !parse_curve(d["water_density_curve"], s.curve, s.water_max_multiplier, curve_error)) {
			return fail("water_density_curve : " + curve_error + "," + ctx);
		}
		if (d.has("wadi_density_curve")) {
			if (!parse_curve(d["wadi_density_curve"], s.wadi_curve, s.wadi_max_multiplier, curve_error)) {
				return fail("wadi_density_curve : " + curve_error + "," + ctx);
			}
			wadi_range_max_ = std::max(wadi_range_max_, s.wadi_curve.back().distance);
		}
		s.max_multiplier = s.water_max_multiplier * s.wadi_max_multiplier;
		s.radius = static_cast<float>(radius);
		s.density_per_hectare = static_cast<float>(density);
		s.max_instances = static_cast<int32_t>(max_inst);
		s.min_normal_y = static_cast<float>(std::cos(slope * static_cast<double>(kPi) / 180.0));
		s.altitude_min = static_cast<float>(alt_min);
		s.altitude_max = static_cast<float>(alt_max);
		s.water_min = static_cast<float>(water_min);
		s.water_max = static_cast<float>(water_max);
		s.scale_min = static_cast<float>(scale_min);
		s.scale_max = static_cast<float>(scale_max);
		s.height_scale_variation = static_cast<float>(hvar);
		s.align_to_normal = static_cast<float>(align);
		s.ground_offset = static_cast<float>(offset);
		s.visibility_range_end = static_cast<float>(vis_end);
		s.visibility_fade_margin = static_cast<float>(vis_fade);
		// Une case de côté rayon * racine(2) contient au plus un point (écart minimal de 2 * rayon).
		s.grid_cell = s.radius * 1.41421356f;
		const double dim = std::ceil(cell_size / static_cast<double>(s.grid_cell)) + 1.0;
		if (dim * dim > static_cast<double>(kMaxGridCells)) {
			return fail("Grille d'occupation trop grande (rayon trop petit)," + ctx);
		}
		s.grid_dim = static_cast<int32_t>(dim);
		all_surfaces = all_surfaces && (s.surface_mask == kSurfaceAll);
		total_instances += s.max_instances;
		for (const Species &other : parsed) {
			if (other.id == s.id) {
				return fail("Identifiant en double," + ctx);
			}
		}
		parsed.push_back(std::move(s));
	}

	world_origin_x_ = static_cast<float>(origin_x);
	world_origin_z_ = static_cast<float>(origin_z);
	cell_size_ = static_cast<float>(cell_size);
	cells_per_side_ = static_cast<int32_t>(cells);
	height_segments_ = static_cast<int32_t>(segments);
	height_step_ = cell_size_ / static_cast<float>(height_segments_);
	attempt_factor_ = static_cast<float>(attempt_factor);
	max_attempts_ = static_cast<int32_t>(max_attempts);
	need_surface_ = !all_surfaces;
	species_ = std::move(parsed);

	// Réservation unique de toute la mémoire de travail.
	const size_t nodes = static_cast<size_t>(height_segments_ + 1) * static_cast<size_t>(height_segments_ + 1);
	heights_.assign(nodes, 0.0f);
	surfaces_.assign(nodes, 0);
	points_.clear();
	points_.reserve(static_cast<size_t>(total_instances));
	outputs_.assign(species_.size(), std::vector<float>());
	for (size_t i = 0; i < species_.size(); i++) {
		species_[i].grid.assign(static_cast<size_t>(species_[i].grid_dim) * static_cast<size_t>(species_[i].grid_dim), -1);
		outputs_[i].reserve(static_cast<size_t>(species_[i].max_instances) * 12U);
	}
	rules_loaded_ = true;
	last_error_ = String();
	return true;
}

bool VegetationScatter::parse_curve(const Variant &p_value, std::vector<CurvePoint> &r_curve, float &r_max, String &r_error) {
	r_curve.clear();
	r_max = 0.0f;
	if (p_value.get_type() != Variant::ARRAY) {
		r_error = "tableau de points attendu";
		return false;
	}
	const Array curve = p_value;
	if (curve.is_empty() || curve.size() > 32) {
		r_error = "entre 1 et 32 points";
		return false;
	}
	for (int64_t k = 0; k < curve.size(); k++) {
		const Variant pv = curve[k];
		if (pv.get_type() != Variant::ARRAY || Array(pv).size() != 2) {
			r_error = "points [distance, multiplicateur]";
			return false;
		}
		const Array pa = pv;
		CurvePoint cp;
		cp.distance = static_cast<float>(static_cast<double>(pa[0]));
		cp.multiplier = static_cast<float>(static_cast<double>(pa[1]));
		if (!std::isfinite(cp.distance) || !std::isfinite(cp.multiplier) || cp.multiplier < 0.0f ||
				(!r_curve.empty() && cp.distance <= r_curve.back().distance)) {
			r_error = "distances croissantes, multiplicateurs positifs";
			return false;
		}
		r_max = std::max(r_max, cp.multiplier);
		r_curve.push_back(cp);
	}
	if (r_max <= 0.0f) {
		r_error = "au moins un multiplicateur non nul";
		return false;
	}
	return true;
}

bool VegetationScatter::set_features(const Array &p_water_bodies, const Array &p_wadis) {
	if (p_water_bodies.size() > 32 || p_wadis.size() > 16) {
		return fail("Trop d'éléments de paysage : 32 plans d'eau et 16 oueds au plus");
	}
	std::vector<WaterBody> bodies;
	std::vector<Segment> segments;
	bodies.reserve(32);
	segments.reserve(16 * 63);
	for (int64_t i = 0; i < p_water_bodies.size(); i++) {
		if (p_water_bodies[i].get_type() != Variant::DICTIONARY) {
			return fail("Plan d'eau : objet attendu");
		}
		const Dictionary body = p_water_bodies[i];
		double radius = 0.0;
		if (!body.has("center") || body["center"].get_type() != Variant::ARRAY || Array(body["center"]).size() != 2 ||
				!read_number(body, "radius_m", radius)) {
			return fail("Plan d'eau : center [x, z] et radius_m obligatoires");
		}
		const Array center = body["center"];
		WaterBody w;
		w.x = static_cast<float>(static_cast<double>(center[0]));
		w.z = static_cast<float>(static_cast<double>(center[1]));
		w.radius = static_cast<float>(radius);
		if (!std::isfinite(w.x) || !std::isfinite(w.z) || !std::isfinite(radius) || radius <= 0.0) {
			return fail("Plan d'eau invalide : rayon positif et centre fini attendus");
		}
		bodies.push_back(w);
	}
	for (int64_t i = 0; i < p_wadis.size(); i++) {
		if (p_wadis[i].get_type() != Variant::DICTIONARY) {
			return fail("Oued : objet attendu");
		}
		const Dictionary wadi = p_wadis[i];
		if (!wadi.has("points") || wadi["points"].get_type() != Variant::ARRAY) {
			return fail("Oued : points obligatoires");
		}
		const Array points = wadi["points"];
		if (points.size() < 2 || points.size() > 64) {
			return fail("Oued : de 2 à 64 points");
		}
		float px = 0.0f;
		float pz = 0.0f;
		for (int64_t k = 0; k < points.size(); k++) {
			if (points[k].get_type() != Variant::ARRAY || Array(points[k]).size() != 2) {
				return fail("Oued : un point est [x, z]");
			}
			const Array pair = points[k];
			const float x = static_cast<float>(static_cast<double>(pair[0]));
			const float z = static_cast<float>(static_cast<double>(pair[1]));
			if (!std::isfinite(x) || !std::isfinite(z)) {
				return fail("Oued : point non fini");
			}
			if (k > 0) {
				Segment seg;
				seg.ax = px;
				seg.az = pz;
				seg.bx = x;
				seg.bz = z;
				segments.push_back(seg);
			}
			px = x;
			pz = z;
		}
	}
	water_bodies_ = std::move(bodies);
	segments_ = std::move(segments);
	cell_segments_.clear();
	cell_segments_.reserve(segments_.size());
	features_set_ = true;
	last_error_ = String();
	return true;
}

bool VegetationScatter::load_features(const String &p_path) {
	if (!godot::FileAccess::file_exists(p_path)) {
		return fail("Fichier des éléments de paysage introuvable : " + p_path);
	}
	godot::Ref<godot::JSON> json;
	json.instantiate();
	if (json->parse(godot::FileAccess::get_file_as_string(p_path)) != godot::OK || json->get_data().get_type() != Variant::DICTIONARY) {
		return fail("JSON invalide : " + p_path);
	}
	const Dictionary root = json->get_data();
	if (!root.has("water_bodies") || root["water_bodies"].get_type() != Variant::ARRAY || !root.has("wadis") ||
			root["wadis"].get_type() != Variant::ARRAY) {
		return fail("water_bodies et wadis obligatoires : " + p_path);
	}
	return set_features(root["water_bodies"], root["wadis"]);
}

float VegetationScatter::curve_multiplier(const std::vector<CurvePoint> &p_curve, float p_distance) {
	const std::vector<CurvePoint> &c = p_curve;
	if (p_distance <= c.front().distance) {
		return c.front().multiplier;
	}
	if (p_distance >= c.back().distance) {
		return c.back().multiplier;
	}
	size_t hi = 1;
	while (c[hi].distance < p_distance) {
		hi++;
	}
	const CurvePoint &a = c[hi - 1];
	const CurvePoint &b = c[hi];
	const float t = (p_distance - a.distance) / (b.distance - a.distance);
	return a.multiplier + (b.multiplier - a.multiplier) * t;
}

bool VegetationScatter::conflicts(float p_x, float p_z, float p_radius, float p_cell_x0, float p_cell_z0) const {
	const float lx = p_x - p_cell_x0;
	const float lz = p_z - p_cell_z0;
	for (const Species &s : species_) {
		const int32_t cx = static_cast<int32_t>(lx / s.grid_cell);
		const int32_t cz = static_cast<int32_t>(lz / s.grid_cell);
		const int32_t reach = static_cast<int32_t>(std::ceil((p_radius + s.radius) / s.grid_cell));
		const int32_t x_from = std::max(cx - reach, 0);
		const int32_t x_to = std::min(cx + reach, s.grid_dim - 1);
		const int32_t z_from = std::max(cz - reach, 0);
		const int32_t z_to = std::min(cz + reach, s.grid_dim - 1);
		for (int32_t gz = z_from; gz <= z_to; gz++) {
			const size_t row = static_cast<size_t>(gz) * static_cast<size_t>(s.grid_dim);
			for (int32_t gx = x_from; gx <= x_to; gx++) {
				const int32_t index = s.grid[row + static_cast<size_t>(gx)];
				if (index < 0) {
					continue;
				}
				const Point &p = points_[static_cast<size_t>(index)];
				const float dx = p.x - p_x;
				const float dz = p.z - p_z;
				const float limit = p.radius + p_radius;
				if (dx * dx + dz * dz < limit * limit) {
					return true;
				}
			}
		}
	}
	return false;
}

void VegetationScatter::scatter_species(size_t p_index, float p_x0, float p_z0, uint64_t p_hash) {
	Species &s = species_[p_index];
	std::vector<float> &out = outputs_[p_index];
	Rng rng;
	rng.state = Rng::mix(p_hash + static_cast<uint64_t>(p_index) * 0x632BE59BD9B4E019ULL);

	// Zone utile de la cellule : écart de « rayon » aux bords (aucun contact possible entre cellules voisines).
	const float inset = s.radius;
	const float span = cell_size_ - 2.0f * inset;
	if (span <= 0.0f) {
		return;
	}
	const float x_min = p_x0 + inset;
	const float z_min = p_z0 + inset;

	// Distance normalisée au plan d'eau le plus proche : bornes sur toute la cellule pour écarter les espèces hors zone.
	// Un point est à la distance min des plans d'eau : elle est donc au moins la plus petite distance minimale
	// et au plus la plus petite distance maximale.
	const float cell_cx = p_x0 + cell_size_ * 0.5f;
	const float cell_cz = p_z0 + cell_size_ * 0.5f;
	const float half = cell_size_ * 0.5f;
	float nearest = std::numeric_limits<float>::infinity();
	float farthest = std::numeric_limits<float>::infinity();
	for (const WaterBody &w : water_bodies_) {
		const float near_dx = std::max(std::fabs(w.x - cell_cx) - half, 0.0f);
		const float near_dz = std::max(std::fabs(w.z - cell_cz) - half, 0.0f);
		const float far_dx = std::fabs(w.x - cell_cx) + half;
		const float far_dz = std::fabs(w.z - cell_cz) + half;
		nearest = std::min(nearest, std::sqrt(near_dx * near_dx + near_dz * near_dz) / w.radius);
		farthest = std::min(farthest, std::sqrt(far_dx * far_dx + far_dz * far_dz) / w.radius);
	}
	if (nearest > s.water_max || farthest < s.water_min) {
		return;
	}

	const double area_ha = static_cast<double>(span) * static_cast<double>(span) / 10000.0;
	const double wanted = area_ha * static_cast<double>(s.density_per_hectare) * static_cast<double>(s.max_multiplier) *
			static_cast<double>(attempt_factor_);
	const int32_t attempts = static_cast<int32_t>(std::min(wanted, static_cast<double>(max_attempts_)));
	const float inv_step = 1.0f / height_step_;
	const size_t stride = static_cast<size_t>(height_segments_ + 1);

	int32_t placed = 0;
	for (int32_t attempt = 0; attempt < attempts && placed < s.max_instances; attempt++) {
		stat_attempts_++;
		const float x = x_min + rng.unit() * span;
		const float z = z_min + rng.unit() * span;
		const float accept_roll = rng.unit();

		float normalized = std::numeric_limits<float>::infinity();
		for (const WaterBody &w : water_bodies_) {
			const float odx = x - w.x;
			const float odz = z - w.z;
			normalized = std::min(normalized, std::sqrt(odx * odx + odz * odz) / w.radius);
		}
		if (normalized < s.water_min || normalized > s.water_max) {
			continue;
		}
		float multiplier = curve_multiplier(s.curve, normalized);
		if (!s.wadi_curve.empty()) {
			float wadi_distance = std::numeric_limits<float>::infinity();
			for (const Segment &seg : cell_segments_) {
				const float sx = seg.bx - seg.ax;
				const float sz = seg.bz - seg.az;
				const float length_squared = sx * sx + sz * sz;
				float t = 0.0f;
				if (length_squared > 0.0f) {
					t = std::min(std::max(((x - seg.ax) * sx + (z - seg.az) * sz) / length_squared, 0.0f), 1.0f);
				}
				const float qx = x - (seg.ax + sx * t);
				const float qz = z - (seg.az + sz * t);
				wadi_distance = std::min(wadi_distance, std::sqrt(qx * qx + qz * qz));
			}
			multiplier *= curve_multiplier(s.wadi_curve, wadi_distance);
		}
		if (accept_roll * s.max_multiplier >= multiplier) {
			continue;
		}
		if (conflicts(x, z, s.radius, p_x0, p_z0)) {
			continue;
		}

		// Hauteur et pente : interpolation bilinéaire de la grille de hauteurs de la cellule.
		const float fx = (x - p_x0) * inv_step;
		const float fz = (z - p_z0) * inv_step;
		const int32_t ix = std::min(static_cast<int32_t>(fx), height_segments_ - 1);
		const int32_t iz = std::min(static_cast<int32_t>(fz), height_segments_ - 1);
		const float tx = fx - static_cast<float>(ix);
		const float tz = fz - static_cast<float>(iz);
		const size_t base = static_cast<size_t>(iz) * stride + static_cast<size_t>(ix);
		const float h00 = heights_[base];
		const float h10 = heights_[base + 1];
		const float h01 = heights_[base + stride];
		const float h11 = heights_[base + stride + 1];
		const float height = (h00 * (1.0f - tx) + h10 * tx) * (1.0f - tz) + (h01 * (1.0f - tx) + h11 * tx) * tz;
		if (height < s.altitude_min || height > s.altitude_max) {
			continue;
		}
		const float grad_x = ((h10 - h00) * (1.0f - tz) + (h11 - h01) * tz) * inv_step;
		const float grad_z = ((h01 - h00) * (1.0f - tx) + (h11 - h10) * tx) * inv_step;
		const float inv_len = 1.0f / std::sqrt(grad_x * grad_x + grad_z * grad_z + 1.0f);
		const float ny = inv_len;
		if (ny < s.min_normal_y) {
			continue;
		}
		if (need_surface_) {
			// Surface du nœud le plus proche.
			const size_t node = static_cast<size_t>(iz + (tz >= 0.5f ? 1 : 0)) * stride + static_cast<size_t>(ix + (tx >= 0.5f ? 1 : 0));
			if ((surfaces_[node] & s.surface_mask) == 0) {
				continue;
			}
		}

		// Placement accepté : occupation, puis transformée.
		const int32_t gx = static_cast<int32_t>((x - p_x0) / s.grid_cell);
		const int32_t gz = static_cast<int32_t>((z - p_z0) / s.grid_cell);
		s.grid[static_cast<size_t>(gz) * static_cast<size_t>(s.grid_dim) + static_cast<size_t>(gx)] = static_cast<int32_t>(points_.size());
		points_.push_back(Point{ x, z, s.radius });

		const float yaw = rng.unit() * 2.0f * kPi;
		const float scale = s.scale_min + rng.unit() * (s.scale_max - s.scale_min);
		const float scale_y = scale * (1.0f + (rng.unit() * 2.0f - 1.0f) * s.height_scale_variation);

		// Axe « haut » : de la verticale vers la normale du terrain selon align_to_normal.
		float ux = -grad_x * inv_len * s.align_to_normal;
		float uy = 1.0f + (ny - 1.0f) * s.align_to_normal;
		float uz = -grad_z * inv_len * s.align_to_normal;
		const float ulen = 1.0f / std::sqrt(ux * ux + uy * uy + uz * uz);
		ux *= ulen;
		uy *= ulen;
		uz *= ulen;
		// Axe avant : cap aléatoire ramené dans le plan perpendiculaire au « haut ».
		float tfx = std::cos(yaw);
		float tfz = std::sin(yaw);
		float tfy = 0.0f;
		const float dot = tfx * ux + tfz * uz;
		tfx -= ux * dot;
		tfy -= uy * dot;
		tfz -= uz * dot;
		const float tlen = 1.0f / std::sqrt(tfx * tfx + tfy * tfy + tfz * tfz);
		tfx *= tlen;
		tfy *= tlen;
		tfz *= tlen;
		// Axe droit = haut x avant.
		const float rx = uy * tfz - uz * tfy;
		const float ry = uz * tfx - ux * tfz;
		const float rz = ux * tfy - uy * tfx;

		// Format MultiMesh (TRANSFORM_3D) : une ligne de la base puis l'origine, trois fois.
		const float oy = height + s.ground_offset;
		out.push_back(rx * scale);
		out.push_back(ux * scale_y);
		out.push_back(tfx * scale);
		out.push_back(x);
		out.push_back(ry * scale);
		out.push_back(uy * scale_y);
		out.push_back(tfy * scale);
		out.push_back(oy);
		out.push_back(rz * scale);
		out.push_back(uz * scale_y);
		out.push_back(tfz * scale);
		out.push_back(z);
		placed++;
	}
	stat_instances_ += placed;
}

Dictionary VegetationScatter::scatter(const godot::Vector2i &p_cell, godot::Object *p_heightfield, int64_t p_seed) {
	const auto started = std::chrono::steady_clock::now();
	stat_instances_ = 0;
	stat_attempts_ = 0;
	stat_heightfield_calls_ = 0;
	stat_duration_ms_ = 0.0;
	if (!rules_loaded_) {
		fail("Règles non chargées : appeler load_rules() d'abord");
		return Dictionary();
	}
	if (!features_set_) {
		fail("Éléments de paysage non définis : appeler set_features() ou load_features() d'abord");
		return Dictionary();
	}
	if (p_heightfield == nullptr || !p_heightfield->has_method("height_at") || (need_surface_ && !p_heightfield->has_method("surface_at"))) {
		fail("Champ de hauteurs absent ou sans height_at()/surface_at()");
		return Dictionary();
	}
	if (p_cell.x < 0 || p_cell.y < 0 || p_cell.x >= cells_per_side_ || p_cell.y >= cells_per_side_) {
		fail("Cellule hors du monde");
		return Dictionary();
	}
	last_error_ = String();

	const float x0 = world_origin_x_ + static_cast<float>(p_cell.x) * cell_size_;
	const float z0 = world_origin_z_ + static_cast<float>(p_cell.y) * cell_size_;

	// Oueds utiles à cette cellule : ceux dont la boîte, élargie de la portée des courbes, touche la cellule
	// (la capacité est réservée dans set_features : aucune allocation ici).
	cell_segments_.clear();
	if (wadi_range_max_ > 0.0f) {
		for (const Segment &seg : segments_) {
			if (std::max(seg.ax, seg.bx) + wadi_range_max_ >= x0 && std::min(seg.ax, seg.bx) - wadi_range_max_ <= x0 + cell_size_ &&
					std::max(seg.az, seg.bz) + wadi_range_max_ >= z0 && std::min(seg.az, seg.bz) - wadi_range_max_ <= z0 + cell_size_) {
				cell_segments_.push_back(seg);
			}
		}
	}

	// Échantillonnage du champ de hauteurs : nombre fixe d'appels par cellule, quelle que soit la densité.
	static const StringName height_method("height_at");
	static const StringName surface_method("surface_at");
	static const StringName sand("sable");
	static const StringName stone("pierre");
	static const StringName earth("terre");
	const size_t stride = static_cast<size_t>(height_segments_ + 1);
	for (size_t iz = 0; iz < stride; iz++) {
		for (size_t ix = 0; ix < stride; ix++) {
			const float x = x0 + static_cast<float>(ix) * height_step_;
			const float z = z0 + static_cast<float>(iz) * height_step_;
			const Variant h = p_heightfield->call(height_method, static_cast<double>(x), static_cast<double>(z));
			stat_heightfield_calls_++;
			const double hv = static_cast<double>(h);
			if (!std::isfinite(hv)) {
				fail("height_at() a renvoyé une valeur non finie");
				return Dictionary();
			}
			heights_[iz * stride + ix] = static_cast<float>(hv);
			if (need_surface_) {
				const Variant sv = p_heightfield->call(surface_method, godot::Vector3(x, static_cast<float>(hv), z));
				stat_heightfield_calls_++;
				const StringName name = sv;
				uint8_t mask = 0;
				if (name == sand) {
					mask = kSurfaceSand;
				} else if (name == stone) {
					mask = kSurfaceStone;
				} else if (name == earth) {
					mask = kSurfaceEarth;
				}
				surfaces_[iz * stride + ix] = mask;
			}
		}
	}

	points_.clear();
	for (Species &s : species_) {
		std::fill(s.grid.begin(), s.grid.end(), -1);
	}
	for (std::vector<float> &out : outputs_) {
		out.clear();
	}

	// Graine propre à (graine, cellule) ; chaque espèce y ajoute son rang.
	uint64_t hash = Rng::mix(static_cast<uint64_t>(p_seed));
	hash = Rng::mix(hash ^ static_cast<uint64_t>(static_cast<int64_t>(p_cell.x) + 0x10000));
	hash = Rng::mix(hash ^ (static_cast<uint64_t>(static_cast<int64_t>(p_cell.y) + 0x10000) << 20));
	for (size_t i = 0; i < species_.size(); i++) {
		scatter_species(i, x0, z0, hash);
	}

	Dictionary result;
	for (size_t i = 0; i < species_.size(); i++) {
		godot::PackedFloat32Array packed;
		packed.resize(static_cast<int64_t>(outputs_[i].size()));
		if (!outputs_[i].empty()) {
			std::memcpy(packed.ptrw(), outputs_[i].data(), outputs_[i].size() * sizeof(float));
		}
		result[species_[i].id] = packed;
	}
	stat_duration_ms_ = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - started).count();
	return result;
}

Dictionary VegetationScatter::get_species_settings() const {
	Dictionary all;
	for (const Species &s : species_) {
		Dictionary d;
		d["radius"] = static_cast<double>(s.radius);
		d["max_instances"] = static_cast<int64_t>(s.max_instances);
		d["visibility_range_end"] = static_cast<double>(s.visibility_range_end);
		d["visibility_fade_margin"] = static_cast<double>(s.visibility_fade_margin);
		d["cast_shadows"] = s.cast_shadows;
		all[s.id] = d;
	}
	return all;
}

godot::PackedStringArray VegetationScatter::get_species_ids() const {
	godot::PackedStringArray ids;
	for (const Species &s : species_) {
		ids.push_back(String(s.id));
	}
	return ids;
}

String VegetationScatter::get_last_error() const {
	return last_error_;
}

Dictionary VegetationScatter::get_last_stats() const {
	Dictionary d;
	d["instances"] = stat_instances_;
	d["attempts"] = stat_attempts_;
	d["heightfield_calls"] = stat_heightfield_calls_;
	d["duration_ms"] = stat_duration_ms_;
	return d;
}

void VegetationScatter::_bind_methods() {
	godot::ClassDB::bind_method(godot::D_METHOD("load_rules", "path"), &VegetationScatter::load_rules);
	godot::ClassDB::bind_method(godot::D_METHOD("set_features", "water_bodies", "wadis"), &VegetationScatter::set_features);
	godot::ClassDB::bind_method(godot::D_METHOD("load_features", "path"), &VegetationScatter::load_features);
	godot::ClassDB::bind_method(godot::D_METHOD("scatter", "cell", "heightfield", "seed"), &VegetationScatter::scatter);
	godot::ClassDB::bind_method(godot::D_METHOD("get_species_settings"), &VegetationScatter::get_species_settings);
	godot::ClassDB::bind_method(godot::D_METHOD("get_species_ids"), &VegetationScatter::get_species_ids);
	godot::ClassDB::bind_method(godot::D_METHOD("get_last_error"), &VegetationScatter::get_last_error);
	godot::ClassDB::bind_method(godot::D_METHOD("get_last_stats"), &VegetationScatter::get_last_stats);
}
