# MockAudioHandler — fixture vérifiant le contrat Combat → Audio (story-020).
#
# Implémente le contrat ADR-0006 D-4c étendu pour story-020 :
#   - AC-CMB-51       : swoosh fade-out wall-clock interpolé dans `_physics_process`
#                       (PAS Tween `_process` — viole r4 A-01 fix Fantasy staccato).
#   - AC-CMB-audio-01 : multi-kill clac dedup via `_kill_sound_played_this_swing: bool`.
#   - AC-CMB-audio-02 : ducking event ordering log (-6 dB sur bus SWING_ACTIVE,
#                       release 30 ms wall-clock, frame N+1 via CONNECT_DEFERRED).
#
# Cette fixture est la vérification contract-only côté test. La production Audio System
# (Sprint Audio à venir) implémentera le même contrat via AudioServer + AudioStreamPlayer
# + bus `default_bus_layout.tres` (ADR-0009 D-1 hierarchy 7-bus).
#
# Pattern d'injection wall-clock : `_get_time_msec: Callable` substituable (ADR-0006 D-5),
# permet aux tests de fournir une séquence déterministe `[1000, 1015, 1025, 1030, 1050]`
# sans dépendre du Time.get_ticks_msec réel (latence CI variable).
#
# NB : pas de `class_name` — le cache `.godot/global_script_class_cache.cfg` n'est rebuildé
# qu'à l'ouverture éditeur, ce qui casse les CI headless. Les tests utilisent
# `preload("res://tests/unit/combat/mock_audio_handler.gd")` directement.
#
# Story  : production/epics/combat-system/story-020-audio-swoosh-fade-multi-kill-ducking.md
# ADR    : ADR-0006 D-4c (mock contract) + D-5 (Callable injection) + D-6 (DEFERRED Combat signals)
# GDD    : design/gdd/player-combat-system.md AC-CMB-51 / AC-CMB-audio-01 / AC-CMB-audio-02

extends Node


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## AC-CMB-51 : nominale du swoosh avant fade (test fixture starts ici).
const SWOOSH_NOMINAL_DB: float = 0.0

## AC-CMB-51 (b) : `lerpf(0.0, FADE_END_DB, 0.833)` doit donner ≈ -20 dB ± 2 dB.
## Math : `0 + (-24) * 0.833 = -19.99` → ∈ [-22, -18] (tolerance AC).
## Choix de -24 dB plutôt que -80 (Implementation Notes) car les AC (b)/(c)
## du GDD imposent un point de contrôle à -20 dB intermédiaire qui n'est pas
## atteignable avec une seule lerp dB linéaire jusqu'à -80 dB. Combiné avec
## un snap silence à t≥1.0 (cf. SWOOSH_SILENCE_DB), satisfait (b) ET (c).
const SWOOSH_FADE_END_DB: float = -24.0

## AC-CMB-51 (c) : à t=1.0 (30 ms exact), `volume_db ≤ -60 dB`.
## Snap à -80 dB pour libérer le slot AudioStreamPlayer (futur production-side).
const SWOOSH_SILENCE_DB: float = -80.0

## AC-CMB-51 : durée totale du fade-out en wall-clock ms (GDD r4 A-01 fix).
const SWOOSH_FADE_DURATION_MS: float = 30.0

## AC-CMB-audio-02 : ducking delta sur bus SWING_ACTIVE à `enemy_killed`.
const DUCKING_DELTA_DB: float = -6.0

## AC-CMB-audio-02 : release wall-clock du ducking (aligné fade-out swoosh).
const DUCKING_RELEASE_MS: float = 30.0

## AC-CMB-audio-02 : nom canonique du bus (ADR-0009 D-1 + Audio GDD r2 Phase A — UPPER_SNAKE_CASE).
const SWING_ACTIVE_BUS: StringName = &"SWING_ACTIVE"


# ---------------------------------------------------------------------------
# AC-CMB-audio-01 — Multi-kill clac dedup state (ADR-0006 D-4c contract figé)
# ---------------------------------------------------------------------------

## Drapeau dedup : `false` = 1er kill du swing peut jouer le clac, `true` = déjà joué.
## Reset à `_on_swing_ended` (AC-CMB-audio-01 (d)).
var _kill_sound_played_this_swing: bool = false

## Compteur observable : combien de fois le clac a été déclenché (≤ 1 par swing).
var clac_played_count: int = 0

## Compteur observable : combien de fois le blood ambiance a été déclenché (1 par enemy_killed).
var blood_played_count: int = 0


# ---------------------------------------------------------------------------
# AC-CMB-51 — Swoosh fade state
# ---------------------------------------------------------------------------

## Volume_db courant du swoosh (proxy d'`AudioStreamPlayer.volume_db` production).
## Lu par les tests pour assertions AC-CMB-51 (b) / (c).
var swoosh_volume_db: float = SWOOSH_NOMINAL_DB

## `true` pendant que la rampe est active (entre 1er enemy_killed du swing et t≥1.0).
var _swoosh_fade_active: bool = false

## Wall-clock ms du début du fade (capturé au 1er `enemy_killed` du swing).
var _swoosh_fade_start_msec: int = 0


# ---------------------------------------------------------------------------
# ADR-0006 D-5 — Wall-clock injection point (substituable en test)
# ---------------------------------------------------------------------------

var _get_time_msec: Callable = Time.get_ticks_msec


# ---------------------------------------------------------------------------
# AC-CMB-audio-02 — Ducking event log (timestamp wall-clock par event)
# ---------------------------------------------------------------------------

## Log Array observable : 1 entry par `enemy_killed` reçu, contient `bus`, `delta_db`,
## `release_ms`, `t_msec` (wall-clock fourni par `_get_time_msec` au moment du dispatch).
##
## Note exception zero-alloc (ADR-0006 D-4d) : Dict literal autorisé hors hot path
## production — fixture test, pas `src/` runtime.
var ducking_events: Array[Dictionary] = []


# ---------------------------------------------------------------------------
# Combat signal handlers (CONNECT_DEFERRED en production, ADR-0006 D-6)
# ---------------------------------------------------------------------------

## Handler `enemy_killed` consommé en CONNECT_DEFERRED (frame N+1 vs frame N kill).
##
## Effets contractuels :
##   1. Si 1er kill du swing : déclenche le clac (+1 compteur, set flag dedup true).
##   2. Pour chaque kill : déclenche blood ambiance (+1 compteur).
##   3. Capture le `_swoosh_fade_start_msec` au 1er kill (idempotent — pas de re-trigger).
##   4. Append entry dans `ducking_events` log avec timestamp wall-clock.
func _on_enemy_killed(_enemy: Node, _position: Vector3) -> void:
	var now_msec: int = _get_time_msec.call()

	# AC-CMB-audio-01 (a)/(b) : clac dedup gate.
	if not _kill_sound_played_this_swing:
		_kill_sound_played_this_swing = true
		clac_played_count += 1

	# AC-CMB-audio-01 (c) : blood ambiance joue à chaque kill (perception N giclées).
	blood_played_count += 1

	# AC-CMB-51 : capture start au 1er kill du swing (idempotent — multi-kill ne reset pas).
	if not _swoosh_fade_active:
		_swoosh_fade_start_msec = now_msec
		_swoosh_fade_active = true

	# AC-CMB-audio-02 (a) : log ducking event timestampé.
	ducking_events.append({
		"bus": SWING_ACTIVE_BUS,
		"delta_db": DUCKING_DELTA_DB,
		"release_ms": DUCKING_RELEASE_MS,
		"t_msec": now_msec,
	})


## Handler `swing_ended` reset le drapeau dedup pour le swing suivant (AC-CMB-audio-01 (d)).
func _on_swing_ended() -> void:
	_kill_sound_played_this_swing = false


# ---------------------------------------------------------------------------
# AC-CMB-51 (a) — Per-tick fade interpolation in `_physics_process`
# (PAS `_process` — Tween `_process` serait scaled par time_scale, viole Fantasy staccato.)
# ---------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if not _swoosh_fade_active:
		return

	var now_msec: int = _get_time_msec.call()
	var elapsed_ms: float = float(now_msec - _swoosh_fade_start_msec)
	var t: float = elapsed_ms / SWOOSH_FADE_DURATION_MS

	if t >= 1.0:
		# AC-CMB-51 (c) : snap à silence en fin de fade (≤ -60 dB satisfait).
		swoosh_volume_db = SWOOSH_SILENCE_DB
		_swoosh_fade_active = false
	else:
		# AC-CMB-51 (b) : linear dB lerp ; à t=0.833 → -19.99 dB ∈ [-22, -18].
		swoosh_volume_db = lerpf(SWOOSH_NOMINAL_DB, SWOOSH_FADE_END_DB, t)


# ---------------------------------------------------------------------------
# Test helpers (lecture state — assertions ACs)
# ---------------------------------------------------------------------------

## Helper assertion-friendly : nombre d'events ducking loggés (`enemy_killed` reçus).
func get_ducking_event_count() -> int:
	return ducking_events.size()


## Helper : retourne la valeur d'un champ pour le N-ième event (0-indexed).
## Utilisé par AC-CMB-audio-02 pour assert ordre temporel + bus + delta.
func get_ducking_event_field(index: int, field: String) -> Variant:
	if index < 0 or index >= ducking_events.size():
		return null
	return ducking_events[index].get(field)
