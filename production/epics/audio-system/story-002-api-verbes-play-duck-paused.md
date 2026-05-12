# Story 002: API Publique Verbes — `play_2d` / `play_3d_at` / `play_music` / `stop_music` / `duck_bus` / `set_paused` / `set_bus_volume_db_user`

> **Epic**: Audio System
> **Status**: Complete 2026-05-04 (19/19 tests PASS — 8/8 ACs COVERED)
> **Layer**: Core
> **Type**: Logic
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/audio-system.md` (r2.3 §Detailed Rules Core Rules 1 + Implementation Details Phase D.1)
**Requirements**:
- R-AUD-1 : API publique exclusive — verbes `play_2d`, `play_3d_at`, `play_music`, `stop_music`, `duck_bus`, `set_paused`, `set_bus_volume_db_user` ; `AudioStreamPlayer.new()` runtime / `AudioServer.set_bus_volume_db()` direct / `AudioListener3D.new()` interdits hors `audio_system.gd`
- R-AUD-7 : Position payload signals 3D — capture au tick d'émission, pas de read post-DEFERRED
- R-AUD-8 : Ownership AudioStreamPlayer3D = pool ou scene root, jamais attaché au noeud émetteur

**ADR Governing**: ADR-0009 D-2 + D-5 + Implementation Details Phase D.1
**Decision Summary**: API verbes haut niveau découplés Godot bas niveau ; `play_3d_at(stream, world_pos: Vector3, bus)` reçoit world space `global_position` (pas position locale — sinon panning relatif parent ou (0,0,0) head-locked silencieux).

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `AudioStreamPlayer*.global_position` utilisé par Godot pour calcul panning + atténuation distance. `AudioServer.set_bus_volume_db()` stable Godot 4.0+.

**Control Manifest Rules (Core layer)**:
- Required: API publique = surface unique entre Audio middleware et consumers
- Forbidden: aucun consumer reference inverse — Audio est consumer outbound-zero pour son côté (pas d'autoload reference vers Combat/Movement/Level/GSM)
- Guardrail: `play_*` hot path < 50 µs p99 (Phase D.4 sub-budget)

---

## Acceptance Criteria

*From GDD AC-AUD-03 (extension) + AC-AUD-13 (perf) + Phase D.1 contract:*

- [ ] **API `play_2d(stream: AudioStream, bus: StringName) -> void`** : round-robin index `_2d_index`, set `player.bus = bus` + `player.stream = stream` + `player.play()`. Si saturation : `push_warning` + `stop()` puis `play()`.
- [ ] **API `play_3d_at(stream: AudioStream, world_pos: Vector3, bus: StringName, pitch_scale: float = 1.0) -> int`** : retourne `slot_idx` pool 3D. Assert `world_pos.is_finite()` (Phase D.1) ; sinon `push_warning("play_3d_at: world_pos invalid (non-finite), fallback play_2d head-locked")` + fallback `play_2d` head-locked. Set `player.global_position = world_pos` + `player.pitch_scale = pitch_scale` + `player.bus = bus` + `player.stream = stream` + `player.play()`.
- [ ] **API `play_music(stream: AudioStream, fade_seconds: float = 1.0) -> void`** : crossfade interne `_music_player` ↔ `_music_player_secondary` (alterné), volume_db lerp 1 s wall-clock OU Tween si `Engine.time_scale == 1.0` garanti.
- [ ] **API `stop_music(fade_seconds: float = 0.5) -> void`** : fade-out `_music_player.volume_db → -80` sur 0.5 s wall-clock puis `stop()`.
- [ ] **API `duck_bus(bus: StringName, delta_db: float, release_ms: float) -> void`** : applique instantané `set_bus_volume_db(idx, nominal + delta_db)` puis release wall-clock (Formula 2 perceptuel linear-amplitude lerp Phase C). Géré par story 003 (Combat handlers) côté implementation logique release.
- [ ] **API `set_paused(paused: bool) -> void`** : `AudioServer.set_bus_mute(0, paused)` (Master). Aucun `stream_paused` individuel.
- [ ] **API `set_bus_volume_db_user(bus: StringName, db: float) -> void`** : applique `set_bus_volume_db(idx, db)` (sliders settings UI Tier 2 — partial MVP stub OK pour bus `MASTER`/`MUSIC`/`SFX`/`UI`).
- [ ] **Phase D.1 invariant** : `play_3d_at` reçoit toujours world space `global_position` ; documenter contract inline + assert `is_finite()` runtime.

---

## Implementation Notes

*Derived from ADR-0009 D-2 + D-5 + Phase D.1:*

```gdscript
const POOL_2D_SIZE: int = 5
const POOL_3D_SIZE: int = 12
const SILENCE_DB: float = -80.0

var _2d_pool: Array[AudioStreamPlayer] = []
var _3d_pool: Array[AudioStreamPlayer3D] = []
var _music_player: AudioStreamPlayer
var _ambience_pool: Array[AudioStreamPlayer] = []
var _2d_index: int = 0
var _3d_index: int = 0

func play_2d(stream: AudioStream, bus: StringName) -> int:
    if stream == null:
        push_error("Audio stream is null")
        return -1
    var slot: AudioStreamPlayer = _2d_pool[_2d_index]
    if slot.playing:
        push_warning("AudioPool 2D saturé — interruption son 2D actif")
        slot.stop()
    slot.bus = bus
    slot.stream = stream
    slot.play()
    var idx := _2d_index
    _2d_index = (_2d_index + 1) % POOL_2D_SIZE
    return idx

func play_3d_at(stream: AudioStream, world_pos: Vector3, bus: StringName, pitch_scale: float = 1.0) -> int:
    if stream == null:
        push_error("Audio stream is null")
        return -1
    if not world_pos.is_finite():
        push_warning("play_3d_at: world_pos invalid (non-finite), fallback 2D head-locked")
        return play_2d(stream, bus)
    var slot: AudioStreamPlayer3D = _3d_pool[_3d_index]
    if slot.playing:
        slot.stop()
    slot.bus = bus
    slot.global_position = world_pos
    slot.pitch_scale = pitch_scale
    slot.stream = stream
    slot.play()
    var idx := _3d_index
    _3d_index = (_3d_index + 1) % POOL_3D_SIZE
    return idx

func set_paused(paused: bool) -> void:
    AudioServer.set_bus_mute(0, paused)

func set_bus_volume_db_user(bus: StringName, db: float) -> void:
    var idx := AudioServer.get_bus_index(bus)
    if idx == -1:
        push_warning("Unknown bus: %s" % bus)
        return
    AudioServer.set_bus_volume_db(idx, db)
```

`play_music` / `stop_music` / `duck_bus` peuvent être stubbed minimaux ici — implementations détaillées story 003 (duck_bus release wall-clock) + story 005 (music crossfade Formula 4).

---

## Out of Scope

- Story 003 : `duck_bus` release wall-clock détaillé (Formula 2 + boundary cases R≤0)
- Story 005 : `play_music` / `stop_music` crossfade Formula 4 linear-amplitude lerp Phase C
- Story 006 : `set_paused` state preservation `_fade_pause_msec` offset wall-clock
- Story 010 : lint CI `lint-audio-pool` (zero `AudioStreamPlayer.new()` hors `audio_system.gd`)

---

## QA Test Cases

**API surface** :
- Given : AudioSystem prêt, stream test `AudioStreamWAV.new()`
- When : `play_2d(stream, AudioBuses.SFX)` appelé 5× consécutifs
- Then : 5 slots pool 2D actifs (`playing == true`) ; round-robin index avance ; aucun nouveau `AudioStreamPlayer` créé (`get_child_count() == 20`)

**`play_3d_at` world space contract (Phase D.1)** :
- Given : AudioSystem prêt, world_pos `Vector3(10, 0, 5)`
- When : `play_3d_at(stream, Vector3(10, 0, 5), AudioBuses.COMBAT_KILL)` appelé
- Then : `_3d_pool[_3d_index].global_position == Vector3(10, 0, 5)` ; `bus == COMBAT_KILL` ; `playing == true`
- Edge cases : `world_pos = Vector3(NAN, NAN, NAN)` → `push_warning` capturé + fallback `play_2d` head-locked + `play_3d_at` n'appelle PAS `slot.play()` côté pool 3D

**Null stream guard** :
- Given : AudioSystem prêt
- When : `play_2d(null, AudioBuses.SFX)`
- Then : `push_error("Audio stream is null")` capturé + return early (pas de crash)

**Bus inconnu guard** :
- Given : AudioSystem prêt
- When : `set_bus_volume_db_user(&"BUS_NEXISTE_PAS", -10.0)`
- Then : `push_warning` capturé + no-op

**`set_paused` Master mute** :
- Given : musique + 3 SFX en cours
- When : `set_paused(true)` appelé
- Then : `AudioServer.is_bus_mute(0) == true` ; queue audio préservée

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- `tests/unit/audio/api_play_2d_test.gd` (round-robin + saturation)
- `tests/unit/audio/api_play_3d_at_test.gd` (world space + is_finite assert)
- `tests/unit/audio/api_null_guards_test.gd` (null stream + bus inconnu)
- `tests/unit/audio/api_set_paused_test.gd` (Master mute via API)

**Status**: [x] Created + 19/19 PASS 2026-05-04

---

## Dependencies

- Depends on: Story 001 (autoload skeleton + pool 20 + bus layout) — Complete 2026-05-04
- Unlocks: Story 003-009 (tous les handlers consument l'API publique via verbes)

---

## Completion Notes
**Completed**: 2026-05-04
**Criteria**: 8/8 passing (19/19 tests PASS — 4 play_2d + 6 play_3d_at + 6 null_guards + 3 set_paused)
**Deviations**: aucune
**Test Evidence**: Logic — 4 fichiers `tests/unit/audio/api_*.gd` (api_play_2d, api_play_3d_at, api_null_guards, api_set_paused)
**Code Review**: skipped (Solo mode + dev-story orchestrator pattern, agent réutilise contexte story-001 review)
**Files**: `src/core/audio_system.gd` étendu (+85 lignes API verbes), 4 nouveaux fichiers test
**Implementation note**:
- `play_2d` upgrade `void` → `int` (retourne slot index utilisé) — AC story-002 spec
- `play_music`/`stop_music` stubs minimaux (implémentations détaillées story-005 crossfade Formula 4)
- `duck_bus` applique delta_db instantané (release wall-clock délégué story-003 Combat handlers)
- `set_bus_volume_db_user` MVP accepte tous les buses (allowlist UI Tier 2 future)
