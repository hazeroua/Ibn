#include "fauna_herds.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include <algorithm>
#include <cmath>
#include <utility>

using godot::Array;
using godot::Dictionary;
using godot::String;
using godot::StringName;
using godot::Variant;
using godot::Vector2;
using godot::Vector3;

namespace {

constexpr float kPi = 3.14159265358979323846f;
constexpr float kTwoPi = 2.0f * kPi;
constexpr int32_t kFloatsPerInstance = 16;
constexpr int32_t kMaxAnimalsLimit = 512;
constexpr int32_t kMaxGridSide = 1024;
constexpr int32_t kMaxGridCells = 1000000;
constexpr int32_t kMaxSubsteps = 64;
constexpr int32_t kPointAttempts = 32;
constexpr float kMaxStepSeconds = 4.0f;
constexpr float kEpsilon = 1.0e-5f;

float clamp_unit(float p_value) {
	return std::min(1.0f, std::max(0.0f, p_value));
}

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

bool FaunaHerds::fail(const String &p_message) {
	last_error_ = p_message;
	ready_ = false;
	return false;
}

String FaunaHerds::get_last_error() const {
	return last_error_;
}

uint64_t FaunaHerds::random_next() {
	rng_state_ += 0x9E3779B97F4A7C15ULL;
	uint64_t z = rng_state_;
	z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
	z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
	return z ^ (z >> 31);
}

float FaunaHerds::random_unit() {
	return static_cast<float>(random_next() >> 40) * (1.0f / 16777216.0f);
}

bool FaunaHerds::read_float(const Dictionary &p_data, const char *p_key, float &r_value, float p_min, float p_max) {
	double value = 0.0;
	if (!read_number(p_data, p_key, value)) {
		return fail(String("Réglage numérique manquant ou invalide : ") + p_key);
	}
	if (value < static_cast<double>(p_min) || value > static_cast<double>(p_max)) {
		return fail(String("Réglage hors limites : ") + p_key);
	}
	r_value = static_cast<float>(value);
	return true;
}

bool FaunaHerds::read_int(const Dictionary &p_data, const char *p_key, int32_t &r_value, int32_t p_min, int32_t p_max) {
	double value = 0.0;
	if (!read_number(p_data, p_key, value)) {
		return fail(String("Réglage entier manquant ou invalide : ") + p_key);
	}
	if (value < static_cast<double>(p_min) || value > static_cast<double>(p_max)) {
		return fail(String("Réglage hors limites : ") + p_key);
	}
	r_value = static_cast<int32_t>(value);
	return true;
}

bool FaunaHerds::read_params(const Dictionary &p_settings) {
	Params &p = params_;
	const float big = 100000.0f;
	float slope_limit_deg = 0.0f;
	float slope_soft_deg = 0.0f;
	if (!read_float(p_settings, "view_distance_m", p.view_distance, 1.0f, big) ||
			!read_float(p_settings, "flee_distance_m", p.flee_distance, 1.0f, big) ||
			!read_float(p_settings, "calm_distance_m", p.calm_distance, 1.0f, big) ||
			!read_float(p_settings, "calm_delay_s", p.calm_delay, 0.0f, 3600.0f) ||
			!read_float(p_settings, "walk_speed_mps", p.walk_speed, 0.1f, 20.0f) ||
			!read_float(p_settings, "run_speed_mps", p.run_speed, 1.0f, 40.0f) ||
			!read_float(p_settings, "run_speed_variation", p.run_variation, 0.0f, 0.9f) ||
			!read_float(p_settings, "acceleration_mps2", p.acceleration, 0.1f, 100.0f) ||
			!read_float(p_settings, "turn_response_per_s", p.turn_response, 0.1f, 100.0f) ||
			!read_float(p_settings, "herd_radius_m", p.herd_radius, 0.5f, 100.0f) ||
			!read_float(p_settings, "separation_m", p.separation, 0.1f, 50.0f) ||
			!read_float(p_settings, "separation_strength", p.separation_strength, 0.0f, 20.0f) ||
			!read_float(p_settings, "graze_min_s", p.graze_min, 0.1f, 36000.0f) ||
			!read_float(p_settings, "graze_max_s", p.graze_max, 0.1f, 36000.0f) ||
			!read_float(p_settings, "relocate_max_m", p.relocate_max, 1.0f, 5000.0f) ||
			!read_float(p_settings, "flee_repick_s", p.flee_repick, 0.1f, 60.0f) ||
			!read_float(p_settings, "max_slope_deg", slope_limit_deg, 1.0f, 80.0f) ||
			!read_float(p_settings, "soft_slope_deg", slope_soft_deg, 0.5f, 80.0f) ||
			!read_float(p_settings, "scale_min", p.scale_min, 0.1f, 10.0f) ||
			!read_float(p_settings, "scale_max", p.scale_max, 0.1f, 10.0f) ||
			!read_float(p_settings, "height_grid_m", p.height_grid, 0.5f, 50.0f) ||
			!read_float(p_settings, "max_substep_s", p.max_substep, 0.005f, 1.0f) ||
			!read_float(p_settings, "walk_stride_hz", p.walk_stride_hz, 0.1f, 10.0f) ||
			!read_float(p_settings, "run_stride_hz", p.run_stride_hz, 0.1f, 20.0f) ||
			!read_int(p_settings, "min_herd_size", p.min_herd, 1, 8) ||
			!read_int(p_settings, "max_herd_size", p.max_herd, 1, 8) ||
			!read_int(p_settings, "max_animals", p.max_animals, 1, kMaxAnimalsLimit) ||
			!read_int(p_settings, "flee_candidates", p.flee_candidates, 1, 64)) {
		return false;
	}
	if (p.calm_distance <= p.flee_distance || p.graze_max < p.graze_min || p.scale_max < p.scale_min ||
			p.max_herd < p.min_herd || slope_soft_deg >= slope_limit_deg || p.run_speed <= p.walk_speed) {
		return fail("Réglages des gazelles incohérents (distances, durées, échelles, pentes ou vitesses).");
	}
	p.slope_limit = std::tan(slope_limit_deg * kPi / 180.0f);
	p.slope_soft = std::tan(slope_soft_deg * kPi / 180.0f);
	return true;
}

bool FaunaHerds::zone_has(const Zone &p_zone, float p_x, float p_z) const {
	if (p_zone.circle) {
		const float dx = p_x - p_zone.cx;
		const float dz = p_z - p_zone.cz;
		return dx * dx + dz * dz <= p_zone.radius * p_zone.radius;
	}
	if (p_x < p_zone.min_x || p_x > p_zone.max_x || p_z < p_zone.min_z || p_z > p_zone.max_z) {
		return false;
	}
	bool inside = false;
	const size_t count = p_zone.px.size();
	size_t previous = count - 1;
	for (size_t i = 0; i < count; i++) {
		const float xi = p_zone.px[i];
		const float zi = p_zone.pz[i];
		const float xj = p_zone.px[previous];
		const float zj = p_zone.pz[previous];
		if (((zi > p_z) != (zj > p_z)) && (p_x < (xj - xi) * (p_z - zi) / (zj - zi) + xi)) {
			inside = !inside;
		}
		previous = i;
	}
	return inside;
}

// Point au hasard à l'intérieur de la zone, à l'écart du bord pour un cercle. Nombre d'essais borné ; repli sur le
// point intérieur sûr de la zone.
bool FaunaHerds::pick_point(const Zone &p_zone, float &r_x, float &r_z) {
	for (int32_t attempt = 0; attempt < kPointAttempts; attempt++) {
		if (p_zone.circle) {
			const float radius = p_zone.radius * 0.9f * std::sqrt(random_unit());
			const float angle = random_unit() * kTwoPi;
			r_x = p_zone.cx + std::cos(angle) * radius;
			r_z = p_zone.cz + std::sin(angle) * radius;
			return true;
		}
		const float x = p_zone.min_x + random_unit() * (p_zone.max_x - p_zone.min_x);
		const float z = p_zone.min_z + random_unit() * (p_zone.max_z - p_zone.min_z);
		if (zone_has(p_zone, x, z)) {
			r_x = x;
			r_z = z;
			return true;
		}
	}
	r_x = p_zone.safe_x;
	r_z = p_zone.safe_z;
	return false;
}

bool FaunaHerds::build_zone(const Dictionary &p_data, godot::Object *p_heightfield, Zone &r_zone) {
	const Variant kind = p_data.get("kind", Variant());
	if (kind.get_type() != Variant::STRING) {
		return fail("Zone sans « kind ».");
	}
	const String kind_text = kind;
	int32_t herds = 0;
	int32_t size_min = 0;
	int32_t size_max = 0;
	if (!read_int(p_data, "herds", herds, 1, 64) || !read_int(p_data, "size_min", size_min, params_.min_herd, params_.max_herd) ||
			!read_int(p_data, "size_max", size_max, params_.min_herd, params_.max_herd)) {
		return false;
	}
	if (size_max < size_min) {
		return fail("Zone : size_max < size_min.");
	}
	r_zone.herds = herds;
	r_zone.size_min = size_min;
	r_zone.size_max = size_max;
	if (kind_text == "circle") {
		const Variant center = p_data.get("center", Variant());
		if (center.get_type() != Variant::VECTOR2) {
			return fail("Zone circulaire sans « center ».");
		}
		const Vector2 c = center;
		float radius = 0.0f;
		if (!read_float(p_data, "radius_m", radius, 5.0f, 100000.0f)) {
			return false;
		}
		r_zone.circle = true;
		r_zone.cx = c.x;
		r_zone.cz = c.y;
		r_zone.radius = radius;
		r_zone.safe_x = c.x;
		r_zone.safe_z = c.y;
		r_zone.min_x = c.x - radius;
		r_zone.max_x = c.x + radius;
		r_zone.min_z = c.y - radius;
		r_zone.max_z = c.y + radius;
	} else if (kind_text == "polygon") {
		const Variant points = p_data.get("points", Variant());
		if (points.get_type() != Variant::PACKED_VECTOR2_ARRAY) {
			return fail("Zone polygonale sans « points ».");
		}
		const godot::PackedVector2Array array = points;
		const int64_t count = array.size();
		if (count < 3 || count > 256) {
			return fail("Zone polygonale : 3 à 256 sommets attendus.");
		}
		r_zone.circle = false;
		r_zone.min_x = array[0].x;
		r_zone.max_x = array[0].x;
		r_zone.min_z = array[0].y;
		r_zone.max_z = array[0].y;
		for (int64_t i = 0; i < count; i++) {
			const Vector2 v = array[i];
			if (!std::isfinite(v.x) || !std::isfinite(v.y)) {
				return fail("Zone polygonale : sommet non fini.");
			}
			r_zone.px.push_back(v.x);
			r_zone.pz.push_back(v.y);
			r_zone.min_x = std::min(r_zone.min_x, v.x);
			r_zone.max_x = std::max(r_zone.max_x, v.x);
			r_zone.min_z = std::min(r_zone.min_z, v.y);
			r_zone.max_z = std::max(r_zone.max_z, v.y);
		}
		// Point intérieur sûr : premier point d'une grille régulière qui tombe dans le polygone.
		bool found = false;
		for (int32_t row = 1; row < 32 && !found; row++) {
			for (int32_t column = 1; column < 32 && !found; column++) {
				const float x = r_zone.min_x + (r_zone.max_x - r_zone.min_x) * static_cast<float>(column) / 32.0f;
				const float z = r_zone.min_z + (r_zone.max_z - r_zone.min_z) * static_cast<float>(row) / 32.0f;
				if (zone_has(r_zone, x, z)) {
					r_zone.safe_x = x;
					r_zone.safe_z = z;
					found = true;
				}
			}
		}
		if (!found) {
			return fail("Zone polygonale dégénérée : aucun point intérieur.");
		}
	} else {
		return fail("Zone : « kind » doit valoir circle ou polygon.");
	}
	if (p_heightfield == nullptr || !p_heightfield->has_method("height_at")) {
		return fail("Champ de hauteurs absent ou sans height_at().");
	}
	// Grille de hauteurs, avec une marge de deux cases : le bord de la zone reste interpolable.
	const float margin = params_.height_grid * 2.0f;
	r_zone.grid_x0 = r_zone.min_x - margin;
	r_zone.grid_z0 = r_zone.min_z - margin;
	const float width = r_zone.max_x - r_zone.min_x + margin * 2.0f;
	const float depth = r_zone.max_z - r_zone.min_z + margin * 2.0f;
	const int32_t nx = static_cast<int32_t>(std::ceil(width / params_.height_grid)) + 1;
	const int32_t nz = static_cast<int32_t>(std::ceil(depth / params_.height_grid)) + 1;
	if (nx < 2 || nz < 2 || nx > kMaxGridSide || nz > kMaxGridSide || static_cast<int64_t>(nx) * nz > kMaxGridCells) {
		return fail("Zone trop grande pour la grille de hauteurs (augmenter height_grid_m).");
	}
	r_zone.grid_nx = nx;
	r_zone.grid_nz = nz;
	r_zone.heights.resize(static_cast<size_t>(nx) * static_cast<size_t>(nz));
	static const StringName height_method("height_at");
	for (int32_t row = 0; row < nz; row++) {
		for (int32_t column = 0; column < nx; column++) {
			const double x = static_cast<double>(r_zone.grid_x0) + static_cast<double>(column) * static_cast<double>(params_.height_grid);
			const double z = static_cast<double>(r_zone.grid_z0) + static_cast<double>(row) * static_cast<double>(params_.height_grid);
			const Variant h = p_heightfield->call(height_method, x, z);
			if (h.get_type() != Variant::FLOAT && h.get_type() != Variant::INT) {
				return fail("height_at() n'a pas renvoyé un nombre.");
			}
			const double value = static_cast<double>(h);
			if (!std::isfinite(value)) {
				return fail("height_at() a renvoyé une valeur non finie.");
			}
			r_zone.heights[static_cast<size_t>(row) * static_cast<size_t>(nx) + static_cast<size_t>(column)] = static_cast<float>(value);
		}
	}
	return true;
}

// Hauteur interpolée et gradient (dh/dx, dh/dz) : O(1), sans appel au moteur. Hors grille : valeurs du bord.
float FaunaHerds::sample_height(const Zone &p_zone, float p_x, float p_z, float &r_gx, float &r_gz) const {
	const float step = params_.height_grid;
	float fx = (p_x - p_zone.grid_x0) / step;
	float fz = (p_z - p_zone.grid_z0) / step;
	const float max_fx = static_cast<float>(p_zone.grid_nx - 1) - 0.001f;
	const float max_fz = static_cast<float>(p_zone.grid_nz - 1) - 0.001f;
	fx = std::min(std::max(fx, 0.0f), max_fx);
	fz = std::min(std::max(fz, 0.0f), max_fz);
	const int32_t ix = static_cast<int32_t>(fx);
	const int32_t iz = static_cast<int32_t>(fz);
	const float tx = fx - static_cast<float>(ix);
	const float tz = fz - static_cast<float>(iz);
	const size_t stride = static_cast<size_t>(p_zone.grid_nx);
	const size_t base = static_cast<size_t>(iz) * stride + static_cast<size_t>(ix);
	const float h00 = p_zone.heights[base];
	const float h10 = p_zone.heights[base + 1];
	const float h01 = p_zone.heights[base + stride];
	const float h11 = p_zone.heights[base + stride + 1];
	r_gx = ((h10 - h00) * (1.0f - tz) + (h11 - h01) * tz) / step;
	r_gz = ((h01 - h00) * (1.0f - tx) + (h11 - h10) * tx) / step;
	return (h00 * (1.0f - tx) + h10 * tx) * (1.0f - tz) + (h01 * (1.0f - tx) + h11 * tx) * tz;
}

bool FaunaHerds::setup(const Dictionary &p_settings, const Array &p_zones, godot::Object *p_heightfield, int64_t p_seed) {
	ready_ = false;
	zones_.clear();
	herds_.clear();
	animals_.clear();
	multimesh_.unref();
	visible_count_ = 0;
	last_error_ = String();
	rng_state_ = static_cast<uint64_t>(p_seed) * 0x2545F4914F6CDD1DULL + 0x1B873593ULL;
	if (!read_params(p_settings)) {
		return false;
	}
	if (p_zones.is_empty() || p_zones.size() > 64) {
		return fail("Entre 1 et 64 zones de gazelles attendues.");
	}
	zones_.reserve(static_cast<size_t>(p_zones.size()));
	int64_t total = 0;
	for (int64_t i = 0; i < p_zones.size(); i++) {
		const Variant entry = p_zones[i];
		if (entry.get_type() != Variant::DICTIONARY) {
			return fail("Chaque zone doit être un dictionnaire.");
		}
		const Dictionary zone_data = entry;
		Zone zone;
		if (!build_zone(zone_data, p_heightfield, zone)) {
			return false;
		}
		total += static_cast<int64_t>(zone.herds) * zone.size_max;
		zones_.push_back(std::move(zone));
	}
	if (total > params_.max_animals) {
		return fail("Trop de gazelles pour max_animals.");
	}
	animals_.reserve(static_cast<size_t>(total));
	herds_.reserve(static_cast<size_t>(total));
	for (size_t zone_index = 0; zone_index < zones_.size(); zone_index++) {
		const Zone &zone = zones_[zone_index];
		for (int32_t h = 0; h < zone.herds; h++) {
			Herd herd;
			herd.zone = static_cast<int32_t>(zone_index);
			herd.first = static_cast<int32_t>(animals_.size());
			const int32_t span = zone.size_max - zone.size_min + 1;
			herd.count = zone.size_min + static_cast<int32_t>(random_next() % static_cast<uint64_t>(span));
			pick_point(zone, herd.anchor_x, herd.anchor_z);
			herd.timer = params_.graze_min + random_unit() * (params_.graze_max - params_.graze_min);
			for (int32_t a = 0; a < herd.count; a++) {
				Animal animal;
				const float radius = params_.herd_radius * std::sqrt(random_unit());
				const float angle = random_unit() * kTwoPi;
				animal.off_x = std::cos(angle) * radius;
				animal.off_z = std::sin(angle) * radius;
				float x = herd.anchor_x + animal.off_x;
				float z = herd.anchor_z + animal.off_z;
				if (!zone_has(zone, x, z)) {
					x = herd.anchor_x;
					z = herd.anchor_z;
				}
				animal.x = x;
				animal.z = z;
				const float heading = random_unit() * kTwoPi;
				animal.hx = std::cos(heading);
				animal.hz = std::sin(heading);
				animal.phase = random_unit() * kTwoPi;
				animal.scale = params_.scale_min + random_unit() * (params_.scale_max - params_.scale_min);
				animal.run_factor = 1.0f - params_.run_variation * random_unit();
				float gx = 0.0f;
				float gz = 0.0f;
				animal.y = sample_height(zone, x, z, gx, gz);
				animals_.push_back(animal);
			}
			herds_.push_back(herd);
		}
	}
	ready_ = true;
	return true;
}

bool FaunaHerds::bind_multimesh(const godot::Ref<godot::MultiMesh> &p_multimesh) {
	if (!ready_) {
		return fail("bind_multimesh() avant setup().");
	}
	if (p_multimesh.is_null()) {
		return fail("MultiMesh absent.");
	}
	if (p_multimesh->get_instance_count() != static_cast<int32_t>(animals_.size())) {
		return fail("instance_count du MultiMesh différent du nombre de gazelles.");
	}
	if (p_multimesh->get_transform_format() != godot::MultiMesh::TRANSFORM_3D || p_multimesh->is_using_colors() ||
			!p_multimesh->is_using_custom_data()) {
		return fail("Le MultiMesh doit être 3D, sans couleurs, avec données personnalisées.");
	}
	multimesh_ = p_multimesh;
	buffer_.resize(static_cast<int64_t>(animals_.size()) * kFloatsPerInstance);
	buffer_.fill(0.0f);
	visible_count_ = 0;
	multimesh_->set_visible_instance_count(0);
	return true;
}

void FaunaHerds::pick_walk_anchor(Herd &p_herd) {
	const Zone &zone = zones_[static_cast<size_t>(p_herd.zone)];
	for (int32_t attempt = 0; attempt < kPointAttempts; attempt++) {
		float x = 0.0f;
		float z = 0.0f;
		pick_point(zone, x, z);
		const float dx = x - p_herd.center_x;
		const float dz = z - p_herd.center_z;
		if (dx * dx + dz * dz <= params_.relocate_max * params_.relocate_max) {
			p_herd.anchor_x = x;
			p_herd.anchor_z = z;
			return;
		}
	}
	p_herd.anchor_x = zone.safe_x;
	p_herd.anchor_z = zone.safe_z;
}

// Point de fuite : parmi quelques candidats de la zone, celui qui éloigne le plus du joueur, en préférant ceux qui
// sont dans le sens opposé au joueur par rapport au troupeau.
void FaunaHerds::pick_flee_anchor(Herd &p_herd, float p_player_x, float p_player_z) {
	const Zone &zone = zones_[static_cast<size_t>(p_herd.zone)];
	float away_x = p_herd.center_x - p_player_x;
	float away_z = p_herd.center_z - p_player_z;
	const float away_length = std::sqrt(away_x * away_x + away_z * away_z);
	if (away_length > kEpsilon) {
		away_x /= away_length;
		away_z /= away_length;
	} else {
		away_x = 1.0f;
		away_z = 0.0f;
	}
	float best_score = -1.0e30f;
	float best_x = zone.safe_x;
	float best_z = zone.safe_z;
	for (int32_t i = 0; i < params_.flee_candidates; i++) {
		float x = 0.0f;
		float z = 0.0f;
		pick_point(zone, x, z);
		const float from_player_x = x - p_player_x;
		const float from_player_z = z - p_player_z;
		const float distance = std::sqrt(from_player_x * from_player_x + from_player_z * from_player_z);
		const float forward = (x - p_herd.center_x) * away_x + (z - p_herd.center_z) * away_z;
		const float score = distance + (forward > 0.0f ? 100000.0f : 0.0f);
		if (score > best_score) {
			best_score = score;
			best_x = x;
			best_z = z;
		}
	}
	p_herd.anchor_x = best_x;
	p_herd.anchor_z = best_z;
	p_herd.repick_timer = params_.flee_repick;
}

void FaunaHerds::update_state(Herd &p_herd, float p_dt, float p_player_x, float p_player_z) {
	const float flee_sq = params_.flee_distance * params_.flee_distance;
	const float calm_sq = params_.calm_distance * params_.calm_distance;
	if (p_herd.state != STATE_FLEEING) {
		if (p_herd.nearest_player_sq < flee_sq) {
			p_herd.state = STATE_FLEEING;
			p_herd.calm_timer = 0.0f;
			pick_flee_anchor(p_herd, p_player_x, p_player_z);
			return;
		}
		p_herd.timer -= p_dt;
		const float dx = p_herd.anchor_x - p_herd.center_x;
		const float dz = p_herd.anchor_z - p_herd.center_z;
		if (p_herd.state == STATE_GRAZING) {
			if (p_herd.timer <= 0.0f) {
				pick_walk_anchor(p_herd);
				p_herd.state = STATE_WALKING;
			}
		} else if (dx * dx + dz * dz < params_.herd_radius * params_.herd_radius) {
			p_herd.state = STATE_GRAZING;
			p_herd.timer = params_.graze_min + random_unit() * (params_.graze_max - params_.graze_min);
		}
		return;
	}
	// Fuite : se calme quand le joueur reste loin assez longtemps ; sinon continue de s'éloigner.
	if (p_herd.nearest_player_sq > calm_sq) {
		p_herd.calm_timer += p_dt;
		if (p_herd.calm_timer >= params_.calm_delay) {
			p_herd.state = STATE_WALKING;
			p_herd.calm_timer = 0.0f;
			pick_walk_anchor(p_herd);
		}
		return;
	}
	p_herd.calm_timer = 0.0f;
	p_herd.repick_timer -= p_dt;
	const float dx = p_herd.anchor_x - p_herd.center_x;
	const float dz = p_herd.anchor_z - p_herd.center_z;
	const bool reached = dx * dx + dz * dz < params_.herd_radius * params_.herd_radius * 4.0f;
	if ((reached || p_herd.repick_timer <= 0.0f) && p_herd.nearest_player_sq < calm_sq) {
		pick_flee_anchor(p_herd, p_player_x, p_player_z);
	}
}

void FaunaHerds::step_herd(Herd &p_herd, float p_dt, float p_player_x, float p_player_z) {
	const Zone &zone = zones_[static_cast<size_t>(p_herd.zone)];
	const Params &p = params_;
	// Centre du troupeau et distance du joueur au plus proche.
	float sum_x = 0.0f;
	float sum_z = 0.0f;
	float nearest = 1.0e30f;
	for (int32_t i = 0; i < p_herd.count; i++) {
		const Animal &a = animals_[static_cast<size_t>(p_herd.first + i)];
		sum_x += a.x;
		sum_z += a.z;
		const float dx = a.x - p_player_x;
		const float dz = a.z - p_player_z;
		nearest = std::min(nearest, dx * dx + dz * dz);
	}
	const float inverse_count = 1.0f / static_cast<float>(p_herd.count);
	p_herd.center_x = sum_x * inverse_count;
	p_herd.center_z = sum_z * inverse_count;
	p_herd.nearest_player_sq = nearest;
	update_state(p_herd, p_dt, p_player_x, p_player_z);

	const bool fleeing = p_herd.state == STATE_FLEEING;
	const float formation = fleeing ? 0.6f : 1.0f;
	for (int32_t i = 0; i < p_herd.count; i++) {
		Animal &a = animals_[static_cast<size_t>(p_herd.first + i)];
		// Cible : point d'ancrage plus décalage de formation (ramené à l'ancrage s'il sort de la zone).
		float target_x = p_herd.anchor_x + a.off_x * formation;
		float target_z = p_herd.anchor_z + a.off_z * formation;
		if (!zone_has(zone, target_x, target_z)) {
			target_x = p_herd.anchor_x;
			target_z = p_herd.anchor_z;
		}
		const float to_x = target_x - a.x;
		const float to_z = target_z - a.z;
		const float distance = std::sqrt(to_x * to_x + to_z * to_z);
		float wanted_speed = 0.0f;
		if (fleeing) {
			wanted_speed = p.run_speed * a.run_factor * clamp_unit(distance / 4.0f);
		} else if (p_herd.state == STATE_WALKING) {
			wanted_speed = p.walk_speed * std::min(2.0f, 0.4f + distance / 4.0f);
		} else {
			wanted_speed = distance > 2.5f ? p.walk_speed * 0.5f : 0.0f;
		}
		float dir_x = 0.0f;
		float dir_z = 0.0f;
		if (distance > kEpsilon) {
			dir_x = to_x / distance;
			dir_z = to_z / distance;
		}
		float want_x = dir_x * wanted_speed;
		float want_z = dir_z * wanted_speed;
		// Séparation : repousse les voisins trop proches (au plus 8 voisins).
		for (int32_t j = 0; j < p_herd.count; j++) {
			if (j == i) {
				continue;
			}
			const Animal &other = animals_[static_cast<size_t>(p_herd.first + j)];
			const float dx = a.x - other.x;
			const float dz = a.z - other.z;
			const float d_sq = dx * dx + dz * dz;
			if (d_sq < p.separation * p.separation && d_sq > kEpsilon) {
				const float d = std::sqrt(d_sq);
				const float push = (p.separation - d) / p.separation * p.separation_strength;
				want_x += dx / d * push;
				want_z += dz / d * push;
			}
		}
		// Pente : sur un versant raide, on retire de la vitesse voulue la part qui monte, et on glisse vers le bas.
		float gx = 0.0f;
		float gz = 0.0f;
		const float ground = sample_height(zone, a.x, a.z, gx, gz);
		const float slope = std::sqrt(gx * gx + gz * gz);
		if (slope > p.slope_soft && slope > kEpsilon) {
			const float up_x = gx / slope;
			const float up_z = gz / slope;
			const float severity = clamp_unit((slope - p.slope_soft) / (p.slope_limit - p.slope_soft));
			const float climb = want_x * up_x + want_z * up_z;
			if (climb > 0.0f) {
				want_x -= up_x * climb * severity;
				want_z -= up_z * climb * severity;
			}
			want_x -= up_x * severity * p.walk_speed;
			want_z -= up_z * severity * p.walk_speed;
		}
		// Vitesse : rejoint la vitesse voulue avec une accélération bornée.
		const float diff_x = want_x - a.vx;
		const float diff_z = want_z - a.vz;
		const float diff = std::sqrt(diff_x * diff_x + diff_z * diff_z);
		const float max_change = p.acceleration * p_dt;
		if (diff > max_change && diff > kEpsilon) {
			const float k = max_change / diff;
			a.vx += diff_x * k;
			a.vz += diff_z * k;
		} else {
			a.vx = want_x;
			a.vz = want_z;
		}
		const float speed_limit = p.run_speed * 1.25f;
		const float speed_now = std::sqrt(a.vx * a.vx + a.vz * a.vz);
		if (speed_now > speed_limit) {
			a.vx *= speed_limit / speed_now;
			a.vz *= speed_limit / speed_now;
		}
		// Déplacement confiné à la zone : glissement le long du bord si le pas complet sort.
		const float new_x = a.x + a.vx * p_dt;
		const float new_z = a.z + a.vz * p_dt;
		if (zone_has(zone, new_x, new_z)) {
			a.x = new_x;
			a.z = new_z;
		} else if (zone_has(zone, new_x, a.z)) {
			a.x = new_x;
			a.vz = 0.0f;
		} else if (zone_has(zone, a.x, new_z)) {
			a.z = new_z;
			a.vx = 0.0f;
		} else {
			a.vx = 0.0f;
			a.vz = 0.0f;
		}
		// Cap : tourne vers la direction du mouvement.
		const float speed = std::sqrt(a.vx * a.vx + a.vz * a.vz);
		if (speed > 0.3f) {
			const float k = std::min(1.0f, p.turn_response * p_dt);
			float nx = a.hx + (a.vx / speed - a.hx) * k;
			float nz = a.hz + (a.vz / speed - a.hz) * k;
			const float length = std::sqrt(nx * nx + nz * nz);
			if (length > kEpsilon) {
				nx /= length;
				nz /= length;
			} else {
				nx = a.vx / speed;
				nz = a.vz / speed;
			}
			a.hx = nx;
			a.hz = nz;
		}
		// Allure (0 : arrêt, 0,3 : marche, 1 : galop) et phase de la foulée.
		if (speed < 0.15f) {
			a.gait = 0.0f;
		} else if (speed < 3.0f) {
			a.gait = 0.3f;
		} else {
			a.gait = 0.3f + 0.7f * clamp_unit((speed - 3.0f) / std::max(p.run_speed - 3.0f, 1.0f));
		}
		const float stride_hz = p.walk_stride_hz + (p.run_stride_hz - p.walk_stride_hz) * clamp_unit((a.gait - 0.3f) / 0.7f);
		if (a.gait > 0.0f) {
			a.phase += kTwoPi * stride_hz * p_dt;
			if (a.phase > kTwoPi) {
				a.phase = std::fmod(a.phase, kTwoPi);
			}
		}
		a.y = ground;
	}
}

void FaunaHerds::write_buffer(float p_player_x, float p_player_z) {
	float *out = buffer_.ptrw();
	const float view_sq = params_.view_distance * params_.view_distance;
	int64_t visible = 0;
	for (const Herd &herd : herds_) {
		const Zone &zone = zones_[static_cast<size_t>(herd.zone)];
		for (int32_t i = 0; i < herd.count; i++) {
			const Animal &a = animals_[static_cast<size_t>(herd.first + i)];
			const float dx = a.x - p_player_x;
			const float dz = a.z - p_player_z;
			if (dx * dx + dz * dz > view_sq) {
				continue;
			}
			float gx = 0.0f;
			float gz = 0.0f;
			const float ground = sample_height(zone, a.x, a.z, gx, gz);
			// Repère de l'animal : haut = normale du sol, avant = cap projeté sur le sol.
			float ux = -gx;
			float uy = 1.0f;
			float uz = -gz;
			const float up_length = std::sqrt(ux * ux + uy * uy + uz * uz);
			ux /= up_length;
			uy /= up_length;
			uz /= up_length;
			const float along = a.hx * ux + a.hz * uz;
			float fx = a.hx - ux * along;
			float fy = -uy * along;
			float fz = a.hz - uz * along;
			const float f_length = std::sqrt(fx * fx + fy * fy + fz * fz);
			fx /= f_length;
			fy /= f_length;
			fz /= f_length;
			// droite = avant x haut
			const float rx = fy * uz - fz * uy;
			const float ry = fz * ux - fx * uz;
			const float rz = fx * uy - fy * ux;
			const float s = a.scale;
			float *row = out + visible * kFloatsPerInstance;
			row[0] = rx * s;
			row[1] = ux * s;
			row[2] = -fx * s;
			row[3] = a.x;
			row[4] = ry * s;
			row[5] = uy * s;
			row[6] = -fy * s;
			row[7] = ground;
			row[8] = rz * s;
			row[9] = uz * s;
			row[10] = -fz * s;
			row[11] = a.z;
			row[12] = a.phase;
			row[13] = a.gait;
			row[14] = 0.0f;
			row[15] = 0.0f;
			visible++;
		}
	}
	visible_count_ = visible;
	multimesh_->set_buffer(buffer_);
	multimesh_->set_visible_instance_count(static_cast<int32_t>(visible));
}

void FaunaHerds::step(double p_delta, const Vector3 &p_player) {
	if (!ready_ || multimesh_.is_null() || !std::isfinite(p_delta) || p_delta <= 0.0) {
		return;
	}
	const float total = std::min(static_cast<float>(p_delta), kMaxStepSeconds);
	int32_t substeps = static_cast<int32_t>(std::ceil(total / params_.max_substep));
	substeps = std::min(std::max(substeps, 1), kMaxSubsteps);
	const float dt = total / static_cast<float>(substeps);
	for (int32_t s = 0; s < substeps; s++) {
		for (Herd &herd : herds_) {
			step_herd(herd, dt, p_player.x, p_player.z);
		}
	}
	write_buffer(p_player.x, p_player.z);
}

int64_t FaunaHerds::get_animal_count() const {
	return static_cast<int64_t>(animals_.size());
}

int64_t FaunaHerds::get_herd_count() const {
	return static_cast<int64_t>(herds_.size());
}

int64_t FaunaHerds::get_visible_count() const {
	return visible_count_;
}

Vector3 FaunaHerds::get_animal_position(int64_t p_index) const {
	if (p_index < 0 || p_index >= static_cast<int64_t>(animals_.size())) {
		return Vector3();
	}
	const Animal &a = animals_[static_cast<size_t>(p_index)];
	return Vector3(a.x, a.y, a.z);
}

Vector3 FaunaHerds::get_herd_center(int64_t p_herd) const {
	if (p_herd < 0 || p_herd >= static_cast<int64_t>(herds_.size())) {
		return Vector3();
	}
	const Herd &h = herds_[static_cast<size_t>(p_herd)];
	return Vector3(h.center_x, 0.0f, h.center_z);
}

int64_t FaunaHerds::get_herd_state(int64_t p_herd) const {
	if (p_herd < 0 || p_herd >= static_cast<int64_t>(herds_.size())) {
		return -1;
	}
	return herds_[static_cast<size_t>(p_herd)].state;
}

int64_t FaunaHerds::get_herd_zone(int64_t p_herd) const {
	if (p_herd < 0 || p_herd >= static_cast<int64_t>(herds_.size())) {
		return -1;
	}
	return herds_[static_cast<size_t>(p_herd)].zone;
}

bool FaunaHerds::zone_contains(int64_t p_zone, double p_x, double p_z) const {
	if (p_zone < 0 || p_zone >= static_cast<int64_t>(zones_.size())) {
		return false;
	}
	return zone_has(zones_[static_cast<size_t>(p_zone)], static_cast<float>(p_x), static_cast<float>(p_z));
}

godot::PackedFloat32Array FaunaHerds::get_zone_bounds(int64_t p_zone) const {
	godot::PackedFloat32Array bounds;
	if (p_zone < 0 || p_zone >= static_cast<int64_t>(zones_.size())) {
		return bounds;
	}
	const Zone &z = zones_[static_cast<size_t>(p_zone)];
	bounds.push_back(z.min_x);
	bounds.push_back(z.min_z);
	bounds.push_back(z.max_x);
	bounds.push_back(z.max_z);
	return bounds;
}

int64_t FaunaHerds::get_zone_count() const {
	return static_cast<int64_t>(zones_.size());
}

bool FaunaHerds::is_state_finite() const {
	for (const Animal &a : animals_) {
		if (!std::isfinite(a.x) || !std::isfinite(a.z) || !std::isfinite(a.y) || !std::isfinite(a.vx) || !std::isfinite(a.vz) ||
				!std::isfinite(a.phase)) {
			return false;
		}
	}
	return true;
}

void FaunaHerds::_bind_methods() {
	godot::ClassDB::bind_method(godot::D_METHOD("setup", "settings", "zones", "heightfield", "seed"), &FaunaHerds::setup);
	godot::ClassDB::bind_method(godot::D_METHOD("bind_multimesh", "multimesh"), &FaunaHerds::bind_multimesh);
	godot::ClassDB::bind_method(godot::D_METHOD("step", "delta", "player"), &FaunaHerds::step);
	godot::ClassDB::bind_method(godot::D_METHOD("get_animal_count"), &FaunaHerds::get_animal_count);
	godot::ClassDB::bind_method(godot::D_METHOD("get_herd_count"), &FaunaHerds::get_herd_count);
	godot::ClassDB::bind_method(godot::D_METHOD("get_visible_count"), &FaunaHerds::get_visible_count);
	godot::ClassDB::bind_method(godot::D_METHOD("get_animal_position", "index"), &FaunaHerds::get_animal_position);
	godot::ClassDB::bind_method(godot::D_METHOD("get_herd_center", "herd"), &FaunaHerds::get_herd_center);
	godot::ClassDB::bind_method(godot::D_METHOD("get_herd_state", "herd"), &FaunaHerds::get_herd_state);
	godot::ClassDB::bind_method(godot::D_METHOD("get_herd_zone", "herd"), &FaunaHerds::get_herd_zone);
	godot::ClassDB::bind_method(godot::D_METHOD("zone_contains", "zone", "x", "z"), &FaunaHerds::zone_contains);
	godot::ClassDB::bind_method(godot::D_METHOD("get_zone_bounds", "zone"), &FaunaHerds::get_zone_bounds);
	godot::ClassDB::bind_method(godot::D_METHOD("get_zone_count"), &FaunaHerds::get_zone_count);
	godot::ClassDB::bind_method(godot::D_METHOD("is_state_finite"), &FaunaHerds::is_state_finite);
	godot::ClassDB::bind_method(godot::D_METHOD("get_last_error"), &FaunaHerds::get_last_error);
}
