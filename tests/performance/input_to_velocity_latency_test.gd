# Tests de performance story-014 — Input→velocity latency p99 (VC-2 + AC-MV-51 ADR-0001).
#
# Valide que le pipeline input→velocity-set se boucle en ≤ 16.6 ms p99 (release)
# ou ≤ 50 ms p99 (debug interpreter, 5–10× plus lent).
#
# Méthodologie :
#   Pour chaque itération (200 au total) :
#   1. Time.get_ticks_usec() → t0
#   2. InputManager.simulate_action_press(&"dash")
#   3. await get_tree().physics_frame  ← un tick complet ; velocity.xz := dash_dir × DASH_SPEED
#   4. Vérification velocity.xz == dash_dir × DASH_SPEED (sanity assert)
#   5. Time.get_ticks_usec() → t1 ; sample = t1 - t0 (µs)
#   6. InputManager.simulate_action_release(&"dash")
#   7. player._dash_cooldown_timer = 0.0  ← force reset pour l'itération suivante
#   8. await get_tree().physics_frame  ← tick de reset
#
#   Le sample couvre le temps total "demande dispatch → état résolu" incluant
#   l'overhead de l'await physique. C'est la latence perçue par le gameplay,
#   pas seulement le coût CPU pur du dispatch signal.
#
# Seuils :
#   release build : p99 ≤ 16.6 ms (AC-MV-51 / ADR-0001 VC-2)
#   debug interpreter : p99 ≤ 50 ms (5× pénalité max acceptée)
#   Gate par OS.has_feature("debug") — voir implémentation.
#
# Attention CI cloud : sur un runner cloud lent (GitHub Actions, pas de GPU
# dédié), même un build release peut présenter des spikes ponctuels > 16.6 ms.
# Le seuil strict reste 16.6 ms (release) car il représente la target hardware
# min-spec. Un seuil CI-cloud élargi (ex: 33 ms, 2× frame) serait acceptable
# pour débloquer CI mais DOIT être documenté comme déviation et suivi.
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Story     : production/epics/player-movement-system/story-014-perf-physics-benchmark.md
# ADR       : ADR-0001 VC-2 (input→velocity p99 ≤ 16.6 ms release)
#             ADR-0005 VC-8 (signal dispatch cumul)

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const PlayerScene: PackedScene = preload("res://src/gameplay/player/Player.tscn")

## Nombre d'itérations pour la mesure p99 (200 = statistiquement robuste).
const SAMPLE_COUNT: int = 200

## Seuil p99 release build (µs). ADR-0001 VC-2 : ≤ 16.6 ms = 16 600 µs.
const P99_THRESHOLD_RELEASE_US: int = 16_600

## Seuil p99 debug interpreter (µs). 5× pénalité max acceptée par ADR-0001.
const P99_THRESHOLD_DEBUG_US: int = 50_000

## Direction dash utilisée pour le bench (XZ normalisée, Y=0).
const DASH_DIRECTION: Vector3 = Vector3(1.0, 0.0, 0.0)

## Vitesse dash attendue — doit correspondre à MovementController.DASH_SPEED.
## Dupliqué ici pour que le test soit auto-documenté (pas de dépendance circulaire).
const EXPECTED_DASH_SPEED: float = 30.0

## Tolérance vitesse pour la vérification velocity post-tick (m/s).
## Absorbe les erreurs virgule flottante et le bruit de move_and_slide().
const VELOCITY_TOLERANCE: float = 0.5


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _player: MovementController


# ---------------------------------------------------------------------------
# Setup / Teardown
# ---------------------------------------------------------------------------

func before_test() -> void:
	# Instancier le player depuis la scène complète pour que _ready() s'exécute
	# (init @onready, assertions invariants, raycasts).
	_player = PlayerScene.instantiate() as MovementController
	add_child(_player)
	auto_free(_player)

	# Activer la capability dash — obligatoire pour que _try_start_dash() ne
	# retourne pas immédiatement sur le gate can_dash (story-013 / AC-MV-60).
	_player.set_capability(&"dash", true)

	# Attendre un tick pour que le player soit bien intégré dans le SceneTree
	# et que son _ready() ait eu le temps de s'exécuter.
	await get_tree().physics_frame


func after_test() -> void:
	_player = null


# ---------------------------------------------------------------------------
# VC-2 + AC-MV-51 — Input→velocity latency p99
# ---------------------------------------------------------------------------

## ADR-0001 VC-2 : GIVEN 200 dash inputs instrumentés via Time.get_ticks_usec(),
## WHEN simulate_action_press(&"dash") + await physics_frame,
## THEN p99 ≤ 16.6 ms (release) ou ≤ 50 ms (debug).
##
## AC-MV-51 : latence timestamp velocity-set − timestamp input event ≤ 16 ms p99.
##
## Note implémentation : le sample inclut le temps d'attente de l'await
## physics_frame (≈ 16.6 ms à 60 Hz). La latence "pure" dispatch est nettement
## inférieure (<< 1 ms), mais VC-2 mesure la latence bout-en-bout perçue par
## le joueur — c'est le bon signal pour valider le budget frame entier.
## Si on voulait isoler le coût dispatch pur, utiliser le bench VC-8
## (movement_signals_dispatch_bench.gd) qui ne comporte pas d'await.
func test_input_to_velocity_latency_p99_under_16_6_ms() -> void:
	# Arrange — pré-allouer le tableau de samples pour éviter les allocs en boucle.
	var samples: Array[int] = []
	samples.resize(SAMPLE_COUNT)

	# Act — 200 itérations dash : press → physics_frame → release → reset → physics_frame.
	for i: int in SAMPLE_COUNT:
		# Timestamp avant la demande d'input.
		var t0: int = Time.get_ticks_usec()

		# Injecter l'input dash via le simulateur InputManager.
		InputManager.simulate_action_press(&"dash")

		# Attendre exactement un tick physics — c'est le tick où _physics_process
		# va lire was_pressed_this_tick(&"dash"), entrer en DASHING, et setter
		# velocity.xz = dash_dir × DASH_SPEED.
		await get_tree().physics_frame

		# Timestamp après que le tick ait résolu l'état velocity.
		var t1: int = Time.get_ticks_usec()

		# Sanity check velocity : vérifier que le dash a bien été appliqué.
		# Si cette assertion fail, le test est invalide (les samples mesureraient
		# un tick où le dash n'a pas été déclenché, faussant le p99).
		# Tolérance VELOCITY_TOLERANCE pour absorber bruit move_and_slide().
		var actual_speed: float = Vector2(_player.velocity.x, _player.velocity.z).length()
		assert_float(actual_speed) \
			.override_failure_message(
				"Sanity FAIL iter %d : velocity XZ speed = %.2f m/s (attendu ≈ %.2f ±%.2f). "
				% [i, actual_speed, EXPECTED_DASH_SPEED, VELOCITY_TOLERANCE] +
				"Le dash n'a peut-être pas été déclenché (cooldown actif ?)."
			) \
			.is_greater(EXPECTED_DASH_SPEED - VELOCITY_TOLERANCE)

		# Stocker le sample en µs.
		samples[i] = t1 - t0

		# Release l'input pour éviter un double-trigger.
		InputManager.simulate_action_release(&"dash")

		# Forcer le reset du cooldown pour que l'itération suivante puisse dasher.
		# Accès direct au champ privé autorisé en test GdUnit4 (pattern story-014 brief).
		_player._dash_cooldown_timer = 0.0

		# Attendre un tick de "repos" pour que le reset soit visible avant la
		# prochaine itération (le _physics_process tick lit le cooldown mis à jour).
		await get_tree().physics_frame

	# Assert — calculer le p99 et vérifier le seuil adapté au build.
	samples.sort()

	# Index p99 : le 198ème sample sur 200 (0-indexed : 199 * 0.99 = 197.01 → 197).
	var p99_index: int = int(float(SAMPLE_COUNT - 1) * 0.99)
	var p99_us: int = samples[p99_index]
	var p99_ms: float = float(p99_us) / 1000.0

	# Calculer aussi la moyenne pour le failure message.
	var sum_us: int = 0
	for s: int in samples:
		sum_us += s
	var mean_ms: float = float(sum_us) / float(SAMPLE_COUNT) / 1000.0

	# Gate selon build type — debug interpreter est 5–10× plus lent.
	var threshold_us: int = P99_THRESHOLD_DEBUG_US if OS.has_feature("debug") \
		else P99_THRESHOLD_RELEASE_US
	var threshold_ms: float = float(threshold_us) / 1000.0
	var build_label: String = "debug" if OS.has_feature("debug") else "release"

	var failure_msg: String = (
		"ADR-0001 VC-2 / AC-MV-51 FAIL (%s build): p99 = %.2f ms (seuil <= %.1f ms). "
		% [build_label, p99_ms, threshold_ms]
		+ "Moyenne = %.2f ms sur %d samples. "
		% [mean_ms, SAMPLE_COUNT]
		+ "Sur CI cloud runner (pas de GPU dedie), un seuil elargi de 33 ms peut etre acceptable."
	)
	assert_int(p99_us) \
		.override_failure_message(failure_msg) \
		.is_less_equal(threshold_us)
