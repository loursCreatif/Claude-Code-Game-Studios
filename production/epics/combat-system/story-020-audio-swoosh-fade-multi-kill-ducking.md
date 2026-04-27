# Story 020: Swoosh fade-out wall-clock + multi-kill clac dedup + ducking ordering

> **Epic**: Player Combat System
> **Status**: Blocked
> **Layer**: Feature
> **Type**: Integration
> **Manifest Version**: 2026-04-23

> **BLOCKED**: Audio System GDD non implémenté. Bloque AC-CMB-51 / AC-CMB-audio-01 / AC-CMB-audio-02. Une partie pourrait être débloquée par mock `MockAudioHandler` côté Combat (contract-only) avant Audio System GDD complet — décision pendant `/architecture-decision audio-system` (#11 du backlog).

## Context

**GDD**: `design/gdd/player-combat-system.md`
**Requirement**: AC-CMB-51 (swoosh fade-out wall-clock), AC-CMB-audio-01 (multi-kill clac dedup contract), AC-CMB-audio-02 (ducking event ordering)

**ADR Governing Implementation**: ADR-0006 D-5 (même Callable injection pattern que slow-mo) + ADR-0005 D-5 (CONNECT_DEFERRED pour AudioStreamPlayer instantiation)
**ADR Decision Summary**: fade-out swoosh `volume_db` interpolé wall-clock via `_get_time_msec()` dans `_physics_process` — PAS Tween dans `_process` (Tween scaled par `time_scale` produit 100 ms wall-clock perçus au lieu de 30 ms, viole Fantasy staccato). Multi-kill : flag `_kill_sound_played_this_swing: bool` côté Audio handler ; 1er `enemy_killed` du tick joue clac, 2e re-emit même tick → clac NON rejoué (anti-saturation phasing). Blood ambiance joue N fois (perceptible). Reset flag à `swing_ended`. Ducking event ordering : `enemy_killed` au tick N → frame N+1 (CONNECT_DEFERRED) ducking -6 dB sur bus `swing_active`, release 30 ms.

**Engine**: Godot 4.6 | **Risk**: LOW (logic) / MEDIUM (Audio System non encore architecté)
**Engine Notes**: AudioBus volume_db modifiable via `AudioServer.set_bus_volume_db(idx, db)`. CONNECT_DEFERRED stable Godot 4.0+.

**Control Manifest Rules (Feature layer)**:
- Required: fade-out via `_get_time_msec()` Callable injection (même pattern AC-CMB-19)
- Forbidden: Tween-based fade dans `_process` (scaled par time_scale, viole AC-CMB-51 Fantasy staccato)
- Guardrail: teardown obligatoire `_get_time_msec = Time.get_ticks_msec` post-test

---

## Acceptance Criteria

*From GDD AC-CMB-51 + AC-CMB-audio-01 + AC-CMB-audio-02 :*

- [ ] **AC-CMB-51** : swing actif `Engine.time_scale = 0.3`, swoosh `volume_db = 0.0`, `enemy_killed` dispatché DEFERRED frame N+1 → fade-out déclenché avec `_get_time_msec()` mocké `1000, 1015, 1025, 1030, 1050` :
  - (a) interpolation wall-clock dans `_physics_process` (PAS Tween `_process`)
  - (b) à 1025 (25 ms elapsed, 83% du fade 30 ms) : `volume_db ≈ -20 dB ± 2 dB`
  - (c) à 1030 (30 ms elapsed exact, 100%) : `volume_db ≤ -60 dB` (silence pratique)
  - (d) résolution complète dans `[25, 50] ms wall-clock`
  - Si résolution observée 75-100 ms wall-clock → AC FAIL "swoosh fade-out scaled by time_scale — viole r4 A-01 fix"
- [ ] **AC-CMB-audio-01 (multi-kill clac dedup)** : 2 MockEnemies tués même tick, `MockAudioHandler` avec flag `_kill_sound_played_this_swing: bool` :
  - (a) 1er `enemy_killed` reçu : flag `false → true`, clac joué 1×
  - (b) 2e `enemy_killed` même tick : flag déjà true → clac NON rejoué
  - (c) blood ambiance joue 2× (1 par enemy_killed individuel)
  - (d) à `swing_ended` : flag reset à `false`
- [ ] **AC-CMB-audio-02 (ducking ordering)** : swing actif, swoosh sur bus `swing_active` (≤ -6 dB) ; `enemy_killed` au tick N :
  - (a) frame N+1 (CONNECT_DEFERRED dispatch) : bus `swing_active` reçoit ducking -6 dB, release 30 ms wall-clock
  - (b) aucun nouveau `swing_started` pendant `[N, N + ATTACK_COOLDOWN/(1000/60) = 24 ticks]` (cooldown couvre période ducking)
  - (c) si `multi_kill(count)` émis : suit les `enemy_killed` individuels (ordre intra-tick coherent)

---

## Implementation Notes

*Derived from GDD §Audio + ADR-0006 D-5 + ADR-0005 D-5 :*

```gdscript
# Audio handler (potentiellement combat_audio_handler.gd ou inline combat_system.gd au MVP)
var _kill_sound_played_this_swing: bool = false
var _swoosh_player: AudioStreamPlayer  # node enfant CombatSystem
var _swoosh_fade_start_msec: int = 0
var _swoosh_fade_active: bool = false
const SWOOSH_FADE_DURATION_MS: float = 30.0

# Injection (même que slow-mo)
var _get_time_msec: Callable = Time.get_ticks_msec

func _on_enemy_killed(enemy: Node3D, pos: Vector3) -> void:
    # Clac dedup
    if not _kill_sound_played_this_swing:
        _kill_sound_played_this_swing = true
        _play_clac_sfx()
    # Blood ambiance jouée chaque kill
    _play_blood_sfx_at(pos)
    # Trigger swoosh fade
    _swoosh_fade_start_msec = _get_time_msec.call()
    _swoosh_fade_active = true
    # Ducking event (CONNECT_DEFERRED automatique depuis enemy_killed → audio bus handler)
    AudioServer.set_bus_volume_db(AudioServer.get_bus_index("swing_active"), -6.0)

func _on_swing_ended() -> void:
    _kill_sound_played_this_swing = false

func _physics_process(delta: float) -> void:
    if _swoosh_fade_active:
        var elapsed := float(_get_time_msec.call() - _swoosh_fade_start_msec)
        var t := elapsed / SWOOSH_FADE_DURATION_MS
        if t >= 1.0:
            _swoosh_player.volume_db = -80.0  # silence
            _swoosh_fade_active = false
        else:
            _swoosh_player.volume_db = lerpf(0.0, -80.0, t)  # linéaire dB
```

- **Forbidden** : `Tween` ou `Tweener` pour le fade — utiliser interpolation manuelle dans `_physics_process` (ADR-0001 autorité)
- **Audio buses** : `swing_active`, `combat_kill`, `combat_ambience` à définir dans `default_bus_layout.tres` (Audio System GDD pendant)

---

## Out of Scope

- Audio System GDD complet (story séparée Audio epic — débloqué par #11 `/architecture-decision audio-system`)
- VFX kill flash + decal (AC-CMB-42 BLOCKED VFX System)

---

## QA Test Cases

- **AC-1** Swoosh fade-out wall-clock under slow-mo
  - Given: `Engine.time_scale = 0.3`, `_swoosh_player.volume_db = 0.0`, `_get_time_msec` mocké séquence `[1000, 1015, 1025, 1030, 1050]`
  - When: `enemy_killed.emit(MockEnemy, ...)` puis 5 `_physics_process` appels avec time mocks
  - Then: à 1025 → -20 ± 2 dB ; à 1030 → ≤ -60 dB ; résolution dans [25, 50] ms
  - Edge cases: si Tween-based → résolution ~75-100 ms (time_scale=0.3) → AC FAIL

- **AC-2** Multi-kill clac dedup
  - Given: 2 MockEnemies tués même tick, MockAudioHandler initialisé `_kill_sound_played_this_swing == false`
  - When: 2× `enemy_killed.emit()` dispatchés
  - Then: clac joué 1×, flag true ; blood SFX 2× ; `swing_ended` reset flag
  - Edge cases: 5 kills même tick → 1 clac, 5 blood SFX

- **AC-3** Ducking event ordering
  - Given: swing actif, swoosh playing
  - When: `enemy_killed` au tick N
  - Then: frame N+1 (DEFERRED), bus `swing_active` -6 dB, release 30 ms
  - Edge cases: `multi_kill(count)` émis → suit les `enemy_killed` (ordre temporel)

- **AC-4** No new swing during ducking window
  - Given: ducking actif, fenêtre `[N, N+24 ticks]` (cooldown)
  - When: `Player.attacked.emit()` pendant cooldown
  - Then: aucun `swing_started` (cooldown gate, story-002 AC-02)
  - Edge cases: à `_cooldown_timer == 0` exact → swing accepté (post-ducking-window)

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/combat/swoosh-fade-wall-clock-test.gd` + `tests/integration/combat/audio-multi-kill-ducking-test.gd` (BLOCKED Audio System GDD)

**Status**: [ ] Not yet created (BLOCKED Audio System)

---

## Dependencies

- Depends on: Story 011/012 (kill resolution émet enemy_killed), Story 013 (slow-mo Callable pattern), **Audio System GDD + ADR Audio (#11 backlog)**
- Unlocks: Combat ↔ Audio contract verification (gate-check pre-production)
