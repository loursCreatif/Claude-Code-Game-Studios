# Story 020: Swoosh fade-out wall-clock + multi-kill clac dedup + ducking ordering

> **Epic**: Player Combat System
> **Status**: Complete — 2026-05-03
> **Layer**: Feature
> **Type**: Integration
> **Manifest Version**: 2026-04-23

> **UNBLOCKED 2026-05-03**: Audio System GDD r2.2 Phase A+B+C+D complete + ADR-0009 Accepted 2026-04-27 + `/consistency-check audio-system` PASS 2026-05-03. AC-CMB-51 / AC-CMB-audio-01 / AC-CMB-audio-02 implémentables côté Combat via `MockAudioHandler` contract-only (pas besoin d'attendre Audio System impl pleine). MockAudioHandler implémente les 3 ACs comme un consumer DEFERRED des signaux Combat (`swing_started`/`swing_ended`/`enemy_killed`/`multi_kill`) : (a) AC-CMB-51 fade-out swoosh wall-clock via `_get_time_msec: Callable` injection même pattern que slow-mo (Combat ADR-0006 D-5) ; (b) AC-CMB-audio-01 multi-kill clac dedup via flag `_kill_sound_played_this_swing: bool` reset à `swing_ended` ; (c) AC-CMB-audio-02 ducking ordering via `AudioServer.set_bus_volume_db("SWING_ACTIVE", -6.0)` à `enemy_killed` DEFERRED frame N+1, release 30 ms wall-clock dans `_physics_process`. Audio bus stub `default_bus_layout.tres` minimal (Master + SFX + SWING_ACTIVE + COMBAT_KILL) suffisant — sidechain compressor `MUSIC` peut être absent au MVP Combat (sera ajouté Sprint Audio). Tests cibles : `tests/integration/combat/swoosh_fade_wall_clock_test.gd` + `tests/integration/combat/audio_multi_kill_ducking_test.gd`. Précédente note BLOCKED conservée historiquement : "Audio System GDD non implémenté ; décision pendant `/architecture-decision audio-system` (#11 du backlog)" — résolu (ADR-0009 Accepted, GDD r2.2 Phase A+B+C+D complete).

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
**Required evidence**: `tests/integration/combat/swoosh_fade_wall_clock_test.gd` + `tests/integration/combat/audio_multi_kill_ducking_test.gd` + fixture `tests/unit/combat/mock_audio_handler.gd`

**Status**: [x] Implémenté 2026-05-03 — 10/10 PASS headless GdUnit4 (4 swoosh fade + 6 multi-kill/ducking, exit code 0, 178 ms total). Naming snake_case retenu (vs dash dans ancien spec) per technical-preferences convention + parité avec les autres tests Combat existants (slow_mo_wall_clock_test.gd, mid_swing_transitions_test.gd).

**Note d'implémentation — divergence vs Implementation Notes pseudo-code (BLOCKING AC suivi)** : Le pseudo-code du story Implementation Notes indique `lerpf(0.0, -80.0, t)` linéaire dB jusqu'à -80, mais AC-CMB-51 (b) impose `volume_db ≈ -20 dB ± 2 dB` à t=0.833 (impossible avec lerpf(0,-80) qui donne -66.6 dB à 0.833) ET (c) `≤ -60 dB` à t=1.0. La résolution retenue : `lerpf(0.0, -24.0, t)` linéaire dB pendant t < 1.0 (à 0.833 → -19.99 dB ∈ [-22, -18] ✓), puis snap `SWOOSH_SILENCE_DB = -80.0` à t ≥ 1.0 (≤ -60 ✓). Audio interpretation valide : fade audible jusqu'à -24 dB (perceptuellement masqué par clac à 0 dB en territoire slow-mo), puis snap silence pour libérer le slot AudioStreamPlayer en production. Le GDD AC reste autorité ; mettre à jour les Implementation Notes pseudo-code en cohérence si revue.

---

## Dependencies

- Depends on: Story 011/012 (kill resolution émet enemy_killed), Story 013 (slow-mo Callable pattern), **Audio System GDD + ADR Audio (#11 backlog)**
- Unlocks: Combat ↔ Audio contract verification (gate-check pre-production)

---

## Completion Notes
**Completed** : 2026-05-03
**Criteria** : 11/11 passing (4 swoosh fade AC-CMB-51 a/b/c/d + 3 multi-kill AC-CMB-audio-01 a/b/c/d + 4 ducking AC-CMB-audio-02 a/b/c)
**Deviations** :
- ADVISORY — Implementation Notes pseudo-code `lerpf(0,-80)` aurait failé AC-CMB-51 (b) à -66.6 dB ; résolu `lerpf(0,-24,t)` + snap silence -80 à t≥1.0 (cohabitation AC b+c). GDD AC reste autorité — Implementation Notes pseudo-code à mettre à jour si GDD revue.
**Test Evidence** : Integration tests `tests/integration/combat/swoosh_fade_wall_clock_test.gd` (4 tests) + `tests/integration/combat/audio_multi_kill_ducking_test.gd` (7 tests) + fixture `tests/unit/combat/mock_audio_handler.gd` — **11/11 PASS** (184 ms total, exit code 0).
**Code Review** : Complete — APPROVED WITH SUGGESTIONS (1 BLOCKING `qa-tester` GAP-1 cooldown gate untested → résolu via `test_attack_cooldown_covers_ducking_release_window` ; 2 BLOCKING `godot-gdscript-specialist` B-1 commentaire TimeMock + B-2 queue_free cleanup → B-1 reformulé empirique, B-2 identifié red herring causant hang inter-test, GdUnit4 native cleanup suffit).
