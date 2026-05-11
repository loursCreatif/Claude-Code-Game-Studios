## Tests de sanity pour AutoloadResetHelper.
##
## Vérifie que snapshot/restore fonctionne correctement pour les autoloads
## couverts par TD-010. Ces tests prouvent le mécanisme sans dépendance
## sur les 4 suites pollution cible.
##
## Story source : docs/tech-debt-register.md TD-010
## Plan : production/tech-debt/story-w4-test-infra-autoload-reset-between-suites.md

extends GdUnitTestSuite

const AutoloadResetHelper := preload("res://tests/helpers/autoload_reset_helper.gd")


# ---------------------------------------------------------------------------
# Sanity 1 — GSM state + Engine.time_scale restaurés après mutation
# ---------------------------------------------------------------------------

## Prouve que AutoloadResetHelper.restore() restaure GSM._current_state et
## Engine.time_scale à leurs valeurs pré-snapshot même si mutées pendant un test.
func test_snapshot_restore_gsm_state_and_time_scale() -> void:
	# Arrange — capture l'état initial
	var snap: Dictionary = AutoloadResetHelper.snapshot(get_tree())
	var state_before: int = snap.gsm_state
	var scale_before: float = snap.time_scale

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
	AutoloadResetHelper.restore(get_tree(), snap)

	# Assert — valeurs pré-snapshot restaurées
	assert_int(GameStateManager.get_current_state()) \
		.override_failure_message(
			"AutoloadResetHelper: GSM state must be restored to pre-snapshot value %d — got %d"
			% [state_before, GameStateManager.get_current_state()]
		) \
		.is_equal(state_before)

	assert_float(Engine.time_scale) \
		.override_failure_message(
			"AutoloadResetHelper: time_scale must be restored to pre-snapshot value %f — got %f"
			% [scale_before, Engine.time_scale]
		) \
		.is_equal_approx(scale_before, 0.001)


# ---------------------------------------------------------------------------
# Sanity 2 — AudioSystem._2d_index restauré après mutation
# ---------------------------------------------------------------------------

## Prouve que AutoloadResetHelper.restore() restaure AudioSystem._2d_index
## même si muté à mi-suite (pollution round-robin index).
func test_snapshot_restore_audio_2d_index() -> void:
	var audio: Node = get_tree().root.get_node_or_null(^"AudioSystem")
	if audio == null:
		# AudioSystem autoload absent — skip gracieux (e.g. test unitaire isolé).
		return

	# Arrange
	var snap: Dictionary = AutoloadResetHelper.snapshot(get_tree())
	var idx_before: int = snap[&"audio_2d_index"]

	# Act — muter l'index round-robin
	audio._2d_index = (idx_before + 3) % 5

	assert_int(audio._2d_index) \
		.override_failure_message("Precondition: _2d_index must differ after mutation") \
		.is_not_equal(idx_before)

	# Act — restaurer
	AutoloadResetHelper.restore(get_tree(), snap)

	# Assert
	assert_int(audio._2d_index) \
		.override_failure_message(
			"AutoloadResetHelper: AudioSystem._2d_index must be restored to %d — got %d"
			% [idx_before, audio._2d_index]
		) \
		.is_equal(idx_before)


# ---------------------------------------------------------------------------
# Sanity 3 — restore() no-op sur snap vide (defensive)
# ---------------------------------------------------------------------------

## Prouve que restore() ne crash pas si appelé avec un Dictionary vide.
## Cas : test qui a oublié de snapshot, ou snap réinitialisé manuellement.
func test_restore_empty_snap_is_noop() -> void:
	var time_scale_before: float = Engine.time_scale
	var empty: Dictionary = {}

	AutoloadResetHelper.restore(get_tree(), empty)

	assert_float(Engine.time_scale) \
		.override_failure_message("restore(empty) must be no-op — time_scale should not change") \
		.is_equal_approx(time_scale_before, 0.0001)
