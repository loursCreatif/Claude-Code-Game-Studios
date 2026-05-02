# Unit tests for Story 001 — _restore_from_snapshot (Checkpoint System contract).
# Couvre AC-ENM-18 (DYING + restore(false) → ALIVE direct, tween killed),
# AC-ENM-18b (DYING + restore(true) → DEAD direct, no signal re-emit).
#
# Source : Enemy GDD Rule 13 + EC-ENM-11/12/13 (Checkpoint snapshot restore semantics).
#
# Story Type : Logic. Test Evidence path : tests/unit/enemy/.
# Framework : GdUnit4 (extends GdUnitTestSuite).

extends GdUnitTestSuite


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
	if _grunt != null and is_instance_valid(_grunt):
		_grunt.queue_free()
	_grunt = null
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# AC-ENM-18 — DYING + restore(false) → ALIVE direct, tween killed
# ---------------------------------------------------------------------------

func test_restore_snapshot_false_during_dying_kills_tween() -> void:
	# Arrange — passer en DYING (tween en cours).
	_grunt.die()
	assert_int(_grunt._state).is_equal(Grunt.State.DYING)
	assert_object(_grunt._death_tween) \
		.override_failure_message("Setup: tween doit être actif post-die()") \
		.is_not_null()
	var tween_ref: Tween = _grunt._death_tween
	assert_bool(tween_ref.is_valid()) \
		.override_failure_message("Setup: tween doit être valid post-die()") \
		.is_true()

	# Act
	_grunt._restore_from_snapshot(false)

	# Assert
	assert_int(_grunt._state) \
		.override_failure_message("AC-ENM-18: state doit être ALIVE post-restore(false)") \
		.is_equal(Grunt.State.ALIVE)
	# Tween reference cleared dans _restore_from_snapshot.
	assert_object(_grunt._death_tween) \
		.override_failure_message("AC-ENM-18: _death_tween reference doit être null post-restore") \
		.is_null()
	# tween_ref.kill() appelé → is_valid() retourne false sur le tween freed.
	assert_bool(tween_ref.is_valid()) \
		.override_failure_message("AC-ENM-18: tween en cours doit être killed") \
		.is_false()


# ---------------------------------------------------------------------------
# AC-ENM-18b — DYING + restore(true) → DEAD direct, NO signal re-emit
# ---------------------------------------------------------------------------

func test_restore_snapshot_true_during_dying_no_signal_re_emit() -> void:
	# Arrange — passer en DYING.
	var emit_count: Array = [0]
	_grunt.enemy_killed.connect(func(_node: Node, _pos: Vector3) -> void:
		emit_count[0] += 1
	)
	_grunt.die()
	assert_int(emit_count[0]) \
		.override_failure_message("Setup: signal émis 1× post-die() initial") \
		.is_equal(1)
	assert_int(_grunt._state).is_equal(Grunt.State.DYING)

	# Act — restore vers DEAD direct (skip natural DYING→DEAD transition).
	_grunt._restore_from_snapshot(true)

	# Assert
	assert_int(_grunt._state) \
		.override_failure_message("AC-ENM-18b: state doit être DEAD post-restore(true)") \
		.is_equal(Grunt.State.DEAD)
	assert_int(emit_count[0]) \
		.override_failure_message("AC-ENM-18b: signal NE doit PAS être ré-émis (kill déjà crédité)") \
		.is_equal(1)
	assert_object(_grunt._death_tween) \
		.override_failure_message("AC-ENM-18b: tween reference cleared post-restore") \
		.is_null()


# ---------------------------------------------------------------------------
# Bonus — restore depuis ALIVE (no-op tween, simple state change)
# ---------------------------------------------------------------------------

func test_restore_snapshot_true_from_alive_transitions_directly_to_dead() -> void:
	# Arrange — grunt en ALIVE (default).
	assert_int(_grunt._state).is_equal(Grunt.State.ALIVE)
	var emit_count: Array = [0]
	_grunt.enemy_killed.connect(func(_node: Node, _pos: Vector3) -> void:
		emit_count[0] += 1
	)

	# Act
	_grunt._restore_from_snapshot(true)

	# Assert
	assert_int(_grunt._state) \
		.override_failure_message("Bonus: ALIVE + restore(true) → DEAD direct") \
		.is_equal(Grunt.State.DEAD)
	assert_int(emit_count[0]) \
		.override_failure_message("Bonus: pas de signal sur restore (snapshot, pas kill organique)") \
		.is_equal(0)


func test_restore_snapshot_false_from_dead_transitions_back_to_alive() -> void:
	# Arrange — force DEAD.
	_grunt._state = Grunt.State.DEAD

	# Act — Player respawn depuis checkpoint où grunt n'était pas encore tué.
	_grunt._restore_from_snapshot(false)

	# Assert
	assert_int(_grunt._state) \
		.override_failure_message("Bonus: DEAD + restore(false) → ALIVE (Pillar 3 reload boundary)") \
		.is_equal(Grunt.State.ALIVE)
