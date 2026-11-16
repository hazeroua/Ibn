extends PlayerPhysicsCase
## Machine d'animation du personnage : animations de la bibliothèque « locomotion » jouées selon
## l'allure et la vitesse ; absente quand aucun AnimationPlayer n'est branché.

const CLIPS: Array[StringName] = [
	&"idle",
	&"walk_slow",
	&"walk",
	&"run",
	&"stop_walk",
	&"stop_run",
	&"turn_left_90",
	&"turn_right_90",
	&"turn_180",
	&"jump_start",
	&"jump_air",
	&"jump_land",
	&"bump",
	&"land_roll",
	&"ride_idle",
	&"ride_gallop",
	&"mount",
	&"dismount",
]


func _make_animation_player(missing: StringName = &"") -> AnimationPlayer:
	var library := AnimationLibrary.new()
	for clip: StringName in CLIPS:
		if clip == missing:
			continue
		var animation := Animation.new()
		animation.length = 1.0
		library.add_animation(clip, animation)
	var animation_player := AnimationPlayer.new()
	animation_player.add_animation_library(&"locomotion", library)
	return animation_player


func _spawn_animated(world: Node3D, missing: StringName = &"") -> Array:
	var player: PlayerCharacter = _spawn(world)
	var animation_player: AnimationPlayer = _make_animation_player(missing)
	player.add_child(animation_player)
	player.animation_player = animation_player
	return [player, animation_player]


## Joue frames images et renvoie les animations vues, dans l'ordre.
func _watch(animation_player: AnimationPlayer, frames: int) -> Array[StringName]:
	var seen: Array[StringName] = []
	for i: int in frames:
		await wait_physics_frames(1)
		var clip: StringName = animation_player.assigned_animation
		if seen.is_empty() or seen.back() != clip:
			seen.append(clip)
	return seen


func test_idle_then_walk_then_run_play_their_loops() -> void:
	var world: Node3D = _new_world()
	PlayerTestWorld.ground(world)
	var pair: Array = _spawn_animated(world)
	var player: PlayerCharacter = pair[0]
	var animation_player: AnimationPlayer = pair[1]
	await _settle()
	assert_true(player.is_animating())
	assert_eq(animation_player.assigned_animation, "locomotion/idle")
	player.input.simulate(Vector2(0.0, 1.0))
	await _simulate(2.0)
	assert_eq(animation_player.assigned_animation, "locomotion/walk")
	assert_eq(animation_player.get_animation("locomotion/walk").loop_mode, Animation.LOOP_LINEAR)
	assert_almost_eq(animation_player.speed_scale, 1.0, 0.1, "à la vitesse de référence, lecture normale")
	player.input.simulate(Vector2(0.0, 1.0), true)
	await _simulate(2.5)
	assert_eq(animation_player.assigned_animation, "locomotion/run")
	assert_between(animation_player.speed_scale, 0.9, 1.1)


func test_playback_speed_follows_the_real_speed_within_bounds() -> void:
	var world: Node3D = _new_world()
	PlayerTestWorld.ground(world)
	var pair: Array = _spawn_animated(world)
	var player: PlayerCharacter = pair[0]
	var animation_player: AnimationPlayer = pair[1]
	await _settle()
	player.input.simulate(Vector2(0.0, 0.5))
	await _simulate(2.0)
	var settings: LocomotionSettings = player.get_settings()
	assert_between(animation_player.speed_scale, settings.speed_scale_min, settings.speed_scale_max)
	var expected: float = player.real_speed / settings.gait_animation_reference_speed[LocomotionSettings.Gait.WALK_SLOW]
	assert_almost_eq(animation_player.speed_scale, clampf(expected, settings.speed_scale_min, settings.speed_scale_max), 0.1)


func test_stopping_plays_stop_run_then_idle() -> void:
	var world: Node3D = _new_world()
	PlayerTestWorld.ground(world)
	var pair: Array = _spawn_animated(world)
	var player: PlayerCharacter = pair[0]
	var animation_player: AnimationPlayer = pair[1]
	await _settle()
	player.input.simulate(Vector2(0.0, 1.0), true)
	await _simulate(3.0)
	player.input.simulate(Vector2.ZERO)
	var seen: Array[StringName] = await _watch(animation_player, 90)
	assert_true(seen.has(&"locomotion/stop_run"), "arrêt de course : %s" % [seen])
	assert_eq(seen.back(), &"locomotion/idle")


func test_u_turn_plays_turn_180() -> void:
	var world: Node3D = _new_world()
	PlayerTestWorld.ground(world)
	var pair: Array = _spawn_animated(world)
	var player: PlayerCharacter = pair[0]
	var animation_player: AnimationPlayer = pair[1]
	await _settle()
	player.input.simulate(Vector2(0.0, 1.0), true)
	await _simulate(3.0)
	player.input.simulate(Vector2(0.0, -1.0), true)
	var seen: Array[StringName] = await _watch(animation_player, 90)
	assert_true(seen.has(&"locomotion/turn_180"), "demi-tour : %s" % [seen])
	assert_eq(seen.back(), &"locomotion/run")


func test_missing_clips_are_listed_by_the_contract_names() -> void:
	var complete: AnimationPlayer = autofree(_make_animation_player())
	assert_true(PlayerAnimator.missing_clips(complete).is_empty())
	var incomplete: AnimationPlayer = autofree(_make_animation_player(&"turn_180"))
	assert_eq(PlayerAnimator.missing_clips(incomplete), PackedStringArray(["locomotion/turn_180"]))
	var empty: AnimationPlayer = autofree(AnimationPlayer.new())
	assert_eq(PlayerAnimator.missing_clips(empty).size(), CLIPS.size())


func test_character_works_without_any_animation_player() -> void:
	var world: Node3D = _new_world()
	PlayerTestWorld.ground(world)
	var player: PlayerCharacter = _spawn(world)
	await _settle()
	assert_false(player.is_animating())
	player.input.simulate(Vector2(0.0, 1.0), true)
	await _simulate(2.0)
	assert_eq(player.get_gait(), &"run")
