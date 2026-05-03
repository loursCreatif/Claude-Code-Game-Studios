# Tests integration Story-020 — Multi-kill clac dedup + ducking event ordering.
#
# Couvre AC-CMB-audio-01 (a/b/c/d) + AC-CMB-audio-02 (a/b/c) :
#
# AC-CMB-audio-01 — clac dedup multi-kill :
#   (a) 1er enemy_killed du swing : flag false→true, clac joué 1×.
#   (b) 2e enemy_killed même tick : flag déjà true → clac NON rejoué.
#   (c) blood ambiance joue chaque kill (counter += 1 par enemy_killed).
#   (d) `swing_ended` reset le flag à false pour le swing suivant.
#
# AC-CMB-audio-02 — ducking event ordering :
#   (a) bus SWING_ACTIVE log -6 dB sur enemy_killed avec release 30 ms wall-clock.
#   (b) connexion CONNECT_DEFERRED → handler reçoit signal au frame N+1 (pas N).
#   (c) multi_kill(count) suit les enemy_killed individuels (ordre intra-tick cohérent).
#
# Pattern : un seul Signal node test driver-side joue le rôle de Combat (émet
# `enemy_killed` / `swing_ended` / `multi_kill`). Connexion CONNECT_DEFERRED puis
# `await get_tree().physics_frame` pour valider la frame N+1 dispatch.
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Story   : production/epics/combat-system/story-020-audio-swoosh-fade-multi-kill-ducking.md
# ADR     : ADR-0006 D-4c (mock contract) + D-6 (Combat signals DEFERRED policy)
# GDD     : design/gdd/player-combat-system.md AC-CMB-audio-01 / AC-CMB-audio-02

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const HANDLER_PATH: String = "res://tests/unit/combat/mock_audio_handler.gd"
const PHYSICS_TICK_MS: float = 1000.0 / 60.0


# ---------------------------------------------------------------------------
# Helpers — Signal source mimant Combat (émetteur DEFERRED)
# ---------------------------------------------------------------------------

class CombatSignalSource extends Node:
	signal swing_started(direction: Vector3)
	signal swing_ended()
	signal enemy_killed(enemy: Node, position: Vector3)
	signal multi_kill(count: int)

	## Helpers test driver
	func emit_enemy_killed(enemy: Node, pos: Vector3) -> void:
		enemy_killed.emit(enemy, pos)

	func emit_swing_ended() -> void:
		swing_ended.emit()

	func emit_multi_kill(count: int) -> void:
		multi_kill.emit(count)


func _make_handler() -> Node:
	var handler: Node = (load(HANDLER_PATH) as Script).new()
	add_child(handler)
	return handler


func _make_combat_signal_source() -> CombatSignalSource:
	var src: CombatSignalSource = CombatSignalSource.new()
	add_child(src)
	return src


## Connecte les 2 signals consommés par le handler en CONNECT_DEFERRED (ADR-0006 D-6).
func _wire_handler_to_source(src: CombatSignalSource, handler: Node) -> void:
	src.enemy_killed.connect(handler._on_enemy_killed, CONNECT_DEFERRED)
	src.swing_ended.connect(handler._on_swing_ended, CONNECT_DEFERRED)


# ---------------------------------------------------------------------------
# AC-CMB-audio-01 (a)/(b) — Multi-kill clac dedup (1 clac, N blood)
# ---------------------------------------------------------------------------

## 2 enemy_killed même tick → 1 clac, 2 blood (AC-CMB-audio-01 (a)+(b)+(c)).
func test_multi_kill_same_tick_plays_clac_once_and_blood_twice() -> void:
	var handler: Node = _make_handler()
	var src: CombatSignalSource = _make_combat_signal_source()
	_wire_handler_to_source(src, handler)

	# Pre-condition : flag false, compteurs zéro.
	assert_bool(handler._kill_sound_played_this_swing).is_false()
	assert_int(handler.clac_played_count).is_equal(0)
	assert_int(handler.blood_played_count).is_equal(0)

	# Act : 2 emit consécutifs (même tick conceptuel ; CONNECT_DEFERRED dispatch frame N+1).
	src.emit_enemy_killed(null, Vector3.ZERO)
	src.emit_enemy_killed(null, Vector3(1.0, 0.0, 0.0))

	# AC-CMB-audio-02 (b) : CONNECT_DEFERRED implique frame N+1 dispatch.
	# Avant le frame next, le handler n'a pas reçu les signals.
	assert_int(handler.clac_played_count) \
		.override_failure_message(
			"AC-CMB-audio-02 (b) : avec CONNECT_DEFERRED, handler ne doit PAS recevoir " \
			+ "le signal au tick N (avant frame next)"
		) \
		.is_equal(0)

	# Awaiting frame next pour dispatch DEFERRED.
	await get_tree().physics_frame

	# AC-CMB-audio-01 (a) : 1er kill → flag true, clac +1.
	# AC-CMB-audio-01 (b) : 2e kill même tick → flag déjà true, clac NON rejoué.
	assert_bool(handler._kill_sound_played_this_swing) \
		.override_failure_message("AC-CMB-audio-01 (a) : flag dedup doit être true post 1er kill") \
		.is_true()
	assert_int(handler.clac_played_count) \
		.override_failure_message("AC-CMB-audio-01 (b) : clac doit être joué 1× seulement (pas 2)") \
		.is_equal(1)

	# AC-CMB-audio-01 (c) : blood ambiance joue 2× (1 par enemy_killed).
	assert_int(handler.blood_played_count) \
		.override_failure_message("AC-CMB-audio-01 (c) : blood ambiance doit jouer 2× (1 par kill)") \
		.is_equal(2)


## Edge case : 5 kills dans le même swing → 1 clac, 5 blood.
func test_five_kills_same_swing_plays_clac_once_and_blood_five_times() -> void:
	var handler: Node = _make_handler()
	var src: CombatSignalSource = _make_combat_signal_source()
	_wire_handler_to_source(src, handler)

	for i: int in range(5):
		src.emit_enemy_killed(null, Vector3(float(i), 0.0, 0.0))

	await get_tree().physics_frame

	assert_int(handler.clac_played_count).is_equal(1)
	assert_int(handler.blood_played_count).is_equal(5)


# ---------------------------------------------------------------------------
# AC-CMB-audio-01 (d) — swing_ended resets dedup flag for next swing
# ---------------------------------------------------------------------------

## AC-CMB-audio-01 (d) : flag reset à `swing_ended`, swing suivant peut rejouer le clac.
func test_swing_ended_resets_dedup_flag_for_next_swing() -> void:
	var handler: Node = _make_handler()
	var src: CombatSignalSource = _make_combat_signal_source()
	_wire_handler_to_source(src, handler)

	# Swing 1 : 1 kill → flag true, clac 1.
	src.emit_enemy_killed(null, Vector3.ZERO)
	await get_tree().physics_frame
	assert_bool(handler._kill_sound_played_this_swing).is_true()
	assert_int(handler.clac_played_count).is_equal(1)

	# Swing fin : flag reset.
	src.emit_swing_ended()
	await get_tree().physics_frame
	assert_bool(handler._kill_sound_played_this_swing) \
		.override_failure_message("AC-CMB-audio-01 (d) : flag dedup doit être reset à swing_ended") \
		.is_false()

	# Swing 2 : 1 kill → flag true à nouveau, clac compteur += 1 (total 2).
	src.emit_enemy_killed(null, Vector3.ZERO)
	await get_tree().physics_frame
	assert_int(handler.clac_played_count) \
		.override_failure_message("AC-CMB-audio-01 (d) : swing suivant doit pouvoir rejouer le clac") \
		.is_equal(2)


# ---------------------------------------------------------------------------
# AC-CMB-audio-02 (a) — Ducking -6 dB on SWING_ACTIVE bus, release 30 ms
# ---------------------------------------------------------------------------

## AC-CMB-audio-02 (a) : enemy_killed → log ducking event sur bus SWING_ACTIVE,
## delta = -6 dB, release = 30 ms wall-clock.
func test_ducking_event_logs_minus_6_db_on_swing_active_bus() -> void:
	var handler: Node = _make_handler()
	var src: CombatSignalSource = _make_combat_signal_source()
	_wire_handler_to_source(src, handler)

	src.emit_enemy_killed(null, Vector3.ZERO)
	await get_tree().physics_frame

	assert_int(handler.get_ducking_event_count()) \
		.override_failure_message("AC-CMB-audio-02 (a) : 1 ducking event loggé par enemy_killed") \
		.is_equal(1)

	var bus: Variant = handler.get_ducking_event_field(0, "bus")
	assert_str(String(bus)) \
		.override_failure_message("AC-CMB-audio-02 (a) : bus doit être SWING_ACTIVE") \
		.is_equal("SWING_ACTIVE")

	var delta_db: Variant = handler.get_ducking_event_field(0, "delta_db")
	assert_float(delta_db) \
		.override_failure_message("AC-CMB-audio-02 (a) : delta_db doit être -6.0 dB") \
		.is_equal_approx(-6.0, 0.001)

	var release_ms: Variant = handler.get_ducking_event_field(0, "release_ms")
	assert_float(release_ms) \
		.override_failure_message("AC-CMB-audio-02 (a) : release doit être 30 ms wall-clock") \
		.is_equal_approx(30.0, 0.001)


# ---------------------------------------------------------------------------
# AC-CMB-audio-02 (b) — CONNECT_DEFERRED dispatch at frame N+1, not N
# ---------------------------------------------------------------------------

## AC-CMB-audio-02 (b) : ce test isole la sémantique CONNECT_DEFERRED — handler ne reçoit
## le signal qu'au frame physics suivant l'emit, jamais le même frame.
func test_connect_deferred_dispatches_at_frame_n_plus_one() -> void:
	var handler: Node = _make_handler()
	var src: CombatSignalSource = _make_combat_signal_source()
	_wire_handler_to_source(src, handler)

	# Pre-emit : compteurs zéro.
	assert_int(handler.get_ducking_event_count()).is_equal(0)

	# Emit synchrone — CONNECT_DEFERRED met l'appel handler en queue.
	src.emit_enemy_killed(null, Vector3.ZERO)

	# Avant le physics_frame : handler PAS encore appelé.
	assert_int(handler.get_ducking_event_count()) \
		.override_failure_message(
			"AC-CMB-audio-02 (b) : CONNECT_DEFERRED doit différer le handler call jusqu'au " \
			+ "frame N+1 — le compteur doit rester 0 immédiatement post-emit"
		) \
		.is_equal(0)

	# Frame N+1 : dispatch DEFERRED.
	await get_tree().physics_frame

	assert_int(handler.get_ducking_event_count()) \
		.override_failure_message(
			"AC-CMB-audio-02 (b) : post-physics_frame, handler doit avoir été appelé"
		) \
		.is_equal(1)


# ---------------------------------------------------------------------------
# AC-CMB-audio-02 (c) — multi_kill follows enemy_killed temporally
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# AC-CMB-audio-02 (b) — Cooldown gate covers ducking release window
# ---------------------------------------------------------------------------

## AC-CMB-audio-02 (b) : `ATTACK_COOLDOWN_MS / (1000/60) ≥ DUCKING_RELEASE_MS / (1000/60)`.
## Le cooldown Combat (24 ticks ≈ 400 ms) couvre intégralement la fenêtre ducking
## (~ 2 ticks ≈ 30 ms wall-clock), donc `swing_started` ne peut pas être émis pendant
## la période où `swing_active` est ducké à -6 dB. Vérification structurelle (constantes)
## plutôt que behaviorale — la propriété "cooldown gate les transitions IDLE→SWINGING"
## est déjà couverte exhaustivement par story-002 (state_machine_lifecycle_test.gd) +
## story-004 (attacked_handler_buffer_test.gd) + story-014 (mid_swing_transitions_test.gd).
## Ce test prouve simplement la **relation numérique** entre cooldown et ducking, robuste
## contre tout futur retune des constantes (alarme automatique si quelqu'un baisse
## ATTACK_COOLDOWN_MS sous DUCKING_RELEASE_MS sans amender l'AC).
func test_attack_cooldown_covers_ducking_release_window() -> void:
	var handler: Node = _make_handler()

	var cooldown_ticks: float = CombatSystem.ATTACK_COOLDOWN_MS / PHYSICS_TICK_MS
	var ducking_ticks: float = handler.DUCKING_RELEASE_MS / PHYSICS_TICK_MS

	assert_float(cooldown_ticks) \
		.override_failure_message(
			("AC-CMB-audio-02 (b) : ATTACK_COOLDOWN_MS (%.0f ms = %.2f ticks) " \
			+ "doit couvrir DUCKING_RELEASE_MS (%.0f ms = %.2f ticks). " \
			+ "Sinon un nouveau swing_started peut être émis pendant la fenêtre " \
			+ "où swing_active est ducké à -6 dB.") % [
				CombatSystem.ATTACK_COOLDOWN_MS,
				cooldown_ticks,
				handler.DUCKING_RELEASE_MS,
				ducking_ticks,
			]
		) \
		.is_greater_equal(ducking_ticks)

	# Vérifier également l'égalité structurelle 24 ticks attendue par le GDD
	# AC-CMB-audio-02 (b) (`ATTACK_COOLDOWN/(1000/60) = 24 ticks`).
	assert_float(cooldown_ticks) \
		.override_failure_message(
			"AC-CMB-audio-02 (b) : 24 ticks attendus (cf. GDD AC text), obtenu %.2f" \
			% cooldown_ticks
		) \
		.is_between(23.5, 24.5)


## AC-CMB-audio-02 (c) : ordre intra-tick cohérent — enemy_killed individuels précèdent
## multi_kill(count). Vérification : log ducking_events contient 1 entry par enemy_killed
## (multi_kill ne déclenche AUCUN ducking event additionnel — c'est un signal d'agrégation).
func test_multi_kill_signal_does_not_add_extra_ducking_events() -> void:
	var handler: Node = _make_handler()
	var src: CombatSignalSource = _make_combat_signal_source()
	_wire_handler_to_source(src, handler)
	# multi_kill n'est PAS connecté côté handler (par design, AC-CMB-audio-02 (c) cohérence).
	# Aligné avec Audio System GDD r2 ligne 176 : "multi_kill(count) → NON connecté côté Audio".

	# Émettre 3 enemy_killed + 1 multi_kill(3) suivant — ordre Combat-side.
	src.emit_enemy_killed(null, Vector3(0.0, 0.0, 0.0))
	src.emit_enemy_killed(null, Vector3(1.0, 0.0, 0.0))
	src.emit_enemy_killed(null, Vector3(2.0, 0.0, 0.0))
	src.emit_multi_kill(3)

	await get_tree().physics_frame

	# 3 ducking events (1 par enemy_killed), pas 4 (multi_kill ne triggere pas ducking).
	assert_int(handler.get_ducking_event_count()) \
		.override_failure_message(
			"AC-CMB-audio-02 (c) : 3 enemy_killed → 3 ducking events. " \
			+ "multi_kill ne doit PAS ajouter d'event additionnel (signal d'agrégation)"
		) \
		.is_equal(3)

	# Clac dedup respecté : 1× malgré 3 kills.
	assert_int(handler.clac_played_count).is_equal(1)
	# Blood ambiance : 3× (un par kill).
	assert_int(handler.blood_played_count).is_equal(3)
