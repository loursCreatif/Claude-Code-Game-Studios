# Unit tests for Story 001 — Death tween wall-clock 150 ms (F-ENM-3).
# Couvre AC-ENM-11 (transition DYING → DEAD post 150 ms wall-clock),
# AC-ENM-12 (tween indépendant de Engine.time_scale = 0.3 slow-mo Combat).
#
# Pattern : await get_tree().create_timer(N).timeout pour wall-clock absolu.
# Tween Grunt utilise `set_ignore_time_scale(true)` (Rule 11.d / F-ENM-3) — donc
# le tween ne ralentit PAS avec Engine.time_scale=0.3 (slow-mo Combat 50 ms).
#
# Story Type : Logic. Test Evidence path : tests/unit/enemy/.
# Framework : GdUnit4 (extends GdUnitTestSuite).

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Buffer au-delà de DEATH_TWEEN_DURATION_MS (150 ms) pour garantir transition
## DYING → DEAD captured par l'assert post-await. 30 ms de marge.
const TWEEN_AWAIT_SEC: float = 0.18


# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------

var _grunt: Grunt = null


# ---------------------------------------------------------------------------
# Lifecycle — hermetic isolation
# ---------------------------------------------------------------------------

func before_test() -> void:
	_grunt = Grunt.new()
	add_child(_grunt)
	await get_tree().process_frame


func after_test() -> void:
	# Restore time_scale au cas où test AC-ENM-12 a échoué avant restore.
	Engine.time_scale = 1.0
	if _grunt != null and is_instance_valid(_grunt):
		_grunt.queue_free()
	_grunt = null
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# AC-ENM-11 — Tween wall-clock 150 ms → DYING → DEAD
# ---------------------------------------------------------------------------

func test_death_tween_completes_in_150ms_wall_clock() -> void:
	# Arrange + Act
	_grunt.die()
	assert_int(_grunt._state).is_equal(Grunt.State.DYING)

	# Wait wall-clock 180 ms (150 ms tween + 30 ms buffer).
	await get_tree().create_timer(TWEEN_AWAIT_SEC).timeout

	# Assert
	assert_int(_grunt._state) \
		.override_failure_message("AC-ENM-11: state doit être DEAD après 180 ms wall-clock") \
		.is_equal(Grunt.State.DEAD)

	# Rule 12 : pas de queue_free() — le nœud existe encore.
	assert_bool(is_instance_valid(_grunt)) \
		.override_failure_message("AC-ENM-11: nœud doit persister (Rule 12 pas de queue_free)") \
		.is_true()


# ---------------------------------------------------------------------------
# AC-ENM-12 — Tween wall-clock indépendant de Engine.time_scale
# ---------------------------------------------------------------------------

func test_death_tween_wall_clock_independent_of_time_scale() -> void:
	# Arrange — simule slow-mo Combat (Engine.time_scale = 0.3) AVANT die().
	Engine.time_scale = 0.3

	# Act
	_grunt.die()
	assert_int(_grunt._state).is_equal(Grunt.State.DYING)

	# Wait wall-clock 180 ms — `create_timer` est SCALE-DEPENDANT par défaut, donc
	# pour mesurer wall-clock on doit attendre `0.18 / 0.3 = 0.6` sec scaled-time
	# OU utiliser `create_timer(0.18, false, false, true)` (4ème arg `ignore_time_scale=true`).
	await get_tree().create_timer(TWEEN_AWAIT_SEC, false, false, true).timeout

	# Restore avant assert (au cas où assert échoue).
	Engine.time_scale = 1.0

	# Assert — tween Grunt utilise set_ignore_time_scale(true), donc DEAD post 150 ms wall-clock
	# absolu indépendamment du Engine.time_scale=0.3.
	assert_int(_grunt._state) \
		.override_failure_message(
			"AC-ENM-12: tween doit être wall-clock 150 ms même avec Engine.time_scale=0.3 — got %d"
			% _grunt._state
		) \
		.is_equal(Grunt.State.DEAD)
