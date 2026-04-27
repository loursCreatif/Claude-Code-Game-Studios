# Tests d'intégration Story-005 — EtageExitTrigger + signal etage_completed
# + transition ACTIVE → UNLOADING fire-once (connexion Area3D.body_entered auto-wirée).
# Couvre AC-LVL-24 (fire-once semantics) et AC-LVL-24 edge-EC6 (no back-out possible).
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Fixture : tests/fixtures/levels/test_etage_05.tscn
#   - PlayerStart Marker3D à (0, 0, 0)
#   - EtageExitTrigger Area3D (BoxShape3D 4×4×4) à (20, 2, 20)
#   - collision_layer=16 (LAYER_INTERACTIVE=5), collision_mask=1 (LAYER_PLAYER=1)
#
# Stratégie : _connect_etage_exit_trigger (story-005) auto-wire Area3D.body_entered →
# _on_etage_exit_body_entered lors du passage LOADING→ACTIVE. Les tests téléportent
# un CharacterBody3D "player" dans la zone et attendent les frames physiques pour que
# body_entered se déclenche naturellement.

extends GdUnitTestSuite

const _FIXTURE_PATH_TEMPLATE: String = "res://tests/fixtures/levels/test_etage_%02d.tscn"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Crée un LevelSystemScript avec la fixture test_etage_05 et l'attache au scene tree.
## scene_path_template défini AVANT add_child() (DI principle, miroir story-004).
func _make_level() -> LevelSystemScript:
	var level: LevelSystemScript = LevelSystemScript.new()
	level.scene_path_template = _FIXTURE_PATH_TEMPLATE
	add_child(level)
	return level


## Crée un CharacterBody3D "player" avec CollisionShape3D et collision layer LAYER_PLAYER.
## Attache au scene tree de la test suite.
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
# AC-LVL-24 — etage_completed fires-once + transition ACTIVE → UNLOADING
# ---------------------------------------------------------------------------

## Vérifie que :
##   1. Player entre dans EtageExitTrigger → signal etage_completed(5) émis exactement 1×
##   2. État transitionne vers UNLOADING (T-3 ADR-0005 : emit avant unload_current())
##   3. Re-entry après 1er trigger (state = UNLOADING) → aucun nouveau signal
##
## Source : TR-lvl-023, AC-LVL-24, ADR-0005 D-4 + T-3 + D-8.
func test_etage_completed_fires_once_and_transitions_to_unloading() -> void:
	# Arrange — level ACTIVE avec etage 5 chargé
	var level: LevelSystemScript = _make_level()
	level.load_etage(5)
	await await_signal_on(level, "level_active", [], 3000)

	assert_int(level.get_state()) \
		.override_failure_message("Precondition: état doit être ACTIVE avant trigger exit") \
		.is_equal(LevelSystemScript.LevelState.ACTIVE)

	var player: CharacterBody3D = _make_player_body()

	var etage_completed_count: int = 0
	var etage_completed_id: int = -1
	level.etage_completed.connect(func(eid: int) -> void:
		etage_completed_count += 1
		etage_completed_id = eid
	)

	# Act 1 — téléporter player dans EtageExitTrigger à (20, 2, 20) et attendre 2 frames
	player.global_position = Vector3(20, 2, 20)
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Assert — signal émis exactement 1× avec etage_id = 5
	assert_int(etage_completed_count) \
		.override_failure_message("AC-LVL-24: etage_completed doit être émis exactement 1× après entrée dans trigger") \
		.is_equal(1)
	assert_int(etage_completed_id) \
		.override_failure_message("AC-LVL-24: etage_completed.etage_id doit être 5 (current_etage_id)") \
		.is_equal(5)

	# Assert — état en UNLOADING ou UNLOADED (transition T-3 enchaînée)
	var state_after: LevelSystemScript.LevelState = level.get_state()
	assert_bool(
		state_after == LevelSystemScript.LevelState.UNLOADING
		or state_after == LevelSystemScript.LevelState.UNLOADED
	) \
		.override_failure_message(
			"AC-LVL-24: état doit être UNLOADING ou UNLOADED après etage_completed (got: %s)"
			% LevelSystemScript.LevelState.keys()[state_after]
		) \
		.is_true()

	# Act 2 — re-entry : sortir puis ré-entrer dans le trigger (state != ACTIVE → ignoré)
	player.global_position = Vector3(0, 0, 0)
	await get_tree().physics_frame
	player.global_position = Vector3(20, 2, 20)
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Assert — toujours exactement 1 emission (idempotence fire-once)
	assert_int(etage_completed_count) \
		.override_failure_message("AC-LVL-24: etage_completed ne doit PAS être ré-émis sur re-entry (state != ACTIVE)") \
		.is_equal(1)

	# Cleanup
	player.queue_free()
	level.queue_free()

# ---------------------------------------------------------------------------
# AC-LVL-24 edge — Body non-player ignoré par le trigger
# ---------------------------------------------------------------------------

## Vérifie qu'un body CharacterBody3D NON dans le groupe "player" n'émet pas
## etage_completed et ne change pas l'état (guard body.is_in_group("player")).
## Couvre QA Test Case "body non-player (no group) = ignoré".
func test_etage_completed_ignores_non_player_body() -> void:
	# Arrange — level ACTIVE, body sans groupe "player"
	var level: LevelSystemScript = _make_level()
	level.load_etage(5)
	await await_signal_on(level, "level_active", [], 3000)

	var enemy: CharacterBody3D = CharacterBody3D.new()
	# Pas de add_to_group("player") — simule un enemy/projectile
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	enemy.add_child(shape)
	enemy.set_collision_layer_value(CollisionLayers.LAYER_PLAYER, true)
	add_child(enemy)

	var etage_completed_count: int = 0
	level.etage_completed.connect(func(_eid: int) -> void:
		etage_completed_count += 1
	)

	# Act — téléporter le body non-player dans la zone et attendre 2 frames
	enemy.global_position = Vector3(20, 2, 20)
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Assert — aucun signal émis, état inchangé
	assert_int(etage_completed_count) \
		.override_failure_message("AC-LVL-24: etage_completed ne doit PAS être émis pour un body non-player") \
		.is_equal(0)
	assert_int(level.get_state()) \
		.override_failure_message("AC-LVL-24: état doit rester ACTIVE après trigger non-player") \
		.is_equal(LevelSystemScript.LevelState.ACTIVE)

	# Cleanup
	enemy.queue_free()
	level.queue_free()

# ---------------------------------------------------------------------------
# AC-LVL-24 edge-EC6 — No back-out possible (transition atomique ACTIVE → UNLOADING)
# ---------------------------------------------------------------------------

## Vérifie qu'après un 1er trigger valide, la transition ACTIVE → UNLOADING est atomique
## et non annulable (EC-6 "no back-out possible") :
##   - 1er trigger → etage_completed(5) émis, state = UNLOADING (atomique)
##   - Sortie immédiate (même tick) → state déjà UNLOADING, pas cancellable
##   - Re-entry pendant UNLOADING → ignoré (guard state != ACTIVE)
##   - Re-entry après UNLOADED (post-tick physique) → ignoré (state != ACTIVE)
##
## Source : AC-LVL-24 edge-EC6, ADR-0005 D-8.
func test_etage_completed_no_back_out_possible() -> void:
	# Arrange
	var level: LevelSystemScript = _make_level()
	level.load_etage(5)
	await await_signal_on(level, "level_active", [], 3000)

	var player: CharacterBody3D = _make_player_body()

	var etage_completed_count: int = 0
	level.etage_completed.connect(func(_eid: int) -> void:
		etage_completed_count += 1
	)

	# Act 1 — player entre dans trigger → 1er trigger valide
	player.global_position = Vector3(20, 2, 20)
	await get_tree().physics_frame

	# Assert — transition atomique : state = UNLOADING ou UNLOADED, count = 1
	assert_int(etage_completed_count) \
		.override_failure_message("EC-6: 1er trigger doit émettre etage_completed exactement 1×") \
		.is_equal(1)

	var state_after_trigger: LevelSystemScript.LevelState = level.get_state()
	assert_bool(
		state_after_trigger == LevelSystemScript.LevelState.UNLOADING
		or state_after_trigger == LevelSystemScript.LevelState.UNLOADED
	) \
		.override_failure_message(
			"EC-6: state doit être UNLOADING ou UNLOADED après 1er trigger (got: %s)"
			% LevelSystemScript.LevelState.keys()[state_after_trigger]
		) \
		.is_true()

	# Act 2 — sortie immédiate (même tick physique) : state déjà UNLOADING → back-out impossible
	player.global_position = Vector3(0, 0, 0)
	await get_tree().physics_frame

	# State doit rester UNLOADING / UNLOADED malgré la sortie
	var state_after_backout: LevelSystemScript.LevelState = level.get_state()
	assert_bool(
		state_after_backout == LevelSystemScript.LevelState.UNLOADING
		or state_after_backout == LevelSystemScript.LevelState.UNLOADED
	) \
		.override_failure_message(
			"EC-6: state ne doit PAS revenir à ACTIVE après back-out (got: %s)"
			% LevelSystemScript.LevelState.keys()[state_after_backout]
		) \
		.is_true()

	# count reste 1 (pas de nouvel emit)
	assert_int(etage_completed_count) \
		.override_failure_message("EC-6: etage_completed ne doit PAS être ré-émis sur back-out") \
		.is_equal(1)

	# Act 3 — re-entry après UNLOADED (après tick physique UNLOADING → UNLOADED)
	await get_tree().physics_frame
	player.global_position = Vector3(20, 2, 20)
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Assert — toujours 1 émission (state != ACTIVE bloque re-trigger)
	assert_int(etage_completed_count) \
		.override_failure_message("EC-6: pas de 2e émission après UNLOADED (state != ACTIVE)") \
		.is_equal(1)

	# Cleanup
	player.queue_free()
	level.queue_free()
