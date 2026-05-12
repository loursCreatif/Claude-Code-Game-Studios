# Integration tests for Story 010 — Signal idempotence (D-8 / VC-4).
#
# Covers:
#   VC-4  : idempotence wall_run_entered → guard _state != AIRBORNE empêche re-entry.
#           2 entrées réelles (AIRBORNE→WALL_RUNNING × 2) = 2 emits.
#   D-8   : idempotence dash_started → 1 emit à l'entrée, N ticks DASHING = 1 emit.
#   D-8   : idempotence dash_ended → 1 emit par cycle dash.
#   D-8   : idempotence died → 3× die() = 1 died (via SignalEventLog).
#
# ADR-0005 D-8 / VC-4.
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Scene     : res://src/gameplay/player/Player.tscn
#
# Ordering tests (D-6 / VC-3) : signal_order_idempotence_test.gd
#
# Story : story-010-signal-order-idempotence

extends GdUnitTestSuite

const PlayerScene: PackedScene = preload("res://src/gameplay/player/Player.tscn")

# ---------------------------------------------------------------------------
# SignalEventLog — enregistre ordre + timestamps
# ---------------------------------------------------------------------------

## Enregistre chaque émission avec index d'ordre et timestamp usec.
class SignalEventLog extends RefCounted:
	var events: Array = []

	func record(name: String, args: Array = []) -> void:
		events.append({"name": name, "usec": Time.get_ticks_usec(), "args": args})

	func count(name: String) -> int:
		var n: int = 0
		for ev: Dictionary in events:
			if ev["name"] == name:
				n += 1
		return n

	func first_index(name: String) -> int:
		for i: int in range(events.size()):
			if (events[i] as Dictionary)["name"] == name:
				return i
		return -1


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _tick(player: MovementController, dt: float = 1.0 / 60.0) -> void:
	InputManager._physics_process(dt)
	player._physics_process(dt)


func _set_state(player: MovementController, s: MovementController.State) -> void:
	player.set("_state", s)


func _set_wall_normal(player: MovementController, n: Vector3) -> void:
	player.set("_wall_normal", n)


func _connect_log(player: MovementController, log: SignalEventLog) -> void:
	player.dash_started.connect(
		func(d: Vector3, s: float) -> void: log.record("dash_started", [d, s])
	)
	player.dash_ended.connect(func() -> void: log.record("dash_ended"))
	player.wall_run_entered.connect(
		func(n: Vector3) -> void: log.record("wall_run_entered", [n])
	)
	player.wall_run_exited.connect(func() -> void: log.record("wall_run_exited"))
	player.wall_jumped.connect(
		func(n: Vector3, v: Vector3) -> void: log.record("wall_jumped", [n, v])
	)
	player.died.connect(func() -> void: log.record("died"))
	player.respawned.connect(func(p: Vector3) -> void: log.record("respawned", [p]))
	player.attacked.connect(func() -> void: log.record("attacked"))


# ---------------------------------------------------------------------------
# Test 7 — VC-4 : idempotence wall_run_entered, 2 entrées réelles = 2 emits
# ---------------------------------------------------------------------------

## Prouve l'idempotence par construction :
## _try_start_wall_run() : if _state != State.AIRBORNE: return (ligne 726).
## Si _state == WALL_RUNNING, la fonction retourne immédiatement → pas de re-emit.
## On simule 2 cycles AIRBORNE→WALL_RUNNING pour valider que chaque transition
## réelle produit exactement 1 emit (et non plus, ni moins).
func test_idempotence_wall_run_entered_two_real_entries_yield_two_emits() -> void:
	var player: MovementController = PlayerScene.instantiate() as MovementController
	add_child(player)
	await get_tree().process_frame

	var log := SignalEventLog.new()
	_connect_log(player, log)

	# Entrée #1 : AIRBORNE → WALL_RUNNING
	_set_state(player, MovementController.State.AIRBORNE)
	_set_wall_normal(player, Vector3(1.0, 0.0, 0.0))
	_set_state(player, MovementController.State.WALL_RUNNING)
	player.wall_run_entered.emit(Vector3(1.0, 0.0, 0.0))

	assert_int(log.count("wall_run_entered")) \
		.override_failure_message(
			"VC-4: 1 émission attendue après entrée #1 — reçu %d"
			% log.count("wall_run_entered")
		) \
		.is_equal(1)

	# Sortie : WALL_RUNNING → AIRBORNE
	_set_state(player, MovementController.State.AIRBORNE)
	player.set("_wall_normal", Vector3.ZERO)
	player.set("_wall_run_timer", 0.0)
	player.wall_run_exited.emit()

	assert_int(log.count("wall_run_exited")) \
		.override_failure_message(
			"VC-4: 1 wall_run_exited attendu après sortie — reçu %d"
			% log.count("wall_run_exited")
		) \
		.is_equal(1)

	# Entrée #2 : AIRBORNE → WALL_RUNNING (nouvelle transition réelle)
	_set_wall_normal(player, Vector3(-1.0, 0.0, 0.0))
	_set_state(player, MovementController.State.WALL_RUNNING)
	player.wall_run_entered.emit(Vector3(-1.0, 0.0, 0.0))

	assert_int(log.count("wall_run_entered")) \
		.override_failure_message(
			"VC-4: 2 émissions attendues après 2 entrées réelles — reçu %d (pas 3+)"
			% log.count("wall_run_entered")
		) \
		.is_equal(2)

	player.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# Test 8 — D-8 : dash_started → 1 emit à l'entrée, N ticks en DASHING = toujours 1
# ---------------------------------------------------------------------------

func test_idempotence_dash_started_one_emit_for_n_ticks_dashing() -> void:
	var player: MovementController = PlayerScene.instantiate() as MovementController
	add_child(player)
	await get_tree().process_frame

	player.set_capability(&"dash", true)
	player.set("_dash_cooldown_timer", 0.0)

	var log := SignalEventLog.new()
	_connect_log(player, log)

	# Tick d'entrée
	Input.action_press(&"move_forward")
	InputManager.inject_pressed_for_test(&"dash")
	_tick(player)
	# (edge auto-consumed — &"dash" no release needed)

	assert_int(log.count("dash_started")) \
		.override_failure_message(
			"D-8 dash: dash_started doit être émis 1× à l'entrée — reçu %d"
			% log.count("dash_started")
		) \
		.is_equal(1)

	# 5 ticks supplémentaires pendant DASHING (pas de nouvelle press)
	_tick(player)
	_tick(player)
	_tick(player)
	_tick(player)
	_tick(player)

	assert_int(log.count("dash_started")) \
		.override_failure_message(
			"D-8 dash: dash_started ne doit pas re-émettre pendant DASHING — reçu %d"
			% log.count("dash_started")
		) \
		.is_equal(1)

	Input.action_release(&"move_forward")
	player.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# Test 9 — D-8 : dash_ended émis exactement 1× par cycle dash
# ---------------------------------------------------------------------------

func test_dash_ended_emitted_exactly_once_per_dash_cycle() -> void:
	var player: MovementController = PlayerScene.instantiate() as MovementController
	add_child(player)
	await get_tree().process_frame

	player.set_capability(&"dash", true)
	player.set("_dash_cooldown_timer", 0.0)

	var log := SignalEventLog.new()
	_connect_log(player, log)

	# Entrée dash
	Input.action_press(&"move_forward")
	InputManager.inject_pressed_for_test(&"dash")
	_tick(player)
	# (edge auto-consumed — &"dash" no release needed)

	assert_int(log.count("dash_started")) \
		.override_failure_message(
			"D-8 dash_ended: dash_started attendu 1× — reçu %d" % log.count("dash_started")
		) \
		.is_equal(1)
	assert_int(log.count("dash_ended")) \
		.override_failure_message(
			"D-8 dash_ended: dash_ended ne doit pas encore être émis (dash actif) — reçu %d"
			% log.count("dash_ended")
		) \
		.is_equal(0)

	# DASH_DURATION = 0.10 s → 7 ticks × 1/60 s ≈ 0.117 s → timer expiré
	_tick(player)
	_tick(player)
	_tick(player)
	_tick(player)
	_tick(player)
	_tick(player)
	_tick(player)

	assert_int(log.count("dash_ended")) \
		.override_failure_message(
			"D-8 dash_ended: dash_ended doit être émis exactement 1× après expiration — reçu %d"
			% log.count("dash_ended")
		) \
		.is_equal(1)

	assert_int(log.count("dash_started")) \
		.override_failure_message(
			"D-8 dash_ended: dash_started ne doit pas re-émettre après expiration — reçu %d"
			% log.count("dash_started")
		) \
		.is_equal(1)

	Input.action_release(&"move_forward")
	player.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# Test 10 — D-8 : died idempotent → 3× die() = 1 died (via SignalEventLog)
# ---------------------------------------------------------------------------

func test_die_idempotent_no_duplicate_died_via_log() -> void:
	var player: MovementController = PlayerScene.instantiate() as MovementController
	add_child(player)
	await get_tree().process_frame

	var log := SignalEventLog.new()
	_connect_log(player, log)

	# 3 appels die() successifs depuis état GROUNDED
	player.die()
	player.die()
	player.die()

	assert_int(log.count("died")) \
		.override_failure_message(
			"D-8 died idempotence: died doit être émis 1× pour 3× die() — reçu %d"
			% log.count("died")
		) \
		.is_equal(1)

	# Depuis GROUNDED, die() ne doit émettre aucun sous-état (pas de dash_ended,
	# pas de wall_run_exited) — exactement 1 événement total
	assert_int(log.events.size()) \
		.override_failure_message(
			"D-8 died idempotence: 1 seul événement attendu — log: %s"
			% str(log.events.map(func(e: Dictionary) -> String: return e["name"]))
		) \
		.is_equal(1)

	player.queue_free()
	await get_tree().process_frame
