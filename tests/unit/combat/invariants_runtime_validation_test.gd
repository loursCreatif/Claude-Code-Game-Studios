# Tests unitaires Story-016 — `_validate_invariants()` runtime + cooldown_ratio + smoke check.
#
# Couvre AC-1 à AC-5 (cf. story-016) + AC-CMB-12/13/17/18/36 + Section D.8 invariants :
#   AC-1 : ACTIVE_TICKS = ceil(SWING_DURATION / delta_ms) → 8 (math invariant).
#   AC-2 : cooldown_ratio formula 0..1 clamp.
#   AC-3 : 8 invariants tous PASS sur valeurs courantes.
#   AC-4 : invariant croisé Movement DASH_DURATION (100 ms) < SWING_DURATION_MS (120 ms).
#   AC-5 : safe ranges Section G — limites individuelles.
#
# NOTE : AC-CMB-17 live-tuning (mut runtime puis assert_fail) DEFERRED — les `const` ne sont
# pas mutables en GDScript. Seul un refactor vers `@export var` permettrait de tester ce cas
# (hors scope MVP : invariants assert sur const = vérification compile-effective).
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Story   : production/epics/combat-system/story-016-invariants-runtime-validation-smoke-check.md
# ADR     : ADR-0006 (Combat Tick Model), ADR-0001 (Physics Rate)
# GDD     : design/gdd/player-combat-system.md AC-CMB-12/13/17/18/36 + Section D.8

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const SCENE_PATH: String = "res://src/gameplay/combat/combat_system.tscn"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_combat() -> CombatSystem:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	assert_object(packed).is_not_null()

	var player: CharacterBody3D = CharacterBody3D.new()
	add_child(player)
	var combat: CombatSystem = packed.instantiate() as CombatSystem
	player.add_child(combat)
	return combat


# ---------------------------------------------------------------------------
# AC-1 — ACTIVE_TICKS formula
# ---------------------------------------------------------------------------

## AC-1 : ACTIVE_TICKS == ceili(SWING_DURATION_MS / (delta * 1000)) = ceil(120/16.67) = 8.
func test_combat_active_ticks_matches_ceil_swing_duration_over_delta_ms() -> void:
	var delta_ms: float = 1000.0 / 60.0
	var expected: int = int(ceil(CombatSystem.SWING_DURATION_MS / delta_ms))
	assert_int(CombatSystem.ACTIVE_TICKS) \
		.override_failure_message(
			"AC-1: ACTIVE_TICKS doit être ceil(SWING/delta_ms) = %d — reçu %d"
			% [expected, CombatSystem.ACTIVE_TICKS]
		) \
		.is_equal(expected)
	assert_int(CombatSystem.ACTIVE_TICKS).is_equal(8)


# ---------------------------------------------------------------------------
# AC-2 — cooldown_ratio formula
# ---------------------------------------------------------------------------

## AC-2 : cooldown_ratio formule clamp 0..1.
func test_combat_cooldown_ratio_clamped_zero_to_one() -> void:
	var combat: CombatSystem = _make_combat()
	var max_cooldown: float = CombatSystem.ATTACK_COOLDOWN_MS / 1000.0  # 0.4 s

	# Cooldown 0 → ratio 0
	combat._cooldown_timer = 0.0
	assert_float(combat.get_cooldown_ratio()).is_equal(0.0)

	# Cooldown plein → ratio 1
	combat._cooldown_timer = max_cooldown
	assert_float(combat.get_cooldown_ratio()) \
		.is_between(1.0 - 0.001, 1.0 + 0.001)

	# Cooldown 0.25 → ratio = 0.25/0.4 = 0.625
	combat._cooldown_timer = 0.25
	var expected: float = 0.25 / max_cooldown
	assert_float(combat.get_cooldown_ratio()) \
		.override_failure_message(
			"AC-2: cooldown_ratio à 0.25 doit être 0.625 — reçu %.3f"
			% combat.get_cooldown_ratio()
		) \
		.is_between(expected - 0.001, expected + 0.001)

	# Overflow (cooldown > max — synthétique) → clampé à 1.0
	combat._cooldown_timer = max_cooldown * 2.0
	assert_float(combat.get_cooldown_ratio()) \
		.override_failure_message("AC-2: ratio > 1 doit être clampé à 1.0") \
		.is_between(1.0 - 0.001, 1.0 + 0.001)

	combat.get_parent().queue_free()


# ---------------------------------------------------------------------------
# AC-3 — 8 invariants tous PASS sur valeurs courantes
# ---------------------------------------------------------------------------

## AC-3 : `_validate_invariants` ne panic pas sur les valeurs courantes (debug build).
## Vérifie chaque invariant individuellement comme assertion de test.
func test_combat_all_eight_invariants_pass_on_current_constants() -> void:
	# Invariant #1
	assert_bool(CombatSystem.KATANA_REACH > CombatSystem.PLAYER_CAPSULE_RADIUS + 1.0) \
		.override_failure_message(
			"Invariant #1 FAIL: KATANA_REACH=%.3f doit être > PLAYER_CAPSULE_RADIUS+1.0=%.3f"
			% [CombatSystem.KATANA_REACH, CombatSystem.PLAYER_CAPSULE_RADIUS + 1.0]
		) \
		.is_true()

	# Invariant #2
	assert_float(CombatSystem.KATANA_REACH).is_greater(0.0)

	# Invariant #3
	var min_cd: float = CombatSystem.SWING_DURATION_MS + (1000.0 / 60.0)
	assert_float(CombatSystem.ATTACK_COOLDOWN_MS).is_greater_equal(min_cd)

	# Invariant #4
	assert_float(CombatSystem.ATTACK_COOLDOWN_MS) \
		.override_failure_message(
			"Invariant #4: COOLDOWN (%.2f) > SWING (%.2f) + SLOW_MO (%.2f) = %.2f"
			% [
				CombatSystem.ATTACK_COOLDOWN_MS,
				CombatSystem.SWING_DURATION_MS,
				CombatSystem.SLOW_MO_DURATION_MS,
				CombatSystem.SWING_DURATION_MS + CombatSystem.SLOW_MO_DURATION_MS
			]
		) \
		.is_greater(CombatSystem.SWING_DURATION_MS + CombatSystem.SLOW_MO_DURATION_MS)

	# Invariant #5 anti-tunneling
	var gap_max: float = CombatSystem.V_MAX * (1.0 / 60.0) / float(CombatSystem.N_SUBSTEPS)
	var enemy_diam: float = 2.0 * CombatSystem.ENEMY_RADIUS_MIN
	assert_float(gap_max) \
		.override_failure_message(
			"Invariant #5 anti-tunneling: gap_max (%.4f) doit être < 2 × r_enemy (%.4f)"
			% [gap_max, enemy_diam]
		) \
		.is_less(enemy_diam)

	# Invariant #6
	assert_float(CombatSystem.SLOW_MO_DURATION_MS) \
		.is_less(CombatSystem.ATTACK_COOLDOWN_MS / 2.0)

	# Invariant #7
	assert_float(CombatSystem.ATTACK_BUFFER_MS) \
		.is_less_equal(CombatSystem.ATTACK_COOLDOWN_MS / 5.0)

	# Invariant #8 duty cycle staccato
	var duty: float = CombatSystem.SWING_DURATION_MS \
			/ (CombatSystem.SWING_DURATION_MS + CombatSystem.ATTACK_COOLDOWN_MS)
	assert_float(duty) \
		.override_failure_message("Invariant #8 duty cycle = %.3f doit être < 0.4" % duty) \
		.is_less(0.4)


# ---------------------------------------------------------------------------
# AC-4 — Invariant croisé Movement DASH_DURATION < SWING_DURATION_MS
# ---------------------------------------------------------------------------

## AC-CMB-18 : DASH_DURATION (Movement) < SWING_DURATION_MS (Combat).
## Garantit qu'un swing démarré à mi-dash finit en Airborne (Rule 8).
func test_combat_swing_duration_greater_than_movement_dash_duration() -> void:
	# DASH_DURATION dans Movement = 0.10 s = 100 ms (cf. movement_controller.gd).
	# Si MovementController exposé (via class_name), on peut le lire.
	var dash_duration_ms: float = MovementController.DASH_DURATION * 1000.0
	assert_float(CombatSystem.SWING_DURATION_MS) \
		.override_failure_message(
			"AC-CMB-18: SWING_DURATION_MS (%.0f) doit être > DASH_DURATION_MS (%.0f) " \
			% [CombatSystem.SWING_DURATION_MS, dash_duration_ms] \
			+ "pour qu'un swing à mi-dash finisse en Airborne (Rule 8)"
		) \
		.is_greater(dash_duration_ms)


# ---------------------------------------------------------------------------
# AC-5 — Safe ranges Section G (smoke check ranges)
# ---------------------------------------------------------------------------

## AC-CMB-36 (smoke check) : valeurs Combat dans les safe ranges Section G du GDD.
## Range guardrails sanity (pas du tuning live, juste des plafonds raisonnables).
func test_combat_constants_within_safe_design_ranges() -> void:
	# SWING_DURATION_MS : [50, 200] ms (raisonnable pour staccato un-coup-tue)
	assert_float(CombatSystem.SWING_DURATION_MS).is_between(50.0, 200.0)

	# ATTACK_COOLDOWN_MS : [200, 1000] ms (Pillar 1 fluidité, Pillar 4 patience)
	assert_float(CombatSystem.ATTACK_COOLDOWN_MS).is_between(200.0, 1000.0)

	# ATTACK_BUFFER_MS : [40, 120] ms (input forgiveness sans dégrader la précision)
	assert_float(CombatSystem.ATTACK_BUFFER_MS).is_between(40.0, 120.0)

	# SLOW_MO_DURATION_MS : [30, 100] ms wall-clock (= 100-333 ms perçu @ scale 0.3)
	assert_float(CombatSystem.SLOW_MO_DURATION_MS).is_between(30.0, 100.0)

	# SLOW_MO_SCALE : [0.2, 0.5] (assez visible mais pas léthargique)
	assert_float(CombatSystem.SLOW_MO_SCALE).is_between(0.2, 0.5)

	# KATANA_REACH : [1.5, 3.0] m (un step de player + marge — pas trop agressif)
	assert_float(CombatSystem.KATANA_REACH).is_between(1.5, 3.0)

	# KATANA_RADIUS : [0.3, 0.6] m (assez large pour grace, pas exagéré)
	assert_float(CombatSystem.KATANA_RADIUS).is_between(0.3, 0.6)

	# N_SUBSTEPS : 3 exact (formule déterministe — pas une range)
	assert_int(CombatSystem.N_SUBSTEPS).is_equal(3)
