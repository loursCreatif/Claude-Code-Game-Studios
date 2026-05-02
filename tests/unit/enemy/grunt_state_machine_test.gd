# Unit tests for Story 001 — Grunt state machine + die() idempotent + is_dead() getter.
# Couvre AC-ENM-01 (die ALIVE → DYING + signal), AC-ENM-02 (idempotent DYING),
# AC-ENM-03 (idempotent DEAD), AC-ENM-07 (physics disabled velocity zero),
# AC-ENM-07b (is_dead per state).
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
# AC-ENM-01 — die() ALIVE → DYING + signal SYNC
# ---------------------------------------------------------------------------

func test_die_alive_transitions_to_dying_emits_signal() -> void:
	# Arrange — grunt instancié en ALIVE par défaut.
	assert_int(_grunt._state) \
		.override_failure_message("Setup: grunt doit être ALIVE après _ready") \
		.is_equal(Grunt.State.ALIVE)

	var emit_count: Array = [0]
	var emitted_node: Array = [null]
	var emitted_position: Array = [Vector3.ZERO]
	_grunt.enemy_killed.connect(func(node: Node, pos: Vector3) -> void:
		emit_count[0] += 1
		emitted_node[0] = node
		emitted_position[0] = pos
	)

	# Act
	_grunt.die()

	# Assert
	assert_int(_grunt._state) \
		.override_failure_message("AC-ENM-01: state doit être DYING post-die()") \
		.is_equal(Grunt.State.DYING)
	assert_int(emit_count[0]) \
		.override_failure_message("AC-ENM-01: enemy_killed signal doit être émis exactement 1×") \
		.is_equal(1)
	assert_object(emitted_node[0]) \
		.override_failure_message("AC-ENM-01: payload node doit être self") \
		.is_equal(_grunt)
	assert_vector(emitted_position[0]) \
		.override_failure_message("AC-ENM-01: payload position doit être global_position") \
		.is_equal_approx(_grunt.global_position, Vector3.ONE * 0.0001)


# ---------------------------------------------------------------------------
# AC-ENM-02 — die() DYING idempotent (no double emit, no tween reset)
# ---------------------------------------------------------------------------

func test_die_dying_idempotent_no_double_emit() -> void:
	# Arrange — passer en DYING.
	var emit_count: Array = [0]
	_grunt.enemy_killed.connect(func(_node: Node, _pos: Vector3) -> void:
		emit_count[0] += 1
	)
	_grunt.die()
	assert_int(_grunt._state).is_equal(Grunt.State.DYING)
	assert_int(emit_count[0]).is_equal(1)
	var first_tween_ref: Tween = _grunt._death_tween

	# Act — 2ème appel die() pendant DYING.
	_grunt.die()

	# Assert — state inchangé, signal pas re-émis, tween pas reset.
	assert_int(_grunt._state) \
		.override_failure_message("AC-ENM-02: state doit rester DYING") \
		.is_equal(Grunt.State.DYING)
	assert_int(emit_count[0]) \
		.override_failure_message("AC-ENM-02: signal ne doit PAS être ré-émis") \
		.is_equal(1)
	assert_object(_grunt._death_tween) \
		.override_failure_message("AC-ENM-02: tween en cours ne doit PAS être reset") \
		.is_equal(first_tween_ref)


# ---------------------------------------------------------------------------
# AC-ENM-03 — die() DEAD idempotent (no-op)
# ---------------------------------------------------------------------------

func test_die_dead_idempotent_no_op() -> void:
	# Arrange — force DEAD (skip tween).
	_grunt._state = Grunt.State.DEAD
	var emit_count: Array = [0]
	_grunt.enemy_killed.connect(func(_node: Node, _pos: Vector3) -> void:
		emit_count[0] += 1
	)

	# Act
	_grunt.die()

	# Assert
	assert_int(_grunt._state) \
		.override_failure_message("AC-ENM-03: state doit rester DEAD") \
		.is_equal(Grunt.State.DEAD)
	assert_int(emit_count[0]) \
		.override_failure_message("AC-ENM-03: aucun signal sur grunt déjà mort") \
		.is_equal(0)


# ---------------------------------------------------------------------------
# AC-ENM-07 — physics disabled + velocity zero (Rule 10)
# ---------------------------------------------------------------------------

func test_grunt_physics_disabled_velocity_zero() -> void:
	# Assert
	assert_bool(_grunt.is_physics_processing()) \
		.override_failure_message("AC-ENM-07: _physics_process doit être désactivé (Rule 10)") \
		.is_false()
	assert_vector(_grunt.velocity) \
		.override_failure_message("AC-ENM-07: velocity doit être ZERO au _ready") \
		.is_equal(Vector3.ZERO)


# ---------------------------------------------------------------------------
# AC-ENM-07b — is_dead() getter per state (DYING+DEAD = dead)
# ---------------------------------------------------------------------------

func test_is_dead_getter_per_state() -> void:
	# ALIVE
	_grunt._state = Grunt.State.ALIVE
	assert_bool(_grunt.is_dead()) \
		.override_failure_message("AC-ENM-07b: ALIVE → is_dead() == false") \
		.is_false()

	# DYING (Checkpoint sémantique : un kill mid-tween est capturé)
	_grunt._state = Grunt.State.DYING
	assert_bool(_grunt.is_dead()) \
		.override_failure_message("AC-ENM-07b: DYING → is_dead() == true") \
		.is_true()

	# DEAD
	_grunt._state = Grunt.State.DEAD
	assert_bool(_grunt.is_dead()) \
		.override_failure_message("AC-ENM-07b: DEAD → is_dead() == true") \
		.is_true()
