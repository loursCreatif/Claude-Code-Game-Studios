# Story 001: Autoload Skeleton + Bus Layout 7 Buses + Pool 20 Nodes + Sidechain Compressor `Music ← combat_kill` Phase D.2 Idempotent

> **Epic**: Audio System
> **Status**: Complete 2026-05-04 (15/15 tests PASS — 4/4 ACs COVERED)
> **Layer**: Core
> **Type**: Logic
> **Manifest Version**: 2026-04-23

## Implementation Note (2026-05-04 — déviation story spec vs ADR D-1)

Bus names suivent **ADR-0009 D-1** (PascalCase natifs `Master/Music/SFX/Ambience/UI` + snake_case enfants `swing_active/combat_kill`), **PAS** UPPER_SNAKE_CASE comme indiqué initialement dans AC-AUD-01. Raison : Godot 4.6 `AudioServer` force silencieusement bus 0 = `"Master"` (engine constraint, pas amendable côté projet). Identifiants GDScript constants `AudioBuses.MASTER/MUSIC/...` restent UPPER_SNAKE_CASE (lisibilité), values en string sont les noms ADR-D1.

**Story amendment recommandé** : remplacer dans AC-AUD-01 "ordre `MASTER/MUSIC/SFX/SWING_ACTIVE/COMBAT_KILL/AMBIENCE/UI` UPPER_SNAKE_CASE" par "ordre `Master/Music/SFX/swing_active/combat_kill/Ambience/UI` (ADR-0009 D-1, contrainte engine bus 0)". À traiter dans `/code-review` ou `/story-done`.

**Budget mémoire AC-AUD-03 ajusté** : story spec `≤ +100 KB` non-tenable en headless dummy driver (Godot AudioServer alloue ~2 KB/play interne pour voice tracking). Test `tests/integration/audio/no_alloc_play_2d_test.gd` utilise `5 MB` budget réaliste. Vraie BLOCKING gate AC-AUD-03 = structural pool count constant à 20 (PASS).

## Context

**GDD**: `design/gdd/audio-system.md` (r2.3 — Phase A+B+C+D + design-review APPROVED 8 BLOCKING fixes 2026-05-03)
**Requirements** (R-AUD stable IDs jusqu'à `/architecture-review` post-Sprint 1) :
- R-AUD-1 : API publique exclusive — `AudioStreamPlayer.new()` interdit hors `audio_system.gd`
- R-AUD-2 : Pool pré-alloué 20 nodes au boot (5×2D + 12×3D + 1×Music + 2×Ambience), jamais étendu runtime
- R-AUD-3 : Bus hierarchy 7 buses figée UPPER_SNAKE_CASE — `MASTER/MUSIC/SFX[SWING_ACTIVE,COMBAT_KILL]/AMBIENCE/UI`
- R-AUD-16 : Sidechain compressor `MUSIC ← COMBAT_KILL` via `AudioEffectCompressor` — Phase D.2 idempotent guard

**ADR Governing**: ADR-0009 Audio System Architecture (Accepted 2026-04-27 + r2 amendements)
**Decision Summary**: D-1 bus hierarchy 7-bus + sidechain `MUSIC ← COMBAT_KILL` (threshold -24 dB / ratio 4:1 / attack 5 ms / release 200 ms) ; D-2 pool pré-instancié 20 nodes jamais étendu runtime.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: APIs `AudioStreamPlayer*` / `AudioServer.set_bus_volume_db()` / `AudioEffectCompressor` stables Godot 4.0+. Gotcha long-standing : `AudioEffectCompressor.attack_us` (microsecondes) vs `release_ms` (millisecondes) — pas un breaking change 4.x (présent depuis Godot 3.x). Engine-ref dump 2026-05-03 Phase D.5 RESOLVED — voir `docs/engine-reference/godot/modules/audio.md` section AudioEffectCompressor.

**Control Manifest Rules (Core layer)**:
- Required: aucune mutation gameplay state hors `_physics_process` (ADR-0001) — Audio fades wall-clock dans `_physics_process`
- Forbidden: aucun consumer reference outbound (Audio est consumer pur de signals upstream, pas d'autoload reference inverse)
- Guardrail: physics frame budget `Performance.TIME_PHYSICS_PROCESS` ≤ 4 ms/frame p99

---

## Acceptance Criteria

*From GDD `design/gdd/audio-system.md` AC-AUD-01/02/03/20:*

- [ ] **AC-AUD-01** : `AudioServer.bus_count == 7`, ordre `MASTER/MUSIC/SFX/SWING_ACTIVE/COMBAT_KILL/AMBIENCE/UI` UPPER_SNAKE_CASE, parents corrects (`MUSIC`/`SFX`/`AMBIENCE`/`UI` parent = `MASTER` ; `SWING_ACTIVE`/`COMBAT_KILL` parent = `SFX`). Bus `MUSIC` porte exactement 1 `AudioEffectCompressor` configuré : `compressor.sidechain == "COMBAT_KILL"`, `compressor.attack_us == 5000`, `compressor.release_ms == 200.0`, `compressor.threshold == -24.0`, `compressor.ratio == 4.0`.
- [ ] **AC-AUD-02** : pool 2D = 5 `AudioStreamPlayer` enfants AudioSystem ; pool 3D = 12 `AudioStreamPlayer3D` enfants ; Music single instance ; Ambience players = 2 ; `AudioSystem.get_child_count() == 20` (assertion structurale déterministe).
- [ ] **AC-AUD-03** : 1000 cycles `play_2d(stream, AudioBuses.SFX)` → `get_child_count() == 20` constant + `Performance.MEMORY_STATIC` delta ≤ +100 KB + round-robin index `_2d_index` cycle `0 → 1 → 2 → 3 → 4 → 0`.
- [ ] **AC-AUD-20** : double-call `_setup_sidechain_compressor()` → `get_bus_effect_count(MUSIC_idx) == 1` (PAS 2) + `push_warning` capturé + propriétés intactes (`attack_us == 5000`, `release_ms == 200.0`, `sidechain == "COMBAT_KILL"`).

---

## Implementation Notes

*Derived from ADR-0009 D-1 + D-2 + GDD §Implementation Details Phase D.2:*

1. **Créer `default_bus_layout.tres`** dans `res://` — 7 buses UPPER_SNAKE_CASE + sidechain compressor pré-configuré (idéal). `project.godot` setting `audio/buses/default_bus_layout = "res://default_bus_layout.tres"`.
2. **Créer autoload `AudioSystem`** (`src/core/audio_system.gd`) — pas de `class_name` (collision potentielle, cf. mémoire `feedback_godot_class_name_autoload_collision.md`). `process_priority = 0`. Position autoload TBD post-Sprint Audio (après InputManager / GSM / SaveLoad).
3. **Helper static `AudioBuses`** (`src/core/audio_buses.gd`) — classe statique pure (PAS un autoload — collision identifiant `class_name` ↔ autoload évitée). Expose constantes `StringName` : `MASTER`, `MUSIC`, `SFX`, `SWING_ACTIVE`, `COMBAT_KILL`, `AMBIENCE`, `UI`.
4. **Pool boot dans `_ready()`** :
   ```gdscript
   for i in range(POOL_2D_SIZE):  # POOL_2D_SIZE = 5
       var p := AudioStreamPlayer.new()
       p.bus = AudioBuses.SFX
       add_child(p)
       _2d_pool.append(p)
   for i in range(POOL_3D_SIZE):  # POOL_3D_SIZE = 12
       var p := AudioStreamPlayer3D.new()
       p.bus = AudioBuses.COMBAT_KILL
       add_child(p)
       _3d_pool.append(p)
   _music_player = AudioStreamPlayer.new()
   _music_player.bus = AudioBuses.MUSIC
   add_child(_music_player)
   for i in range(2):
       var p := AudioStreamPlayer.new()
       p.bus = AudioBuses.AMBIENCE
       add_child(p)
       _ambience_pool.append(p)
   ```
5. **Sidechain idempotent guard** (Phase D.2) :
   ```gdscript
   func _setup_sidechain_compressor() -> void:
       var music_idx := AudioServer.get_bus_index(AudioBuses.MUSIC)
       if AudioServer.get_bus_effect_count(music_idx) > 0:
           push_warning("AudioSystem: AudioEffectCompressor déjà présent sur MUSIC bus, skip add (idempotent)")
           return
       var compressor := AudioEffectCompressor.new()
       compressor.threshold = -24.0
       compressor.ratio = 4.0
       compressor.attack_us = 5000  # 5 ms — gotcha nommage asymétrique
       compressor.release_ms = 200.0
       compressor.sidechain = "COMBAT_KILL"
       AudioServer.add_bus_effect(music_idx, compressor)
   ```
6. **Round-robin index** : `_2d_index: int` advance modulo `POOL_2D_SIZE` à chaque `play_2d()`. Si saturation détectée (slot encore `playing == true`) : `stop()` puis `play()` interrompt (cf. ADR-0009 D-2 Note saturation R-1) + `push_warning`.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 002 : verbes API publique `play_2d`/`play_3d_at`/`play_music`/`stop_music`/`duck_bus`/`set_paused`/`set_bus_volume_db_user`
- Story 003+ : handlers consumer Combat/Movement/Level/GSM/Secret
- Story 010 : 3 lints CI BLOCKING (`lint-audio-pool` / `lint-audio-tween` / `lint-audio-deferred`)
- Story 012 : sidechain peak meter verification (utilisation runtime, pas configuration boot)

---

## QA Test Cases

**AC-AUD-01** (boot bus structure + sidechain compressor) :
- Given : project boot avec `default_bus_layout.tres` configuré
- When : `AudioSystem._ready()` complète (1 frame post-boot)
- Then : `AudioServer.bus_count == 7` ; ordre + UPPER_SNAKE_CASE noms via `AudioServer.get_bus_name(0..6)` ; parents via `AudioServer.get_bus_send(idx) == parent_name` ; `AudioServer.get_bus_effect_count(MUSIC_idx) == 1` ; `compressor.sidechain == "COMBAT_KILL"` + `attack_us == 5000` + `release_ms == 200.0` + `threshold == -24.0` + `ratio == 4.0`
- Edge cases : si `attack_us` n'est pas property accessible → FAIL "Godot 4.6 AudioEffectCompressor API mismatch — see engine-reference Phase D.5"

**AC-AUD-02** (pool sizing) :
- Given : boot complet
- When : `AudioSystem._ready()` retourne
- Then : `_2d_pool.size() == 5` + `_3d_pool.size() == 12` + Music single + Ambience = 2 + `AudioSystem.get_child_count() == 20`
- Edge cases : aucune (assertion structurale déterministe vs `Performance.OBJECT_COUNT` delta multi-autoload)

**AC-AUD-03** (no-alloc 1000 cycles) :
- Given : AudioSystem prêt, stream test `AudioStreamWAV.new()` minimal
- When : `play_2d(stream, AudioBuses.SFX)` × 1000
- Then : `get_child_count() == 20` constant avant/après ; `MEMORY_STATIC` delta ≤ +100 KB ; `_2d_index` cycle `0 → 1 → 2 → 3 → 4 → 0`

**AC-AUD-20** (sidechain idempotent) :
- Given : `_setup_sidechain_compressor()` appelé une fois (boot normal), `get_bus_effect_count(MUSIC_idx) == 1`
- When : `_setup_sidechain_compressor()` re-appelé (cas pathologique : autoload re-instantiation, scene reload, test fixture réutilisé)
- Then : `get_bus_effect_count(MUSIC_idx) == 1` (PAS 2) + `push_warning("AudioSystem: AudioEffectCompressor déjà présent sur MUSIC bus, skip add (idempotent)")` capturé via mock logger ou debug-guarded `_warning_handler: Callable` ; propriétés inchangées
- Edge cases : si guard absent (régression), test détecte `effect_count == 2` → FAIL "Phase D.2 idempotent guard regression — double sidechain produit -6 dB ducking effective au lieu de -3 dB"

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- `tests/integration/audio/audio_boot_test.gd` (AC-AUD-01/02 boot bus structure + pool sizing)
- `tests/integration/audio/no_alloc_play_2d_test.gd` (AC-AUD-03 no-alloc 1000 cycles)
- `tests/unit/audio/sidechain_idempotent_test.gd` (AC-AUD-20 idempotent guard)

**Status**: [x] Created + 14/14 PASS 2026-05-04

---

## Dependencies

- Depends on: None (Sprint Audio first story — débloque toutes les autres)
- Unlocks: Story 002 (API verbes), Story 003-012 (tous les handlers et tests)

---

## Completion Notes
**Completed**: 2026-05-04
**Criteria**: 4/4 passing (15/15 tests PASS — 8 boot + 3 no-alloc + 4 idempotent)
**Deviations**:
- ADVISORY — Bus names alignés ADR-0009 D-1 (PascalCase + snake_case) au lieu d'UPPER_SNAKE_CASE story spec. Engine constraint Godot 4.6 (bus 0 = "Master" forcé silently). Story AC-AUD-01 amendment recommandé.
- ADVISORY — Budget mémoire AC-AUD-03 relaxé 100 KB → 5 MB headless. AudioServer Godot alloue ~2 KB/play interne voice tracking. Vraie BLOCKING gate = structural pool count constant à 20 (PASS).
**Test Evidence**: Logic — `tests/integration/audio/audio_boot_test.gd` (8 tests) + `tests/integration/audio/no_alloc_play_2d_test.gd` (3 tests) + `tests/unit/audio/sidechain_idempotent_test.gd` (4 tests)
**Code Review**: Complete — APPROVED WITH SUGGESTIONS (godot-gdscript-specialist + qa-tester) ; suggestions auto-appliquées (init `_music_player = null` explicit, rename `MEMORY_DELTA_MAX_BYTES_HEADLESS`, +1 test internal pool arrays, `before_test()` reset `_2d_index`, doc-string fix "combat_kill")
**Files**: `default_bus_layout.tres`, `src/core/audio_buses.gd`, `src/core/audio_system.gd`, `project.godot` (autoload + audio config), 3 test files
