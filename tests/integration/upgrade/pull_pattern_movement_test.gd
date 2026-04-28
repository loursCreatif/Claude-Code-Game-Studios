# Integration test Story-007 — Movement pull pattern 60 Hz.
# Couvre AC-UPG-24(a) BLOCKING + AC-UPG-25 + AC-UPG-26 ADVISORY + AC-UPG-31 + AC-UPG-32.
# AC-UPG-24(b) couvert dans pull_pattern_real_player_test.gd (skip MVP — scène player.tscn).
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Integration — utilise l'autoload Upgrade live + MockMovementReader fixture.

extends GdUnitTestSuite

const _SAVE_KEY: String = "owned_upgrades"


# =============================================================================
# Setup / Teardown — reset autoload state entre tests
# =============================================================================

func before_test() -> void:
	# Reset save state pour pas qu'un boot futur réintroduise un upgrade.
	SaveLoadSystem.save_string_array(_SAVE_KEY, [] as Array[StringName])
	# Reset flags + owned dict (autoload mutable mais pas re-instanciable).
	Upgrade._owned.clear()
	Upgrade.can_air_jump = false
	Upgrade.can_dash = false
	Upgrade.can_wall_run = false


func after_test() -> void:
	SaveLoadSystem.save_string_array(_SAVE_KEY, [] as Array[StringName])
	Upgrade._owned.clear()
	Upgrade.can_air_jump = false
	Upgrade.can_dash = false
	Upgrade.can_wall_run = false
	# Cleanup pause state au cas où un test a oublié.
	get_tree().paused = false


# =============================================================================
# AC-UPG-24 (a) BLOCKING — Mock Movement reader lit flag post-apply
# =============================================================================

## GIVEN apply_upgrade(&"double_jump") avant Player instancié,
## WHEN MockMovementReader spawné + 2× await physics_frame,
## THEN reader.first_tick_can_air_jump == true ET first_tick_can_dash == false.
func test_movement_reader_observes_flag_after_apply() -> void:
	# Arrange
	Upgrade.apply_upgrade(&"double_jump")
	var reader: MockMovementReader = MockMovementReader.new()
	add_child(reader)

	# Act — 2 ticks pour garantir first_tick_observed
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Assert
	assert_bool(reader.first_tick_observed) \
		.override_failure_message("AC-UPG-24(a): reader doit avoir observé son premier tick") \
		.is_true()
	assert_bool(reader.first_tick_can_air_jump) \
		.override_failure_message("AC-UPG-24(a): first_tick_can_air_jump == true post-apply double_jump") \
		.is_true()
	assert_bool(reader.first_tick_can_dash) \
		.override_failure_message("AC-UPG-24(a): first_tick_can_dash == false (pas de dash applied)") \
		.is_false()

	# Cleanup
	reader.queue_free()


# =============================================================================
# AC-UPG-25 — apply pendant despawn propage à new player
# =============================================================================

## GIVEN player1 spawn → free → apply_upgrade pendant absence → player2 spawn,
## WHEN player2._physics_process premier tick,
## THEN player2.first_tick_can_air_jump == true (autoload survit despawn).
func test_apply_during_player_despawn_propagates_to_new_player() -> void:
	# Arrange — sequence
	var player1: MockMovementReader = MockMovementReader.new()
	add_child(player1)
	await get_tree().physics_frame
	player1.queue_free()
	await get_tree().process_frame    # full despawn cycle

	# Act — apply pendant absence Player + spawn nouveau
	Upgrade.apply_upgrade(&"double_jump")
	assert_bool(Upgrade.can_air_jump).is_true()    # sanity
	var player2: MockMovementReader = MockMovementReader.new()
	add_child(player2)
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Assert
	assert_bool(player2.first_tick_observed) \
		.override_failure_message("AC-UPG-25: player2 doit avoir observé son premier tick") \
		.is_true()
	assert_bool(player2.first_tick_can_air_jump) \
		.override_failure_message("AC-UPG-25: player2 doit lire can_air_jump=true (autoload survit)") \
		.is_true()

	# Cleanup
	player2.queue_free()


# =============================================================================
# AC-UPG-26 ADVISORY — 100 lectures intra-tick stables (no torn read)
# =============================================================================

## GIVEN can_air_jump = true,
## WHEN 100 lectures consécutives,
## THEN toutes retournent true. ADVISORY — documente l'invariant single-threaded.
func test_no_torn_read_100_consecutive_reads_intra_tick() -> void:
	# Arrange
	Upgrade.apply_upgrade(&"double_jump")

	# Act + Assert
	var all_true: bool = true
	for i in 100:
		if not Upgrade.can_air_jump:
			all_true = false
			break
	assert_bool(all_true) \
		.override_failure_message("AC-UPG-26 ADVISORY: 100 lectures consécutives doivent toutes retourner true") \
		.is_true()


# =============================================================================
# AC-UPG-31 — apply_upgrade pendant pause mute le flag immédiatement
# =============================================================================

## GIVEN get_tree().paused = true,
## WHEN apply_upgrade(&"double_jump"),
## THEN can_air_jump == true immédiatement (PROCESS_MODE_ALWAYS).
func test_apply_during_pause_mutes_flag_immediately() -> void:
	# Arrange
	get_tree().paused = true

	# Act
	Upgrade.apply_upgrade(&"double_jump")

	# Assert
	assert_bool(Upgrade.can_air_jump) \
		.override_failure_message("AC-UPG-31: apply_upgrade pendant pause doit muter can_air_jump immédiatement") \
		.is_true()

	# Cleanup
	get_tree().paused = false


# =============================================================================
# AC-UPG-32 — reader PROCESS_MODE_ALWAYS lit flag pendant pause
# =============================================================================

## GIVEN get_tree().paused = true ET reader.process_mode = PROCESS_MODE_ALWAYS,
## WHEN reader._physics_process s'exécute pendant pause,
## THEN reader.first_tick_can_air_jump == true (no stale value).
func test_pause_resilient_reader_observes_flag_correctly() -> void:
	# Arrange — apply avant pause pour garantir flag set
	Upgrade.apply_upgrade(&"double_jump")
	get_tree().paused = true
	var reader: MockMovementReader = MockMovementReader.new()
	reader.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(reader)

	# Act
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Assert
	assert_bool(reader.first_tick_observed) \
		.override_failure_message("AC-UPG-32: reader PROCESS_MODE_ALWAYS doit ticker pendant pause") \
		.is_true()
	assert_bool(reader.first_tick_can_air_jump) \
		.override_failure_message("AC-UPG-32: reader doit lire can_air_jump=true pendant pause") \
		.is_true()

	# Cleanup
	get_tree().paused = false
	reader.queue_free()
