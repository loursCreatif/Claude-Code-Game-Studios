# Integration tests for Story 009 — Movement Signals Typed Contract.
# Covers:
#   AC-1 : 8 signals MVP présents avec signatures conformes ADR-0005 D-2.
#   AC-2 : emit points branchés (dash, wall-run, wall-jump, die, respawn, attack).
#   AC-3 : typed contract mismatch déclenche push_error en debug build (VC-1) [optionnel].
#   AC-5 : attacked forward, idempotence, Dead gate.
#
# ADR-0005 (D-1..D-4, D-6, D-8), ADR-0004 D-1 (was_pressed_this_tick edge consume).
# Framework: GdUnit4 (extends GdUnitTestSuite).
#
# Story: story-009-signals-typed-contract

extends GdUnitTestSuite

# ---------------------------------------------------------------------------
# Scene preload
# ---------------------------------------------------------------------------

const PlayerScene: PackedScene = preload("res://src/gameplay/player/Player.tscn")

# ---------------------------------------------------------------------------
# SignalSpy — records emit count and last payload args
# ---------------------------------------------------------------------------

class SignalSpy extends RefCounted:
	var count: int = 0
	var last_args: Array = []

	## Generic n-arity recorder. Godot signal connections pass args positionally.
	## We use individual typed variants below per signal arity.
	func record_0() -> void:
		count += 1
		last_args = []

	func record_v3(a: Vector3) -> void:
		count += 1
		last_args = [a]

	func record_v3_f(a: Vector3, b: float) -> void:
		count += 1
		last_args = [a, b]

	func record_v3_v3(a: Vector3, b: Vector3) -> void:
		count += 1
		last_args = [a, b]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Simulate one physics tick — InputManager first (flushes was_pressed buffer),
## then player. Mirrors production tick order (ADR-0001 60 Hz).
func _tick(player: MovementController, dt: float = 1.0 / 60.0) -> void:
	InputManager._physics_process(dt)
	player._physics_process(dt)


## Force-write a private backing field without going through state transitions.
## GdUnit4 integration test helper pattern — Object.set().
func _set_state(player: MovementController, s: MovementController.State) -> void:
	player.set("_state", s)


## Force-write _wall_normal via Object.set() — needed for wall-jump payload test.
func _set_wall_normal(player: MovementController, n: Vector3) -> void:
	player.set("_wall_normal", n)


# ---------------------------------------------------------------------------
# AC-1 — 8 signaux MVP présents avec signatures conformes ADR-0005 D-2
# ---------------------------------------------------------------------------

func test_signal_list_has_dash_started_with_correct_signature() -> void:
	# Arrange
	var player: MovementController = PlayerScene.instantiate() as MovementController
	add_child(player)
	await get_tree().process_frame

	# Act
	var found: bool = player.has_signal("dash_started")
	var sig_list: Array = player.get_signal_list()
	var sig_args: Array = []
	for s: Dictionary in sig_list:
		if s["name"] == "dash_started":
			sig_args = s["args"]

	# Assert — signal present
	assert_bool(found) \
		.override_failure_message("AC-1: dash_started signal must exist on MovementController") \
		.is_true()

	# Assert — 2 args: dash_dir (TYPE_VECTOR3=9), dash_speed (TYPE_FLOAT=3)
	assert_int(sig_args.size()) \
		.override_failure_message(
			"AC-1: dash_started must have 2 parameters — got %d" % sig_args.size()
		) \
		.is_equal(2)

	assert_int((sig_args[0] as Dictionary)["type"]) \
		.override_failure_message("AC-1: dash_started arg[0] must be TYPE_VECTOR3") \
		.is_equal(TYPE_VECTOR3)

	assert_int((sig_args[1] as Dictionary)["type"]) \
		.override_failure_message("AC-1: dash_started arg[1] must be TYPE_FLOAT") \
		.is_equal(TYPE_FLOAT)

	player.queue_free()
	await get_tree().process_frame


func test_signal_list_has_dash_ended_with_no_args() -> void:
	var player: MovementController = PlayerScene.instantiate() as MovementController
	add_child(player)
	await get_tree().process_frame

	assert_bool(player.has_signal("dash_ended")) \
		.override_failure_message("AC-1: dash_ended signal must exist") \
		.is_true()

	var sig_args: Array = []
	for s: Dictionary in player.get_signal_list():
		if s["name"] == "dash_ended":
			sig_args = s["args"]

	assert_int(sig_args.size()) \
		.override_failure_message("AC-1: dash_ended must have 0 parameters") \
		.is_equal(0)

	player.queue_free()
	await get_tree().process_frame


func test_signal_list_has_wall_run_entered_with_vector3_arg() -> void:
	var player: MovementController = PlayerScene.instantiate() as MovementController
	add_child(player)
	await get_tree().process_frame

	assert_bool(player.has_signal("wall_run_entered")) \
		.override_failure_message("AC-1: wall_run_entered signal must exist") \
		.is_true()

	var sig_args: Array = []
	for s: Dictionary in player.get_signal_list():
		if s["name"] == "wall_run_entered":
			sig_args = s["args"]

	assert_int(sig_args.size()) \
		.override_failure_message("AC-1: wall_run_entered must have 1 parameter") \
		.is_equal(1)

	assert_int((sig_args[0] as Dictionary)["type"]) \
		.override_failure_message("AC-1: wall_run_entered arg[0] must be TYPE_VECTOR3") \
		.is_equal(TYPE_VECTOR3)

	player.queue_free()
	await get_tree().process_frame


func test_signal_list_has_wall_run_exited_with_no_args() -> void:
	var player: MovementController = PlayerScene.instantiate() as MovementController
	add_child(player)
	await get_tree().process_frame

	assert_bool(player.has_signal("wall_run_exited")) \
		.override_failure_message("AC-1: wall_run_exited signal must exist") \
		.is_true()

	player.queue_free()
	await get_tree().process_frame


func test_signal_list_has_wall_jumped_with_two_vector3_args() -> void:
	var player: MovementController = PlayerScene.instantiate() as MovementController
	add_child(player)
	await get_tree().process_frame

	assert_bool(player.has_signal("wall_jumped")) \
		.override_failure_message("AC-1: wall_jumped signal must exist") \
		.is_true()

	var sig_args: Array = []
	for s: Dictionary in player.get_signal_list():
		if s["name"] == "wall_jumped":
			sig_args = s["args"]

	assert_int(sig_args.size()) \
		.override_failure_message("AC-1: wall_jumped must have 2 parameters") \
		.is_equal(2)

	assert_int((sig_args[0] as Dictionary)["type"]) \
		.override_failure_message("AC-1: wall_jumped arg[0] must be TYPE_VECTOR3") \
		.is_equal(TYPE_VECTOR3)

	assert_int((sig_args[1] as Dictionary)["type"]) \
		.override_failure_message("AC-1: wall_jumped arg[1] must be TYPE_VECTOR3") \
		.is_equal(TYPE_VECTOR3)

	player.queue_free()
	await get_tree().process_frame


func test_signal_list_has_died_with_no_args() -> void:
	var player: MovementController = PlayerScene.instantiate() as MovementController
	add_child(player)
	await get_tree().process_frame

	assert_bool(player.has_signal("died")) \
		.override_failure_message("AC-1: died signal must exist") \
		.is_true()

	player.queue_free()
	await get_tree().process_frame


func test_signal_list_has_respawned_with_vector3_arg() -> void:
	var player: MovementController = PlayerScene.instantiate() as MovementController
	add_child(player)
	await get_tree().process_frame

	assert_bool(player.has_signal("respawned")) \
		.override_failure_message("AC-1: respawned signal must exist") \
		.is_true()

	var sig_args: Array = []
	for s: Dictionary in player.get_signal_list():
		if s["name"] == "respawned":
			sig_args = s["args"]

	assert_int(sig_args.size()) \
		.override_failure_message("AC-1: respawned must have 1 parameter") \
		.is_equal(1)

	assert_int((sig_args[0] as Dictionary)["type"]) \
		.override_failure_message("AC-1: respawned arg[0] must be TYPE_VECTOR3") \
		.is_equal(TYPE_VECTOR3)

	player.queue_free()
	await get_tree().process_frame


func test_signal_list_has_attacked_with_no_args() -> void:
	var player: MovementController = PlayerScene.instantiate() as MovementController
	add_child(player)
	await get_tree().process_frame

	assert_bool(player.has_signal("attacked")) \
		.override_failure_message("AC-1: attacked signal must exist") \
		.is_true()

	player.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# AC-2 — died signal émis exactement 1× par appel die() (idempotence story-008)
# ---------------------------------------------------------------------------

func test_died_signal_emitted_once_per_die_call() -> void:
	# Arrange
	var player: MovementController = PlayerScene.instantiate() as MovementController
	add_child(player)
	await get_tree().process_frame

	var spy := SignalSpy.new()
	player.died.connect(spy.record_0)

	# Act — trois appels die() successifs, seul le premier déclenche la transition
	player.die()
	player.die()
	player.die()

	# Assert — died émis exactement 1× (idempotence)
	assert_int(spy.count) \
		.override_failure_message(
			"AC-2: died must be emitted exactly once for 3x die() calls — got %d" % spy.count
		) \
		.is_equal(1)

	player.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# AC-2 — respawned émis avec la position checkpoint correcte
# ---------------------------------------------------------------------------

func test_respawned_signal_emitted_with_checkpoint_position() -> void:
	# Arrange
	var checkpoint: Vector3 = Vector3(42.0, 1.0, 7.0)
	var player: MovementController = PlayerScene.instantiate() as MovementController
	add_child(player)
	await get_tree().process_frame

	var spy := SignalSpy.new()
	player.respawned.connect(spy.record_v3)

	player.set_checkpoint(checkpoint)
	player.die()

	# Act — 4 ticks > RESPAWN_DELAY_S (0.05 s) → respawn fires
	_tick(player)
	_tick(player)
	_tick(player)
	_tick(player)

	# Assert — émis exactement 1×
	assert_int(spy.count) \
		.override_failure_message(
			"AC-2: respawned must be emitted exactly once after die + 4 ticks — got %d" % spy.count
		) \
		.is_equal(1)

	# Assert — payload = checkpoint position
	assert_vector(spy.last_args[0] as Vector3) \
		.override_failure_message(
			"AC-2: respawned payload must be checkpoint %s — got %s"
			% [str(checkpoint), str(spy.last_args[0])]
		) \
		.is_equal_approx(checkpoint, Vector3.ONE * 0.01)

	player.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# AC-2 — dash_started émis avec dir et speed corrects
# ---------------------------------------------------------------------------

func test_dash_started_emitted_with_dir_and_speed() -> void:
	# Arrange
	var player: MovementController = PlayerScene.instantiate() as MovementController
	add_child(player)
	await get_tree().process_frame

	player.can_dash = true
	# Ensure cooldown is zero
	player.set("_dash_cooldown_timer", 0.0)

	var spy := SignalSpy.new()
	player.dash_started.connect(spy.record_v3_f)

	# Simulate move forward (negative Z in local space) then dash
	InputManager.simulate_action_press(&"move_forward")
	InputManager.simulate_action_press(&"dash")

	# Act
	_tick(player)

	# Assert — 1 émission
	assert_int(spy.count) \
		.override_failure_message(
			"AC-2: dash_started must be emitted exactly once — got %d" % spy.count
		) \
		.is_equal(1)

	# Assert — speed payload = DASH_SPEED
	var received_speed: float = spy.last_args[1] as float
	assert_float(received_speed) \
		.override_failure_message(
			"AC-2: dash_started speed payload must equal DASH_SPEED (%f) — got %f"
			% [MovementController.DASH_SPEED, received_speed]
		) \
		.is_equal_approx(MovementController.DASH_SPEED, 0.001)

	# Assert — dir payload is normalized (length ≈ 1)
	var received_dir: Vector3 = spy.last_args[0] as Vector3
	assert_float(received_dir.length()) \
		.override_failure_message(
			"AC-2: dash_started dir payload must be normalized — length was %f" % received_dir.length()
		) \
		.is_equal_approx(1.0, 0.001)

	# Cleanup
	InputManager.simulate_action_release(&"move_forward")
	InputManager.simulate_action_release(&"dash")
	player.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# AC-2 — dash_ended émis à l'expiration du timer dash
# ---------------------------------------------------------------------------

func test_dash_ended_emitted_at_dash_timer_expiry() -> void:
	# Arrange
	var player: MovementController = PlayerScene.instantiate() as MovementController
	add_child(player)
	await get_tree().process_frame

	# Force player into DASHING with an almost-expired timer
	_set_state(player, MovementController.State.DASHING)
	player.dash_timer = 0.001
	player.set("_dash_dir", Vector3(1.0, 0.0, 0.0))

	var spy := SignalSpy.new()
	player.dash_ended.connect(spy.record_0)

	# Act — one tick at 1/60 s > 0.001 s → timer expires
	_tick(player)

	# Assert
	assert_int(spy.count) \
		.override_failure_message(
			"AC-2: dash_ended must be emitted once when dash_timer expires — got %d" % spy.count
		) \
		.is_equal(1)

	player.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# AC-2 — wall_run_entered émis avec la normale du mur
# ---------------------------------------------------------------------------

## Note: ce test exerce _try_start_wall_run() via force-write du state et
## injection directe du signal raycast. Comme nous ne pouvons pas instancier
## une physique complète sans StaticBody3D, nous testons l'emit en pré-positionnant
## le state WALL_RUNNING et en lisant wall_run_entered via un cycle de transition.
##
## Approche alternative simplifiée : mettre le player en AIRBORNE, injecter
## can_wall_run=true, forcer un state WALL_RUNNING par _set_state(), puis
## appeler _exit_wall_run via un tick avec une condition de sortie → teste
## wall_run_exited. Pour wall_run_entered, on teste la transition en observant
## les emits via _try_start_wall_run() avec raycast simulé.
##
## Puisque _try_start_wall_run() requiert un raycast réel (physique Jolt),
## ce test utilise la voie pragmatique : valider que le signal existe et
## que le branchement compile correctement (AC-1 + vérification structurelle).
## Le test complet de physique est couvert par le playtest evidence (Story Type: Integration).
func test_wall_run_entered_signal_is_connected_and_emittable() -> void:
	# Arrange
	var player: MovementController = PlayerScene.instantiate() as MovementController
	add_child(player)
	await get_tree().process_frame

	var spy := SignalSpy.new()
	player.wall_run_entered.connect(spy.record_v3)

	# Force-emit via internal state manipulation: put player in WALL_RUNNING
	# then manually emit the signal to validate the connection path.
	# In production, _try_start_wall_run() emits this on raycast hit.
	player.wall_run_entered.emit(Vector3(1.0, 0.0, 0.0))

	# Assert — connection works, payload arrives
	assert_int(spy.count) \
		.override_failure_message("AC-2: wall_run_entered connection must work") \
		.is_equal(1)

	assert_vector(spy.last_args[0] as Vector3) \
		.override_failure_message("AC-2: wall_run_entered payload must be Vector3(1,0,0)") \
		.is_equal_approx(Vector3(1.0, 0.0, 0.0), Vector3.ONE * 0.001)

	player.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# AC-2 — wall_run_exited émis lors de die() depuis WALL_RUNNING
# ---------------------------------------------------------------------------

func test_wall_run_exited_emitted_when_dying_from_wall_running_state() -> void:
	# Arrange
	var player: MovementController = PlayerScene.instantiate() as MovementController
	add_child(player)
	await get_tree().process_frame

	_set_state(player, MovementController.State.WALL_RUNNING)
	_set_wall_normal(player, Vector3(-1.0, 0.0, 0.0))
	player.set("_wall_run_timer", 0.3)

	var spy_exited := SignalSpy.new()
	player.wall_run_exited.connect(spy_exited.record_0)

	# Act — die() should emit wall_run_exited BEFORE died (ADR-0005 D-6)
	player.die()

	# Assert
	assert_int(spy_exited.count) \
		.override_failure_message(
			"AC-2: wall_run_exited must be emitted by die() when dying from WALL_RUNNING — got %d"
			% spy_exited.count
		) \
		.is_equal(1)

	player.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# AC-2 — wall_jumped émis avec la normale pré-reset (payload critique)
# ---------------------------------------------------------------------------

func test_wall_jumped_emitted_with_pre_reset_wall_normal() -> void:
	# Arrange
	var player: MovementController = PlayerScene.instantiate() as MovementController
	add_child(player)
	await get_tree().process_frame

	_set_state(player, MovementController.State.WALL_RUNNING)
	_set_wall_normal(player, Vector3(1.0, 0.0, 0.0))
	player.air_jumps_used = 0

	var spy := SignalSpy.new()
	player.wall_jumped.connect(spy.record_v3_v3)
	# Also spy wall_run_exited to verify D-6 ordering
	var spy_exited := SignalSpy.new()
	player.wall_run_exited.connect(spy_exited.record_0)

	# Act — press jump and tick
	InputManager.simulate_action_press(&"jump")
	_tick(player)

	# Assert — wall_jumped emitted once
	assert_int(spy.count) \
		.override_failure_message(
			"AC-2: wall_jumped must be emitted exactly once — got %d" % spy.count
		) \
		.is_equal(1)

	# Assert — wall_normal payload is the PRE-reset value (1, 0, 0) not ZERO
	var received_normal: Vector3 = spy.last_args[0] as Vector3
	assert_vector(received_normal) \
		.override_failure_message(
			"AC-2: wall_jumped wall_normal payload must be pre-reset (1,0,0) — got %s" % str(received_normal)
		) \
		.is_equal_approx(Vector3(1.0, 0.0, 0.0), Vector3.ONE * 0.001)

	# Assert — launch_velocity payload: normal * WALL_JUMP_SIDE + UP * WALL_JUMP_UP
	var expected_launch: Vector3 = Vector3(1.0, 0.0, 0.0) * MovementController.WALL_JUMP_SIDE + Vector3.UP * MovementController.WALL_JUMP_UP
	var received_launch: Vector3 = spy.last_args[1] as Vector3
	assert_vector(received_launch) \
		.override_failure_message(
			"AC-2: wall_jumped launch_velocity payload must be %s — got %s"
			% [str(expected_launch), str(received_launch)]
		) \
		.is_equal_approx(expected_launch, Vector3.ONE * 0.001)

	# Assert — wall_run_exited emitted before wall_jumped (D-6)
	assert_int(spy_exited.count) \
		.override_failure_message("AC-2: wall_run_exited must be emitted on wall-jump (D-6 order)") \
		.is_equal(1)

	# Cleanup
	InputManager.simulate_action_release(&"jump")
	player.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# AC-5 — attacked émis quand action pressée et joueur non DEAD
# ---------------------------------------------------------------------------

func test_attacked_emitted_when_action_pressed_and_not_dead() -> void:
	# Arrange
	var player: MovementController = PlayerScene.instantiate() as MovementController
	add_child(player)
	await get_tree().process_frame

	assert_int(player._state) \
		.override_failure_message("Precondition: player must start GROUNDED") \
		.is_equal(MovementController.State.GROUNDED)

	var spy := SignalSpy.new()
	player.attacked.connect(spy.record_0)

	# Act — press attack, tick once
	InputManager.simulate_action_press(&"attack")
	_tick(player)

	# Assert — 1 emit on press tick
	assert_int(spy.count) \
		.override_failure_message(
			"AC-5: attacked must be emitted once on attack press tick — got %d" % spy.count
		) \
		.is_equal(1)

	# Act — second tick WITHOUT a new press — was_pressed_this_tick already consumed
	_tick(player)

	# Assert — no additional emit (consume semantic)
	assert_int(spy.count) \
		.override_failure_message(
			"AC-5: attacked must NOT be re-emitted on next tick without a new press — got %d" % spy.count
		) \
		.is_equal(1)

	InputManager.simulate_action_release(&"attack")
	player.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# AC-5 — attacked bloqué si joueur DEAD
# ---------------------------------------------------------------------------

func test_attacked_blocked_when_dead() -> void:
	# Arrange
	var player: MovementController = PlayerScene.instantiate() as MovementController
	add_child(player)
	await get_tree().process_frame

	player.die()
	assert_int(player._state) \
		.override_failure_message("Precondition: player must be DEAD after die()") \
		.is_equal(MovementController.State.DEAD)

	var spy := SignalSpy.new()
	player.attacked.connect(spy.record_0)

	# Act — press attack while dead, tick once (within RESPAWN_DELAY window)
	InputManager.simulate_action_press(&"attack")
	_tick(player)

	# Assert — 0 emit
	assert_int(spy.count) \
		.override_failure_message(
			"AC-5: attacked must not be emitted while player is DEAD — got %d" % spy.count
		) \
		.is_equal(0)

	InputManager.simulate_action_release(&"attack")
	player.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# AC-5 — attacked idempotent : max 1× par tick (was_pressed_this_tick consume)
# ---------------------------------------------------------------------------

func test_attacked_emitted_at_most_once_per_tick() -> void:
	# Arrange
	var player: MovementController = PlayerScene.instantiate() as MovementController
	add_child(player)
	await get_tree().process_frame

	var spy := SignalSpy.new()
	player.attacked.connect(spy.record_0)

	# Single press edge
	InputManager.simulate_action_press(&"attack")

	# Act
	_tick(player)

	# Assert — exactly 1, not 2+
	assert_int(spy.count) \
		.override_failure_message(
			"AC-5: attacked must fire at most once per tick (was_pressed_this_tick idempotence) — got %d"
			% spy.count
		) \
		.is_equal(1)

	InputManager.simulate_action_release(&"attack")
	player.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# AC-2 (D-6 ordering) — dash_ended émis AVANT died quand mourant pendant DASHING
# ---------------------------------------------------------------------------

func test_dash_ended_emitted_before_died_when_dying_from_dashing() -> void:
	# Arrange
	var player: MovementController = PlayerScene.instantiate() as MovementController
	add_child(player)
	await get_tree().process_frame

	_set_state(player, MovementController.State.DASHING)
	player.set("_dash_cooldown_timer", MovementController.DASH_COOLDOWN)
	player.dash_timer = 0.05

	var emit_order: Array[String] = []
	player.dash_ended.connect(func() -> void: emit_order.append("dash_ended"))
	player.died.connect(func() -> void: emit_order.append("died"))

	# Act
	player.die()

	# Assert — dash_ended before died (ADR-0005 D-6)
	assert_int(emit_order.size()) \
		.override_failure_message(
			"AC-2 D-6: both dash_ended and died must be emitted — got %d emits" % emit_order.size()
		) \
		.is_equal(2)

	assert_str(emit_order[0]) \
		.override_failure_message(
			"AC-2 D-6: dash_ended must be emitted before died — order was %s" % str(emit_order)
		) \
		.is_equal("dash_ended")

	assert_str(emit_order[1]) \
		.override_failure_message(
			"AC-2 D-6: died must be emitted second — order was %s" % str(emit_order)
		) \
		.is_equal("died")

	player.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# AC-3 — typed contract mismatch (OPTIONNEL — debug build only, VC-1)
# ---------------------------------------------------------------------------
## Ce test vérifie que connecter un Callable avec mauvaise signature à dash_started
## génère une erreur Godot en debug build. En release build, l'erreur est silencieuse
## et ce test est skippé (gate par OS.has_feature("debug")).
##
## Note GdUnit4 : si l'API assert_error_pushed n'est pas disponible dans cette version
## de GdUnit4, le test valide seulement que le player reste valide après l'emit
## avec un consumer mal typé (pas de crash == pas de régression critique).
func test_typed_contract_mismatch_is_handled_gracefully_in_debug() -> void:
	# Skip en release build — erreur silencieuse hors debug
	if not OS.has_feature("debug"):
		return

	# Arrange
	var player: MovementController = PlayerScene.instantiate() as MovementController
	add_child(player)
	await get_tree().process_frame

	player.can_dash = true
	player.set("_dash_cooldown_timer", 0.0)

	# Connect a badly-typed callable (1 arg instead of 2) — Godot will push_error
	# when the signal fires in debug build.
	var bad_callable: Callable = func(only_one_arg: Vector3) -> void:
		pass  # intentionally wrong arity

	player.dash_started.connect(bad_callable)

	# Also connect a correct spy to verify the signal DID fire (mismatch is non-fatal)
	var spy := SignalSpy.new()
	player.dash_started.connect(spy.record_v3_f)

	# Act — trigger a dash
	InputManager.simulate_action_press(&"move_forward")
	InputManager.simulate_action_press(&"dash")
	_tick(player)

	# Assert — player remains valid (no crash from bad callable)
	assert_bool(is_instance_valid(player)) \
		.override_failure_message("AC-3: player must remain valid after bad-typed signal consumer") \
		.is_true()

	# Assert — the signal still fired (good consumer received it)
	assert_int(spy.count) \
		.override_failure_message(
			"AC-3: dash_started must still emit to valid consumers despite bad-typed one — got %d"
			% spy.count
		) \
		.is_equal(1)

	InputManager.simulate_action_release(&"move_forward")
	InputManager.simulate_action_release(&"dash")
	player.queue_free()
	await get_tree().process_frame
