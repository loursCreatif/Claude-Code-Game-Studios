## Tests de sanity pour AutoloadResetTestSuite.
##
## Vérifie que snapshot/restore fonctionne correctement pour les autoloads
## couverts par TD-010. Ces 2 tests prouvent le mécanisme sans dépendance
## sur les 4 suites pollution cible.
##
## Story source : docs/tech-debt-register.md TD-010
## Plan : production/tech-debt/story-w4-test-infra-autoload-reset-between-suites.md

extends "res://tests/helpers/autoload_reset_test_suite.gd"


# ---------------------------------------------------------------------------
# Sanity 1 — GSM state + Engine.time_scale restaurés après mutation
# ---------------------------------------------------------------------------

## Prouve que _restore_autoload_state() restaure GSM._current_state et
## Engine.time_scale à leurs valeurs pré-snapshot même si mutées pendant un test.
func test_snapshot_restore_gsm_state_and_time_scale() -> void:
	# Arrange — capture l'état initial via before_test() (déjà exécuté)
	var state_before: int = _snap_gsm_state
	var scale_before: float = _snap_time_scale

	# Act — muter GSM et time_scale comme une suite pollution le ferait
	GameStateManager._current_state = GameStateManager.State.PAUSED
	Engine.time_scale = 0.5

	# Vérifier que les mutations sont bien en place
	assert_int(GameStateManager.get_current_state()) \
		.override_failure_message("Precondition: GSM must be PAUSED after mutation") \
		.is_equal(GameStateManager.State.PAUSED)
	assert_float(Engine.time_scale) \
		.override_failure_message("Precondition: time_scale must be 0.5 after mutation") \
		.is_equal_approx(0.5, 0.001)

	# Act — restaurer explicitement
	_restore_autoload_state()

	# Assert — valeurs pré-snapshot restaurées
	assert_int(GameStateManager.get_current_state()) \
		.override_failure_message(
			"AutoloadReset: GSM state must be restored to pre-snapshot value %d — got %d"
			% [state_before, GameStateManager.get_current_state()]
		) \
		.is_equal(state_before)

	assert_float(Engine.time_scale) \
		.override_failure_message(
			"AutoloadReset: time_scale must be restored to pre-snapshot value %f — got %f"
			% [scale_before, Engine.time_scale]
		) \
		.is_equal_approx(scale_before, 0.001)


# ---------------------------------------------------------------------------
# Sanity 2 — AudioSystem._2d_index restauré après mutation
# ---------------------------------------------------------------------------

## Prouve que _restore_autoload_state() restaure AudioSystem._2d_index
## même si muté à mi-suite (pollution round-robin index).
func test_snapshot_restore_audio_2d_index() -> void:
	# Arrange — index snapshot par before_test()
	var index_before: int = _snap_audio_2d_index

	var audio: Node = _get_autoload_node(&"AudioSystem")
	if audio == null:
		# Autoload absent (suite isolée sans projet complet) — skip gracieux
		return

	# Act — muter l'index comme no_alloc_play_2d_test le ferait
	var mutated_index: int = (index_before + 3) % 5
	audio._2d_index = mutated_index

	assert_int(audio._2d_index) \
		.override_failure_message("Precondition: _2d_index must be mutated") \
		.is_equal(mutated_index)

	# Act — restaurer
	_restore_autoload_state()

	# Assert — index initial restauré
	assert_int(audio._2d_index) \
		.override_failure_message(
			"AutoloadReset: AudioSystem._2d_index must be restored to %d — got %d"
			% [index_before, audio._2d_index]
		) \
		.is_equal(index_before)
