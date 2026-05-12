# Unit tests for Story 002 — LaserCone body_entered handler logic (AC-ENM-04, AC-ENM-05).
# Verifies handler calls Player.die() when ALIVE + group "player", skips when DYING/DEAD.
#
# Pattern : test handler logic directly via `_on_laser_cone_body_entered(body)` — bypass
# physics simulation. La connexion signal elle-même est testée par grunt_collision_layers_test.
#
# Story Type : Logic. Test Evidence path : tests/unit/enemy/.
# Framework : GdUnit4 (extends GdUnitTestSuite).

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Mock Player — minimal stub avec die() + group "player"
# ---------------------------------------------------------------------------

class MockPlayer extends CharacterBody3D:
	var die_call_count: int = 0

	func die() -> void:
		die_call_count += 1


# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------

var _grunt: Grunt = null
var _mock_player: MockPlayer = null


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func before_test() -> void:
	_grunt = Grunt.new()
	add_child(_grunt)
	await get_tree().process_frame

	_mock_player = MockPlayer.new()
	_mock_player.add_to_group("player")
	add_child(_mock_player)
	await get_tree().process_frame


func after_test() -> void:
	if _mock_player != null and is_instance_valid(_mock_player):
		_mock_player.queue_free()
	_mock_player = null
	if _grunt != null and is_instance_valid(_grunt):
		_grunt.queue_free()
	_grunt = null
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# AC-ENM-04 — ALIVE + Player in group → Player.die() called 1×
# ---------------------------------------------------------------------------

func test_laser_handler_calls_player_die_when_alive() -> void:
	# Arrange — grunt ALIVE par défaut.
	assert_int(_grunt._state).is_equal(Grunt.State.ALIVE)
	assert_int(_mock_player.die_call_count).is_equal(0)

	# Act
	_grunt._on_laser_cone_body_entered(_mock_player)

	# Assert
	assert_int(_mock_player.die_call_count) \
		.override_failure_message("AC-ENM-04: Player.die() doit être appelé exactement 1×") \
		.is_equal(1)


# ---------------------------------------------------------------------------
# AC-ENM-05 — DYING grunt → handler retourne, pas de Player.die()
# ---------------------------------------------------------------------------

func test_laser_handler_skips_when_dying() -> void:
	# Arrange — force DYING.
	_grunt._state = Grunt.State.DYING

	# Act
	_grunt._on_laser_cone_body_entered(_mock_player)

	# Assert — guard `_state != ALIVE` empêche l'appel.
	assert_int(_mock_player.die_call_count) \
		.override_failure_message("AC-ENM-05: grunt DYING ne doit PAS tuer le Player") \
		.is_equal(0)


func test_laser_handler_skips_when_dead() -> void:
	# Arrange — force DEAD.
	_grunt._state = Grunt.State.DEAD

	# Act
	_grunt._on_laser_cone_body_entered(_mock_player)

	# Assert
	assert_int(_mock_player.die_call_count) \
		.override_failure_message("EC-ENM-4: grunt DEAD ne doit PAS tuer le Player") \
		.is_equal(0)


# ---------------------------------------------------------------------------
# Bonus — body sans group "player" ignoré (anti-friendly-fire)
# ---------------------------------------------------------------------------

func test_laser_handler_ignores_non_player_body() -> void:
	# Arrange — body sans group "player".
	var stranger: CharacterBody3D = CharacterBody3D.new()
	add_child(stranger)
	await get_tree().process_frame

	# Act
	_grunt._on_laser_cone_body_entered(stranger)

	# Assert — pas de crash, pas de side-effect.
	assert_bool(_grunt._state == Grunt.State.ALIVE) \
		.override_failure_message("Bonus: state inchangé sur body non-player") \
		.is_true()

	stranger.queue_free()


# ---------------------------------------------------------------------------
# Bonus — Multi-grunt LaserCone overlap (EC-ENM-5 idempotence Player.die())
# ---------------------------------------------------------------------------

func test_two_grunts_overlap_call_player_die_independently() -> void:
	# Arrange — un second grunt côté à côté.
	var grunt2: Grunt = Grunt.new()
	add_child(grunt2)
	await get_tree().process_frame

	# Act — les deux LaserCone fire sur le Player.
	_grunt._on_laser_cone_body_entered(_mock_player)
	grunt2._on_laser_cone_body_entered(_mock_player)

	# Assert — Player.die() appelé 2× (chaque grunt indépendant ; idempotence côté Player
	# par Movement Rule die() — pas tracking croisé entre grunts).
	assert_int(_mock_player.die_call_count) \
		.override_failure_message("EC-ENM-5: chaque grunt appelle die() indépendamment") \
		.is_equal(2)

	grunt2.queue_free()
