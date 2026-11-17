#include "world_streamer.h"

#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/json.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/classes/worker_thread_pool.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/memory.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

namespace {

constexpr int kMaxGrid = 32; // 1024 cellules au plus : tout est réservé une fois à la configuration
constexpr int kMaxConcurrent = 16;

// Lit une valeur numérique obligatoire du dictionnaire de réglages.
bool read_number(const Dictionary &p_config, const char *p_key, double &r_value) {
	const StringName key(p_key);
	if (!p_config.has(key)) {
		UtilityFunctions::push_error(String::utf8("WorldStreamer : réglage manquant : ") + String(p_key));
		return false;
	}
	const Variant value = p_config[key];
	const Variant::Type type = value.get_type();
	if (type != Variant::INT && type != Variant::FLOAT) {
		UtilityFunctions::push_error(String::utf8("WorldStreamer : le réglage doit être un nombre : ") + String(p_key));
		return false;
	}
	r_value = static_cast<double>(value);
	return std::isfinite(r_value);
}

} // namespace

WorldStreamer::WorldStreamer() = default;

WorldStreamer::~WorldStreamer() {
	wait_all_tasks();
	abort_attach(true);
	for (size_t i = retiring_head_; i < retiring_.size(); ++i) {
		memdelete(retiring_[i]);
	}
	retiring_.clear();
	for (size_t i = doomed_head_; i < doomed_.size(); ++i) {
		memdelete(doomed_[i]);
	}
	doomed_.clear();
	for (Slot &slot : slots_) {
		const int state = slot.state.load(std::memory_order_acquire);
		if ((state == STATE_READY) && slot.node != nullptr) {
			memdelete(slot.node);
			slot.node = nullptr;
		}
	}
}

void WorldStreamer::_bind_methods() {
	ClassDB::bind_method(D_METHOD("load_config", "path"), &WorldStreamer::load_config);
	ClassDB::bind_method(D_METHOD("configure", "config"), &WorldStreamer::configure);
	ClassDB::bind_method(D_METHOD("register_provider", "provider"), &WorldStreamer::register_provider);
	ClassDB::bind_method(D_METHOD("set_focus", "position", "velocity"), &WorldStreamer::set_focus);
	ClassDB::bind_method(D_METHOD("update", "delta"), &WorldStreamer::update);
	ClassDB::bind_method(D_METHOD("clear"), &WorldStreamer::clear);
	ClassDB::bind_method(D_METHOD("is_cell_loaded", "cell"), &WorldStreamer::is_cell_loaded);
	ClassDB::bind_method(D_METHOD("get_cell_node", "cell"), &WorldStreamer::get_cell_node);
	ClassDB::bind_method(D_METHOD("get_loaded_count"), &WorldStreamer::get_loaded_count);
	ClassDB::bind_method(D_METHOD("get_pending_count"), &WorldStreamer::get_pending_count);
	ClassDB::bind_method(D_METHOD("get_loaded_cells"), &WorldStreamer::get_loaded_cells);
	ClassDB::bind_method(D_METHOD("world_to_cell", "position"), &WorldStreamer::world_to_cell);
	ClassDB::bind_method(D_METHOD("get_stats"), &WorldStreamer::get_stats);
	ClassDB::bind_method(D_METHOD("reset_stats"), &WorldStreamer::reset_stats);
	ClassDB::bind_method(D_METHOD("set_auto_update", "enabled"), &WorldStreamer::set_auto_update);
	ClassDB::bind_method(D_METHOD("get_auto_update"), &WorldStreamer::get_auto_update);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "auto_update"), "set_auto_update", "get_auto_update");

	ADD_SIGNAL(MethodInfo("cell_loaded", PropertyInfo(Variant::VECTOR2I, "cell")));
	ADD_SIGNAL(MethodInfo("cell_unloaded", PropertyInfo(Variant::VECTOR2I, "cell")));
}

void WorldStreamer::_notification(int p_what) {
	if (p_what == NOTIFICATION_READY) {
		set_process(auto_update_);
	} else if (p_what == NOTIFICATION_PROCESS) {
		update(get_process_delta_time());
	}
}

void WorldStreamer::set_auto_update(bool p_enabled) {
	auto_update_ = p_enabled;
	if (is_inside_tree()) {
		set_process(p_enabled);
	}
}

bool WorldStreamer::get_auto_update() const {
	return auto_update_;
}

bool WorldStreamer::load_config(const String &p_path) {
	ERR_FAIL_COND_V_MSG(!FileAccess::file_exists(p_path), false, String::utf8("WorldStreamer : fichier de réglages introuvable : ") + p_path);
	const Variant parsed = JSON::parse_string(FileAccess::get_file_as_string(p_path));
	ERR_FAIL_COND_V_MSG(parsed.get_type() != Variant::DICTIONARY, false, String::utf8("WorldStreamer : JSON invalide : ") + p_path);
	return configure(parsed);
}

bool WorldStreamer::configure(const Dictionary &p_config) {
	double cell_size = 0.0;
	double grid = 0.0;
	double origin_x = 0.0;
	double origin_z = 0.0;
	double radius = 0.0;
	double hysteresis = 0.0;
	double lookahead = 0.0;
	double budget = 0.0;
	double concurrent = 0.0;
	const bool read_ok = read_number(p_config, "cell_size_m", cell_size) && read_number(p_config, "grid_size", grid) &&
			read_number(p_config, "origin_x_m", origin_x) && read_number(p_config, "origin_z_m", origin_z) &&
			read_number(p_config, "load_radius_m", radius) && read_number(p_config, "unload_hysteresis_m", hysteresis) &&
			read_number(p_config, "lookahead_s", lookahead) && read_number(p_config, "frame_budget_ms", budget) &&
			read_number(p_config, "max_concurrent_builds", concurrent);
	if (!read_ok) {
		return false;
	}
	const bool range_ok = cell_size > 0.0 && grid >= 1.0 && grid <= static_cast<double>(kMaxGrid) && radius > 0.0 && hysteresis >= 0.0 &&
			lookahead >= 0.0 && budget > 0.0 && concurrent >= 1.0 && concurrent <= static_cast<double>(kMaxConcurrent);
	ERR_FAIL_COND_V_MSG(!range_ok, false, "WorldStreamer : réglages hors limites.");

	clear();
	cell_size_ = static_cast<float>(cell_size);
	grid_size_ = static_cast<int>(grid);
	origin_x_ = static_cast<float>(origin_x);
	origin_z_ = static_cast<float>(origin_z);
	load_radius_ = static_cast<float>(radius);
	unload_radius_ = static_cast<float>(radius + hysteresis);
	lookahead_s_ = static_cast<float>(lookahead);
	budget_ms_ = budget;
	max_concurrent_ = static_cast<int>(concurrent);

	const size_t count = static_cast<size_t>(grid_size_) * static_cast<size_t>(grid_size_);
	slots_ = std::vector<Slot>(count);
	queue_.assign(count, 0U);
	queue_.clear();
	loaded_.assign(count, 0U);
	loaded_.clear();
	staged_.reserve(kStagedReserve);
	doomed_.reserve(kDoomedReserve);
	retiring_.clear();
	retiring_.reserve(count);
	build_callables_.clear();
	build_callables_.reserve(count);
	for (size_t i = 0; i < count; ++i) {
		build_callables_.push_back(callable_mp(this, &WorldStreamer::build_task).bind(static_cast<int64_t>(i)));
	}
	queue_head_ = 0;
	in_flight_ = 0;
	dirty_ = true;
	last_focus_index_ = -2;
	last_predicted_index_ = -2;
	configured_ = true;
	return true;
}

bool WorldStreamer::register_provider(Object *p_provider) {
	ERR_FAIL_NULL_V_MSG(p_provider, false, "WorldStreamer : fournisseur nul.");
	ERR_FAIL_COND_V_MSG(!p_provider->has_method("build_cell"), false, "WorldStreamer : le fournisseur doit exposer build_cell(cell).");
	if (provider_ != p_provider) {
		clear();
	}
	provider_ = p_provider;
	provider_hold_ = Variant(p_provider);
	dirty_ = true;
	return true;
}

void WorldStreamer::set_focus(const Vector3 &p_position, const Vector3 &p_velocity) {
	focus_x_ = p_position.x;
	focus_z_ = p_position.z;
	velocity_x_ = p_velocity.x;
	velocity_z_ = p_velocity.z;
	focus_set_ = true;
	if (!configured_) {
		return;
	}
	const int64_t focus_index = cell_index_at(focus_x_, focus_z_);
	const int64_t predicted_index = cell_index_at(focus_x_ + velocity_x_ * lookahead_s_, focus_z_ + velocity_z_ * lookahead_s_);
	if (focus_index != last_focus_index_ || predicted_index != last_predicted_index_) {
		last_focus_index_ = focus_index;
		last_predicted_index_ = predicted_index;
		dirty_ = true;
	}
}

int64_t WorldStreamer::cell_index_at(float p_x, float p_z) const {
	const float fx = std::floor((p_x - origin_x_) / cell_size_);
	const float fz = std::floor((p_z - origin_z_) / cell_size_);
	if (!(fx >= 0.0F) || !(fz >= 0.0F) || fx >= static_cast<float>(grid_size_) || fz >= static_cast<float>(grid_size_)) {
		return -1;
	}
	return static_cast<int64_t>(fz) * grid_size_ + static_cast<int64_t>(fx);
}

Vector2i WorldStreamer::index_to_cell(size_t p_index) const {
	const int size = grid_size_;
	const int index = static_cast<int>(p_index);
	return Vector2i(index % size, index / size);
}

void WorldStreamer::cell_center(size_t p_index, float &r_x, float &r_z) const {
	const Vector2i cell = index_to_cell(p_index);
	r_x = origin_x_ + (static_cast<float>(cell.x) + 0.5F) * cell_size_;
	r_z = origin_z_ + (static_cast<float>(cell.y) + 0.5F) * cell_size_;
}

Vector2i WorldStreamer::world_to_cell(const Vector3 &p_position) const {
	const int64_t index = cell_index_at(p_position.x, p_position.z);
	if (index < 0) {
		return Vector2i(-1, -1);
	}
	return index_to_cell(static_cast<size_t>(index));
}

void WorldStreamer::build_task(int64_t p_index) {
	// Fil de travail : n'écrit que dans son propre emplacement, puis publie l'état (release).
	Slot &slot = slots_[static_cast<size_t>(p_index)];
	std::lock_guard<std::mutex> lock(provider_mutex_);
	const Variant result = provider_->call(StringName("build_cell"), Variant(index_to_cell(static_cast<size_t>(p_index))));
	Node3D *node = Object::cast_to<Node3D>(static_cast<Object *>(result));
	slot.node = node;
	slot.state.store(node != nullptr ? STATE_READY : STATE_FAILED, std::memory_order_release);
}

void WorldStreamer::recompute_desired() {
	const float predicted_x = focus_x_ + velocity_x_ * lookahead_s_;
	const float predicted_z = focus_z_ + velocity_z_ * lookahead_s_;
	queue_.clear();
	const size_t count = slots_.size();
	for (size_t i = 0; i < count; ++i) {
		float cx = 0.0F;
		float cz = 0.0F;
		cell_center(i, cx, cz);
		const float d_focus = std::hypot(cx - focus_x_, cz - focus_z_);
		const float d_pred = std::hypot(cx - predicted_x, cz - predicted_z);
		const float nearest = std::min(d_focus, d_pred);
		Slot &slot = slots_[i];
		slot.want = nearest <= load_radius_ ? 1 : 0;
		slot.keep = nearest <= unload_radius_ ? 1 : 0;
		// Priorité : les cellules entre le joueur et sa position anticipée passent en premier.
		slot.priority = d_focus + d_pred;
		if (slot.want != 0 && slot.state.load(std::memory_order_relaxed) == STATE_ABSENT) {
			queue_.push_back(static_cast<uint32_t>(i)); // capacité réservée : pas d'allocation
		}
	}
	std::sort(queue_.begin(), queue_.end(), [this](uint32_t p_a, uint32_t p_b) { return slots_[p_a].priority < slots_[p_b].priority; });
	queue_head_ = 0;
	unload_pending_ = true;
}

void WorldStreamer::dispatch_builds() {
	WorkerThreadPool *pool = WorkerThreadPool::get_singleton();
	while (in_flight_ < max_concurrent_ && queue_head_ < queue_.size()) {
		const uint32_t index = queue_[queue_head_++];
		Slot &slot = slots_[index];
		if (slot.want == 0 || slot.state.load(std::memory_order_relaxed) != STATE_ABSENT) {
			continue;
		}
		slot.state.store(STATE_BUILDING, std::memory_order_relaxed);
		slot.task_id = pool->add_task(build_callables_[index]);
		++in_flight_;
	}
}

void WorldStreamer::integrate_ready(int64_t p_deadline_us) {
	Time *time = Time::get_singleton();
	if (attaching_ >= 0) {
		if (slots_[static_cast<size_t>(attaching_)].keep == 0) {
			abort_attach(false); // le joueur est reparti : la cellule n'est jamais terminée
		} else if (!attach_staged(p_deadline_us)) {
			return;
		} else {
			finish_attach();
		}
	}
	if (in_flight_ == 0) {
		return;
	}
	WorkerThreadPool *pool = WorkerThreadPool::get_singleton();
	const size_t count = slots_.size();
	for (size_t i = 0; i < count; ++i) {
		Slot &slot = slots_[i];
		const int state = slot.state.load(std::memory_order_acquire);
		if (state != STATE_READY && state != STATE_FAILED) {
			continue;
		}
		if (static_cast<int64_t>(time->get_ticks_usec()) >= p_deadline_us) {
			return;
		}
		pool->wait_for_task_completion(slot.task_id); // déjà terminée : libère simplement la tâche
		slot.task_id = -1;
		--in_flight_;
		if (state == STATE_FAILED) {
			++failed_count_;
			slot.node = nullptr;
			slot.state.store(STATE_DEAD, std::memory_order_relaxed); // jamais réessayée : erreur de programmation du fournisseur
			UtilityFunctions::push_error(String::utf8("WorldStreamer : build_cell n'a pas renvoyé de Node3D pour la cellule ") +
					String(Variant(index_to_cell(i))));
			continue;
		}
		if (slot.keep == 0) {
			// Devenue inutile pendant sa construction (joueur parti ailleurs) : jetée sans toucher à l'arbre,
			// enfant par enfant sous le budget (hors de l'arbre, le détachement ne coûte rien).
			for (int32_t c = slot.node->get_child_count() - 1; c >= 0; --c) {
				Node *child = slot.node->get_child(c);
				slot.node->remove_child(child);
				doom(child);
			}
			doom(slot.node);
			slot.node = nullptr;
			slot.state.store(STATE_ABSENT, std::memory_order_relaxed);
			dirty_ = true;
			continue;
		}
		begin_attach(i);
		if (!attach_staged(p_deadline_us)) {
			return; // une seule cellule s'attache à la fois
		}
		finish_attach();
	}
}

void WorldStreamer::begin_attach(size_t p_index) {
	Slot &slot = slots_[p_index];
	Node3D *node = slot.node;
	// Enfants mis de côté hors de l'arbre (sans coût), la racine entre seule : ses formes de collision
	// (relief) sont prêtes tout de suite, le reste (maillages, végétation, décor) arrive sous le budget.
	staged_.clear();
	staged_next_ = 0;
	const int32_t children = node->get_child_count();
	for (int32_t c = 0; c < children; ++c) {
		staged_.push_back(node->get_child(c));
	}
	for (int32_t c = children - 1; c >= 0; --c) {
		node->remove_child(staged_[static_cast<size_t>(c)]);
	}
	add_child(node);
	slot.state.store(STATE_ATTACHING, std::memory_order_relaxed);
	attaching_ = static_cast<int64_t>(p_index);
}

bool WorldStreamer::attach_staged(int64_t p_deadline_us) {
	Node3D *node = slots_[static_cast<size_t>(attaching_)].node;
	Time *time = Time::get_singleton();
	while (staged_next_ < staged_.size()) {
		node->add_child(staged_[staged_next_]);
		++staged_next_;
		if (static_cast<int64_t>(time->get_ticks_usec()) >= p_deadline_us) {
			break;
		}
	}
	return staged_next_ >= staged_.size();
}

void WorldStreamer::finish_attach() {
	const size_t index = static_cast<size_t>(attaching_);
	attaching_ = -1;
	staged_.clear();
	staged_next_ = 0;
	slots_[index].state.store(STATE_LOADED, std::memory_order_relaxed);
	loaded_.push_back(static_cast<uint32_t>(index));
	++load_count_;
	emit_signal(StringName("cell_loaded"), index_to_cell(index));
}

void WorldStreamer::abort_attach(bool p_immediate) {
	if (attaching_ < 0) {
		return;
	}
	const size_t index = static_cast<size_t>(attaching_);
	attaching_ = -1;
	for (size_t c = staged_next_; c < staged_.size(); ++c) {
		if (p_immediate) {
			memdelete(staged_[c]);
		} else {
			doom(staged_[c]);
		}
	}
	staged_.clear();
	staged_next_ = 0;
	release_slot(index, false, p_immediate);
	dirty_ = true;
}

void WorldStreamer::doom(Node *p_node) {
	if (doomed_.size() < kDoomedReserve) {
		doomed_.push_back(p_node);
	} else {
		memdelete(p_node); // réserve de 16 384 nœuds jamais atteinte en pratique : pas d'allocation
	}
}

void WorldStreamer::free_doomed(int64_t p_deadline_us) {
	Time *time = Time::get_singleton();
	// Démontage : un enfant sort de l'arbre à chaque pas, la racine en dernier.
	while (retiring_head_ < retiring_.size()) {
		Node3D *root = retiring_[retiring_head_];
		const int32_t children = root->get_child_count();
		if (children > 0) {
			Node *child = root->get_child(children - 1);
			root->remove_child(child);
			doom(child);
		} else {
			remove_child(root);
			doom(root);
			++retiring_head_;
		}
		if (static_cast<int64_t>(time->get_ticks_usec()) >= p_deadline_us) {
			break;
		}
	}
	if (retiring_head_ >= retiring_.size()) {
		retiring_.clear();
		retiring_head_ = 0;
	}
	while (doomed_head_ < doomed_.size()) {
		memdelete(doomed_[doomed_head_]);
		++doomed_head_;
		if (static_cast<int64_t>(time->get_ticks_usec()) >= p_deadline_us) {
			break;
		}
	}
	if (doomed_head_ >= doomed_.size()) {
		doomed_.clear();
		doomed_head_ = 0;
	}
}

void WorldStreamer::release_slot(size_t p_index, bool p_emit, bool p_immediate) {
	Slot &slot = slots_[p_index];
	Node3D *node = slot.node;
	slot.node = nullptr;
	slot.state.store(STATE_ABSENT, std::memory_order_relaxed);
	if (node != nullptr) {
		if (p_immediate) {
			remove_child(node);
			memdelete(node);
		} else if (retiring_.size() < retiring_.capacity()) {
			// Reste dans l'arbre et se démonte sous le budget des images suivantes (free_doomed).
			retiring_.push_back(node);
		} else {
			remove_child(node);
			memdelete(node);
		}
	}
	++unload_count_;
	if (p_emit) {
		emit_signal(StringName("cell_unloaded"), index_to_cell(p_index));
	}
}

void WorldStreamer::unload_stale(int64_t p_deadline_us) {
	if (!unload_pending_) {
		return;
	}
	Time *time = Time::get_singleton();
	size_t i = 0;
	while (i < loaded_.size()) {
		const size_t index = loaded_[i];
		if (slots_[index].keep != 0) {
			++i;
			continue;
		}
		if (static_cast<int64_t>(time->get_ticks_usec()) >= p_deadline_us) {
			return; // reste à faire : unload_pending_ reste vrai
		}
		loaded_[i] = loaded_.back();
		loaded_.pop_back();
		release_slot(index, true, false);
	}
	unload_pending_ = false;
}

void WorldStreamer::update(double p_delta) {
	(void)p_delta;
	if (!configured_ || provider_ == nullptr || !focus_set_) {
		return;
	}
	Time *time = Time::get_singleton();
	const int64_t start_us = static_cast<int64_t>(time->get_ticks_usec());
	const int64_t deadline_us = start_us + static_cast<int64_t>(budget_ms_ * 1000.0);
	if (dirty_) {
		dirty_ = false;
		recompute_desired();
	}
	// Les retraits d'abord : ils libèrent de la place avant les insertions.
	unload_stale(deadline_us);
	integrate_ready(deadline_us);
	free_doomed(deadline_us);
	dispatch_builds();
	const double elapsed_ms = static_cast<double>(static_cast<int64_t>(time->get_ticks_usec()) - start_us) / 1000.0;
	max_update_ms_ = std::max(max_update_ms_, elapsed_ms);
	if (elapsed_ms > budget_ms_) {
		++over_budget_frames_;
	}
	++update_count_;
}

void WorldStreamer::wait_all_tasks() {
	WorkerThreadPool *pool = WorkerThreadPool::get_singleton();
	for (Slot &slot : slots_) {
		if (slot.task_id >= 0) {
			pool->wait_for_task_completion(slot.task_id);
			slot.task_id = -1;
		}
	}
	in_flight_ = 0;
}

void WorldStreamer::clear() {
	wait_all_tasks();
	abort_attach(true);
	for (size_t i = retiring_head_; i < retiring_.size(); ++i) {
		remove_child(retiring_[i]);
		memdelete(retiring_[i]);
	}
	retiring_.clear();
	retiring_head_ = 0;
	for (size_t i = doomed_head_; i < doomed_.size(); ++i) {
		memdelete(doomed_[i]);
	}
	doomed_.clear();
	doomed_head_ = 0;
	const size_t count = slots_.size();
	for (size_t i = 0; i < count; ++i) {
		Slot &slot = slots_[i];
		const int state = slot.state.load(std::memory_order_acquire);
		if (state == STATE_READY && slot.node != nullptr) {
			memdelete(slot.node);
			slot.node = nullptr;
		} else if (state == STATE_LOADED) {
			release_slot(i, true, true);
		}
		slot.state.store(STATE_ABSENT, std::memory_order_relaxed);
		slot.want = 0;
		slot.keep = 0;
	}
	loaded_.clear();
	queue_.clear();
	queue_head_ = 0;
	unload_pending_ = false;
	dirty_ = true;
	last_focus_index_ = -2;
	last_predicted_index_ = -2;
}

bool WorldStreamer::is_cell_loaded(const Vector2i &p_cell) const {
	if (p_cell.x < 0 || p_cell.y < 0 || p_cell.x >= grid_size_ || p_cell.y >= grid_size_) {
		return false;
	}
	const size_t index = static_cast<size_t>(p_cell.y) * static_cast<size_t>(grid_size_) + static_cast<size_t>(p_cell.x);
	return slots_[index].state.load(std::memory_order_relaxed) == STATE_LOADED;
}

Node3D *WorldStreamer::get_cell_node(const Vector2i &p_cell) const {
	if (!is_cell_loaded(p_cell)) {
		return nullptr;
	}
	return slots_[static_cast<size_t>(p_cell.y) * static_cast<size_t>(grid_size_) + static_cast<size_t>(p_cell.x)].node;
}

int64_t WorldStreamer::get_loaded_count() const {
	return static_cast<int64_t>(loaded_.size());
}

int64_t WorldStreamer::get_pending_count() const {
	return in_flight_ + (attaching_ >= 0 ? 1 : 0);
}

PackedVector2Array WorldStreamer::get_loaded_cells() const {
	PackedVector2Array result;
	result.resize(static_cast<int64_t>(loaded_.size()));
	for (size_t i = 0; i < loaded_.size(); ++i) {
		const Vector2i cell = index_to_cell(loaded_[i]);
		result[static_cast<int64_t>(i)] = Vector2(static_cast<real_t>(cell.x), static_cast<real_t>(cell.y));
	}
	return result;
}

Dictionary WorldStreamer::get_stats() const {
	Dictionary stats;
	stats["max_update_ms"] = max_update_ms_;
	stats["over_budget_frames"] = over_budget_frames_;
	stats["updates"] = update_count_;
	stats["loads"] = load_count_;
	stats["unloads"] = unload_count_;
	stats["failures"] = failed_count_;
	stats["budget_ms"] = budget_ms_;
	stats["attaching"] = attaching_ >= 0;
	stats["doomed"] = static_cast<int64_t>(doomed_.size() - doomed_head_ + retiring_.size() - retiring_head_);
	return stats;
}

void WorldStreamer::reset_stats() {
	max_update_ms_ = 0.0;
	over_budget_frames_ = 0;
	load_count_ = 0;
	unload_count_ = 0;
	failed_count_ = 0;
	update_count_ = 0;
}
