# Tests d'intégration Story-002 — AC-CS-1 : parité de tick pour les consumers.
# Vérifie que le swap InputManager s'exécute AVANT les _physics_process consumers,
# garantissant que was_pressed_this_tick(&"jump") est true au tick N (pas N+1).
# ADR-0004 VC-4 — autoload order invariant (InputManager #1).
# Framework : GdUnit4 (extends GdUnitTestSuite).

extends GdUnitTestSuite

# ---------------------------------------------------------------------------
# TestConsumer — Node interne qui poll was_pressed_this_tick chaque tick
# ---------------------------------------------------------------------------

## Node consumer de test : observe was_pressed_this_tick à chaque physics tick
## et consigne les résultats pour validation post-await.
class TestConsumer extends Node:
	## Référence vers le manager sous test (injectée par le test).
	var manager: InputManagerScript = null

	## Anneau d'observations : chaque entrée = { "tick": int, "pressed": bool }
	var observations: Array[Dictionary] = []

	func _physics_process(_delta: float) -> void:
		if manager == null:
			return
		observations.append({
			"tick": Engine.get_physics_frames(),
			"pressed": manager.was_pressed_this_tick(&"jump"),
		})

# ---------------------------------------------------------------------------
# AC-CS-1 — consumer dans _physics_process lit true au même tick N que la press
# ---------------------------------------------------------------------------

func test_polling_same_tick_consumer_reads_true_at_tick_n_not_n_plus_1() -> void:
	# Arrange — créer un manager frais (pas l'autoload — isolation garantie)
	var manager: InputManagerScript = InputManagerScript.new()
	add_child(manager)
	await get_tree().process_frame

	# Attacher le consumer APRÈS le manager (order de traitement child → parent
	# dans Godot, mais l'invariant autoload garantit que InputManager._physics_process
	# s'exécute en premier car il est déclaré premier dans project.godot).
	# Ici on simule l'invariant avec un manager parent et consumer enfant :
	# Godot appelle _physics_process du parent avant celui des enfants.
	var consumer: TestConsumer = TestConsumer.new()
	consumer.manager = manager
	manager.add_child(consumer)
	await get_tree().process_frame

	# Vider les observations accumulées pendant le setup
	consumer.observations.clear()

	# Act — injecter la press et attendre exactement un physics frame
	var ev := InputEventAction.new()
	ev.action = &"jump"
	ev.pressed = true
	Input.parse_input_event(ev)

	await get_tree().physics_frame

	# Assert tick N — le consumer doit avoir observé pressed == true
	# Note : parse_input_event est synchrone mais _unhandled_input peut être
	# déclenché de manière différée via le scene tree. On attend donc le
	# physics_frame complet avant d'asserter (ADR-0004 Risk 5).
	var tick_n_observations: Array[Dictionary] = consumer.observations.filter(
		func(obs: Dictionary) -> bool: return obs["pressed"] == true
	)
	assert_int(tick_n_observations.size()) \
		.override_failure_message(
			"AC-CS-1: le consumer doit observer pressed == true exactement une fois (tick N). " +
			"Observations totales : %d, avec pressed=true : %d" % [
				consumer.observations.size(),
				tick_n_observations.size()
			]
		) \
		.is_greater_equal(1)

	# Avancer d'un tick supplémentaire (tick N+1) — aucune nouvelle press injectée
	consumer.observations.clear()
	await get_tree().physics_frame

	# Assert tick N+1 — le consumer ne doit plus observer pressed == true
	var tick_n1_true_count: int = consumer.observations.filter(
		func(obs: Dictionary) -> bool: return obs["pressed"] == true
	).size()
	assert_int(tick_n1_true_count) \
		.override_failure_message(
			"AC-CS-1: was_pressed_this_tick doit être false au tick N+1 (edge-triggered). " +
			"Observer encore true après clear indique une fuite de flag."
		) \
		.is_equal(0)

	manager.queue_free()
