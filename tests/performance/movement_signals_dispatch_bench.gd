# Tests de performance story-014 — Signal dispatch cumul ≤ 0.1 ms/frame amorti (VC-8 ADR-0005).
#
# Valide que le coût CPU cumulé des emits de signals Movement (dash_started,
# wall_run_entered, attacked) reste ≤ 0.1 ms/frame amorti sur 3600 frames
# (60 s simulées à 60 Hz).
#
# Méthodologie :
#   - Pattern adapté du brief story-014 : 3600 itérations en boucle for (sans await).
#   - Les emits sont synchrones — pas de await get_tree().physics_frame entre les
#     itérations. Cela mesure UNIQUEMENT le coût du dispatch signal + callback
#     sync, sans l'overhead du tick physique complet.
#   - C'est le signal ADR-0005 VC-8 cherche : le coût "par signal dispatch",
#     pas le coût "par frame entier". Le benchmark VC-4 (physics_frame_budget_test)
#     mesure le budget total ; VC-8 isole le coût signal.
#   - 3 consumers stubs (SignalSink) connectés simulent un environnement réaliste
#     (HUD + CameraSystem + AudioSystem).
#
# Seuil :
#   per_frame_us ≤ 100 µs (0.1 ms). Sur 3600 frames, elapsed total ≤ 360 ms.
#   Ce seuil est très confortable : un dispatch signal GDScript pur coûte
#   << 1 µs — la barre est volontairement haute pour détecter des régressions
#   graves (alloc heap par dispatch, Array boxing, String concat, etc.).
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Story     : production/epics/player-movement-system/story-014-perf-physics-benchmark.md
# ADR       : ADR-0005 VC-8 (signal dispatch cumul ≤ 0.1 ms/frame amorti)
#             ADR-0005 D-9 (zero-alloc dispatch, payloads value types)

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const PlayerScene: PackedScene = preload("res://src/gameplay/player/Player.tscn")

## Nombre de frames simulées (60 Hz × 60 s = 3600). Pas d'await entre les frames
## car on mesure le coût dispatch pur, pas le coût frame physique.
const FRAME_COUNT: int = 3600

## Périodicité dash_started.emit() (toutes les 60 "frames" = une fois par "seconde").
const DASH_EMIT_PERIOD: int = 60

## Périodicité wall_run_entered.emit() (toutes les 60 frames, décalé de 30).
const WALL_EMIT_PERIOD: int = 60
const WALL_EMIT_OFFSET: int = 30

## Périodicité attacked.emit() (toutes les 60 frames, décalé de 45).
const ATTACK_EMIT_PERIOD: int = 60
const ATTACK_EMIT_OFFSET: int = 45

## Seuil dur VC-8 : ≤ 100 µs par frame amorti (= 0.1 ms).
const PER_FRAME_THRESHOLD_US: float = 100.0

## Payloads pré-alloués (Vector3 = value types, pas de heap alloc).
## ADR-0005 D-3 : payloads Vector3/float uniquement — zero-alloc garanti.
const DASH_DIRECTION: Vector3 = Vector3(1.0, 0.0, 0.0)
const DASH_SPEED_PAYLOAD: float = 30.0
const WALL_NORMAL_PAYLOAD: Vector3 = Vector3(0.0, 0.0, 1.0)


# ---------------------------------------------------------------------------
# SignalSink — consumer stub zero-alloc
# ---------------------------------------------------------------------------

## Consumer stub à 3 handlers (dash, wall_run, attack).
## Chaque handler incrémente un compteur int — aucune alloc heap.
## Pattern identique à story-011 (movement_signals_zero_alloc_test.gd).
## Utilisé ici pour simuler des consumers réels (HUD, Camera, Audio)
## sans polluer la mesure de latence avec des allocs de handlers.
class SignalSink extends RefCounted:
	## Compteur total de signals reçus (tous handlers).
	var n: int = 0

	func on_dash(_dir: Vector3, _speed: float) -> void:
		n += 1

	func on_wall(_normal: Vector3) -> void:
		n += 1

	func on_attack() -> void:
		n += 1


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _player: MovementController


# ---------------------------------------------------------------------------
# Setup / Teardown
# ---------------------------------------------------------------------------

func before_test() -> void:
	_player = PlayerScene.instantiate() as MovementController
	add_child(_player)
	auto_free(_player)

	# Attendre un tick pour que _ready() s'exécute et que le SceneTree
	# soit stable avant les connexions de signals.
	await get_tree().physics_frame


func after_test() -> void:
	_player = null


# ---------------------------------------------------------------------------
# VC-8 — Signal dispatch cumul ≤ 0.1 ms/frame amorti
# ---------------------------------------------------------------------------

## ADR-0005 VC-8 : GIVEN MovementController + 3 consumers stubs connectés,
## WHEN 3600 frames simulées (60 dash_started + 60 wall_run_entered + 60 attacked
##      sur 3600 frames, soit 1 emit/signal/seconde),
## THEN temps CPU cumulé / 3600 ≤ 100 µs par frame amorti (0.1 ms).
##
## Ce test mesure uniquement le coût dispatch synchrone (emit → callback).
## Il n'inclut PAS le temps d'attente des physics frames — voir VC-4 pour le
## budget complet par tick. La distinction est intentionnelle : VC-8 cherche
## à détecter des régressions dans le dispatch signal lui-même (alloc heap,
## String boxing, Dict création, etc.) indépendamment du budget moteur global.
##
## Sanity checks : les 3 sinks vérifient que les connexions étaient bien actives
## pendant la mesure (garantie que les callbacks ont bien été appelés).
func test_signal_dispatch_cumul_under_01_ms_per_frame_amortized() -> void:
	# Arrange — connecter 3 stubs consumers (un par type de signal).
	var sink_dash: SignalSink = SignalSink.new()
	var sink_wall: SignalSink = SignalSink.new()
	var sink_attack: SignalSink = SignalSink.new()

	_player.dash_started.connect(sink_dash.on_dash)
	_player.wall_run_entered.connect(sink_wall.on_wall)
	_player.attacked.connect(sink_attack.on_attack)

	# Baseline GC — laisser Godot finaliser les init lazy avant la mesure
	# pour éviter de comptabiliser la lazy-init signal table dans le bench.
	await get_tree().process_frame

	# Act — boucle 3600 itérations sans await (mesure coût dispatch pur).
	# Les payloads sont des constantes value-type Vector3/float — zero-alloc.
	var t_start: int = Time.get_ticks_usec()

	for frame: int in FRAME_COUNT:
		# dash_started.emit() : 1 fois par DASH_EMIT_PERIOD frames.
		if frame % DASH_EMIT_PERIOD == 0:
			_player.dash_started.emit(DASH_DIRECTION, DASH_SPEED_PAYLOAD)

		# wall_run_entered.emit() : 1 fois par WALL_EMIT_PERIOD, décalé de WALL_EMIT_OFFSET.
		if frame % WALL_EMIT_PERIOD == WALL_EMIT_OFFSET:
			_player.wall_run_entered.emit(WALL_NORMAL_PAYLOAD)

		# attacked.emit() : 1 fois par ATTACK_EMIT_PERIOD, décalé de ATTACK_EMIT_OFFSET.
		if frame % ATTACK_EMIT_PERIOD == ATTACK_EMIT_OFFSET:
			_player.attacked.emit()

	var elapsed_us: float = float(Time.get_ticks_usec() - t_start)
	var per_frame_us: float = elapsed_us / float(FRAME_COUNT)
	var per_frame_ms: float = per_frame_us / 1000.0
	var total_ms: float = elapsed_us / 1000.0

	# Calcul des emits attendus pour les sanity checks.
	# FRAME_COUNT / EMIT_PERIOD = nombre d'emits.
	var expected_dash_emits: int = FRAME_COUNT / DASH_EMIT_PERIOD      # = 60
	var expected_wall_emits: int = FRAME_COUNT / WALL_EMIT_PERIOD      # = 60
	var expected_attack_emits: int = FRAME_COUNT / ATTACK_EMIT_PERIOD  # = 60

	# Assert — coût par frame amorti ≤ seuil VC-8.
	assert_float(per_frame_us) \
		.override_failure_message(
			"ADR-0005 VC-8 FAIL: coût dispatch = %.2f µs/frame amorti "
			% per_frame_us +
			"(seuil ≤ %.1f µs = %.2f ms/frame). "
			% [PER_FRAME_THRESHOLD_US, PER_FRAME_THRESHOLD_US / 1000.0] +
			"Temps total = %.2f ms sur %d frames. "
			% [total_ms, FRAME_COUNT] +
			"Rechercher des allocs heap dans les signal handlers (Dict, Array, String)."
		) \
		.is_less(PER_FRAME_THRESHOLD_US)

	# Sanity checks — garantir que les connexions étaient actives.
	# Si ces assertions échouent, les seuils de latence sont invalides.
	assert_int(sink_dash.n) \
		.override_failure_message(
			"Sanity FAIL : sink_dash attendait %d dash_started, reçu %d."
			% [expected_dash_emits, sink_dash.n]
		) \
		.is_equal(expected_dash_emits)

	assert_int(sink_wall.n) \
		.override_failure_message(
			"Sanity FAIL : sink_wall attendait %d wall_run_entered, reçu %d."
			% [expected_wall_emits, sink_wall.n]
		) \
		.is_equal(expected_wall_emits)

	assert_int(sink_attack.n) \
		.override_failure_message(
			"Sanity FAIL : sink_attack attendait %d attacked, reçu %d."
			% [expected_attack_emits, sink_attack.n]
		) \
		.is_equal(expected_attack_emits)
