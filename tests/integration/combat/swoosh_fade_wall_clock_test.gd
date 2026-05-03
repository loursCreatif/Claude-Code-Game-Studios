# Tests integration Story-020 — Swoosh fade-out wall-clock sous slow-mo.
#
# Couvre AC-CMB-51 (a/b/c/d) :
#   AC-CMB-51 (a) : interpolation wall-clock dans `_physics_process` (PAS Tween `_process`).
#   AC-CMB-51 (b) : à t = 25/30 (83% du fade) : `volume_db ≈ -20 dB ± 2 dB`.
#   AC-CMB-51 (c) : à t = 30/30 (100% du fade) : `volume_db ≤ -60 dB` (silence pratique).
#   AC-CMB-51 (d) : résolution complète dans `[25, 50] ms wall-clock` (sous Engine.time_scale=0.3
#                   pour valider qu'un Tween `_process`-based produirait 75-100 ms et FAIL).
#
# Pattern d'injection : `_get_time_msec: Callable` sur MockAudioHandler, séquence mockée
# `[1000, 1015, 1025, 1030, 1050]` (cf. story-020 Implementation Notes + ADR-0006 D-5 réutilisé).
#
# Teardown obligatoire : `Engine.time_scale = 1.0` en `after_test()` — sinon contamination
# cross-test process-wide (analogue slow_mo_wall_clock_test pattern AC-CMB-19 r6 teardown clause).
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Story   : production/epics/combat-system/story-020-audio-swoosh-fade-multi-kill-ducking.md
# ADR     : ADR-0006 D-4c (mock contract) + D-5 (Callable injection)
# GDD     : design/gdd/player-combat-system.md AC-CMB-51

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const HANDLER_PATH: String = "res://tests/unit/combat/mock_audio_handler.gd"
const DELTA_60HZ: float = 1.0 / 60.0
const DB_TOLERANCE: float = 2.0
const SLOW_MO_TIME_SCALE: float = 0.3


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func after_test() -> void:
	# Teardown obligatoire — restore le state global qu'on a muté en setup AC-CMB-51 (d).
	Engine.time_scale = 1.0
	# NB : pas de queue_free explicite ici — GdUnit4 gère le cleanup du test scope.
	# Ajout explicite de `for child: Node in get_children(): child.queue_free()` provoque
	# un hang sur le 2e test (handler du test 1 fade-active reste vivant via queue_free
	# défer + scene tree run inter-test). Pattern slow_mo_wall_clock_test.gd queue_free
	# explicite n'a pas le même handler-restant-fade-active issue (slow-mo se résout 50 ms).


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Builder pour mock `_get_time_msec` retournant des valeurs séquentielles depuis un array.
##
## **Pattern empirique `extends Node` + `add_child`** : quand TimeMock est créé dans un
## helper qui retourne, un `extends RefCounted` local échoue à conserver la cible du
## Callable injecté côté handler (`Attempt to call function 'null::get_msec' on null instance`,
## cf. report 328 → fix dans report 330). En l'attachant à la scene tree via `add_child`,
## le Node survit jusqu'au teardown `after_test()`. Le pattern `slow_mo_wall_clock_test.gd`
## utilise `extends RefCounted` car le mock y est créé dans le scope direct du test (pas
## dans un helper qui retourne) — la lifetime est garantie par la frame stack du test.
class TimeMock extends Node:
	var values: Array[int] = []
	var index: int = 0

	func get_msec() -> int:
		var v: int = values[index] if index < values.size() else values[values.size() - 1]
		index += 1
		return v


func _make_handler_with_mock_time(time_values: Array[int]) -> Node:
	var handler: Node = (load(HANDLER_PATH) as Script).new()
	add_child(handler)
	var time_mock: TimeMock = TimeMock.new()
	time_mock.values = time_values
	add_child(time_mock)
	handler._get_time_msec = Callable(time_mock, "get_msec")
	return handler


# ---------------------------------------------------------------------------
# AC-CMB-51 (a) — Fade interpolation runs in `_physics_process` (not `_process`)
# ---------------------------------------------------------------------------

## AC-CMB-51 (a) : trigger via `_on_enemy_killed`, puis 1 appel `_physics_process` doit
## actualiser `swoosh_volume_db` (preuve : la rampe avance via _physics_process, pas `_process`).
func test_swoosh_fade_interpolates_in_physics_process_not_process() -> void:
	# Arrange : time mocks [1000 (trigger), 1015 (1st physics tick)]
	var handler: Node = _make_handler_with_mock_time([1000, 1015])

	# Pre-condition : volume nominal, fade inactif.
	assert_float(handler.swoosh_volume_db).is_equal_approx(handler.SWOOSH_NOMINAL_DB, 0.001)
	assert_bool(handler._swoosh_fade_active).is_false()

	# Act 1 : trigger fade via enemy_killed (consume 1000 → fade_start).
	handler._on_enemy_killed(null, Vector3.ZERO)
	assert_bool(handler._swoosh_fade_active).is_true()
	assert_int(handler._swoosh_fade_start_msec).is_equal(1000)

	# Act 2 : appel `_physics_process` consume 1015 → t = 15/30 = 0.5 → lerpf(0, -24, 0.5) = -12 dB.
	handler._physics_process(DELTA_60HZ)

	# Assert : volume a bougé (preuve interpolation _physics_process).
	assert_float(handler.swoosh_volume_db) \
		.override_failure_message(
			("AC-CMB-51 (a) : `_physics_process` doit interpoler le fade " \
			+ "(volume attendu ≈ -12 dB à t=0.5, obtenu %f)") % handler.swoosh_volume_db
		) \
		.is_between(-12.0 - DB_TOLERANCE, -12.0 + DB_TOLERANCE)
	assert_bool(handler._swoosh_fade_active).is_true()


# ---------------------------------------------------------------------------
# AC-CMB-51 (b) — At 25 ms wall-clock (83% of fade), volume_db ≈ -20 dB ± 2 dB
# ---------------------------------------------------------------------------

## AC-CMB-51 (b) : la séquence canonique du GDD `[1000, 1015, 1025, 1030, 1050]` consume :
##   - 1000 au trigger (fade_start)
##   - 1015 au tick 1 (t=0.5, ≈ -12 dB)
##   - 1025 au tick 2 (t=0.833, ≈ -20 dB ± 2 dB) → ASSERT
func test_swoosh_fade_at_25ms_wall_clock_yields_minus_20_db() -> void:
	var handler: Node = _make_handler_with_mock_time([1000, 1015, 1025, 1030, 1050])

	handler._on_enemy_killed(null, Vector3.ZERO)
	handler._physics_process(DELTA_60HZ)  # consume 1015 (t=0.5)
	handler._physics_process(DELTA_60HZ)  # consume 1025 (t=0.833)

	# At t=0.833 : lerpf(0.0, -24.0, 0.833) = -19.99 dB ∈ [-22, -18].
	assert_float(handler.swoosh_volume_db) \
		.override_failure_message(
			("AC-CMB-51 (b) : à 25 ms wall-clock (83%% du fade), volume_db doit être " \
			+ "-20 dB ± 2 dB (obtenu %f). Si valeur ≈ -66 dB, l'implémentation " \
			+ "utilise lerpf(0,-80) sans snap silence — diverge du AC.") % handler.swoosh_volume_db
		) \
		.is_between(-20.0 - DB_TOLERANCE, -20.0 + DB_TOLERANCE)
	assert_bool(handler._swoosh_fade_active) \
		.override_failure_message("AC-CMB-51 (b) : fade actif à t=0.833 (avant fin)") \
		.is_true()


# ---------------------------------------------------------------------------
# AC-CMB-51 (c) — At 30 ms wall-clock (100% of fade), volume_db ≤ -60 dB
# ---------------------------------------------------------------------------

## AC-CMB-51 (c) : à t = 30/30 = 1.0, snap à silence (-80 dB), satisfait `≤ -60 dB`.
func test_swoosh_fade_at_30ms_wall_clock_reaches_silence() -> void:
	var handler: Node = _make_handler_with_mock_time([1000, 1015, 1025, 1030])

	handler._on_enemy_killed(null, Vector3.ZERO)
	handler._physics_process(DELTA_60HZ)  # consume 1015
	handler._physics_process(DELTA_60HZ)  # consume 1025
	handler._physics_process(DELTA_60HZ)  # consume 1030 (t=1.0 → snap silence)

	# Snap à SWOOSH_SILENCE_DB (-80) à t≥1.0. Assertion AC = ≤ -60 dB.
	assert_float(handler.swoosh_volume_db) \
		.override_failure_message(
			("AC-CMB-51 (c) : à 30 ms wall-clock (100%% du fade), volume_db doit être " \
			+ "≤ -60 dB silence pratique (obtenu %f)") % handler.swoosh_volume_db
		) \
		.is_less_equal(-60.0)
	assert_bool(handler._swoosh_fade_active) \
		.override_failure_message("AC-CMB-51 (c) : fade doit être inactif post-snap silence") \
		.is_false()


# ---------------------------------------------------------------------------
# AC-CMB-51 (d) — Resolution within [25, 50] ms wall-clock (under time_scale=0.3)
# ---------------------------------------------------------------------------

## AC-CMB-51 (d) : sous `Engine.time_scale = 0.3` (slow-mo), le fade wall-clock ne doit
## PAS être affecté par time_scale (preuve : injection wall-clock vs Tween scaled).
## Résolution complète à 30 ms wall-clock + 1 frame tolerance ≤ 50 ms.
##
## Si le test observe résolution à 75-100 ms wall-clock → indicateur d'un Tween `_process`-based
## (Tween scaled par time_scale=0.3 produit 30/0.3 = 100 ms wall-clock perçus) → AC FAIL.
func test_swoosh_fade_resolution_unaffected_by_engine_time_scale() -> void:
	# Setup slow-mo (mute global state — restore obligatoire en after_test).
	Engine.time_scale = SLOW_MO_TIME_SCALE

	var handler: Node = _make_handler_with_mock_time([1000, 1015, 1025, 1030, 1050])

	handler._on_enemy_killed(null, Vector3.ZERO)
	# Tick à 1015 (15 ms wall-clock) : fade actif, en cours.
	handler._physics_process(DELTA_60HZ)
	assert_bool(handler._swoosh_fade_active) \
		.override_failure_message("AC-CMB-51 (d) : à 15 ms wall-clock, fade encore actif") \
		.is_true()

	# Tick à 1025 (25 ms wall-clock) : fade actif, en cours.
	handler._physics_process(DELTA_60HZ)
	assert_bool(handler._swoosh_fade_active) \
		.override_failure_message("AC-CMB-51 (d) : à 25 ms wall-clock, fade encore actif") \
		.is_true()

	# Tick à 1030 (30 ms wall-clock) : fade résolu (snap silence).
	handler._physics_process(DELTA_60HZ)
	assert_bool(handler._swoosh_fade_active) \
		.override_failure_message(
			"AC-CMB-51 (d) : fade doit être résolu à 30 ms wall-clock même sous time_scale=0.3. " \
			+ "Si encore actif, l'implémentation est probablement Tween-scaled (FAIL r4 A-01)."
		) \
		.is_false()
	assert_float(handler.swoosh_volume_db).is_less_equal(-60.0)

	# Tick suivant (1050 = 50 ms wall-clock) : reste silencieux.
	handler._physics_process(DELTA_60HZ)
	assert_float(handler.swoosh_volume_db).is_less_equal(-60.0)
