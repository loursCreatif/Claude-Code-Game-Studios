# Tests de performance story-011 — Zero-alloc signal dispatch (VC-2 ADR-0005).
#
# Valide que 3000 emits de signals Movement (burst : 1000 × dash_started +
# 1000 × wall_jumped + 1000 × attacked) ne produisent pas plus de 64 KB de
# MEMORY_STATIC delta.
#
# Rationale ADR-0005 D-9 : payloads Vector3/float sont des value types. Godot
# ne les boxe pas en heap lors du dispatch signal → zero-alloc garanti si les
# handlers eux-mêmes n'allouent pas. Le SignalSink ci-dessous ne fait qu'un
# incrément d'entier → aucune alloc dans les handlers.
#
# Note simplification VC-2 : ADR-0005 VC-2 spécifie "1000 emits / 60 s".
# Ce test mesure un burst ponctuel (sans fenêtre temporelle) car une attente
# de 60 s serait trop longue pour CI. La mesure post-loop capture le delta
# d'alloc cumulé sur 3000 emits — équivalent pour détecter un leak par emit.
# Si un drift continu est suspecté sur fenêtre longue, utiliser le runner
# headless dédié (pattern identique à input_zero_alloc_stress_runner.gd).
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Story     : production/epics/player-movement-system/story-011-zero-alloc-outbound-lint.md
# ADR       : ADR-0005 D-9 (zero-alloc dispatch) + VC-2 (MEMORY_STATIC gate 64 KB)

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const PlayerScene: PackedScene = preload("res://src/gameplay/player/Player.tscn")

## Seuil dur VC-2 : delta MEMORY_STATIC < 64 KB sur le burst de 3000 emits.
const MEMORY_DELTA_GATE_BYTES: int = 65_536  # 64 KB


# ---------------------------------------------------------------------------
# SignalSink — consumer stub zéro-alloc
# ---------------------------------------------------------------------------

## Consumer stub qui absorbe les signals sans allouer.
## Chaque handler incrémente un compteur int — aucune alloc heap.
## Utilisé pour maintenir des connexions actives pendant la mesure
## (simule des consumers réels sans polluer la mesure d'alloc).
class SignalSink extends RefCounted:
	## Nombre total de signals reçus (tous handlers confondus).
	var n: int = 0

	func on_dash(_d: Vector3, _s: float) -> void:
		n += 1

	func on_wall_jump(_n: Vector3, _v: Vector3) -> void:
		n += 1

	func on_attack() -> void:
		n += 1


# ---------------------------------------------------------------------------
# VC-2 — Zero-alloc 3000 emits < 64 KB MEMORY_STATIC delta
# ---------------------------------------------------------------------------

## VC-2 ADR-0005 D-9 : GIVEN MovementController + 3 consumers stubs connectés,
## WHEN 1000 dash_started.emit() + 1000 wall_jumped.emit() + 1000 attacked.emit(),
## THEN Performance.get_monitor(MEMORY_STATIC) delta < 64 KB.
##
## Les payloads sont pré-alloués avant la mesure (Vector3 / float = value types,
## alloués sur la stack, copiés lors du passage en signal — pas de heap).
## Les sinks ne font qu'incrémenter un int → zéro alloc dans les handlers.
func test_zero_alloc_3000_emits_under_64kb_static() -> void:
	# Arrange — instancier le player depuis la scene complète pour que _ready()
	# s'exécute (init @onready, assertions invariants).
	var player: MovementController = PlayerScene.instantiate() as MovementController
	add_child(player)
	auto_free(player)

	# Stubs consumers — connectés pour simuler des handlers réels.
	# RefCounted : pas besoin de free() manuel (GdUnit4 auto_free couvre le player,
	# les sinks sont relâchés automatiquement quand les références tombent).
	var sink_a: SignalSink = SignalSink.new()
	var sink_b: SignalSink = SignalSink.new()
	var sink_c: SignalSink = SignalSink.new()
	player.dash_started.connect(sink_a.on_dash)
	player.wall_jumped.connect(sink_b.on_wall_jump)
	player.attacked.connect(sink_c.on_attack)

	# Pré-allouer les payloads AVANT la mesure baseline.
	# Vector3 sont des value types — leur construction ici n'est pas comptée.
	var dash_dir: Vector3 = Vector3(1.0, 0.0, 0.0)
	var wall_normal: Vector3 = Vector3(0.0, 0.0, 1.0)
	var launch_vel: Vector3 = Vector3(7.0, 6.5, 0.0)
	var dash_speed: float = 30.0

	# Forcer un GC frame avant baseline pour éviter de compter des allocs
	# de lazy-init Godot (signal table, overlay debug, etc.).
	await get_tree().process_frame
	var baseline: int = Performance.get_monitor(Performance.MEMORY_STATIC)

	# Act — 3000 emits en burst (1000 par signal).
	# Aucune allocation attendue : Vector3/float copiés par valeur,
	# handlers n'allouent pas (incrément int uniquement).
	for i: int in 1000:
		player.dash_started.emit(dash_dir, dash_speed)
		player.wall_jumped.emit(wall_normal, launch_vel)
		player.attacked.emit()

	# Assert — delta MEMORY_STATIC < 64 KB.
	var delta: int = Performance.get_monitor(Performance.MEMORY_STATIC) - baseline
	assert_int(delta) \
		.override_failure_message(
			"VC-2 ADR-0005 D-9 FAIL: MEMORY_STATIC delta = %d bytes sur 3000 emits "
			% delta +
			"(gate < %d bytes). Identifier le signal incriminé via bisect "
			% MEMORY_DELTA_GATE_BYTES +
			"(tester dash_started seul, wall_jumped seul, attacked seul)."
		) \
		.is_less(MEMORY_DELTA_GATE_BYTES)

	# Sanity check : les stubs ont bien reçu les 1000 signals chacun.
	# Garantit que les connexions étaient actives pendant la mesure.
	assert_int(sink_a.n) \
		.override_failure_message("sink_a doit avoir reçu 1000 dash_started") \
		.is_equal(1000)
	assert_int(sink_b.n) \
		.override_failure_message("sink_b doit avoir reçu 1000 wall_jumped") \
		.is_equal(1000)
	assert_int(sink_c.n) \
		.override_failure_message("sink_c doit avoir reçu 1000 attacked") \
		.is_equal(1000)
