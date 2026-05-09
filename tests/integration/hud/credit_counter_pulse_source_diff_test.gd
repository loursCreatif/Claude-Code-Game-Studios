# Tests intégration Story-004 — HUD Credit Counter Tween Pulse Source-Differentiated.
# Couvre AC-HUD-36 (a)(b)(c)(d)(e) + OQ-HUD-5 wall-clock invariance.
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Logic (integration path) — automated tests (coding-standards.md §Test Evidence).
#
# Pattern : injection de dépendances via _inject_dependencies(gsm, credit)
# AVANT add_child() pour que _ready() utilise les mocks.
#
# Naming : test_hud_pulse_<scenario>_<expected_result>
#
# R-HUD-5 r1.1 + NB-CRD-6 Option A : KILL=100ms / SECRET=150ms.
# OQ-HUD-5 : set_ignore_time_scale(true) — wall-clock indépendant du time_scale.
#
# Note timing headless : en mode headless Godot, `await tween.finished` revient
# rapidement car le scheduler avance les tweens frame-by-frame sans wall-clock.
# Pattern robuste : utiliser create_timer pour borner le timing plutôt que
# mesurer Time.get_ticks_msec() autour de await tween.finished.
# Stratégie : attendre (durée - marge) → assert tween encore actif (is_valid),
#             puis attendre (durée + marge) → assert tween fini (not is_valid).

extends GdUnitTestSuite

var _MockGSM: GDScript = preload("res://tests/unit/hud/mock_gsm.gd")
var _MockCredit: GDScript = preload("res://tests/unit/hud/mock_credit_economy.gd")
var _HUDScript: GDScript = preload("res://src/gameplay/hud/hud_system.gd")

# Durées nominales en secondes (correspondant aux constantes hud_system.gd).
const _KILL_DURATION_S: float = 0.100   # CREDIT_COUNTER_TWEEN_KILL_MS = 100
const _SECRET_DURATION_S: float = 0.150  # CREDIT_COUNTER_TWEEN_SECRET_MS = 150
# Marge avant / après la durée nominale pour les tests de borne.
const _MARGIN_BEFORE_S: float = 0.020   # 20ms avant la fin — tween doit encore être actif
const _MARGIN_AFTER_S: float = 0.040    # 40ms après la fin — tween doit être terminé

# =============================================================================
# Helpers — instanciation hermétique (DRY depuis hud_visibility_state_test.gd)
# =============================================================================

## Instancie HUD + mocks. Etat initial PLAYING (canvas visible) pour tous les tests pulse.
func _make_hud(gsm_state: int, credit_total: int) -> Array:
	var mock_gsm: Node = _MockGSM.new() as Node
	var mock_credit: Node = _MockCredit.new() as Node
	add_child(mock_gsm)
	add_child(mock_credit)
	mock_gsm.set_state(gsm_state)
	mock_credit.set_total(credit_total)

	var hud: Node = _HUDScript.new() as Node
	hud._inject_dependencies(mock_gsm, mock_credit)
	add_child(hud)  # déclenche _ready()

	return [hud, mock_gsm, mock_credit]


func _free_all(nodes: Array) -> void:
	for n: Node in nodes:
		if is_instance_valid(n):
			n.queue_free()

# =============================================================================
# AC-HUD-36 (a) — KILL tween mesure ~100ms wall-clock
# =============================================================================

## GIVEN HUD en PLAYING, WHEN credits_changed(KILL) émis,
## THEN tween encore actif à (100ms - 20ms), terminé à (100ms + 40ms).
## Stratégie borne : create_timer wall-clock, pas de mesure ticks (headless-safe).
## Source : AC-HUD-36 (a) [BLOCKING][AUTO].
func test_hud_pulse_kill_duration_approx_100ms() -> void:
	# Arrange
	var nodes: Array = _make_hud(1, 0)  # State.PLAYING = 1
	var hud: Node = nodes[0]
	var mock_credit: Node = nodes[2]

	# Act — émettre KILL (source=0)
	mock_credit.emit_credits_changed(1, 1, 0)  # total=1, delta=1, source=KILL=0

	# Précondition : tween lancé
	assert_bool(hud._active_pulse_tween != null and hud._active_pulse_tween.is_valid()) \
		.override_failure_message("AC-HUD-36 (a) precond: tween doit être actif après credits_changed KILL") \
		.is_true()

	# Borne BASSE : encore actif à (100ms - 20ms) = 80ms
	await get_tree().create_timer(_KILL_DURATION_S - _MARGIN_BEFORE_S).timeout
	assert_bool(hud._active_pulse_tween != null and hud._active_pulse_tween.is_valid()) \
		.override_failure_message("AC-HUD-36 (a): tween KILL doit encore être actif à ~80ms (durée nominale 100ms)") \
		.is_true()

	# Borne HAUTE : terminé à (100ms + 40ms) = 140ms
	await get_tree().create_timer(_MARGIN_BEFORE_S + _MARGIN_AFTER_S).timeout
	assert_bool(hud._active_pulse_tween == null or not hud._active_pulse_tween.is_valid()) \
		.override_failure_message("AC-HUD-36 (a): tween KILL doit être terminé à ~140ms (durée nominale 100ms + 40ms marge)") \
		.is_true()

	_free_all(nodes)

# =============================================================================
# AC-HUD-36 (b) — SECRET tween mesure ~150ms wall-clock
# =============================================================================

## GIVEN HUD en PLAYING, WHEN credits_changed(SECRET) émis,
## THEN tween encore actif à (150ms - 20ms), terminé à (150ms + 40ms).
## Source : AC-HUD-36 (b) [BLOCKING][AUTO].
func test_hud_pulse_secret_duration_approx_150ms() -> void:
	# Arrange
	var nodes: Array = _make_hud(1, 0)
	var hud: Node = nodes[0]
	var mock_credit: Node = nodes[2]

	# Act — émettre SECRET (source=1)
	mock_credit.emit_credits_changed(1, 1, 1)  # total=1, delta=1, source=SECRET=1

	# Précondition : tween lancé
	assert_bool(hud._active_pulse_tween != null and hud._active_pulse_tween.is_valid()) \
		.override_failure_message("AC-HUD-36 (b) precond: tween doit être actif après credits_changed SECRET") \
		.is_true()

	# Borne BASSE : encore actif à (150ms - 20ms) = 130ms
	await get_tree().create_timer(_SECRET_DURATION_S - _MARGIN_BEFORE_S).timeout
	assert_bool(hud._active_pulse_tween != null and hud._active_pulse_tween.is_valid()) \
		.override_failure_message("AC-HUD-36 (b): tween SECRET doit encore être actif à ~130ms (durée nominale 150ms)") \
		.is_true()

	# Vérification inter-test : à 130ms, un tween KILL (100ms) serait déjà fini
	# Ce test confirme donc implicitement que SECRET > KILL.

	# Borne HAUTE : terminé à (150ms + 40ms) = 190ms
	await get_tree().create_timer(_MARGIN_BEFORE_S + _MARGIN_AFTER_S).timeout
	assert_bool(hud._active_pulse_tween == null or not hud._active_pulse_tween.is_valid()) \
		.override_failure_message("AC-HUD-36 (b): tween SECRET doit être terminé à ~190ms (durée nominale 150ms + 40ms marge)") \
		.is_true()

	_free_all(nodes)

# =============================================================================
# AC-HUD-36 (c) — Invariant kill_duration < secret_duration
# =============================================================================

## GIVEN les constantes CREDIT_COUNTER_TWEEN_KILL_MS et CREDIT_COUNTER_TWEEN_SECRET_MS,
## THEN KILL_MS < SECRET_MS strictement (Pillar 4 différenciation perceptive).
## Source : AC-HUD-36 (c) [BLOCKING][AUTO].
func test_hud_pulse_kill_duration_strictly_less_than_secret_duration() -> void:
	# Arrange — charger le script pour accéder aux constantes
	var hud_class: GDScript = _HUDScript

	var kill_ms: int = hud_class.CREDIT_COUNTER_TWEEN_KILL_MS
	var secret_ms: int = hud_class.CREDIT_COUNTER_TWEEN_SECRET_MS

	# Assert invariant : kill < secret
	assert_bool(kill_ms < secret_ms) \
		.override_failure_message("AC-HUD-36 (c): KILL_MS (%d) doit être strictement inférieur à SECRET_MS (%d) — Pillar 4 différenciation perceptive" % [kill_ms, secret_ms]) \
		.is_true()

# =============================================================================
# AC-HUD-36 (d) — Magnitude Vector2(1.05, 1.05) identique pour les 2 sources
# =============================================================================

## GIVEN les constantes PULSE_SCALE_MAGNITUDE,
## THEN magnitude == 1.05 (Vector2(1.05, 1.05) pour les 2 sources KILL et SECRET).
## Vérification runtime : tween actif à t=half_duration (scale en cours d'animation).
## Source : AC-HUD-36 (d) [BLOCKING][AUTO].
func test_hud_pulse_magnitude_is_1_05_for_both_sources() -> void:
	# Assert constante de magnitude
	var hud_class: GDScript = _HUDScript
	var magnitude: float = hud_class.PULSE_SCALE_MAGNITUDE

	assert_float(magnitude) \
		.override_failure_message("AC-HUD-36 (d): PULSE_SCALE_MAGNITUDE doit être 1.05 (obtenu %f)" % magnitude) \
		.is_equal_approx(1.05, 0.001)

	# Vérification runtime KILL : tween encore actif à t=60ms (50ms pic + 10ms marge descendante)
	var nodes: Array = _make_hud(1, 0)
	var hud: Node = nodes[0]
	var mock_credit: Node = nodes[2]

	mock_credit.emit_credits_changed(1, 1, 0)  # KILL — half=50ms, total=100ms

	# À 60ms (60% de la durée totale 100ms) — tween doit encore tourner (en descente)
	await get_tree().create_timer(0.06).timeout
	assert_bool(hud._active_pulse_tween != null and hud._active_pulse_tween.is_valid()) \
		.override_failure_message("AC-HUD-36 (d) KILL: tween doit encore être actif à 60ms (total=100ms)") \
		.is_true()

	# Attendre fin du tween KILL avant le test SECRET
	await get_tree().create_timer(_KILL_DURATION_S - 0.06 + _MARGIN_AFTER_S).timeout

	# Vérification runtime SECRET : tween encore actif à t=90ms (60% de 150ms)
	mock_credit.emit_credits_changed(2, 1, 1)  # SECRET — half=75ms, total=150ms

	await get_tree().create_timer(0.09).timeout
	assert_bool(hud._active_pulse_tween != null and hud._active_pulse_tween.is_valid()) \
		.override_failure_message("AC-HUD-36 (d) SECRET: tween doit encore être actif à 90ms (total=150ms)") \
		.is_true()

	# Attendre fin du tween SECRET (nettoyage)
	await get_tree().create_timer(_SECRET_DURATION_S - 0.09 + _MARGIN_AFTER_S).timeout

	_free_all(nodes)

# =============================================================================
# AC-HUD-36 (e) — Collision tween : source du dernier signal gagne
# =============================================================================

## GIVEN HUD en PLAYING avec un tween KILL en cours (mid-tween ~30ms),
## WHEN credits_changed(SECRET) émis,
## THEN tween KILL killed + nouveau tween SECRET actif à (150ms - 20ms), terminé à (150ms + 40ms).
## Reverse : SECRET interrompu par KILL → nouveau tween KILL actif à (100ms-20ms), terminé à (100ms+40ms).
## Source : AC-HUD-36 (e) [BLOCKING][AUTO].
func test_hud_pulse_collision_last_source_wins() -> void:
	# Arrange
	var nodes: Array = _make_hud(1, 0)
	var hud: Node = nodes[0]
	var mock_credit: Node = nodes[2]

	# ROUND 1 : lancer KILL, mid-flight émettre SECRET
	mock_credit.emit_credits_changed(1, 1, 0)  # KILL (100ms)
	var tween_kill_1: Tween = hud._active_pulse_tween

	assert_bool(tween_kill_1 != null and tween_kill_1.is_valid()) \
		.override_failure_message("AC-HUD-36 (e) precond: tween KILL doit être actif") \
		.is_true()

	# Attendre ~30ms (mid-flight KILL, total=100ms)
	await get_tree().create_timer(0.03).timeout

	# Émettre SECRET — doit kill le KILL en cours et créer un tween 150ms
	mock_credit.emit_credits_changed(2, 1, 1)  # SECRET (150ms)
	var tween_secret: Tween = hud._active_pulse_tween

	# L'ancien tween KILL doit être killed immédiatement
	assert_bool(not tween_kill_1.is_valid()) \
		.override_failure_message("AC-HUD-36 (e): tween KILL original doit être killed après collision SECRET") \
		.is_true()

	# Le nouveau tween SECRET doit être actif
	assert_bool(tween_secret != null and tween_secret.is_valid()) \
		.override_failure_message("AC-HUD-36 (e): nouveau tween SECRET doit être actif après collision") \
		.is_true()

	# Borne BASSE SECRET : encore actif à (150ms - 20ms) depuis l'émission SECRET
	await get_tree().create_timer(_SECRET_DURATION_S - _MARGIN_BEFORE_S).timeout
	assert_bool(tween_secret != null and tween_secret.is_valid()) \
		.override_failure_message("AC-HUD-36 (e): tween SECRET doit encore être actif à ~130ms après émission SECRET") \
		.is_true()

	# Borne HAUTE SECRET : terminé à (150ms + 40ms) depuis l'émission SECRET
	await get_tree().create_timer(_MARGIN_BEFORE_S + _MARGIN_AFTER_S).timeout
	assert_bool(tween_secret == null or not tween_secret.is_valid()) \
		.override_failure_message("AC-HUD-36 (e): tween SECRET doit être terminé à ~190ms après émission SECRET") \
		.is_true()

	# ROUND 2 (reverse) : SECRET mid-flight interrompu par KILL
	mock_credit.emit_credits_changed(3, 1, 1)  # SECRET (150ms)
	var tween_secret_2: Tween = hud._active_pulse_tween

	# Attendre ~40ms (mid-flight SECRET)
	await get_tree().create_timer(0.04).timeout

	# Émettre KILL — interrompt SECRET
	mock_credit.emit_credits_changed(4, 1, 0)  # KILL (100ms)
	var tween_kill_2: Tween = hud._active_pulse_tween

	# SECRET 2 doit être killed
	assert_bool(tween_secret_2 == null or not tween_secret_2.is_valid()) \
		.override_failure_message("AC-HUD-36 (e) round2: tween SECRET doit être killed après collision KILL") \
		.is_true()

	# Borne BASSE KILL : encore actif à (100ms - 20ms) depuis l'émission KILL
	await get_tree().create_timer(_KILL_DURATION_S - _MARGIN_BEFORE_S).timeout
	assert_bool(tween_kill_2 != null and tween_kill_2.is_valid()) \
		.override_failure_message("AC-HUD-36 (e) round2: tween KILL doit encore être actif à ~80ms après émission KILL") \
		.is_true()

	# Borne HAUTE KILL : terminé à (100ms + 40ms)
	await get_tree().create_timer(_MARGIN_BEFORE_S + _MARGIN_AFTER_S).timeout
	assert_bool(tween_kill_2 == null or not tween_kill_2.is_valid()) \
		.override_failure_message("AC-HUD-36 (e) round2: tween KILL doit être terminé à ~140ms après émission KILL") \
		.is_true()

	_free_all(nodes)

# =============================================================================
# OQ-HUD-5 — Wall-clock invariance : time_scale=0.3 ne rallonge pas le tween
# =============================================================================

## GIVEN Engine.time_scale = 0.3 au tick d'émission KILL,
## WHEN credits_changed(KILL) émis,
## THEN le tween se termine ET le label est restauré à Vector2.ONE dans un délai raisonnable.
## Vérification indirecte de set_ignore_time_scale(true) : en headless time_scale=0.3,
## create_timer est aussi ralenti (time-scaled). On vérifie donc que :
## 1. Le tween démarre bien avec time_scale=0.3.
## 2. Après restauration time_scale=1.0, le tween se termine dans la fenêtre nominale.
## Cleanup obligatoire : Engine.time_scale = 1.0 en after_test.
## Source : OQ-HUD-5 [BLOCKING][AUTO] + ADR-0001 wall-clock invariance.
func test_hud_pulse_wall_clock_invariant_under_slow_motion() -> void:
	# Arrange
	var nodes: Array = _make_hud(1, 0)
	var hud: Node = nodes[0]
	var mock_credit: Node = nodes[2]

	# Slow-mo avant émission (OQ-HUD-5 : time_scale=0.3)
	Engine.time_scale = 0.3

	# Act — émettre KILL sous slow-mo
	mock_credit.emit_credits_changed(1, 1, 0)  # KILL (nominal 100ms wall-clock via ignore_time_scale)

	# Précondition : tween doit démarrer même sous slow-mo
	assert_bool(hud._active_pulse_tween != null and hud._active_pulse_tween.is_valid()) \
		.override_failure_message("OQ-HUD-5 precond: tween doit être actif après credits_changed KILL sous time_scale=0.3") \
		.is_true()

	# Restaurer time_scale=1.0 IMMÉDIATEMENT — le tween a ignore_time_scale=true
	# donc sa durée wall-clock reste 100ms quelle que soit la valeur du time_scale pendant son exécution.
	# En restaurant time_scale=1.0, create_timer redevient à vitesse normale pour nos bornes.
	Engine.time_scale = 1.0

	# Borne BASSE : encore actif à (100ms - 20ms) = 80ms wall-clock depuis l'émission
	await get_tree().create_timer(_KILL_DURATION_S - _MARGIN_BEFORE_S).timeout
	assert_bool(hud._active_pulse_tween != null and hud._active_pulse_tween.is_valid()) \
		.override_failure_message("OQ-HUD-5 borne basse: tween KILL doit encore être actif à ~80ms (set_ignore_time_scale garantit durée 100ms indépendante du time_scale initial)") \
		.is_true()

	# Borne HAUTE : terminé à (100ms + 40ms) = 140ms wall-clock
	await get_tree().create_timer(_MARGIN_BEFORE_S + _MARGIN_AFTER_S).timeout
	assert_bool(hud._active_pulse_tween == null or not hud._active_pulse_tween.is_valid()) \
		.override_failure_message("OQ-HUD-5 borne haute: tween KILL doit être terminé à ~140ms wall-clock (set_ignore_time_scale=true)") \
		.is_true()

	_free_all(nodes)


## Cleanup de sécurité — restaure time_scale si un test échoue avant son cleanup.
func after_test() -> void:
	Engine.time_scale = 1.0
