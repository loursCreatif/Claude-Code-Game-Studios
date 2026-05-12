# Tests unitaires Story-022 — CombatSystem accessibility reduce_motion.
#
# Couvre AC-1 à AC-5 (cf. story-022) + GDD AC-CMB-19 r6 branch C + Section G accessibility :
#   AC-1 : disable_slow_mo=true → 5 kills consécutifs, Engine.time_scale reste 1.0.
#   AC-2 : slow_mo_scale_mult=2.0 → effective_scale=0.6 ± 0.0001 (atténuation 50%).
#   AC-3 : defaults invariant — mult=1.0/disable=false/flash=1.0 → comportement MVP (0.3).
#   AC-4 : settings_changed mid-game → prochain kill respecte nouveau setting.
#   AC-5 : bornes service-level — mult=5.0 clampé à 3.33, mult=0.5 clampé à 1.0.
#
# Pattern : injection via AccessibilityService.apply_settings() pour AC-4 (signal flow),
# injection directe sur combat fields pour AC-1/2/3/5 (isolation pure).
#
# Hermetic teardown : reset AccessibilityService aux defaults + Engine.time_scale=1.0
# après chaque test (cross-test contamination interdite).
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Story    : production/epics/combat-system/story-022-accessibility-reduce-motion-combat.md
# ADR      : ADR-0015 (Accessibility Interface Layer), ADR-0006 D-5 (slow-mo Callable)
# GDD      : design/gdd/player-combat-system.md AC-CMB-19 r6 + Section G

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const SCENE_PATH: String = "res://src/gameplay/combat/combat_system.tscn"
const TIME_SCALE_TOLERANCE: float = 0.0001


# ---------------------------------------------------------------------------
# Lifecycle — hermetic isolation
# ---------------------------------------------------------------------------

func before_test() -> void:
	# Reset AccessibilityService aux defaults pour isolation cross-test.
	AccessibilityService.apply_settings(AccessibilitySettings.create_defaults())


func after_test() -> void:
	# Reset autoload + Engine.time_scale (slow-mo trigger peut polluer cross-test).
	AccessibilityService.apply_settings(AccessibilitySettings.create_defaults())
	Engine.time_scale = 1.0


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


## Builder pour mock `_get_time_msec` retournant des valeurs séquentielles.
class TimeMock extends RefCounted:
	var values: Array[int] = []
	var index: int = 0

	func get_msec() -> int:
		var v: int = values[index] if index < values.size() else values[values.size() - 1]
		index += 1
		return v


# ---------------------------------------------------------------------------
# AC-1 — disable_slow_mo == true → 5 kills, time_scale stays 1.0
# ---------------------------------------------------------------------------

## AC-1 : disable=true → 5 kills consécutifs n'altèrent jamais Engine.time_scale.
## Couvre AC-CMB-19 r6 branch C (déjà partiellement testé story-013, ici via interface ADR-0015).
func test_combat_accessibility_disable_slow_mo_blocks_all_kills() -> void:
	# Arrange — apply settings via service (signal flow réel).
	var s: AccessibilitySettings = AccessibilitySettings.create_defaults()
	s.disable_slow_mo = true
	AccessibilityService.apply_settings(s)

	var combat: CombatSystem = _make_combat()
	var time_mock: TimeMock = TimeMock.new()
	time_mock.values = [1000, 2000, 3000, 4000, 5000]
	combat._get_time_msec = Callable(time_mock, "get_msec")

	# Act — 5 kills "simultanés".
	for _i: int in range(5):
		combat._trigger_slow_mo_if_first_kill()

	# Assert
	assert_float(Engine.time_scale) \
		.override_failure_message("AC-1: time_scale doit rester 1.0 quand disable_slow_mo=true") \
		.is_between(1.0 - TIME_SCALE_TOLERANCE, 1.0 + TIME_SCALE_TOLERANCE)
	assert_bool(combat._slow_mo_active) \
		.override_failure_message("AC-1: _slow_mo_active doit rester false") \
		.is_false()
	assert_int(time_mock.index) \
		.override_failure_message("AC-1: _get_time_msec NE doit PAS être consommé (early return)") \
		.is_equal(0)
	assert_bool(combat._reduce_motion_disable_slow_mo) \
		.override_failure_message("AC-1: cache combat doit refléter service.disable=true") \
		.is_true()

	combat.get_parent().queue_free()


# ---------------------------------------------------------------------------
# AC-2 — slow_mo_scale_mult attenuation (mult=2.0 → 0.6)
# ---------------------------------------------------------------------------

## AC-2 : mult=2.0 → effective_scale = 0.3 × 2.0 = 0.6 ± 0.0001.
func test_combat_accessibility_slow_mo_mult_2_attenuates_to_half() -> void:
	# Arrange
	var s: AccessibilitySettings = AccessibilitySettings.create_defaults()
	s.slow_mo_scale_mult = 2.0
	AccessibilityService.apply_settings(s)

	var combat: CombatSystem = _make_combat()
	var time_mock: TimeMock = TimeMock.new()
	time_mock.values = [1000]
	combat._get_time_msec = Callable(time_mock, "get_msec")

	# Act
	combat._trigger_slow_mo_if_first_kill()

	# Assert
	assert_float(Engine.time_scale) \
		.override_failure_message("AC-2: mult=2.0 → time_scale doit être 0.6 (0.3 × 2.0)") \
		.is_between(0.6 - TIME_SCALE_TOLERANCE, 0.6 + TIME_SCALE_TOLERANCE)
	assert_bool(combat._slow_mo_active).is_true()

	combat.get_parent().queue_free()


## AC-2 edge : mult=3.33 (max bound) → effective_scale ≈ 1.0 (équivalent disable).
func test_combat_accessibility_slow_mo_mult_max_equivalent_to_disable() -> void:
	var s: AccessibilitySettings = AccessibilitySettings.create_defaults()
	s.slow_mo_scale_mult = 3.33
	AccessibilityService.apply_settings(s)

	var combat: CombatSystem = _make_combat()
	combat._get_time_msec = func() -> int: return 1000

	# Act
	combat._trigger_slow_mo_if_first_kill()

	# Assert — clampé à 1.0 max par effective_scale (0.3 × 3.33 = 0.999 → ~1.0).
	# Tolérance large car 0.3 × 3.33 = 0.999 strictement.
	assert_float(Engine.time_scale) \
		.override_failure_message("AC-2 edge: mult=3.33 → time_scale doit être ~1.0") \
		.is_between(0.99, 1.0 + TIME_SCALE_TOLERANCE)

	combat.get_parent().queue_free()


# ---------------------------------------------------------------------------
# AC-3 — Defaults invariant (mult=1.0/disable=false/flash=1.0 → MVP behavior)
# ---------------------------------------------------------------------------

## AC-3 : tous defaults → comportement bit-identique non-accessibility MVP.
## Engine.time_scale = SLOW_MO_SCALE = 0.3 (story-013 baseline preserved).
func test_combat_accessibility_defaults_preserve_mvp_behavior() -> void:
	# Arrange — defaults explicites (already done in before_test, re-affirmé ici).
	AccessibilityService.apply_settings(AccessibilitySettings.create_defaults())

	var combat: CombatSystem = _make_combat()
	combat._get_time_msec = func() -> int: return 1000

	# Assert defaults cached
	assert_bool(combat._reduce_motion_disable_slow_mo) \
		.override_failure_message("AC-3: defaults disable=false") \
		.is_false()
	assert_float(combat._reduce_motion_slow_mo_scale_mult) \
		.override_failure_message("AC-3: defaults mult=1.0") \
		.is_equal_approx(1.0, 0.001)
	assert_float(combat._reduce_motion_flash_mult) \
		.override_failure_message("AC-3: defaults flash=1.0") \
		.is_equal_approx(1.0, 0.001)

	# Act — kill normal
	combat._trigger_slow_mo_if_first_kill()

	# Assert — comportement MVP (slow-mo full = 0.3).
	assert_float(Engine.time_scale) \
		.override_failure_message("AC-3: defaults → time_scale doit être SLOW_MO_SCALE=0.3 (MVP)") \
		.is_between(
			CombatSystem.SLOW_MO_SCALE - TIME_SCALE_TOLERANCE,
			CombatSystem.SLOW_MO_SCALE + TIME_SCALE_TOLERANCE
		)
	assert_bool(combat._slow_mo_active).is_true()

	combat.get_parent().queue_free()


# ---------------------------------------------------------------------------
# AC-4 — Settings reload mid-game via signal flow
# ---------------------------------------------------------------------------

## AC-4 : settings_changed émis avec disable=true mid-game →
## cache combat est mis à jour, prochain kill respecte le nouveau setting.
func test_combat_accessibility_settings_changed_signal_reloads_cache_mid_game() -> void:
	# Arrange — boot avec defaults.
	AccessibilityService.apply_settings(AccessibilitySettings.create_defaults())
	var combat: CombatSystem = _make_combat()
	assert_bool(combat._reduce_motion_disable_slow_mo) \
		.override_failure_message("AC-4: boot doit lire defaults disable=false") \
		.is_false()

	# Act — apply settings mid-game (Settings Menu Tier 2+ flow).
	var new_s: AccessibilitySettings = AccessibilitySettings.create_defaults()
	new_s.disable_slow_mo = true
	new_s.slow_mo_scale_mult = 1.5
	AccessibilityService.apply_settings(new_s)

	# Assert — signal a propagé, cache combat mis à jour.
	assert_bool(combat._reduce_motion_disable_slow_mo) \
		.override_failure_message("AC-4: signal handler doit reloader disable=true") \
		.is_true()
	assert_float(combat._reduce_motion_slow_mo_scale_mult) \
		.override_failure_message("AC-4: signal handler doit reloader mult=1.5") \
		.is_equal_approx(1.5, 0.001)

	# Act 2 — prochain kill doit respecter nouveau setting (disable=true).
	combat._get_time_msec = func() -> int: return 2000
	combat._trigger_slow_mo_if_first_kill()

	# Assert 2 — disable=true bloque, time_scale reste 1.0.
	assert_float(Engine.time_scale) \
		.override_failure_message("AC-4: post-signal, kill respecte disable=true → time_scale=1.0") \
		.is_between(1.0 - TIME_SCALE_TOLERANCE, 1.0 + TIME_SCALE_TOLERANCE)
	assert_bool(combat._slow_mo_active).is_false()

	combat.get_parent().queue_free()


# ---------------------------------------------------------------------------
# AC-5 — Bornes service-level clamping (D-7)
# ---------------------------------------------------------------------------

## AC-5 : settings retourne mult=5.0 (out of bounds [1.0, 3.33]) →
## getter service clamp à 3.33, cache combat reflète 3.33 (pas de panic).
func test_combat_accessibility_slow_mo_mult_above_max_clamped_to_3_33() -> void:
	# Arrange — settings avec mult hors bornes (Resource accepte _range mais le service clampe).
	var s: AccessibilitySettings = AccessibilitySettings.create_defaults()
	s.slow_mo_scale_mult = 5.0  # > 3.33 max
	AccessibilityService.apply_settings(s)

	# Act
	var combat: CombatSystem = _make_combat()

	# Assert — clampé service-level à SLOW_MO_SCALE_MULT_MAX (3.33).
	assert_float(combat._reduce_motion_slow_mo_scale_mult) \
		.override_failure_message("AC-5: mult=5.0 doit être clampé à 3.33 (service D-7)") \
		.is_equal_approx(
			AccessibilityServiceScript.SLOW_MO_SCALE_MULT_MAX, 0.001
		)

	combat.get_parent().queue_free()


## AC-5 : settings retourne mult=0.5 (< 1.0 min) → clampé à 1.0 (atténuation négative interdite).
func test_combat_accessibility_slow_mo_mult_below_min_clamped_to_1_0() -> void:
	var s: AccessibilitySettings = AccessibilitySettings.create_defaults()
	s.slow_mo_scale_mult = 0.5  # < 1.0 min
	AccessibilityService.apply_settings(s)

	# Act
	var combat: CombatSystem = _make_combat()

	# Assert — clampé à 1.0.
	assert_float(combat._reduce_motion_slow_mo_scale_mult) \
		.override_failure_message("AC-5: mult=0.5 doit être clampé à 1.0 (service D-7)") \
		.is_equal_approx(
			AccessibilityServiceScript.SLOW_MO_SCALE_MULT_MIN, 0.001
		)

	combat.get_parent().queue_free()


## AC-5 : flash_mult hors bornes [0.0, 1.0] → clampé.
func test_combat_accessibility_flash_mult_above_max_clamped_to_1_0() -> void:
	var s: AccessibilitySettings = AccessibilitySettings.create_defaults()
	# flash_mult @export_range(0.0, 1.0) — Inspector clamp ne s'applique pas en code,
	# on peut force la valeur out of bounds ici.
	s.flash_mult = 2.0  # > 1.0 max
	AccessibilityService.apply_settings(s)

	# Act
	var combat: CombatSystem = _make_combat()

	# Assert
	assert_float(combat._reduce_motion_flash_mult) \
		.override_failure_message("AC-5: flash_mult=2.0 doit être clampé à 1.0 (service D-7)") \
		.is_equal_approx(AccessibilityServiceScript.FLASH_MULT_MAX, 0.001)

	combat.get_parent().queue_free()
