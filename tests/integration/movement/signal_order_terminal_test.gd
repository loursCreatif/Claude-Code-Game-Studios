# Integration tests for Story 010 — Signal order : terminal + respawn + attacked (D-6).
#
# Covers:
#   D-6 : died terminal → aucun signal Movement (sauf respawned) après DEAD.
#   D-6 : respawned unique → 1× au respawn, aucun signal parasite.
#   D-6 : attacked fin de tick → émis APRÈS les state machine signals.
#
# ADR-0005 D-6.
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Scene     : res://src/gameplay/player/Player.tscn
#
# Exit-before-entry tests (VC-3) : signal_order_exit_test.gd
# Idempotence tests (D-8 / VC-4) : signal_idempotence_test.gd
#
# Story : story-010-signal-order-idempotence

extends GdUnitTestSuite

const PlayerScene: PackedScene = preload("res://src/gameplay/player/Player.tscn")

# ---------------------------------------------------------------------------
# SignalEventLog
# ---------------------------------------------------------------------------

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

	## Compte les signaux après sentinel qui ne sont pas dans allowed_names.
	func count_after_excluding(sentinel: String, allowed_names: Array[String]) -> int:
		var idx: int = first_index(sentinel)
		if idx == -1:
			return 0
		var violations: int = 0
		for i: int in range(idx + 1, events.size()):
			var n: String = (events[i] as Dictionary)["name"] as String
			if not n in allowed_names:
				violations += 1
		return violations


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _tick(player: MovementController, dt: float = 1.0 / 60.0) -> void:
	InputManager._physics_process(dt)
	player._physics_process(dt)


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
# Test 4 — D-6 : died terminal → aucun signal Movement après DEAD
# ---------------------------------------------------------------------------

func test_died_is_terminal_no_other_signals_until_respawn() -> void:
	var player: MovementController = PlayerScene.instantiate() as MovementController
	add_child(player)
	await get_tree().process_frame

	var log := SignalEventLog.new()
	_connect_log(player, log)

	player.die()

	# dt très court (0.005 s) pour rester dans la fenêtre DEAD (RESPAWN_DELAY_S = 0.05 s)
	InputManager.inject_pressed_for_test(&"jump")
	InputManager.inject_pressed_for_test(&"dash")
	InputManager.inject_pressed_for_test(&"attack")
	_tick(player, 0.005)
	_tick(player, 0.005)
	_tick(player, 0.005)

	var allowed: Array[String] = ["died", "respawned"]
	var violations: int = log.count_after_excluding("died", allowed)
	assert_int(violations) \
		.override_failure_message(
			"D-6 died terminal: %d signal(s) interdit(s) après died — log: %s"
			% [violations, str(log.events.map(func(e: Dictionary) -> String: return e["name"]))]
		) \
		.is_equal(0)

	# (edge auto-consumed — &"jump" no release needed)
	# (edge auto-consumed — &"dash" no release needed)
	# (edge auto-consumed — &"attack" no release needed)
	player.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# Test 5 — D-6 : respawned unique, aucun signal parasite au respawn
# ---------------------------------------------------------------------------

func test_respawn_emits_only_respawned_no_extra_signals() -> void:
	var player: MovementController = PlayerScene.instantiate() as MovementController
	add_child(player)
	await get_tree().process_frame

	player.set_checkpoint(Vector3(5.0, 0.0, 0.0))
	player.die()

	# Log connecté APRÈS die() — capture uniquement les émissions post-mort
	var log := SignalEventLog.new()
	_connect_log(player, log)

	# 4 ticks × 1/60 s ≈ 0.067 s > RESPAWN_DELAY_S (0.05 s) → respawn déclenché
	_tick(player)
	_tick(player)
	_tick(player)
	_tick(player)

	assert_int(log.count("respawned")) \
		.override_failure_message(
			"D-6 respawned: doit être émis exactement 1× — reçu %d" % log.count("respawned")
		) \
		.is_equal(1)

	var unexpected: int = 0
	for ev: Dictionary in log.events:
		if ev["name"] != "respawned":
			unexpected += 1

	assert_int(unexpected) \
		.override_failure_message(
			"D-6 respawned: aucun autre signal attendu — log: %s"
			% str(log.events.map(func(e: Dictionary) -> String: return e["name"]))
		) \
		.is_equal(0)

	player.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# Test 6 — D-6 : attacked émis APRÈS dash_started dans le même tick
# ---------------------------------------------------------------------------

func test_attacked_emitted_after_dash_started_in_same_tick() -> void:
	var player: MovementController = PlayerScene.instantiate() as MovementController
	add_child(player)
	await get_tree().process_frame

	player.set_capability(&"dash", true)
	player.set("_dash_cooldown_timer", 0.0)

	var log := SignalEventLog.new()
	_connect_log(player, log)

	# dash (phase 8 dans _physics_process) + attack (phase 11b) même tick
	Input.action_press(&"move_forward")
	InputManager.inject_pressed_for_test(&"dash")
	InputManager.inject_pressed_for_test(&"attack")
	_tick(player)

	assert_int(log.count("dash_started")) \
		.override_failure_message(
			"D-6 attacked last: dash_started attendu 1× — reçu %d" % log.count("dash_started")
		) \
		.is_equal(1)

	# DASHING ne bloque PAS attacked — gate = _state != DEAD uniquement
	assert_int(log.count("attacked")) \
		.override_failure_message(
			"D-6 attacked last: attacked attendu 1× — reçu %d" % log.count("attacked")
		) \
		.is_equal(1)

	assert_int(log.first_index("dash_started")) \
		.override_failure_message(
			"D-6 attacked last: dash_started doit précéder attacked — ordre : %s"
			% str(log.events.map(func(e: Dictionary) -> String: return e["name"]))
		) \
		.is_less(log.first_index("attacked"))

	Input.action_release(&"move_forward")
	# (edge auto-consumed — &"dash" no release needed)
	# (edge auto-consumed — &"attack" no release needed)
	player.queue_free()
	await get_tree().process_frame
