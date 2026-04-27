# Tests d'intégration Story-008 — signal player_out_of_world.
# Couvre AC-LVL-25 path 1 (WorldBoundsVolume body_exited),
# AC-LVL-25 path 2 (safety net Y < -2.0),
# AC-LVL-25 idempotence (flag _out_of_world_emitted_this_life one-shot par life).
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Fixture : tests/fixtures/levels/test_etage_08.tscn
#   - PlayerStart Marker3D à (0, 0, 0)
#   - EtageExitTrigger Area3D à (0, 2, -100) — loin, ne bloque pas
#   - InteractiveVolumes Node3D parent de WorldBoundsVolume
#   - WorldBoundsVolume Area3D à (0, 0, 0), BoxShape3D 30×25×10 m
#     Bounds : X [-15,+15], Y [-12.5,+12.5], Z [-5,+5]
#   - Pas de RoomTrigger_NN → push_warning bénin attendu (out-of-scope story-008)
#
# Source : TR-lvl-017 / TR-lvl-018 / TR-lvl-024, ADR-0005 D-3 + D-4 + D-8, ADR-0011 D-9.

extends GdUnitTestSuite

const _FIXTURE_PATH_TEMPLATE: String = "res://tests/fixtures/levels/test_etage_%02d.tscn"

# WorldBoundsVolume : Box 30×25×10 centré (0, 0, 0) → bounds [-15,+15] × [-12.5,+12.5] × [-5,+5].
# (50, 1, 0) est hors bounds X ; (0, 5, 0) est dans bounds Y/Z ; (0, -5, 0) est dans bounds mais sous Y=-2 (safety net).
const _POS_INSIDE_BOUNDS: Vector3 = Vector3(0, 5, 0)
const _POS_OUTSIDE_BOUNDS_X: Vector3 = Vector3(50, 1, 0)
const _POS_BELOW_Y_THRESHOLD: Vector3 = Vector3(0, -5, 0)
const _POS_AT_Y_THRESHOLD: Vector3 = Vector3(0, -2.0, 0)  # Gate strict `< -2.0` → pas de trigger

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Crée un LevelSystemScript avec la fixture test_etage_08 et l'attache au scene tree.
## scene_path_template défini AVANT add_child() (DI principle, miroir story-005/007).
func _make_level() -> LevelSystemScript:
	var level: LevelSystemScript = LevelSystemScript.new()
	level.scene_path_template = _FIXTURE_PATH_TEMPLATE
	add_child(level)
	return level


## Crée un CharacterBody3D dans le groupe "player" avec CollisionShape3D + LAYER_PLAYER.
## Attache au scene tree de la test suite. Pattern miroir story-007.
func _make_player_body() -> CharacterBody3D:
	var player: CharacterBody3D = CharacterBody3D.new()
	player.add_to_group("player")
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	player.add_child(shape)
	player.set_collision_layer_value(CollisionLayers.LAYER_PLAYER, true)
	add_child(player)
	return player

# ---------------------------------------------------------------------------
# AC-LVL-25 path 1 — body_exited WorldBoundsVolume → player_out_of_world émis 1×
# ---------------------------------------------------------------------------

## Vérifie que :
##   1. Player démarre dans WorldBoundsVolume → _last_valid_position se met à jour
##   2. Player téléporté hors bounds (X=50) → body_exited fire → player_out_of_world émis 1×
##   3. Payload `last_valid_position` ≈ position dans bounds avant exit
##   4. Re-entry dans bounds = pas de nouveau signal (idempotent flag bloque)
##
## Source : TR-lvl-017, TR-lvl-024, AC-LVL-25 path 1, ADR-0005 D-4 + D-8.
func test_player_out_of_world_emits_via_worldbounds_exit() -> void:
	# Arrange — level ACTIVE
	var level: LevelSystemScript = _make_level()
	level.load_etage(8)
	await await_signal_on(level, "level_active", [], 3000)

	assert_int(level.get_state()) \
		.override_failure_message("Precondition: état doit être ACTIVE avant trigger WorldBounds") \
		.is_equal(LevelSystemScript.LevelState.ACTIVE)

	var player: CharacterBody3D = _make_player_body()
	# Player démarre dans bounds — laisse 2 frames pour que _last_valid_position se mette à jour
	player.global_position = _POS_INSIDE_BOUNDS
	await get_tree().physics_frame
	await get_tree().physics_frame

	var emitted_position: Vector3 = Vector3.INF  # Sentinelle invalide
	var emit_count: int = 0
	level.player_out_of_world.connect(func(last_valid_position: Vector3) -> void:
		emitted_position = last_valid_position
		emit_count += 1
	)

	# Act — téléporter hors WorldBoundsVolume (X=50, hors bounds X [-15,15])
	player.global_position = _POS_OUTSIDE_BOUNDS_X
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Assert — signal émis exactement 1× avec last_valid_position = pos dans bounds
	assert_int(emit_count) \
		.override_failure_message("AC-LVL-25 path 1: player_out_of_world doit être émis 1× sur exit WorldBoundsVolume") \
		.is_equal(1)
	assert_vector(emitted_position) \
		.override_failure_message("AC-LVL-25 path 1: last_valid_position doit être ≈ pos dans bounds avant exit") \
		.is_equal_approx(_POS_INSIDE_BOUNDS, Vector3(0.1, 0.1, 0.1))

	# Re-entry — vérifier idempotence : flag bloque re-emission
	player.global_position = _POS_INSIDE_BOUNDS
	await get_tree().physics_frame
	await get_tree().physics_frame
	player.global_position = _POS_OUTSIDE_BOUNDS_X
	await get_tree().physics_frame
	await get_tree().physics_frame

	assert_int(emit_count) \
		.override_failure_message("AC-LVL-25 idempotence: re-exit même life ne doit PAS ré-émettre (flag bloque)") \
		.is_equal(1)

	# Cleanup
	player.queue_free()
	level.queue_free()

# ---------------------------------------------------------------------------
# AC-LVL-25 path 2 — Y < -2.0 safety net → player_out_of_world émis 1×
# ---------------------------------------------------------------------------

## Vérifie que :
##   1. Player dans bounds + y >= -2 → _last_valid_position update
##   2. Player téléporté à (0, -5, 0) → safety net `y < -2.0` fire → signal émis 1×
##   3. Payload `last_valid_position` ≈ dernière position dans bounds avec y >= -2
##   4. Edge gate strict : y = -2.0 pile ne déclenche PAS (assertion `< -2.0`)
##
## Source : TR-lvl-018, TR-lvl-024, AC-LVL-25 path 2, ADR-0005 D-4 + D-8.
func test_player_out_of_world_emits_via_y_below_minus_two() -> void:
	# Arrange — level ACTIVE, player dans bounds avec y=5 (≥ -2, _last_valid_position update)
	var level: LevelSystemScript = _make_level()
	level.load_etage(8)
	await await_signal_on(level, "level_active", [], 3000)

	var player: CharacterBody3D = _make_player_body()
	player.global_position = _POS_INSIDE_BOUNDS  # (0, 5, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var emitted_position: Vector3 = Vector3.INF
	var emit_count: int = 0
	level.player_out_of_world.connect(func(last_valid_position: Vector3) -> void:
		emitted_position = last_valid_position
		emit_count += 1
	)

	# Edge gate strict : y = -2.0 pile NE doit PAS fire (assertion `pos.y < -2.0`).
	# Signal connecté avant le déplacement → assertion explicite que emit_count reste 0.
	player.global_position = _POS_AT_Y_THRESHOLD  # (0, -2.0, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_int(emit_count) \
		.override_failure_message("AC-LVL-25 gate strict: y=-2.0 pile NE doit PAS fire (assertion `< -2.0`)") \
		.is_equal(0)

	# Reposer player dans bounds pour update _last_valid_position fresh avant la chute.
	player.global_position = _POS_INSIDE_BOUNDS
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Act — téléporter à y=-5 (sous gate strict)
	player.global_position = _POS_BELOW_Y_THRESHOLD
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Assert — signal émis 1× avec last_valid_position = pos dans bounds avant chute
	# Note : (0, -5, 0) reste dans bounds X/Z → seul path 2 (Y safety net) peut se déclencher.
	# L'invariant garanti est : exactement 1 signal, quel que soit le path interne.
	assert_int(emit_count) \
		.override_failure_message("AC-LVL-25 path 2: player_out_of_world doit être émis 1× sur y < -2.0") \
		.is_equal(1)
	assert_vector(emitted_position) \
		.override_failure_message("AC-LVL-25 path 2: last_valid_position doit être ≈ pos dans bounds avant chute") \
		.is_equal_approx(_POS_INSIDE_BOUNDS, Vector3(0.1, 0.1, 0.1))

	# Cleanup
	player.queue_free()
	level.queue_free()

# ---------------------------------------------------------------------------
# AC-LVL-25 idempotence — 5 frames consécutifs sous y=-2 → 1× signal seulement
# ---------------------------------------------------------------------------

## Vérifie que :
##   1. Player tombe sous y=-2 → signal émis 1×
##   2. 5 frames consécutifs avec player à y=-10 → toujours 1 signal cumulé
##   3. reset_out_of_world_flag() → re-emission possible au tick suivant
##   4. load_etage() fresh = re-emission possible (reset auto via _reset_runtime_state)
##
## Source : TR-lvl-024, ADR-0005 D-8 (idempotent par cycle vie).
func test_player_out_of_world_idempotent_single_life() -> void:
	# Arrange — level ACTIVE, player dans bounds
	var level: LevelSystemScript = _make_level()
	level.load_etage(8)
	await await_signal_on(level, "level_active", [], 3000)

	var player: CharacterBody3D = _make_player_body()
	player.global_position = _POS_INSIDE_BOUNDS
	await get_tree().physics_frame
	await get_tree().physics_frame

	var emit_count: int = 0
	level.player_out_of_world.connect(func(_last_valid_position: Vector3) -> void:
		emit_count += 1
	)

	# Act — chute sous y=-2, puis 5 frames consécutifs à y=-10 (path 2 safety net)
	player.global_position = _POS_BELOW_Y_THRESHOLD
	for i: int in range(5):
		await get_tree().physics_frame

	# Assert — signal émis 1× malgré 5 frames consécutifs (flag bloque re-emission)
	assert_int(emit_count) \
		.override_failure_message("AC-LVL-25 idempotence: signal émis 1× sur 5 frames consécutifs y<-2 (flag one-shot bloque)") \
		.is_equal(1)

	# Act 2 — reset flag puis re-trigger : re-emission attendue
	level.reset_out_of_world_flag()
	# Re-mise dans bounds + frame pour update _last_valid_position
	player.global_position = _POS_INSIDE_BOUNDS
	await get_tree().physics_frame
	await get_tree().physics_frame
	# Re-chute
	player.global_position = _POS_BELOW_Y_THRESHOLD
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Assert — emit_count = 2 (re-emission après reset_out_of_world_flag)
	assert_int(emit_count) \
		.override_failure_message("AC-LVL-25 idempotence: reset_out_of_world_flag() doit permettre re-emission") \
		.is_equal(2)

	# Cleanup
	player.queue_free()
	level.queue_free()

# ---------------------------------------------------------------------------
# AC-LVL-25 idempotence — reset auto via load_etage() fresh → re-emission possible
# ---------------------------------------------------------------------------

## Vérifie que le flag `_out_of_world_emitted_this_life` est resetté automatiquement
## par `_reset_runtime_state()` lors d'un `load_etage()` fresh (TR-lvl-034 EC-12).
##
##   1. Player tombe sous y=-2 → signal émis 1×
##   2. unload_current() puis load_etage(8) fresh → flag resetté via _reset_runtime_state()
##   3. Player re-tombe sous y=-2 → signal émis à nouveau (emit_count = 2)
##
## Source : TR-lvl-024, TR-lvl-034 EC-12, ADR-0007 D-8 (Level reset son propre state à
## chaque load_etage fresh), QA spec AC-LVL-25 edge case "reset flag on load_etage() fresh".
func test_player_out_of_world_reset_via_fresh_load_etage() -> void:
	# Arrange — level ACTIVE, player dans bounds
	var level: LevelSystemScript = _make_level()
	level.load_etage(8)
	await await_signal_on(level, "level_active", [], 3000)

	var player: CharacterBody3D = _make_player_body()
	player.global_position = _POS_INSIDE_BOUNDS
	await get_tree().physics_frame
	await get_tree().physics_frame

	var emit_count: int = 0
	level.player_out_of_world.connect(func(_last_valid_position: Vector3) -> void:
		emit_count += 1
	)

	# Act 1 — chute sous y=-2, signal émis 1×
	player.global_position = _POS_BELOW_Y_THRESHOLD
	await get_tree().physics_frame
	await get_tree().physics_frame

	assert_int(emit_count) \
		.override_failure_message("Precondition: 1er trigger doit émettre le signal une fois") \
		.is_equal(1)

	# Act 2 — unload puis re-load fresh : _reset_runtime_state() doit reset le flag
	level.unload_current()
	# Attendre la transition UNLOADING → UNLOADED (1 physics_frame post queue_free)
	await get_tree().physics_frame
	await get_tree().physics_frame
	level.load_etage(8)
	await await_signal_on(level, "level_active", [], 3000)

	# Re-mise dans bounds après re-load (le player_node cache a été reset par
	# _reset_runtime_state ; player toujours dans le scene tree de la suite test)
	player.global_position = _POS_INSIDE_BOUNDS
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Re-chute sous y=-2
	player.global_position = _POS_BELOW_Y_THRESHOLD
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Assert — emit_count = 2 (re-emission car flag resetté par load_etage fresh, pas
	# par reset_out_of_world_flag — couvre l'edge case QA spec AC-LVL-25)
	assert_int(emit_count) \
		.override_failure_message("AC-LVL-25 idempotence: load_etage() fresh doit reset _out_of_world_emitted_this_life via _reset_runtime_state()") \
		.is_equal(2)

	# Cleanup
	player.queue_free()
	level.queue_free()
