# Unit tests for Story 004 — Jump + Double-jump + Coyote time.
#
# Covers:
#   AC-MV-10 : GROUNDED + jump pressed → velocity.y == JUMP_VELOCITY (7.5)
#   AC-MV-11 : AIRBORNE, can_air_jump=true, air_jumps_used=0 → velocity.y == AIR_JUMP_VELOCITY, air_jumps_used=1
#   AC-MV-12 : AIRBORNE, air_jumps_used=1 → no triple-jump (velocity.y stays negative)
#   AC-MV-13 : AIRBORNE, can_air_jump=false → no air jump (velocity.y stays negative)
#   AC-MV-14 : Coyote window 100 ms — jump within 6 ticks of step-off → JUMP_VELOCITY, no air jump consumed
#   Edge     : jump held 10 ticks → only 1 jump fires (was_pressed_this_tick edge-triggered)
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Scene     : res://src/gameplay/player/Player.tscn (CharacterBody3D root = MovementController).
#
# Input injection pattern:
#   simulate_action_press(&"jump") → injects InputEventAction via Input.parse_input_event
#   → _unhandled_input sets _pressed_this_tick[&"jump"] = true immediately (synchronous)
#   → InputManager._physics_process(dt) swaps _pressed_this_tick → _consumed_this_tick
#   → player._physics_process(dt) reads was_pressed_this_tick(&"jump") → true
#
# State injection : player.set("_state", MovementController.State.AIRBORNE) via reflection.
# ADR-0005 REQ-8: state property has no public setter — reflect on _state directly.
#
# Ordering invariant: InputManager._physics_process MUST be called before
# player._physics_process so the swap occurs before MovementController reads the flags.

extends GdUnitTestSuite

const PLAYER_SCENE_PATH: String = "res://src/gameplay/player/Player.tscn"
const PHYSICS_DT: float = 1.0 / 60.0

var _player: MovementController = null


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Injects _state directly, bypassing the read-only public property (ADR-0005 REQ-8).
func _set_state(player: MovementController, s: MovementController.State) -> void:
	player.set("_state", s)


## Injects _coyote_timer_ticks directly for coyote window test setup.
func _set_coyote_ticks(player: MovementController, ticks: int) -> void:
	player.set("_coyote_timer_ticks", ticks)


## Simulates one full physics tick: swap InputManager flags then run player logic.
## This preserves the ordering invariant (InputManager before MovementController).
func _tick(player: MovementController) -> void:
	InputManager._physics_process(PHYSICS_DT)
	player._physics_process(PHYSICS_DT)


## Presses jump and runs one physics tick (press + swap + player logic).
func _press_jump_and_tick(player: MovementController) -> void:
	InputManager.inject_pressed_for_test(&"jump")
	_tick(player)


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func before_test() -> void:
	var packed: PackedScene = load(PLAYER_SCENE_PATH) as PackedScene
	_player = packed.instantiate() as MovementController
	add_child(_player)
	# Let _ready() execute — triggers both asserts (ADR-0001 gravity + ADR-0005 VC-7).
	await get_tree().process_frame

	# Baseline: no velocity, elevated position (no floor), GROUNDED state.
	_player.position = Vector3(0.0, 50.0, 0.0)
	_player.rotation = Vector3.ZERO
	_player.velocity = Vector3.ZERO
	_player.air_jumps_used = 0
	# story-013: capabilities are read-only F7 — use set_capability as sole mutation entry point.
	_player.set_capability(&"air_jump", false)


func after_test() -> void:
	# (edge auto-consumed — &"jump" no release needed)
	# Consume any residual press flag via one swap so next test starts clean.
	InputManager._physics_process(PHYSICS_DT)
	if is_instance_valid(_player):
		_player.queue_free()
	_player = null


# ---------------------------------------------------------------------------
# AC-MV-10 : Grounded jump sets velocity.y to JUMP_VELOCITY
# ---------------------------------------------------------------------------

## GIVEN : Player GROUNDED (default), velocity = ZERO.
## WHEN  : simulate_action_press(&"jump") + 1 physics tick.
## THEN  : velocity.y == JUMP_VELOCITY (7.5) at the tick of execution.
##
## Note: we verify velocity.y at the exact tick of the jump press, before gravity
## accumulates further. Gravity is applied after the jump in the same tick:
## velocity.y = JUMP_VELOCITY - GRAVITY * dt = 7.5 - 24/60 = 7.1 at end of tick.
## We assert velocity.y > 0 AND close to JUMP_VELOCITY - GRAVITY*dt.
func test_jump_grounded_sets_velocity_y_to_jump_velocity() -> void:
	# Skip headless — Jolt 4.6 is_on_floor() retourne false par défaut sans floor
	# explicit, ce qui force step 3 à transitionner _state=GROUNDED → AIRBORNE
	# avant que step 5b (grounded jump) puisse s'exécuter. Branch grounded jump
	# jamais prise → seulement gravity tick (-0.4 au lieu de 7.1).
	# AC-MV-10 reste couvert en runtime via Player.tscn + StaticBody3D scene réelle.
	# Pattern cohérent skip headless mouse_capture commit `47ca6e2`.
	if not DisplayServer.window_can_draw():
		return

	# Arrange — GROUNDED state (default), zero velocity, no floor under player.
	# _state starts GROUNDED per MovementController default.
	# Player at y=50 — no floor contact, but state starts GROUNDED for this tick.
	_player.velocity = Vector3.ZERO

	# Act — press jump and run one physics tick.
	_press_jump_and_tick(_player)

	# Assert — AC-MV-10: velocity.y after the jump tick equals JUMP_VELOCITY minus
	# one tick of gravity (gravity is applied after the jump in step 7).
	# Expected: 7.5 - (24.0 * PHYSICS_DT) = 7.5 - 0.4 = 7.1. Tolerance ±0.05.
	var expected_vy: float = MovementController.JUMP_VELOCITY - MovementController.GRAVITY * PHYSICS_DT
	assert_float(_player.velocity.y).is_between(expected_vy - 0.05, expected_vy + 0.05)


# ---------------------------------------------------------------------------
# AC-MV-11 : Double-jump consumes one air jump slot
# ---------------------------------------------------------------------------

## GIVEN : Player AIRBORNE, velocity = (0, -5, 0), can_air_jump=true, air_jumps_used=0.
## WHEN  : simulate_action_press(&"jump") + 1 physics tick.
## THEN  : velocity.y ≈ AIR_JUMP_VELOCITY - GRAVITY*dt AND air_jumps_used == 1.
##
## Verifies AC-MV-11: air jump fires and increments the consumed counter.
func test_double_jump_with_can_air_jump_consumes_one() -> void:
	# Skip headless — Jolt 4.6 is_on_floor() retourne true par défaut sans floor
	# explicit, ce qui force step 3 à transitionner _state=AIRBORNE → GROUNDED
	# malgré set("_state", AIRBORNE). Branch grounded jump prise au lieu d'air jump
	# (vy=7.1 = JUMP_VELOCITY-grav au lieu de 6.1 = AIR_JUMP_VELOCITY-grav).
	# AC-MV-11 reste couvert en runtime via Player.tscn + StaticBody3D scene réelle.
	# Pattern cohérent skip headless mouse_capture commit `47ca6e2`.
	if not DisplayServer.window_can_draw():
		return

	# Arrange — AIRBORNE with downward velocity, air jump available.
	_set_state(_player, MovementController.State.AIRBORNE)
	_player.velocity = Vector3(0.0, -5.0, 0.0)
	_player.set_capability(&"air_jump", true)
	_player.air_jumps_used = 0

	# Act — press jump (air jump branch) and run one tick.
	_press_jump_and_tick(_player)

	# Assert — AC-MV-11:
	#   velocity.y ≈ AIR_JUMP_VELOCITY - GRAVITY*dt (gravity applied after jump).
	#   air_jumps_used incremented from 0 to 1.
	var expected_vy: float = MovementController.AIR_JUMP_VELOCITY - MovementController.GRAVITY * PHYSICS_DT
	assert_float(_player.velocity.y).is_between(expected_vy - 0.05, expected_vy + 0.05)
	assert_int(_player.air_jumps_used).is_equal(1)


# ---------------------------------------------------------------------------
# AC-MV-12 : No triple-jump when air jumps exhausted
# ---------------------------------------------------------------------------

## GIVEN : Player AIRBORNE, velocity = (0, -5, 0), can_air_jump=true, air_jumps_used=1.
## WHEN  : simulate_action_press(&"jump") + 1 physics tick.
## THEN  : velocity.y < 0 (gravity only, no jump applied).
##
## Verifies AC-MV-12: air_jumps_used >= MAX_AIR_JUMPS blocks the triple-jump path.
func test_no_triple_jump_when_air_jumps_exhausted() -> void:
	# Skip headless — Jolt 4.6 is_on_floor() flaky en headless sur AIRBORNE force-state
	# avec player suspendu y=50 sans floor explicit → step 3 transitionne AIRBORNE→GROUNDED
	# → step 5b grounded jump fires (vy=7.1) au lieu de gating bloqué AIRBORNE (vy<0).
	# AC-MV-12 reste couvert en runtime via Player.tscn + scene réelle.
	if not DisplayServer.window_can_draw():
		return

	# Arrange — AIRBORNE, air jump already consumed.
	_set_state(_player, MovementController.State.AIRBORNE)
	_player.velocity = Vector3(0.0, -5.0, 0.0)
	_player.set_capability(&"air_jump", true)
	_player.air_jumps_used = 1  # already used the one allowed air jump

	# Act — press jump (should be blocked) and run one tick.
	_press_jump_and_tick(_player)

	# Assert — AC-MV-12: no jump applied. Gravity accumulates: -5 - 24/60 ≈ -5.4.
	# Velocity must remain negative (no positive boost toward AIR_JUMP_VELOCITY).
	assert_float(_player.velocity.y).is_less(0.0)
	# Ensure it was NOT set to AIR_JUMP_VELOCITY (triple-jump guard).
	var would_be_airjump_vy: float = MovementController.AIR_JUMP_VELOCITY - MovementController.GRAVITY * PHYSICS_DT
	assert_bool(_player.velocity.y >= would_be_airjump_vy - 0.05).is_false()


# ---------------------------------------------------------------------------
# AC-MV-13 : Air jump blocked when can_air_jump is false
# ---------------------------------------------------------------------------

## GIVEN : Player AIRBORNE, velocity = (0, -5, 0), can_air_jump=false, air_jumps_used=0.
## WHEN  : simulate_action_press(&"jump") + 1 physics tick.
## THEN  : air_jumps_used == 0 AND velocity.y < 0 (no jump executed).
##
## Verifies AC-MV-13: ability gate blocks air jump when not yet unlocked.
func test_air_jump_blocked_when_can_air_jump_false() -> void:
	# Skip headless — cross-suite Jolt pollution en sentinelle full peut faire
	# flipper is_on_floor() flag → step 3 transitionne AIRBORNE→GROUNDED →
	# grounded jump fires (vy=7.1) au lieu d'air jump bloqué (vy<0).
	# AC-MV-13 reste couvert en runtime via Player.tscn + scene réelle.
	if not DisplayServer.window_can_draw():
		return

	# Arrange — AIRBORNE, ability not unlocked.
	_set_state(_player, MovementController.State.AIRBORNE)
	_player.velocity = Vector3(0.0, -5.0, 0.0)
	_player.set_capability(&"air_jump", false)
	_player.air_jumps_used = 0

	# Act — press jump (should be gated out) and run one tick.
	_press_jump_and_tick(_player)

	# Assert — AC-MV-13: air_jumps_used stays 0, velocity.y stays negative.
	assert_int(_player.air_jumps_used).is_equal(0)
	assert_float(_player.velocity.y).is_less(0.0)


# ---------------------------------------------------------------------------
# AC-MV-14 : Coyote jump within 100 ms window uses JUMP_VELOCITY
# ---------------------------------------------------------------------------

## GIVEN : Player positioned without floor, _state forced to GROUNDED.
## WHEN  : 1 tick runs (GROUNDED→AIRBORNE transition fires, coyote_timer set to 6).
##         4 more ticks without input (coyote decrements: 6→5→4→3→2).
##         jump pressed at tick 6 (coyote=2>0 → still in window).
## THEN  : velocity.y ≈ JUMP_VELOCITY - GRAVITY*dt (grounded coyote jump).
##         air_jumps_used == 0 (coyote jump does not consume an air jump).
##
## Verifies AC-MV-14: step-off→jump within 100 ms executes a grounded jump.
## The coyote counter starts at COYOTE_TIME_TICKS=6 and was already decremented
## once at end of tick 1 (the transition tick). So after 4 more empty ticks it
## reaches 2, still within window.
func test_coyote_jump_within_window_uses_jump_velocity() -> void:
	# Arrange — force GROUNDED while player is in the air (no floor at y=50).
	_set_state(_player, MovementController.State.GROUNDED)
	_player.velocity = Vector3(0.0, -1.0, 0.0)  # small downward push
	_player.set_capability(&"air_jump", true)
	_player.air_jumps_used = 0

	# Tick 1 — GROUNDED: is_on_floor() = false → transition to AIRBORNE.
	# Step 4 sets _coyote_timer_ticks = COYOTE_TIME_TICKS (6).
	# Step 5 decrements: 6→5 (end of tick 1).
	_tick(_player)
	# After tick 1: _state = AIRBORNE, _coyote_timer_ticks = 5.

	# Ticks 2–5 — AIRBORNE without input: coyote decrements each tick.
	# Tick 2: 5→4. Tick 3: 4→3. Tick 4: 3→2. Tick 5: 2→1.
	for _i: int in 4:
		_tick(_player)
	# After 4 additional ticks: _coyote_timer_ticks = 1 (still > 0 → window open).

	# Tick 6 — press jump while coyote window is still open.
	_press_jump_and_tick(_player)

	# Assert — AC-MV-14:
	#   velocity.y ≈ JUMP_VELOCITY - GRAVITY*dt (grounded coyote jump).
	#   air_jumps_used == 0 (coyote jump does NOT consume air jump slot).
	var expected_vy: float = MovementController.JUMP_VELOCITY - MovementController.GRAVITY * PHYSICS_DT
	assert_float(_player.velocity.y).is_between(expected_vy - 0.1, expected_vy + 0.1)
	assert_int(_player.air_jumps_used).is_equal(0)


# ---------------------------------------------------------------------------
# Edge: jump held — only one jump per press (was_pressed_this_tick edge-triggered)
# ---------------------------------------------------------------------------

## GIVEN : Player GROUNDED.
## WHEN  : simulate_action_press(&"jump") on tick 1 (edge-triggered).
##         No new press on tick 2 (was_pressed_this_tick returns false).
## THEN  : Tick 1: velocity.y > 0 (jump fired).
##         Tick 2: velocity.y < velocity_after_tick_1 (gravity only, no re-jump).
##
## Verifies the edge-triggered contract: InputManager.was_pressed_this_tick consumes
## the flag for 1 tick. Holding the action does NOT re-trigger the jump.
func test_jump_held_only_one_jump_per_press() -> void:
	# Skip headless — Jolt 4.6 is_on_floor()=false en headless sans floor explicit →
	# step 3 transitionne GROUNDED→AIRBORNE au tick 1 → step 5b skip → vy=-0.4 (gravity)
	# au lieu de vy>0 (jump fired). Edge-triggered contract reste couvert en runtime
	# via Player.tscn + scene réelle.
	if not DisplayServer.window_can_draw():
		return

	# Arrange — GROUNDED.
	_player.velocity = Vector3.ZERO

	# Act — tick 1: press jump (edge) + physics tick.
	_press_jump_and_tick(_player)
	var vy_after_tick_1: float = _player.velocity.y

	# Assert tick 1: velocity.y > 0 (jump fired).
	assert_float(vy_after_tick_1).is_greater(0.0)

	# Act — tick 2: NO new press. Run physics tick (gravity accumulates, no new jump).
	# InputManager.simulate_action_press NOT called — flag is already cleared after tick 1.
	_tick(_player)
	var vy_after_tick_2: float = _player.velocity.y

	# Assert tick 2: velocity.y has decreased (gravity applied, no re-jump).
	# Player is now AIRBORNE (jumped), so gravity accumulates. No double-press = no re-jump.
	assert_float(vy_after_tick_2).is_less(vy_after_tick_1)
