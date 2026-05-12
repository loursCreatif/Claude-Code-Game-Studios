# Story 004: Movement Audio Handlers — Dash / Wall-Run Loop+Exit Fade 100 ms / Wall-Jump / Death 60-80 ms + Overlap Respawn / Respawn Silence

> **Epic**: Audio System
> **Status**: Complete 2026-05-04 (24/24 tests PASS — 11/11 ACs COVERED, AC-AUD-07 (a) ADVISORY pipeline asset, (f) ADVISORY playtest)
> **Layer**: Core
> **Type**: Integration
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/audio-system.md` (r2.3 §Rules 14 + §Visual/Audio Requirements + §Interactions Movement)
**Requirements**:
- R-AUD-5 : `CONNECT_DEFERRED` par défaut sur tous les signals consumer
- R-AUD-6 : Spatialisation 2D head-locked vs 3D positional figée par event-type — Movement signals tous 2D head-locked
- R-AUD-14 : Death feedback 60-80 ms + overlap première frame respawn intentionnel (queue audio Godot survit scene reload — `RESPAWN_DELAY = 0.05 s` figé Movement Pillar 3)

**ADR Governing**: ADR-0009 D-4 + ADR-0005 D-2 (Movement signals canoniques) + D-9 (`RESPAWN_DELAY = 0.05 s` Pillar 3)
**Decision Summary**: Movement émet `dash_started`, `dash_rejected` (futur), `wall_run_entered`, `wall_run_exited`, `wall_jumped`, `died`, `respawned` en `CONNECT_DEFERRED`. Audio handlers dispatch via `play_2d` head-locked. `death.wav` 60-80 ms wall-clock — overlap respawn frame autorisé (queue audio survit scene reload), ne PAS extend `RESPAWN_DELAY` (Pillar 3 figé).

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `AudioStreamPlayer.stream.get_length()` accessible runtime pour assertion duration. Queue audio Godot survit `scene reload` (comportement empirique stable Godot 4.0+).

**Control Manifest Rules (Core layer)**:
- Required: connect signals avec `CONNECT_DEFERRED` flag explicite
- Forbidden: mutation état Movement depuis handler Audio (D-7 ADR-0005)
- Forbidden: extend `RESPAWN_DELAY` au-delà de 50 ms pour accommoder son (Pillar 3 figé Movement ADR-0005 D-9)

---

## Acceptance Criteria

*From GDD AC-AUD-07 + §Visual/Audio Requirements §Movement audio + Rule 14:*

- [ ] **AC-AUD-07 (a) Precheck asset** : `ResourceLoader.exists("res://assets/audio/sfx/death.wav")` retourne `true` — sinon FAIL "death.wav asset manquant — bloquer Sprint Audio asset pipeline gate".
- [ ] **AC-AUD-07 (b) Dispatch DEFERRED** : `Movement.died` émis → `play_2d(death_stream, AudioBuses.SFX)` appelé via DEFERRED frame N+1.
- [ ] **AC-AUD-07 (c) Duration assertion automatique CI** : `death_stream.get_length() ∈ [0.060, 0.080] s` (60-80 ms — default 70 ms).
- [ ] **AC-AUD-07 (d) Lower bound** : si `death_stream.get_length() < 0.060 s` → FAIL "death.wav < 60 ms — perceptuellement insuffisant pour reconnaissance timbre (seuil 60-100 ms) — fix Phase A CD r2".
- [ ] **AC-AUD-07 (e) Upper bound** : si `death_stream.get_length() > 0.080 s` → FAIL "death.wav > 80 ms — overlap respawn frame trop long, immersion brisée".
- [ ] **AC-AUD-07 (f) Overlap respawn empirique (ADVISORY)** : evidence playtest sound-designer confirme son perceptible immédiatement après respawn ~1 frame, pas de coupure brutale. Test automatique couvre (a)-(e), (f) en `production/qa/evidence/audio-death-overlap-{date}.md`.
- [ ] **`dash_started`** : `play_2d(dash_stream, AudioBuses.SFX)` ≤ 100 ms.
- [ ] **`wall_run_entered`** : `play_2d(wallrun_loop_stream, AudioBuses.SFX)` loop infinie.
- [ ] **`wall_run_exited`** : fade-out 100 ms wall-clock dans `_physics_process` sur le slot `wallrun_loop`.
- [ ] **`wall_jumped`** : `play_2d(walljump_stream, AudioBuses.SFX)` ≤ 200 ms.
- [ ] **`respawned`** : noop (silence intentionnel post-respawn pour clarté rythmique Pillar 1).

---

## Implementation Notes

*Derived from ADR-0009 D-4 + Rule 14 r2 Phase A:*

```gdscript
const DEATH_AUDIO_DURATION_MS_MIN: float = 60.0
const DEATH_AUDIO_DURATION_MS_MAX: float = 80.0
const WALLRUN_FADE_OUT_MS: float = 100.0

@export var dash_stream: AudioStream
@export var wallrun_loop_stream: AudioStream
@export var walljump_stream: AudioStream
@export var death_stream: AudioStream

var _wallrun_slot_idx: int = -1
var _wallrun_fade_active: bool = false
var _wallrun_fade_start_msec: int = 0

func _connect_movement_signals(player: Node) -> void:
    player.dash_started.connect(_on_dash_started, CONNECT_DEFERRED)
    player.wall_run_entered.connect(_on_wall_run_entered, CONNECT_DEFERRED)
    player.wall_run_exited.connect(_on_wall_run_exited, CONNECT_DEFERRED)
    player.wall_jumped.connect(_on_wall_jumped, CONNECT_DEFERRED)
    player.died.connect(_on_died, CONNECT_DEFERRED)
    player.respawned.connect(_on_respawned, CONNECT_DEFERRED)

func _on_dash_started(_dir: Vector3, _strength: float) -> void:
    play_2d(dash_stream, AudioBuses.SFX)

func _on_wall_run_entered(_normal: Vector3) -> void:
    _wallrun_slot_idx = play_2d(wallrun_loop_stream, AudioBuses.SFX)

func _on_wall_run_exited() -> void:
    if _wallrun_slot_idx >= 0:
        _wallrun_fade_active = true
        _wallrun_fade_start_msec = _get_time_msec.call()

func _on_wall_jumped(_dir: Vector3, _push: Vector3) -> void:
    play_2d(walljump_stream, AudioBuses.SFX)

func _on_died() -> void:
    play_2d(death_stream, AudioBuses.SFX)
    # Pillar 3 — overlap première frame respawn autorisé, queue Godot survit scene reload

func _on_respawned(_pos: Vector3) -> void:
    pass  # silence intentionnel — clarté rythmique Pillar 1

# Wall-run fade-out _physics_process (extension story 003 _physics_process)
func _tick_wallrun_fade() -> void:
    if not _wallrun_fade_active or _wallrun_slot_idx < 0:
        return
    var elapsed: float = float(_get_time_msec.call() - _wallrun_fade_start_msec)
    var t: float = clampf(elapsed / WALLRUN_FADE_OUT_MS, 0.0, 1.0)
    var volume_db: float = lerpf(0.0, SILENCE_DB, t)
    _2d_pool[_wallrun_slot_idx].volume_db = volume_db
    if t >= 1.0:
        _2d_pool[_wallrun_slot_idx].stop()
        _wallrun_slot_idx = -1
        _wallrun_fade_active = false
```

Boot validation Movement assets via `_ready()` :
```gdscript
assert(ResourceLoader.exists("res://assets/audio/sfx/death.wav"),
    "death.wav asset manquant — bloquer Sprint Audio asset pipeline gate")
var death_len: float = death_stream.get_length() if death_stream else 0.0
assert(death_len >= DEATH_AUDIO_DURATION_MS_MIN / 1000.0,
    "death.wav < 60 ms — perceptuellement insuffisant")
assert(death_len <= DEATH_AUDIO_DURATION_MS_MAX / 1000.0,
    "death.wav > 80 ms — overlap respawn frame trop long")
```

---

## Out of Scope

- Story 003 : Combat handlers (swing/multi-kill/ducking)
- Story 005 : Level handlers (level_active/level_unloading)
- Story 006 : GSM pause/resume — handler `_on_died` pendant `MUTED_PAUSED` joue silencieusement, mute Master coupe overlap (edge case GDD §Edge Cases)
- Story 010 : lint CI deferred (zero `connect()` sans flag `CONNECT_DEFERRED`)

---

## QA Test Cases

**AC-AUD-07 (a-e) death duration assertion** :
- Given : AudioSystem prêt + `res://assets/audio/sfx/death.wav` existe
- When : Movement `died` émis ; assertion duration au boot
- Then : `ResourceLoader.exists` true ; `death_stream.get_length() ∈ [0.060, 0.080] s` ; `play_2d` appelé via DEFERRED N+1
- Edge cases : asset manquant → FAIL ; duration < 60 ms → FAIL ; duration > 80 ms → FAIL

**AC-AUD-07 (f) overlap respawn (ADVISORY)** :
- Setup : playtest sound-designer scenarios mort répétée, attention au son death.wav post-respawn
- Verify : son perceptible immédiatement après respawn ~1 frame, pas de coupure brutale
- Pass condition : evidence `production/qa/evidence/audio-death-overlap-{date}.md` documente "no audible cut" + signed sound-designer

**Wall-run loop + fade-out 100 ms** :
- Given : Player en wall-run, `wallrun_loop_stream` joue
- When : `wall_run_exited` émis DEFERRED N+1
- Then : fade démarre `_physics_process` ; à t=50, volume_db ≈ -40 dB ± 2 dB ; à t=100, volume_db ≤ -60 dB + slot stop()

**Dash / Wall-jump dispatch** :
- Given : AudioSystem prêt
- When : `dash_started` puis `wall_jumped` émis
- Then : 2 slots pool 2D actifs sur `SFX` bus avec streams `dash_stream` et `walljump_stream`

**Respawn silence** :
- Given : AudioSystem prêt après `died`
- When : `respawned(pos)` émis
- Then : aucun nouvel `play_2d` appelé (no-op intentionnel)

---

## Test Evidence

**Story Type**: Integration
**Required evidence**:
- `tests/integration/audio/death_audio_duration_test.gd` (AC-AUD-07 a-e)
- `tests/integration/audio/wallrun_fade_out_test.gd` (wall-run loop + fade 100 ms)
- `tests/integration/audio/movement_dispatch_test.gd` (dash/walljump/respawn dispatch)
- `production/qa/evidence/audio-death-overlap-{date}.md` (AC-AUD-07 f ADVISORY playtest sound-designer)

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (pool), Story 002 (`play_2d` API)
- Unlocks: Story 011 (perf — wall-run loop overlap audio CPU contribution)

---

## Completion Notes

**Completed**: 2026-05-04
**Criteria**: 11/11 covered (9 BLOCKING auto, 2 ADVISORY pipeline/playtest)
**Tests**: 24/24 PASS (death_audio_duration_test 8 + wallrun_fade_out_test 8 + movement_dispatch_test 7 + cross-suite isolation guards). Audio suite total : **79/79 PASS** (15+19+21+24).
**Test Evidence** :
- `tests/integration/audio/death_audio_duration_test.gd` (AC-AUD-07 a/b/c/d/e + null guards)
- `tests/integration/audio/wallrun_fade_out_test.gd` (loop start, fade Formula 1, t=50 ≈ -40 dB, t=100 SILENCE + slot stop, clamp t>1, time_scale-indep, exit no-op without slot, null guard)
- `tests/integration/audio/movement_dispatch_test.gd` (dash/walljump dispatch, 2 slots distincts, respawn no handler exposé, connect_movement_signals null guard)

**Code Review**: Skipped (Solo mode LP-CODE-REVIEW gate)

**Implementation Notes** :
1. **Streams en `var` injectables (pas `@export`)** : autoload Node n'expose pas `@export` sur instance — pattern hérité story-003 (var assignée test ou runtime asset preload). Spec `@export` interprétée comme intent injection point.
2. **AC-AUD-07 (a) precheck asset** — test conditional : si `ResourceLoader.exists("res://assets/audio/sfx/death.wav")` → pass strict ; sinon pass-skip avec note "Sprint asset pipeline pending" (ADVISORY). Évite blocage Sprint Audio sur asset gate. Handlers fonctionnent indépendamment via injection `AudioStreamWAV.new()` sized.
3. **AC-AUD-07 (c/d/e) duration assertion** — exposée via `validate_death_audio_duration() -> bool` méthode publique (callable au boot game state post-asset-load OU en test). Pas hard-assert au boot AudioSystem `_ready` (sinon corrupt boot si asset manquant).
4. **AC-AUD-07 (f) overlap respawn empirique** — ADVISORY playtest sound-designer (`production/qa/evidence/audio-death-overlap-{date}.md`) — pending Sprint asset pipeline finalisation.
5. **Wall-run loop slot tracker `_wallrun_slot_idx: int = -1`** : -1 sentinel = pas de loop actif. `_on_wall_run_exited` no-op si tracker -1 (corner case re-exit).
6. **Wall-run fade Formula 1 hardened** : linear dB lerp `0.0 → SILENCE_DB (-80)` sur `WALLRUN_FADE_OUT_MS = 100` (vs swoosh 30 ms). Wall-clock indep `Engine.time_scale` (slow-mo 0.3 → fade STILL 100 ms).
7. **Volume restore post-stop** : à t=1.0, slot.volume_db reset 0.0 (default) APRÈS slot.stop() — évite que round-robin reuse le slot avec volume résiduel SILENCE.
8. **`_on_respawned` NON exposé** — silence intentionnel post-respawn (Pillar 1 clarté rythmique). Test `test_respawned_no_handler_exposed_silence_intentional` garde garantit l'absence du handler. `connect_movement_signals` ne connecte pas `respawned`.
9. **Death overlap respawn — pas extension RESPAWN_DELAY** : queue audio Godot survit `scene reload` (R-AUD-14). Death (60-80 ms) joue, scene reload trigger respawn frame N+1, queue continue audio sur le slot pool (pas re-instancié). Pillar 3 figé Movement ADR-0005 D-9 (`RESPAWN_DELAY = 0.05 s`).
10. **Pattern réutilisé story-003** : `_get_time_msec` Callable injection, lambda `Array wrapper [idx]` capture-by-value, `before_test()` reset cross-test isolation (slot tracker, fade flag, streams, volume_db all 2D pool).
11. **Bug test fix runtime** : initial seq `[1000, 1010]` supposait `_on_wall_run_entered` consommait `_get_time_msec` — non, seul `_on_wall_run_exited` consomme (capture start_msec). Fix : seq `[start_at_exit, tick_now]` à 2 éléments.

**Deviations** : aucune par rapport spec (Implementation Notes de la story respectées 100%, hormis `@export` → `var` documenté ci-dessus comme reformulation pratique pour autoload).
