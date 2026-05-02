# Integration tests for Story 010 — Signal order : exit-before-entry (D-6 / VC-3).
#
# Covers:
#   VC-3 : die-during-dash → dash_ended AVANT died (timestamps croissants).
#   D-6  : die-during-wall-run → wall_run_exited AVANT died.
#   D-6  : wall-jump → wall_run_exited AVANT wall_jumped, payload pré-reset.
#
# ADR-0005 D-6 / VC-3.
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Scene     : res://src/gameplay/player/Player.tscn
#
# Terminal + respawn + attacked tests : signal_order_terminal_test.gd
# Idempotence tests (D-8 / VC-4)     : signal_idempotence_test.gd
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

	func first_usec(name: String) -> int:
		for ev: Dictionary in events:
			if ev["name"] == name:
				return (ev as Dictionary)["usec"] as int
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
# Test 1 — VC-3 : die-during-dash → dash_ended AVANT died (timestamps)
# ---------------------------------------------------------------------------

func test_die_during_dashing_emits_dash_ended_before_died() -> void:
	var player: MovementController = PlayerScene.instantiate() as MovementController
	add_child(player)
	await get_tree().process_frame

	_set_state(player, MovementController.State.DASHING)
	player.set("_dash_dir", Vector3(0.0, 0.0, -1.0))
	player.dash_timer = 0.05
	player.set("_dash_cooldown_timer", MovementController.DASH_COOLDOWN)

	var log := SignalEventLog.new()
	_connect_log(player, log)

	player.die()

	assert_int(log.count("dash_ended")) \
		.override_failure_message(
			"VC-3: dash_ended doit être émis 1× — reçu %d" % log.count("dash_ended")
		) \
		.is_equal(1)

	assert_int(log.count("died")) \
		.override_failure_message("VC-3: died doit être émis 1× — reçu %d" % log.count("died")) \
		.is_equal(1)

	assert_int(log.first_index("dash_ended")) \
		.override_failure_message(
			"VC-3: dash_ended doit précéder died — ordre : %s"
			% str(log.events.map(func(e: Dictionary) -> String: return e["name"]))
		) \
		.is_less(log.first_index("died"))

	# Note timestamp : `first_index` (assert ci-dessus) est l'oracle canonique
	# d'ordre — déterministe et non-flaky. Le timestamp `<=` ci-dessous est
	# défensif uniquement (deux emits dans la même call stack `die()` peuvent
	# avoir le même usec si la résolution horloge OS est insuffisante).
	assert_bool(log.first_usec("dash_ended") <= log.first_usec("died")) \
		.override_failure_message(
			"VC-3 (defensive): timestamp dash_ended (%d) <= died (%d) — first_index est l'oracle canonique"
			% [log.first_usec("dash_ended"), log.first_usec("died")]
		) \
		.is_true()

	player.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# Test 1b — D-6 / GDD line 288 : dash-during-wall-run → wall_run_exited AVANT dash_started
# Source : code-review 2026-04-27 godot-specialist Issue 6 + GDD line 288
# ---------------------------------------------------------------------------

func test_dash_during_wall_run_emits_wall_run_exited_before_dash_started() -> void:
	var player: MovementController = PlayerScene.instantiate() as MovementController
	add_child(player)
	await get_tree().process_frame

	# Activer la capability dash + bypasser la WALL_RUN gate.
	player.set_capability(&"dash", true)
	_set_state(player, MovementController.State.WALL_RUNNING)
	_set_wall_normal(player, Vector3(1.0, 0.0, 0.0))
	player.set("_wall_run_timer", 0.3)
	player.set("_dash_cooldown_timer", 0.0)
	player.velocity = Vector3(0.0, 0.0, -10.0)

	var log := SignalEventLog.new()
	_connect_log(player, log)

	# Trigger le dash via was_pressed_this_tick edge.
	InputManager.simulate_action_press(&"dash")
	_tick(player)

	assert_int(log.count("wall_run_exited")) \
		.override_failure_message(
			"GDD line 288 : wall_run_exited doit être émis 1× quand dash interrompt wall-run — reçu %d"
			% log.count("wall_run_exited")
		) \
		.is_equal(1)

	assert_int(log.count("dash_started")) \
		.override_failure_message(
			"GDD line 288 : dash_started doit être émis 1× — reçu %d" % log.count("dash_started")
		) \
		.is_equal(1)

	assert_int(log.first_index("wall_run_exited")) \
		.override_failure_message(
			"D-6 : wall_run_exited doit précéder dash_started — ordre : %s"
			% str(log.events.map(func(e: Dictionary) -> String: return e["name"]))
		) \
		.is_less(log.first_index("dash_started"))

	# Reset wall_normal vérifié post-transition (GDD line 288 explicite).
	assert_vector(player.wall_normal) \
		.override_failure_message(
			"GDD line 288 : _wall_normal doit être reset à ZERO post dash-from-wall-run — reçu %s"
			% str(player.wall_normal)
		) \
		.is_equal_approx(Vector3.ZERO, 0.001)

	InputManager.simulate_action_release(&"dash")
	player.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# Test 2 — D-6 : die-during-wall-run → wall_run_exited AVANT died
# ---------------------------------------------------------------------------

func test_die_during_wall_run_emits_wall_run_exited_before_died() -> void:
	var player: MovementController = PlayerScene.instantiate() as MovementController
	add_child(player)
	await get_tree().process_frame

	_set_state(player, MovementController.State.WALL_RUNNING)
	_set_wall_normal(player, Vector3(1.0, 0.0, 0.0))
	player.set("_wall_run_timer", 0.3)

	var log := SignalEventLog.new()
	_connect_log(player, log)

	player.die()

	assert_int(log.count("wall_run_exited")) \
		.override_failure_message(
			"D-6: wall_run_exited doit être émis 1× — reçu %d" % log.count("wall_run_exited")
		) \
		.is_equal(1)

	assert_int(log.count("died")) \
		.override_failure_message("D-6: died doit être émis 1× — reçu %d" % log.count("died")) \
		.is_equal(1)

	assert_int(log.first_index("wall_run_exited")) \
		.override_failure_message(
			"D-6: wall_run_exited doit précéder died — ordre : %s"
			% str(log.events.map(func(e: Dictionary) -> String: return e["name"]))
		) \
		.is_less(log.first_index("died"))

	player.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# Test 3 — D-6 wall-jump : wall_run_exited AVANT wall_jumped, payload pré-reset
# ---------------------------------------------------------------------------

func test_wall_jump_emits_wall_run_exited_before_wall_jumped() -> void:
	var player: MovementController = PlayerScene.instantiate() as MovementController
	add_child(player)
	await get_tree().process_frame

	_set_state(player, MovementController.State.WALL_RUNNING)
	_set_wall_normal(player, Vector3(1.0, 0.0, 0.0))
	player.velocity = Vector3(0.0, 0.0, -10.0)
	player.air_jumps_used = 0

	var log := SignalEventLog.new()
	_connect_log(player, log)

	InputManager.simulate_action_press(&"jump")
	_tick(player)

	assert_int(log.count("wall_run_exited")) \
		.override_failure_message(
			"D-6 wall-jump: wall_run_exited doit être émis 1× — reçu %d"
			% log.count("wall_run_exited")
		) \
		.is_equal(1)

	assert_int(log.count("wall_jumped")) \
		.override_failure_message(
			"D-6 wall-jump: wall_jumped doit être émis 1× — reçu %d" % log.count("wall_jumped")
		) \
		.is_equal(1)

	assert_int(log.first_index("wall_run_exited")) \
		.override_failure_message(
			"D-6 wall-jump: wall_run_exited doit précéder wall_jumped — ordre : %s"
			% str(log.events.map(func(e: Dictionary) -> String: return e["name"]))
		) \
		.is_less(log.first_index("wall_jumped"))

	var wj_idx: int = log.first_index("wall_jumped")
	var wj_args: Array = (log.events[wj_idx] as Dictionary)["args"] as Array
	var received_normal: Vector3 = wj_args[0] as Vector3
	assert_vector(received_normal) \
		.override_failure_message(
			"D-6 wall-jump: payload wall_normal doit être (1,0,0) pré-reset — reçu %s"
			% str(received_normal)
		) \
		.is_equal_approx(Vector3(1.0, 0.0, 0.0), 0.001)

	InputManager.simulate_action_release(&"jump")
	player.queue_free()
	await get_tree().process_frame
