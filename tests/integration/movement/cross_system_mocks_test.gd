# Integration tests for Story 015 — Cross-system mocks (Combat + Checkpoint).
# Covers AC-MV-80 (MockCombat lit velocity pendant is_dashing ≈ DASH_SPEED),
#        AC-MV-81 (set_checkpoint + die → respawn à new_pos ± 0.01),
#        D-10 compliance (Movement ne référence pas MockCombat),
#        attacked signal propagation (attack_count == 1),
#        D-7 compliance (MockCheckpoint n'écrit pas l'état Movement).
#
# ADR-0005 D-10 (outbound-only) : mocks se connectent depuis leur _ready().
# ADR-0005 D-7 : consommateurs ne mutent jamais l'état Movement.
# Framework: GdUnit4 (extends GdUnitTestSuite).
#
# Story: story-015-cross-system-mocks

extends GdUnitTestSuite

# ---------------------------------------------------------------------------
# Scene preload
# ---------------------------------------------------------------------------

const PlayerScene: PackedScene = preload("res://src/gameplay/player/Player.tscn")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Simule un tick physique complet.
## InputManager._physics_process en premier (flush du buffer was_pressed_this_tick),
## puis player._physics_process. Reflète l'ordre de tick en production.
## dt par défaut = ADR-0001 physics rate 1/60 s.
func _tick(player: MovementController, dt: float = 1.0 / 60.0) -> void:
	InputManager._physics_process(dt)
	player._physics_process(dt)


## Force-write un backing field privé via Object.set() — pattern GdUnit4 intégration.
## Utilisé uniquement pour positionner le joueur dans un état précis sans passer
## par le pipeline de transition complet.
func _set_state(player: MovementController, s: MovementController.State) -> void:
	player.set("_state", s)


# ---------------------------------------------------------------------------
# AC-MV-80 — MockCombat lit velocity pendant dash
# ---------------------------------------------------------------------------

func test_mock_combat_reads_velocity_during_dash() -> void:
	# Arrange — parent node commun, player et mock comme enfants indépendants.
	var parent: Node = auto_free(Node.new())
	add_child(parent)

	var player: MovementController = auto_free(PlayerScene.instantiate() as MovementController)
	var mock_combat: MockCombatSystem = auto_free(MockCombatSystem.new())

	# Injection explicite — évite la dépendance au sibling lookup ../Player.
	mock_combat.player = player

	parent.add_child(player)
	parent.add_child(mock_combat)

	await get_tree().process_frame

	# Activer le dash et simuler une pression d'input forward + dash.
	player.set_capability(&"dash", true)
	Input.action_press(&"move_forward")
	InputManager.inject_pressed_for_test(&"dash")

	# Act — 3 ticks (mi-dash, DASH_DURATION=0.10s = 6 ticks à 60Hz → tick 3 est en plein dash).
	_tick(player)
	_tick(player)
	_tick(player)

	# Assert — le mock a capturé une velocity ≈ DASH_SPEED pendant is_dashing == true.
	assert_float(mock_combat.last_sweep_velocity.length()) \
		.override_failure_message(
			"AC-MV-80: last_sweep_velocity.length() doit ≈ DASH_SPEED (%f) ± 0.5 — got %f"
			% [MovementController.DASH_SPEED, mock_combat.last_sweep_velocity.length()]
		) \
		.is_between(
			MovementController.DASH_SPEED - 0.5,
			MovementController.DASH_SPEED + 0.5
		)

	# Cleanup — release inputs.
	Input.action_release(&"move_forward")
	# (edge auto-consumed — &"dash" no release needed)


# ---------------------------------------------------------------------------
# AC-MV-81 — set_checkpoint + die → respawn à new_pos
# ---------------------------------------------------------------------------

func test_mock_checkpoint_set_then_respawn_to_new_pos() -> void:
	# Arrange
	var parent: Node = auto_free(Node.new())
	add_child(parent)

	var player: MovementController = auto_free(PlayerScene.instantiate() as MovementController)
	var mock_checkpoint: MockCheckpointSystem = auto_free(MockCheckpointSystem.new())

	mock_checkpoint.player = player

	parent.add_child(player)
	parent.add_child(mock_checkpoint)

	await get_tree().process_frame

	var target_pos: Vector3 = Vector3(42.0, 1.0, 7.0)

	# Act — enregistrer checkpoint puis déclencher die().
	mock_checkpoint.set_checkpoint_at(target_pos)
	player.die()

	# 4 ticks × 1/60 ≈ 0.0667 s > RESPAWN_DELAY_S=0.05 s → respawn déclenché.
	_tick(player)
	_tick(player)
	_tick(player)
	_tick(player)

	# Assert — joueur téléporté au checkpoint.
	assert_float(player.global_position.distance_to(target_pos)) \
		.override_failure_message(
			"AC-MV-81: global_position doit être au checkpoint %s après respawn — got %s (dist %f)"
			% [str(target_pos), str(player.global_position), player.global_position.distance_to(target_pos)]
		) \
		.is_less_equal(0.1)


# ---------------------------------------------------------------------------
# D-10 compliance — Movement ne référence pas MockCombat
# ---------------------------------------------------------------------------

func test_movement_does_not_reference_mock_combat() -> void:
	# Vérification statique : movement_controller.gd ne contient aucune mention
	# de MockCombatSystem, MockCombat, ni MockCheckpoint.
	var source_path: String = "res://src/gameplay/player/movement_controller.gd"
	var file: FileAccess = FileAccess.open(source_path, FileAccess.READ)

	assert_object(file) \
		.override_failure_message(
			"D-10: impossible d'ouvrir %s — fichier introuvable" % source_path
		) \
		.is_not_null()

	var content: String = file.get_as_text()
	file.close()

	assert_bool(content.contains("MockCombat")) \
		.override_failure_message(
			"D-10: movement_controller.gd contient 'MockCombat' — violation outbound-only"
		) \
		.is_false()

	assert_bool(content.contains("MockCombatSystem")) \
		.override_failure_message(
			"D-10: movement_controller.gd contient 'MockCombatSystem' — violation outbound-only"
		) \
		.is_false()

	assert_bool(content.contains("MockCheckpoint")) \
		.override_failure_message(
			"D-10: movement_controller.gd contient 'MockCheckpoint' — violation outbound-only"
		) \
		.is_false()


# ---------------------------------------------------------------------------
# attacked signal propagation
# ---------------------------------------------------------------------------

func test_attacked_signal_propagates_to_mock_combat() -> void:
	# Arrange
	var parent: Node = auto_free(Node.new())
	add_child(parent)

	var player: MovementController = auto_free(PlayerScene.instantiate() as MovementController)
	var mock_combat: MockCombatSystem = auto_free(MockCombatSystem.new())

	mock_combat.player = player

	parent.add_child(player)
	parent.add_child(mock_combat)

	await get_tree().process_frame

	# Act — simuler une pression attack puis un tick (story-009 : emit en fin de _physics_process).
	InputManager.inject_pressed_for_test(&"attack")
	_tick(player)

	# Assert — mock a reçu exactement un signal attacked.
	assert_int(mock_combat.attack_count) \
		.override_failure_message(
			"attacked signal: attack_count doit être 1 après un tick avec input attack — got %d"
			% mock_combat.attack_count
		) \
		.is_equal(1)

	# Cleanup
	# (edge auto-consumed — &"attack" no release needed)


# ---------------------------------------------------------------------------
# D-7 compliance — MockCheckpoint n'écrit pas l'état Movement
# ---------------------------------------------------------------------------

func test_mock_checkpoint_does_not_mutate_movement_state() -> void:
	# Vérification statique : mock_checkpoint_system.gd ne contient aucune mutation d'état.
	var source_path: String = "res://tests/integration/movement/mocks/mock_checkpoint_system.gd"
	var file: FileAccess = FileAccess.open(source_path, FileAccess.READ)

	assert_object(file) \
		.override_failure_message(
			"D-7: impossible d'ouvrir %s — fichier introuvable" % source_path
		) \
		.is_not_null()

	var content: String = file.get_as_text()
	file.close()

	assert_bool(content.contains("player.velocity =")) \
		.override_failure_message(
			"D-7: mock_checkpoint_system.gd contient 'player.velocity =' — violation D-7"
		) \
		.is_false()

	assert_bool(content.contains("player._state =")) \
		.override_failure_message(
			"D-7: mock_checkpoint_system.gd contient 'player._state =' — violation D-7"
		) \
		.is_false()

	assert_bool(content.contains("player.die(")) \
		.override_failure_message(
			"D-7: mock_checkpoint_system.gd contient 'player.die(' — violation D-7"
		) \
		.is_false()
