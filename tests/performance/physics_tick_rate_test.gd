# Tests de performance story-014 — Tick rate physics stable 60 Hz (VC-1 ADR-0001).
#
# Valide qu'Engine.get_physics_frames() dérive de ≤ 1% sur une fenêtre de 5 s
# (proxy fiable pour l'assertion 30 s spécifiée dans ADR-0001 VC-1).
#
# Rationale simplification CI : le critère ADR-0001 VC-1 complet est delta
# ∈ [1782, 1818] sur 30 s (60×30 ±1%). Ce test utilise une fenêtre de 5 s
# (delta attendu ∈ [297, 303]) pour rester dans le budget temps CI tout en
# restant statistiquement équivalent pour détecter une dérive du tick rate.
# La fenêtre 1 s (∈ [58, 62]) est aussi définie comme variante ultra-rapide.
#
# Environnement requis : build quelconque (debug ou release). Le tick rate
# Physics est fixé par project.godot (physics_ticks_per_second=60, ADR-0001).
# Sur CI runner cloud, la charge OS peut induire des jitter ponctuels — un
# seul spike n'invalide pas le delta global (loi des grands nombres sur 5 s).
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Story     : production/epics/player-movement-system/story-014-perf-physics-benchmark.md
# ADR       : ADR-0001 VC-1 (tick rate stable 60 Hz ±1% sur 30 s)

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Durée de la fenêtre de mesure courte en secondes (proxy CI pour 30 s).
## ADR-0001 VC-1 : 30 s complets demandent 1800 ticks — trop coûteux pour CI.
## 5 s à 60 Hz = 300 ticks attendus, tolérance ±1% → [297, 303].
const WINDOW_SECONDS_SHORT: float = 5.0

## Delta minimum attendu sur WINDOW_SECONDS_SHORT (60 Hz × 5 s − 1%).
const TICKS_MIN_5S: int = 297

## Delta maximum attendu sur WINDOW_SECONDS_SHORT (60 Hz × 5 s + 1%).
const TICKS_MAX_5S: int = 303

## Durée de la fenêtre ultra-courte (variante 1 s, pour smoke-check).
const WINDOW_SECONDS_ULTRA: float = 1.0

## Delta minimum attendu sur 1 s à 60 Hz (−2 ticks, ≈ 3.3% — marge élargie
## car un seul spike sur 60 ticks est plus pénalisant statistiquement).
const TICKS_MIN_1S: int = 58

## Delta maximum attendu sur 1 s à 60 Hz (+2 ticks).
const TICKS_MAX_1S: int = 62


# ---------------------------------------------------------------------------
# VC-1 — Tick rate stable 5 s (gate principal CI)
# ---------------------------------------------------------------------------

## ADR-0001 VC-1 proxy : GIVEN projet configuré à 60 Hz (project.godot),
## WHEN on mesure Engine.get_physics_frames() avant et après 5 s de simulation,
## THEN delta ∈ [297, 303] (60 Hz × 5 s ±1%).
##
## Ce test remplace la mesure 30 s (trop coûteuse pour CI). La dérive de tick
## rate s'exprime sur l'ensemble de la fenêtre — 5 s est suffisant pour
## détecter un projet mal configuré (physics_ticks_per_second ≠ 60) ou une
## surcharge moteur systématique.
##
## Déviations par rapport à ADR-0001 VC-1 strict :
## - Fenêtre 5 s au lieu de 30 s (ADVISORY : la mesure 30 s reste la cible
##   gold standard hors CI, en environment playtest contrôlé).
## - Tolérance élargie à ±2% sur 5 s (vs ±1% sur 30 s) pour absorber le
##   jitter CI cloud. L'assert utilise ±1% (297-303) car ±2% serait trop laxiste.
func test_physics_tick_rate_stable_60hz_over_5_seconds() -> void:
	# Arrange — laisser le moteur se stabiliser avant la mesure.
	# Un frame process permet à Godot de finaliser la resolution des deferred
	# init (scene tree, signal table) avant le baseline.
	await get_tree().process_frame

	var start_frame: int = Engine.get_physics_frames()

	# Act — attendre 5 s réelles (300 ticks théoriques à 60 Hz).
	# create_timer utilise le temps réel (Time.get_ticks_msec en interne) ;
	# le nombre de physics ticks accumulés dépend du scheduler OS.
	await get_tree().create_timer(WINDOW_SECONDS_SHORT).timeout

	var elapsed: int = Engine.get_physics_frames() - start_frame

	# Assert — delta ∈ [297, 303].
	# Failure message inclut la valeur mesurée pour faciliter le diagnostic.
	assert_int(elapsed) \
		.override_failure_message(
			"ADR-0001 VC-1 FAIL: physics tick delta = %d sur 5 s "
			% elapsed +
			"(attendu [%d, %d], soit 60 Hz ±1%%). "
			% [TICKS_MIN_5S, TICKS_MAX_5S] +
			"Vérifier physics_ticks_per_second=60 dans project.godot."
		) \
		.is_between(TICKS_MIN_5S, TICKS_MAX_5S)


# ---------------------------------------------------------------------------
# VC-1 — Smoke-check ultra-rapide 1 s (variante gate CI quick)
# ---------------------------------------------------------------------------

## Variante 1 s — détecte les configurations radicalement incorrectes
## (e.g. physics_ticks_per_second=30 ou 120) en moins d'1 s de CI.
## Tolérance élargie à ±2 ticks (≈ 3.3%) pour absorber le jitter CI
## sur une fenêtre courte (un seul spike représente 1.7% à lui seul).
##
## Note : ce test NE remplace PAS test_physics_tick_rate_stable_60hz_over_5_seconds.
## Les deux doivent passer. La variante 1 s est un filet de sécurité rapide ;
## la variante 5 s est le gate ADR-0001 VC-1 officiel.
func test_physics_tick_rate_stable_60hz_over_1_second() -> void:
	# Arrange
	await get_tree().process_frame
	var start_frame: int = Engine.get_physics_frames()

	# Act
	await get_tree().create_timer(WINDOW_SECONDS_ULTRA).timeout

	var elapsed: int = Engine.get_physics_frames() - start_frame

	# Assert — tolérance élargie pour la fenêtre courte.
	assert_int(elapsed) \
		.override_failure_message(
			"ADR-0001 VC-1 smoke FAIL: physics tick delta = %d sur 1 s "
			% elapsed +
			"(attendu [%d, %d], 60 Hz ±2 ticks). "
			% [TICKS_MIN_1S, TICKS_MAX_1S] +
			"Vérifier physics_ticks_per_second=60 dans project.godot."
		) \
		.is_between(TICKS_MIN_1S, TICKS_MAX_1S)
