# Tests d'intégration Story-006 — Complete reset on reload (EC-12 + quit-to-menu)
# Couvre AC-LVL-9 (re-load reset _current_room_index) et AC-LVL-42 (quit-to-menu
# fresh state) + edge case "re-load 3× = pas de leak cumulatif".
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Fixture : tests/fixtures/levels/test_etage_01.tscn et test_etage_02.tscn.
#
# Stratégie : `_current_room_index` est muté en debug par écriture directe (story-007
# introduira l'API publique via signal `room_entered`). Précédent story-004
# `_simulate_load_elapsed_ms` — pattern test-only debug field-write accepté.
#
# Note ADR-0007 D-8 : Level reset SON propre state ; progression GSM (secrets, kills)
# hors scope cette story (owned par story-007+ GSM).

extends GdUnitTestSuite

const _FIXTURE_PATH_TEMPLATE: String = "res://tests/fixtures/levels/test_etage_%02d.tscn"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Crée un LevelSystemScript avec la fixture de test et l'attache au scene tree.
func _make_level() -> LevelSystemScript:
	var level: LevelSystemScript = LevelSystemScript.new()
	level.scene_path_template = _FIXTURE_PATH_TEMPLATE
	add_child(level)
	return level


## Charge l'étage spécifié et pump explicitement jusqu'à ACTIVE.
## En headless GdUnit4, await physics_frame ne pump pas systématiquement le
## `_process` / `_physics_process` du level — on les call directement.
func _load_and_wait(level: LevelSystemScript, etage_id: int) -> void:
	level.load_etage(etage_id)
	for i: int in range(50):
		if level.get_state() == LevelSystemScript.LevelState.ACTIVE:
			break
		level._process(0.0)
		level._physics_process(0.0)
		await get_tree().physics_frame


## Décharge le niveau courant et force la transition UNLOADING → UNLOADED.
func _unload_and_wait(level: LevelSystemScript) -> void:
	level.unload_current()
	level._physics_process(0.0)  # force commit UNLOADING → UNLOADED

# ---------------------------------------------------------------------------
# AC-LVL-9 — Re-load après unload reset complètement
# ---------------------------------------------------------------------------

## Vérifie que :
##   1. Charger etage 1 → state ACTIVE, _current_room_index = -1 (default)
##   2. Simuler progression : `_current_room_index = 2` (mute manuel pour test)
##   3. unload_current + tick physique → state UNLOADED
##   4. Re-load_etage(1) → state ACTIVE, `get_current_room_index() == -1` (reset OK)
##   5. `get_current_etage_id() == 1` (préservé après re-load)
##   6. `get_player_start() != Vector3.ZERO` (re-discovery OK depuis fresh PackedScene)
## Couvre AC-LVL-9.
func test_reload_same_etage_resets_room_index() -> void:
	# Arrange — load etage 1 (état ACTIVE)
	var level: LevelSystemScript = _make_level()
	await _load_and_wait(level, 1)

	assert_int(level.get_state()) \
		.override_failure_message("Precondition: état doit être ACTIVE après 1er load") \
		.is_equal(LevelSystemScript.LevelState.ACTIVE)
	assert_int(level.get_current_room_index()) \
		.override_failure_message("Precondition: _current_room_index init à -1") \
		.is_equal(-1)

	var initial_player_start: Vector3 = level.get_player_start()

	# Act 1 — simuler progression (room 3 = index 2)
	level._current_room_index = 2

	# Act 2 — unload + tick physique (UNLOADING → UNLOADED)
	await _unload_and_wait(level)

	assert_int(level.get_state()) \
		.override_failure_message("AC-LVL-9: état doit être UNLOADED après unload + 1 tick physics") \
		.is_equal(LevelSystemScript.LevelState.UNLOADED)
	assert_int(level.get_current_room_index()) \
		.override_failure_message("AC-LVL-9: _current_room_index reset à -1 par UNLOADING→UNLOADED helper") \
		.is_equal(-1)

	# Act 3 — re-load même etage (validation AC-LVL-9 cœur)
	await _load_and_wait(level, 1)

	# Assert — fresh state complet
	assert_int(level.get_state()) \
		.override_failure_message("AC-LVL-9: état doit être ACTIVE après re-load") \
		.is_equal(LevelSystemScript.LevelState.ACTIVE)
	assert_int(level.get_current_etage_id()) \
		.override_failure_message("AC-LVL-9: get_current_etage_id() == 1 après re-load") \
		.is_equal(1)
	assert_int(level.get_current_room_index()) \
		.override_failure_message("AC-LVL-9 cœur: _current_room_index == -1 après re-load (reset)") \
		.is_equal(-1)
	assert_vector(level.get_player_start()) \
		.override_failure_message("AC-LVL-9: player_start re-découvert depuis fresh PackedScene instance") \
		.is_equal(initial_player_start)

	# Cleanup
	await _unload_and_wait(level)
	level.queue_free()


## Edge case AC-LVL-9 : load_etage(2) après unload etage 1 = même comportement reset.
## Vérifie que le reset s'applique aussi en switch d'etage_id (pas seulement re-load identique).
func test_reload_different_etage_resets_room_index() -> void:
	# Arrange — load etage 1, set room_index, unload
	var level: LevelSystemScript = _make_level()
	await _load_and_wait(level, 1)
	level._current_room_index = 4
	await _unload_and_wait(level)

	# Act — load etage 2 (different etage)
	await _load_and_wait(level, 2)

	# Assert — reset même en switch d'etage
	assert_int(level.get_current_etage_id()) \
		.override_failure_message("AC-LVL-9 edge: load_etage(2) après unload(1) → etage_id = 2") \
		.is_equal(2)
	assert_int(level.get_current_room_index()) \
		.override_failure_message("AC-LVL-9 edge: _current_room_index reset même en switch etage") \
		.is_equal(-1)

	# Cleanup
	await _unload_and_wait(level)
	level.queue_free()

# ---------------------------------------------------------------------------
# AC-LVL-42 — Quit-to-menu puis re-load fresh state (EC-12)
# ---------------------------------------------------------------------------

## Simule scénario EC-12 : reach room 5, quit-to-menu (unload), re-load stage 1.
## Note : GSM n'existe pas encore (story-007+) — `quit` simulé via `unload_current()`
## direct. Le scope de cette story = Level reset SON propre state (ADR-0007 D-8).
##   - reach room 5 → `_current_room_index = 4`
##   - quit (unload) → state UNLOADED, room_index reset
##   - re-load stage 1 → fresh state vérifié sur tous les champs Level-owned
##   - assertion node count : tree stable ± 5 nodes (pas de leak orphan)
## Couvre AC-LVL-42 (Level scope ; progression GSM hors scope).
func test_quit_to_menu_then_reload_fresh_state() -> void:
	# Arrange — load etage 1 + simuler reach room 5
	var level: LevelSystemScript = _make_level()
	await _load_and_wait(level, 1)
	level._current_room_index = 4  # 0-indexed : room 5

	var node_count_baseline: int = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)

	# Act — quit-to-menu simulé (unload) puis re-load stage 1
	await _unload_and_wait(level)
	await _load_and_wait(level, 1)

	# Attendre 2 frames pour stabilisation tree (queue_free deferred + add_child)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var node_count_after_reload: int = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)

	# Assert — fresh state Level-owned
	assert_int(level.get_state()) \
		.override_failure_message("AC-LVL-42: état doit être ACTIVE après re-load") \
		.is_equal(LevelSystemScript.LevelState.ACTIVE)
	assert_int(level.get_current_room_index()) \
		.override_failure_message("AC-LVL-42: _current_room_index == -1 après quit + reload") \
		.is_equal(-1)
	assert_int(level.get_current_etage_id()) \
		.override_failure_message("AC-LVL-42: _current_etage_id == 1 après reload") \
		.is_equal(1)

	# Assert — tree count stable (tolérance ± 5 nodes pour internal Godot transients)
	var delta: int = abs(node_count_after_reload - node_count_baseline)
	assert_int(delta) \
		.override_failure_message(
			"AC-LVL-42: node count delta = %d (tolérance ± 5) — possible leak orphan ?" % delta
		) \
		.is_less_equal(5)

	# Cleanup
	await _unload_and_wait(level)
	level.queue_free()


## Edge case AC-LVL-42 : re-load 3× consécutif = tree count stable (pas de leak cumulatif).
## Vérifie que la séquence unload/load répétée ne fait pas grandir la mémoire.
func test_repeated_reload_no_node_leak() -> void:
	# Arrange — premier load + baseline
	var level: LevelSystemScript = _make_level()
	await _load_and_wait(level, 1)
	await get_tree().physics_frame  # stabilisation
	var baseline: int = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)

	# Act — 3 cycles unload/load consécutifs
	for i in 3:
		await _unload_and_wait(level)
		await _load_and_wait(level, 1)
		await get_tree().physics_frame

	var final_count: int = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)

	# Assert — tree stable (tolérance ± 10 sur 3 cycles, ~3/cycle)
	var delta: int = abs(final_count - baseline)
	assert_int(delta) \
		.override_failure_message(
			"EC-12 leak: node count delta = %d après 3 reload (tolérance ± 10) — leak cumulatif ?" % delta
		) \
		.is_less_equal(10)

	# Cleanup
	await _unload_and_wait(level)
	level.queue_free()
