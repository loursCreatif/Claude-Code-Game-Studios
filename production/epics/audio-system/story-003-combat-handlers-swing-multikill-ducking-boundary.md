# Story 003: Combat Audio Handlers — Swing + Multi-Kill Rangs +0/+2/+4 Cap + Ducking `SWING_ACTIVE` -6 dB + Boundary Cases D≤0/R≤0

> **Epic**: Audio System
> **Status**: Complete 2026-05-04 (21/21 tests PASS — 7/7 ACs COVERED)
> **Layer**: Core
> **Type**: Integration
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/audio-system.md` (r2.3 §Rules 4/12/13 + §Formulas 1/2 hardened Phase C + §Implementation Details Phase D.3)
**Requirements**:
- R-AUD-4 : Wall-clock fades dans `_physics_process` exclusivement via `_get_time_msec` Callable — Tween interdit sur `volume_db` time-critical
- R-AUD-7 : Position payload `enemy_killed(enemy, position: Vector3)` — capture au tick d'émission Combat
- R-AUD-12 : Ducking event-driven `duck_bus(SWING_ACTIVE, -6.0, 30.0)` — instantané + release wall-clock 30 ms expo perceptuel (Formula 2 linear-amplitude Phase C)
- R-AUD-13 : Multi-kill clac pitch-shift +N semitones — counter `_kill_count_this_swing` owned Audio (reset `swing_started`/`swing_ended`), rangs +0/+2/+4 cap, asset reuse `clac.wav` via `pitch_scale` natif

**ADR Governing**: ADR-0009 D-3 + ADR-0006 D-3 (Combat capture position au tick d'émission) + D-4 (`_get_time_msec` Callable injection partagé Combat ↔ Audio)
**Decision Summary**: Combat émet `swing_started`, `swing_ended`, `enemy_killed(enemy, position)`, `multi_kill(count)` en `CONNECT_DEFERRED`. Audio handler counter multi-kill `_kill_count_this_swing` géré côté Audio (PAS Combat) ; clac `pitch_scale ∈ {1.0, 1.122, 1.260}` cap 4e+ kill.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `AudioStreamPlayer.pitch_scale` runtime mid-`play()` — vérifier empiriquement pas de pop transitoire (cf. story-008 ADVISORY waveform). `_get_time_msec: Callable = Time.get_ticks_msec` injection cohérente Combat ADR-0006 D-4.

**Control Manifest Rules (Core layer)**:
- Required: handlers connectent en `CONNECT_DEFERRED` (R-AUD-5 default — pas d'exemption SYNC pour Audio MVP)
- Required: capture `position` payload AU MOMENT du handler (Rule 7) — pas `enemy.global_position` (queue_free risk)
- Forbidden: aucune mutation état Combat depuis handler Audio (D-7 ADR-0005)
- Guardrail: `_on_enemy_killed` handler isolé p99 < 100 µs (Phase D.4 sub-budget)

---

## Acceptance Criteria

*From GDD AC-AUD-04/05/06/17 + boundary cases r2.3 D≤0/R≤0:*

- [ ] **AC-AUD-04** (swoosh fade-out wall-clock indépendant `time_scale`) : à `Engine.time_scale = 0.3` slow-mo, `swing_ended` reçu DEFERRED N+1 → fade démarre ; à `t = 1015` (15 ms wall-clock), `volume_db ≈ -43 dB ± 2 dB` (Formula 1) ; à `t = 1030` (30 ms 100%), `volume_db ≤ -60 dB` ; résolution complète dans `[25, 50] ms` wall-clock. Si test observe résolution 75-100 ms : FAIL "swoosh scaled by time_scale — Tween used in `_process` instead of wall-clock `_physics_process` — violation Rule 4 ADR-0009 D-3 + Combat AC-CMB-51".
- [ ] **AC-AUD-04 boundary D = 0.0** : si `swoosh_fade_duration_ms = 0.0` → `volume_db == -80.0` immédiat (Formula 1 short-circuit `D ≤ 0 → SILENCE_DB`) + `push_warning` capturé 1× au boot.
- [ ] **AC-AUD-04 boundary D = -1.0** : même comportement que D=0.0 (guard symétrique négatif).
- [ ] **AC-AUD-05** (multi-kill rangs +0/+2/+4 cap) : 4 `enemy_killed` même swing → clac 1 `pitch_scale ≈ 1.0 ± 0.001` ; clac 2 `≈ 1.122 ± 0.005` (+2 semitones) ; clac 3 `≈ 1.260 ± 0.01` (+4 semitones) ; clac 4 `≈ 1.260 ± 0.01` (cap, PAS +6 carry-over) ; blood ambiance jouée 4× avec délai 50 ms wall-clock chacune `pitch_scale = 1.0` (à `time_scale = 1.0` allowlist non activée).
- [ ] **AC-AUD-06** (ducking SWING_ACTIVE -6 dB instantané + release 30 ms wall-clock) : `enemy_killed` reçu DEFERRED N+1 → `get_bus_volume_db(swing_active_idx) == -12.0 dB` instantané (1 frame) ; release démarre `_physics_process` ; à t=1015 (50% perceptuel), bus ≈ `-8.5 dB ± 1 dB` (Formula 2 linear-amplitude lerp) ; à t=1030, bus = `-6.0 dB` nominal.
- [ ] **AC-AUD-06 boundary R = 0.0** : `ducking_release_ms = 0.0` → `get_bus_volume_db(swing_active_idx) == NOMINAL_DB` immédiat (short-circuit) + `push_warning`.
- [ ] **AC-AUD-06 boundary R = -1.0** : même que R=0.0.
- [ ] **AC-AUD-17** (multi-kill counter reset) : après 3 kills, `_kill_count_this_swing == 3` ; `swing_ended` reçu → counter reset à 0 ; `swing_started` suivant confirme 0 ; nouveau premier kill `pitch_scale = 1.0` (pas +6 bug carry-over).

---

## Implementation Notes

*Derived from ADR-0009 D-3 + Phase D.3 + Formulas 1/2 hardened Phase C:*

```gdscript
const SWOOSH_FADE_DURATION_MS: float = 30.0
const DUCKING_RELEASE_MS: float = 30.0
const DUCKING_DELTA_DB: float = -6.0
const SWING_ACTIVE_NOMINAL_DB: float = -6.0
const BLOOD_DELAY_MS: float = 50.0
const SILENCE_DB: float = -80.0
const MAX_PITCH_RANK: int = 3  # cap +4 semitones (rank 3+)
const MULTI_KILL_PITCH_SHIFT_SEMITONES: float = 2.0  # per rank

var _kill_count_this_swing: int = 0
var _active_clac_players: Dictionary[int, bool] = {}  # slot_idx → true (Phase D.3)
var _swoosh_fade_active: bool = false
var _swoosh_fade_start_msec: int = 0
var _ducking_release_active: bool = false
var _ducking_release_start_msec: int = 0
var _get_time_msec: Callable = Time.get_ticks_msec

# Boot guard for D / R ≤ 0
func _ready() -> void:
    if SWOOSH_FADE_DURATION_MS <= 0.0:
        push_warning("swoosh_fade_duration_ms <= 0 — fade short-circuit SILENCE_DB")
    if DUCKING_RELEASE_MS <= 0.0:
        push_warning("ducking_release_ms <= 0 — release short-circuit NOMINAL_DB")

# Connect signals (CONNECT_DEFERRED)
func _connect_combat_signals(combat: Node) -> void:
    combat.swing_started.connect(_on_swing_started, CONNECT_DEFERRED)
    combat.swing_ended.connect(_on_swing_ended, CONNECT_DEFERRED)
    combat.enemy_killed.connect(_on_enemy_killed, CONNECT_DEFERRED)

func _on_swing_started() -> void:
    _kill_count_this_swing = 0
    play_2d(swoosh_stream, AudioBuses.SWING_ACTIVE)

func _on_swing_ended() -> void:
    _kill_count_this_swing = 0
    _start_swoosh_fade()

func _on_enemy_killed(enemy: Node, position: Vector3) -> void:
    _kill_count_this_swing += 1
    var rank := mini(_kill_count_this_swing - 1, MAX_PITCH_RANK - 1)  # 0/1/2 cap
    var pitch_scale := 2.0 ** ((MULTI_KILL_PITCH_SHIFT_SEMITONES * rank) / 12.0)
    var slot_idx := play_3d_at(clac_stream, position, AudioBuses.COMBAT_KILL, pitch_scale)
    if slot_idx >= 0:
        _active_clac_players[slot_idx] = true
        # Phase D.3 — disconnect on finished CONNECT_ONE_SHOT
        var slot: AudioStreamPlayer3D = _3d_pool[slot_idx]
        if slot.finished.is_connected(_on_clac_slot_finished.bind(slot_idx)):
            slot.finished.disconnect(_on_clac_slot_finished.bind(slot_idx))
        slot.finished.connect(_on_clac_slot_finished.bind(slot_idx), CONNECT_ONE_SHOT)
    duck_bus(AudioBuses.SWING_ACTIVE, DUCKING_DELTA_DB, DUCKING_RELEASE_MS)
    # blood ambiance 50 ms post-clac wall-clock — schedule via _physics_process timer
    _schedule_blood_play(position)

func _on_clac_slot_finished(slot_idx: int) -> void:
    _active_clac_players.erase(slot_idx)

# Formula 1 hardened — wall-clock fade
func _physics_process(_delta: float) -> void:
    if _swoosh_fade_active:
        _tick_swoosh_fade()
    if _ducking_release_active:
        _tick_ducking_release()

func _tick_swoosh_fade() -> void:
    if SWOOSH_FADE_DURATION_MS <= 0.0:
        _set_swoosh_volume_db(SILENCE_DB)
        _swoosh_fade_active = false
        return
    var elapsed: float = float(_get_time_msec.call() - _swoosh_fade_start_msec)
    var t: float = clampf(elapsed / SWOOSH_FADE_DURATION_MS, 0.0, 1.0)
    var volume_db: float = lerpf(SWING_ACTIVE_NOMINAL_DB, SILENCE_DB, t)
    _set_swoosh_volume_db(volume_db)
    if t >= 1.0:
        _swoosh_fade_active = false
```

`_active_clac_players` Dictionary tracker (Phase D.3) — utilisé par story 007 (slow-mo pitch shift bus allowlist) pour exclure les slots clac du pitch shift.

---

## Out of Scope

- Story 005 : Level handler crossfade (utilise même `_get_time_msec` injection mais autre formule F-04)
- Story 006 : GSM pause state preservation `_fade_pause_msec` offset wall-clock pour fades en cours
- Story 007 : slow-mo pitch shift bus allowlist Rule 11 (utilise `_active_clac_players` tracker pour exclusion clac)
- Story 010 : lint CI `lint-audio-tween` (zero `Tween.tween_property.*volume_db`)
- Story 011 : perf 5-swings stress + sub-budgets handler/play_3d_at
- Story 012 : sidechain peak meter verification

---

## QA Test Cases

**AC-AUD-04** (swoosh fade-out wall-clock) :
- Given : swing en cours sur `SWING_ACTIVE` `volume_db = -6.0`, `Engine.time_scale = 0.3`, `_get_time_msec` mocké séquence `[1000, 1015, 1025, 1030, 1050]`
- When : `swing_ended` reçu DEFERRED frame N+1
- Then : à t=1015, `volume_db ≈ -43 dB ± 2 dB` (Formula 1) ; à t=1030, `volume_db ≤ -60 dB` ; résolution dans `[25, 50] ms` wall-clock
- Edge cases : si test observe 75-100 ms → FAIL "Tween scaled — violation Rule 4"

**AC-AUD-04 boundary D=0** :
- Given : `SWOOSH_FADE_DURATION_MS = 0.0` (corruption save / fixture mal configuré)
- When : `_tick_swoosh_fade()` exécuté
- Then : `volume_db == SILENCE_DB == -80.0` immédiat + `push_warning` capturé au boot

**AC-AUD-05 multi-kill rangs** :
- Given : swing actif, counter = 0
- When : 4 `enemy_killed` émis (4e pathologique au-delà MAX_KILLS_PER_SWING=3 Combat)
- Then : pitch_scale rangs 1.0 / 1.122 / 1.260 / 1.260 (cap) ; blood ambiance jouée 4× avec délai 50 ms wall-clock chacune `pitch_scale = 1.0`

**AC-AUD-06 ducking release** :
- Given : swoosh joue `SWING_ACTIVE` `volume_db = -6.0`
- When : `enemy_killed` reçu DEFERRED N+1
- Then : `get_bus_volume_db(swing_active_idx) == -12.0 dB` instantané (1 frame) ; release `_physics_process` ; à t=1015 ≈ -8.5 dB ± 1 dB ; à t=1030 = -6.0 dB
- Edge cases : R=0.0 → restore instantané + `push_warning` ; R=-1.0 → idem

**AC-AUD-17 counter reset** :
- Given : 3 kills, counter = 3
- When : `swing_ended` reçu DEFERRED N+1 ; puis `swing_started` ; puis `enemy_killed`
- Then : counter reset 0 → 1 ; nouveau premier clac `pitch_scale = 1.0` (pas carry-over +6)

---

## Test Evidence

**Story Type**: Integration
**Required evidence**:
- `tests/integration/audio/swoosh_fade_wall_clock_test.gd` (AC-AUD-04 + boundary D≤0)
- `tests/integration/audio/multi_kill_pitch_shift_test.gd` (AC-AUD-05 + AC-AUD-17 counter reset)
- `tests/integration/audio/ducking_release_wall_clock_test.gd` (AC-AUD-06 + boundary R≤0)
- Note : `MockAudioHandler` Combat (`tests/unit/combat/mock_audio_handler.gd` Complete 2026-05-03) sert de référence canonique — production AudioSystem implémente même contract D-4c

**Status**: [x] Created + 21/21 PASS 2026-05-04

---

## Dependencies

- Depends on: Story 001 (autoload + bus + pool) — Complete 2026-05-04, Story 002 (API verbes `play_2d` / `play_3d_at` / `duck_bus`) — Complete 2026-05-04
- Unlocks: Story 007 (slow-mo pitch shift utilise `_active_clac_players` tracker), Story 011 (perf 5-swings stress), Story 012 (sidechain peak meter)

---

## Completion Notes
**Completed**: 2026-05-04
**Criteria**: 7/7 passing (21/21 tests PASS — 7 swoosh fade wall-clock + 8 multi-kill pitch + 6 ducking release wall-clock)
**Deviations**: aucune
**Test Evidence**: Integration — 3 fichiers `tests/integration/audio/` (swoosh_fade_wall_clock, multi_kill_pitch_shift, ducking_release_wall_clock)
**Code Review**: skipped (Solo mode + mécanique extension d'`audio_system.gd` review story-001/002 existant)
**Files**: `src/core/audio_system.gd` étendu (+~190 lignes Combat handlers + ticker), 3 nouveaux fichiers test
**Implementation note**:
- `swoosh_fade_duration_ms` / `ducking_release_ms` exposés en `var` (pas `const`) pour permettre boundary tests D≤0/R≤0 + future migration `tuning_knobs.yaml`. Defaults figés ADR-0009 Phase D.3 (30 ms / 30 ms).
- Formula 2 perceptuel hardened : `db_to_linear(start) → db_to_linear(end)` lerp puis `linear_to_db` (vs lerp dB direct = perceptuel cassé). Vérifié à t=0.5 → -8.49 dB ∈ [-9.5, -7.5] tolerance AC.
- Multi-kill rangs : `mini(_kill_count_this_swing - 1, MAX_PITCH_RANK - 1)` cap rang 2 = +4 semitones. 4e+ kill PAS +6 carry-over (régression test passé).
- `_active_clac_players: Dictionary` tracker populé via Phase D.3 (CONNECT_ONE_SHOT auto-cleanup via pre-built Callable per slot zero-alloc). Story-007 dependency satisfaite.
- Blood queue `PackedFloat32Array` + `PackedVector3Array` pré-alloués 8 slots (sentinel `-1.0` = vide) — zero-alloc hot path conforme engine-code rules.
- Wall-clock independence vs `Engine.time_scale = 0.3` slow-mo vérifié : fade complete à 30 ms wall-clock (PAS 100 ms = 30/0.3 si Tween scaled).
- `_get_time_msec: Callable` injection point (ADR-0006 D-5) — substituable test via lambda capture-by-value Array wrapper `[idx]` pattern hérité MockAudioHandler.
- Ducking restart from -12 (PAS accumulation) sur kills rapides — confirmé via test dédié.
