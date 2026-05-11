# Epic: Audio System

> **Layer**: Core
> **GDD**: design/gdd/audio-system.md (Draft r2.3 — Phase A+B+C+D complete + design-review fresh APPROVED 8 BLOCKING fixes 2026-05-03)
> **Architecture Module**: Audio System (autoload `AudioSystem` + helper static `AudioBuses` — `src/core/audio_system.gd`)
> **Status**: Complete (12/12 stories shipped 2026-05-04)
> **Stories**: 12/12 créées + shippées 2026-05-04 (`story-001` … `story-012`)

## Overview

L'Audio System est l'autoload Godot middleware qui livre tous les sons du jeu : SFX combat (swoosh, clac, blood ambiance), SFX movement (dash, wall-run, jump, death), musique d'étage, ambiance positionnelle, UI clicks, secret collect différencié. Il expose une API publique exclusive (`play_2d`, `play_3d_at`, `play_music`, `stop_music`, `duck_bus`, `set_paused`, `set_bus_volume_db_user`) qui découple les producteurs (Combat / Movement / Level / GSM / Secret) de l'implémentation Godot bas niveau (`AudioStreamPlayer*`, `AudioServer`, `AudioListener3D`). Toutes les opérations passent par un pool pré-instancié de **20 nodes** (5×2D + 12×3D + 1×Music + 2×Ambience — zéro alloc runtime), tous les fades sensibles slow-mo sont wall-clock dans `_physics_process` (jamais Tween scaled par `Engine.time_scale`), et toutes les connexions consumer sont `CONNECT_DEFERRED` par défaut (aucune exemption SYNC MVP). Le système préserve la Fantasy staccato Combat (Couche 1 silence rythmique post-clac via sidechain compressor `MUSIC ← COMBAT_KILL`, Couche 2 swoosh proprioceptif head-locked, Couche 3 continuité musicale invisible, Couche 4 drone HLM en slow-mo via pitch-shift bus allowlist Rule 11 avec exclusion explicite slot clac via `_active_clac_players` tracker), garantit la latence audio déterministe ≤ 0.5 ms / frame (sub-budgets handler ≤ 100 µs / `play_3d_at` ≤ 50 µs Phase D.4), et différencie sémantiquement kill (`COMBAT_KILL` + sidechain armed) vs secret (`SFX` + pitch +5 semitones, ducking absent — Rule 17 r2.2 NB-CRD-6 Option A).

## Governing ADRs

| ADR | Decision Summary | Engine Risk |
|-----|-----------------|-------------|
| **ADR-0009: Audio System Architecture** (Accepted 2026-04-27 + r2 amendements) | 6 décisions D-1..D-6 + 8 VC : (D-1) bus hierarchy 7-bus immutables `MASTER/MUSIC/SFX[SWING_ACTIVE,COMBAT_KILL]/AMBIENCE/UI` UPPER_SNAKE_CASE + sidechain compressor `MUSIC ← COMBAT_KILL` (r2 amendement, threshold -24 dB / ratio 4:1 / attack 5 ms / release 200 ms) ; (D-2) pool pré-instancié 20 nodes (5+12+1+2 r2 sizing) jamais étendu runtime, round-robin saturation = `stop()`/`play()` interrupt + `push_warning` ; (D-3) wall-clock fades dans `_physics_process` exclusivement via `_get_time_msec: Callable` injection partagée Combat ADR-0006 D-4 (zéro Tween sur `volume_db` time-critical) + allowlist bus-level `pitch_scale_follows_time_scale` per bus (r2 amendement : `COMBAT_KILL=true`/`AMBIENCE=true`/autres `false` — préserve `MUSIC`/`SWING_ACTIVE`/`UI` invariants Couche 2/3) ; (D-4) `CONNECT_DEFERRED` par défaut sur tous les signals consumer, aucune exemption SYNC MVP ; (D-5) spatialisation 2D head-locked vs 3D positional figée par event-type (matrice §Visual/Audio Requirements) ; (D-6) `AudioListener3D` enfant explicite Camera3D per ADR-0002 chain (1 listener unique scene tree, no second instance — r2 reconciliation). 8 VC verifiable : VC-1..VC-8 (boot bus structure, pool size, wall-clock fade resolution, multi-kill counter, ducking release, lint anti-tween, no-alloc 1000 cycles, perf 5-swings stress). | LOW |
| ADR-0001: Physics Rate 60 Hz | Autorité simulation pour fades wall-clock dans `_physics_process` (60 Hz, thread principal garanti) | LOW |
| ADR-0002: Camera Scene Tree | Chain `... → CameraEffects → Camera3D → AudioListener3D` enfant explicite — Audio System ne doit JAMAIS instancier un second listener (D-6 amendement) | LOW |
| ADR-0005: Movement Signals Architecture | Audio consume `dash_started`, `dash_rejected` (futur), `wall_run_entered`, `wall_run_exited`, `wall_jumped`, `died`, `respawned` en `CONNECT_DEFERRED` (D-4 default) ; D-5 instanciation Node + `play()` = opérations lourdes ≥ 256 B alloc + ≥ 0.5 ms → DEFERRED obligatoire | LOW |
| ADR-0006: Combat Tick Model | Audio consume `swing_started`, `swing_ended`, `enemy_killed(enemy, position)`, `multi_kill(count)` (noop côté Audio — Rule 13 r2 logique multi-kill via rangs `enemy_killed`). D-3 capture `position: Vector3` au tick d'émission (Audio handler n'utilise jamais `enemy.global_position` post-réception — risque queue_free). D-4 `_get_time_msec` Callable injection pattern partagé Combat ↔ Audio (mocks `MockAudioHandler` réutilisables) | LOW |
| ADR-0007: Game State Manager | Audio consume `state_changed(new_state)` en `CONNECT_DEFERRED` pour mute/unmute Master bus sur `PAUSED`/`PLAYING`/`SCENE_TRANSITION` ; D-1 ordre autoload (Audio position TBD post-Sprint Audio, après InputManager / GSM / SaveLoad) ; D-4 `process_mode = ALWAYS = 3` Godot 4.6 erratum (audio handlers actifs même pendant pause) | LOW |
| ADR-0011: Level Scene Architecture | Audio consume `level_active(etage_id, player_start)` (Level r4 Option C) en `CONNECT_DEFERRED` + lookup synchrone `LevelSystem.get_etage_audio_streams(etage_id) -> Dictionary{music, ambient}` puis `play_music(streams.music)` + crossfade ambient (Formula 4 linear-amplitude lerp, Phase C hardened) ; consume aussi `level_unloading(etage_id)` pour fade-out music + ambient ; signal `room_entered` consommé optionnel MVP pour ambient layer swap intra-étage | LOW |

**Engine Risk : LOW** (pas de breaking change Godot 4.4-4.6 sur APIs `AudioStreamPlayer*`, `AudioServer.set_bus_volume_db()`, `AudioStreamPlayer.pitch_scale`, `AudioListener3D` — tous stables Godot 4.0+ per ADR-0009 Engine Compatibility + `docs/engine-reference/godot/modules/audio.md` r3 2026-05-03). 1 gotcha de nommage long-standing documenté (`attack_us` µs vs `release_ms` ms sur `AudioEffectCompressor` — pas un breaking change 4.x, présent depuis Godot 3.x ; engine-ref dump 2026-05-03 résolu Phase D.5). 3 verifications empiriques pré-Sprint Audio : (1) `pitch_scale` runtime mid-`play()` n'introduit pas de pop sonore (transition `1.0 → 0.7935 → 1.0` AC-AUD-15-b ADVISORY) ; (2) AudioListener3D auto-current via Camera3D actif Godot 4.6 default (AC-AUD-14 ADVISORY) ; (3) pool latency `play()` pré-instancié pas de hitch ≥ 1 frame.

## GDD Requirements

Audio System utilise un schéma `R-AUD-N` (Rules numérotées 1-17 dans GDD §Detailed Rules) comme stable IDs en attendant rotation `/architecture-review` post-Sprint 1. **Aucune entrée TR-aud-* dans `docs/architecture/tr-registry.yaml`** (commentaire registry r5 2026-04-27 explicite : *"TR-aud-* à créer post `/design-system audio-system`"* — la rotation TR sera exécutée lors de la prochaine `/architecture-review` qui scannera le GDD r2.3 finalisé).

| R-AUD | Requirement (résumé) | ADR Coverage |
|-------|---------------------|--------------|
| R-AUD-1 | API publique exclusive — `AudioStreamPlayer.new()` / `AudioServer.set_bus_volume_db()` direct interdits hors `audio_system.gd` (lint CI `lint-audio-pool`) | ADR-0009 D-2 ✅ |
| R-AUD-2 | Pool pré-alloué 20 nodes au boot (5×2D + 12×3D + 1×Music + 2×Ambience), jamais étendu runtime, round-robin index | ADR-0009 D-2 ✅ |
| R-AUD-3 | Bus hierarchy 7 buses figée UPPER_SNAKE_CASE — `MASTER/MUSIC/SFX[SWING_ACTIVE,COMBAT_KILL]/AMBIENCE/UI` via `default_bus_layout.tres` | ADR-0009 D-1 ✅ |
| R-AUD-4 | Wall-clock fades dans `_physics_process` exclusivement via `_get_time_msec` Callable — Tween interdit sur `volume_db` time-critical (lint CI `lint-audio-tween`) | ADR-0009 D-3 ✅ |
| R-AUD-5 | `CONNECT_DEFERRED` par défaut sur tous les signals consumer (lint CI `lint-audio-deferred`) | ADR-0009 D-4 ✅ |
| R-AUD-6 | Spatialisation 2D head-locked vs 3D positional figée par event-type (Section §Visual/Audio Requirements + ADR-0009 D-5) | ADR-0009 D-5 ✅ |
| R-AUD-7 | Position payload pour signals 3D — capture au tick d'émission, jamais `enemy.global_position` au moment de réception DEFERRED (queue_free risk) | ADR-0006 D-3 + ADR-0009 D-5 ✅ |
| R-AUD-8 | Ownership AudioStreamPlayer3D — pool ou scene root, jamais attaché au noeud émetteur (queue_free durant `play()` = pop / crash) | ADR-0009 D-2 + D-5 ✅ |
| R-AUD-9 | AudioListener3D enfant Camera3D ADR-0002 chain — Audio System n'instancie pas de second listener (1 listener unique scene tree) | ADR-0009 D-6 + ADR-0002 ✅ |
| R-AUD-10 | Pause/resume — silence total via `MASTER` bus mute (`AudioServer.set_bus_mute(0, true/false)`), aucun `stream_paused` individuel | ADR-0009 D-1 + ADR-0007 D-10 ✅ |
| R-AUD-11 | Pitch shift bus-level allowlist sous slow-mo (`COMBAT_KILL=true` queue blood UNIQUEMENT / `AMBIENCE=true` ; autres invariants) + exclusion explicite slot clac via `_active_clac_players` tracker | ADR-0009 D-3 amendement r2 ✅ |
| R-AUD-12 | Ducking event-driven via `AudioSystem.duck_bus(bus, delta_db, release_ms)` — instantané -6 dB + release 30 ms wall-clock expo (Formula 2 perceptuel linear-amplitude Phase C) | ADR-0009 D-3 ✅ |
| R-AUD-13 | Multi-kill clac avec pitch-shift +N semitones (`_kill_count_this_swing` owned Audio, reset `swing_started`/`swing_ended`) — rangs +0/+2/+4 cap, asset reuse `clac.wav` via `pitch_scale` natif | ADR-0009 D-3 amendement r2 ✅ |
| R-AUD-14 | Death feedback 60-80 ms wall-clock + overlap première frame respawn intentionnel (queue audio Godot survit scene reload) — `RESPAWN_DELAY = 0.05 s` figé Movement Pillar 3 | ADR-0009 D-3 + ADR-0005 D-9 ✅ |
| R-AUD-15 | Ambient loop par etage — `Ambience #1`/`Ambience #2` crossfade 1 s linear-amplitude (Formula 4 hardened Phase C anti-dip dB-domain) sur `level_active` + lookup `LevelSystem.get_etage_audio_streams` | ADR-0011 + ADR-0009 D-2 ✅ |
| R-AUD-16 | Sidechain compressor `MUSIC ← COMBAT_KILL` via `AudioEffectCompressor` (Rule 16 r2 + Formula 6) — résout Couche 1 vs Couche 3 contradiction Player Fantasy par mécanisme (pas verbal) | ADR-0009 D-1 amendement r2 ✅ |
| R-AUD-17 | Secret collect clac différencié — pitch +5 semitones bus `SFX` (PAS `COMBAT_KILL` — sidechain n'arme pas), positionnel 3D depuis `secret_node.global_position`, pas de ducking ni multi-kill counter (Rule 17 r2.2 NB-CRD-6 Option A creative-director adjudication) | ADR-0009 D-3 + D-5 ✅ |

**Coverage** : **17/17 R-AUD ✅** par ADR-0009 (Accepted + r2 amendements). Aucun gap, aucun untraced requirement. **0 BLOCKED** au niveau architecture.

## Definition of Done

This epic is complete when:

- All stories implementing R-AUD-1..17 are written, reviewed via `/code-review`, and closed via `/story-done`
- All **21 acceptance criteria** AC-AUD-01..21 sont vérifiés (15 BLOCKING Logic/Integration + 1 BLOCKING Performance + 2 BLOCKING boundary cases r2.3 (D≤0/R≤0 short-circuit) + 1 BLOCKING headless-testable pitch + 1 ADVISORY headless-conditional anti-pop waveform + 1 BLOCKING idempotent guard + 1 BLOCKING F-04 midpoint anti-regression)
- **Architecture invariants** verifiés :
  - **VC-1** `AudioServer.bus_count == 7`, ordre `MASTER/MUSIC/SFX/SWING_ACTIVE/COMBAT_KILL/AMBIENCE/UI`, parents corrects
  - **VC-2** `AudioSystem.get_child_count() == 20` (assertion structurale déterministe vs `Performance.OBJECT_COUNT` delta multi-autoload)
  - **VC-3** Swoosh fade-out résolu en `[25, 50] ms wall-clock` indépendant `Engine.time_scale` (AC-CMB-51 contract Combat ↔ Audio)
  - **VC-4** Multi-kill counter rangs `+0/+2/+4 cap` testé jusqu'à 4e kill (Rule 13 r2)
  - **VC-5** Ducking release 30 ms wall-clock expo perceptuel + boundary `R ≤ 0` short-circuit
  - **VC-6** Lint CI `lint-audio-tween` zero match `Tween.tween_property.*volume_db` (exception annotée `# lint-audio-tween-ok` autorisée pour ambient crossfade time_scale==1.0)
  - **VC-7** No-alloc 1000 cycles `play_2d` — `Performance.MEMORY_STATIC` delta ≤ +100 KB + `get_child_count() == 20` constant
  - **VC-8** Perf 5 swings stress + 1000 frames : `frame_time p99 ≤ 16.6 ms`, audio CPU `p99 ≤ 0.5 ms`, sub-budgets handler `< 100 µs` / `play_3d_at` `< 50 µs` (Phase D.4)
- **3 lint CI gates BLOCKING** activés et zero match :
  - `lint-audio-pool` — pas de `AudioStreamPlayer.new()` / `AudioStreamPlayer3D.new()` / `AudioListener3D.new()` hors `src/core/audio_system.gd`
  - `lint-audio-tween` — pas de `Tween.tween_property.*volume_db` hors exceptions annotées
  - `lint-audio-deferred` — tous les `connect()` dans handlers `src/gameplay/audio/` ou `src/core/audio_system.gd` `_on_*` méthodes incluent flag `CONNECT_DEFERRED`
- **Combat ↔ Audio contracts vérifiés** côté production AudioSystem :
  - AC-CMB-51 swoosh fade-out wall-clock 25-50 ms (AC-AUD-04)
  - AC-CMB-audio-01 multi-kill clac pitch-shift +0/+2/+4 cap (AC-AUD-05/17)
  - AC-CMB-audio-02 ducking `SWING_ACTIVE` -6 dB instantané + release 30 ms (AC-AUD-06)
  - **Note** : MockAudioHandler test fixture livré story-020 Combat (`tests/unit/combat/mock_audio_handler.gd` 171 lignes Implemented 2026-05-03 + Complete via `/story-done` 2026-05-03) sert de **référence canonique** pour la production AudioSystem — même contract D-4c, même séparation slot clac vs blood, même `_kill_sound_played_this_swing` flag, même log `ducking_events: Array[Dictionary]` avec `bus = SWING_ACTIVE`, `delta_db = -6.0`, `release_ms = 30.0`, `t_msec` wall-clock
- **Movement audio dispatch** verifiés : dash / wall-run loop / wall-run exit fade 100 ms / wall-jump / died (60-80 ms duration AC-AUD-07 + Pillar 3 overlap respawn) / respawned (silence intentionnel)
- **Level audio handler** verifié : `level_active` lookup `get_etage_audio_streams` synchrone + crossfade 1 s linear-amplitude (Formula 4 Phase C anti-dip) + `level_unloading` fade-out + fallback `push_warning` si mapping vide
- **Secret audio handler** verifié : `secret_collected` → `play_3d_at(clac_stream, secret_node.global_position, AudioBuses.SFX)` pitch +5 semitones, pas de ducking, pas d'incrément multi-kill counter, fallback 2D si position invalide (AC-AUD-18/19)
- **Sidechain compressor verification** : peak meter post-effects via `AudioServer.get_bus_peak_volume_left_db(MUSIC_idx, 0)` ≈ -6 dB ducked à t≈5-30 ms post-clac, release exponentielle ~200 ms vers -3 dB nominal, `music_player.playing == true` constant pendant ducking (AC-AUD-16) + idempotent boot guard `get_bus_effect_count(MUSIC_idx) == 1` (AC-AUD-20 Phase D.2)
- **Pause/resume** verifié : Master mute instantané DEFERRED N+1 + restoration état pré-pause (`_swoosh_fade_active` / `_ducking_release_active` + `_fade_pause_msec` offset wall-clock) — fade en cours reprend où il était (AC-AUD-08/09)
- All Logic and Integration stories have passing test files in `tests/unit/audio/` and `tests/integration/audio/`
- All Performance stories have passing benchmark evidence in `production/qa/evidence/audio-perf-{date}.md` + `tests/perf/audio_*`
- All Visual/Feel ADVISORY stories (AC-AUD-15-b anti-pop waveform, AC-AUD-14 panning panning empirique) have evidence docs in `production/qa/evidence/audio-{date}.md` with sound-designer + godot-specialist sign-off
- **Bidirectional dependencies fixed** dans GDDs amont :
  - `game-state-manager.md` : Audio System ajouté table `Interactions with Other Systems` aval (mute/unmute Master) — verifier post-`/design-system game-state-manager`
  - `camera-system.md` : Audio System ajouté Cross-References (Camera3D actif = AudioListener3D, ADR-0002 chain)
  - `level-system.md` : ✅ déjà résolu r4 Option C (2026-04-27)
  - `player-combat-system.md` : ✅ déjà documenté §Audio Requirements (APPROVED r6)
  - `player-movement-system.md` : ✅ déjà documenté §Visual/Audio Requirements
  - `secret-system.md` : Audio System ajouté Dependencies + Interactions table aval (consume `secret_collected`) — verifier post-`/design-system secret-system`

## Cluster décomposition prévisionnelle (~12 stories)

`/create-stories audio-system` produira ~12 stories cluster :

| # | Cluster | Stories prévues | Type | ACs couvertes |
|---|---------|----------------|------|---------------|
| C1 | Architecture / Boot | autoload `AudioSystem` skeleton + `default_bus_layout.tres` + pool 20 nodes + sidechain compressor `MUSIC ← COMBAT_KILL` Phase D.2 idempotent guard | Logic | AC-AUD-01/02/03/20 |
| C2 | API publique verbes | `play_2d` / `play_3d_at` (world space global_position + `is_finite` assert Phase D.1) / `play_music` / `stop_music` / `duck_bus` / `set_paused` / `set_bus_volume_db_user` (Tier 2 Save/Load — partial MVP stub) | Logic | (architecturalement gated par C1) |
| C3 | Combat audio handlers | `_on_swing_started` (reset counter + swoosh) / `_on_swing_ended` (fade-out swoosh wall-clock 30 ms Formula 1) / `_on_enemy_killed` (rangs multi-kill +0/+2/+4 cap + clac + blood delay 50 ms slot tracker `_active_clac_players` + ducking `SWING_ACTIVE` -6 dB Formula 2) / multi-kill counter reset | Integration | AC-AUD-04/05/06/17 + boundary cases D≤0 / R≤0 |
| C4 | Movement audio handlers | `_on_dash_started` / `_on_wall_run_entered` (loop) / `_on_wall_run_exited` (fade-out 100 ms wall-clock) / `_on_wall_jumped` / `_on_died` (60-80 ms `death.wav` ResourceLoader precheck + overlap respawn frame intentionnel) / `_on_respawned` (silence intentionnel) | Integration | AC-AUD-07 + Pillar 3 |
| C5 | Level audio handler | `_on_level_active` lookup synchrone `LevelSystem.get_etage_audio_streams(etage_id)` + `play_music` fade-in 1 s + crossfade ambient `Ambience #1`↔`#2` 1 s linear-amplitude lerp Formula 4 Phase C / `_on_level_unloading` fade-out 0.5 s / `_on_room_entered` ambient layer swap (optionnel MVP) / fallback `push_warning` si mapping vide | Integration | AC-AUD-21 (F-04 midpoint anti-regression) |
| C6 | GSM pause/resume | `_on_state_changed` Master mute/unmute + state preservation `_fade_pause_msec` offset wall-clock pour fades en cours | Logic | AC-AUD-08/09 |
| C7 | Slow-mo pitch shift bus allowlist | détection `Engine.time_scale != 1.0` + iteration pool actifs + `pitch_scale = 2.0 ** (semitones / 12.0)` Formula 5 sur bus allowlisted (`COMBAT_KILL` queue blood + `AMBIENCE` room tone) — exclusion explicite slot clac via `_active_clac_players` Dictionary tracker (Phase D.3 erase callback `finished` CONNECT_ONE_SHOT) — pitch appliqué AVANT `play()` côté handler dispatch (zero latency 1 tick) | Integration | AC-AUD-15-a BLOCKING + AC-AUD-15-b ADVISORY headless-conditional |
| C8 | Secret audio handler | `_on_secret_collected` → `play_3d_at(clac_stream, secret_node.global_position, AudioBuses.SFX, pitch_scale=SECRET_PITCH_SCALE=2.0**(5/12))` — invariant slow-mo (bus `SFX` PAS dans pitch allowlist Rule 11) — fallback 2D si position invalide | Logic | AC-AUD-18/19 |
| C9 | Anti-patterns lint static | 3 grep gates BLOCKING CI : `lint-audio-pool` (no `AudioStreamPlayer.new()` hors audio_system.gd) + `lint-audio-tween` (no `Tween.tween_property.*volume_db` sauf `# lint-audio-tween-ok`) + `lint-audio-deferred` (all `connect()` include `CONNECT_DEFERRED` flag) | Config/Data | AC-AUD-10/11/12 |
| C10 | AudioListener3D verification ADR-0002 | empirique panning + atténuation distance + `find_children("*", "AudioListener3D", true).size() == 1` (1 listener unique scene tree) — sign-off sound-designer + godot-specialist | Visual/Feel ADVISORY | AC-AUD-14 |
| C11 | Performance budget | `tests/perf/audio_5_swings_stress_test.gd` — 5 swings overlappés simultanés × 1000 frames : `frame_time p99 ≤ 16.6 ms` + audio CPU `p99 ≤ 0.5 ms` + `_on_enemy_killed` handler isolé `p99 < 100 µs` + `play_3d_at` isolé `p99 < 50 µs` (Phase D.4 sub-budgets) + `MEMORY_STATIC` delta ≤ +100 KB | Performance | AC-AUD-13 |
| C12 | Sidechain compressor MUSIC verification | peak meter post-effects `AudioServer.get_bus_peak_volume_left_db(MUSIC_idx, 0)` ≈ -6 dB ducked + release exponentielle ~200 ms + reset multi-kill + continuité music — headless fallback ADVISORY si CI dummy driver ne supporte pas peak meter post-effects | Integration | AC-AUD-16 |

**Sprint Audio prereq** (boot dependencies Audio System) :

- ✅ ADR-0009 Audio System Architecture **Accepted** 2026-04-27 (+ r2 amendements appliqués)
- ✅ Engine reference `docs/engine-reference/godot/modules/audio.md` r3 + section `AudioEffectCompressor (Sidechain Ducking)` complète **2026-05-03** (Phase D.5 RESOLVED — gotcha `attack_us` µs vs `release_ms` ms documenté)
- ✅ Combat MockAudioHandler test fixture **Complete** 2026-05-03 (`tests/unit/combat/mock_audio_handler.gd` 171 lignes — D-4c contract opérationnel, sert de référence canonique production AudioSystem)
- ✅ Combat AC-CMB-51 / AC-CMB-audio-01 / AC-CMB-audio-02 **vérifiés côté Combat 11/11 PASS** 2026-05-03 (story-020 swoosh_fade_wall_clock_test.gd + audio_multi_kill_ducking_test.gd)
- ✅ Level System r4 Option C — `LevelSystem.get_etage_audio_streams(etage_id)` lookup API + `ETAGE_AUDIO_MAPPING` Tuning Knob (Level epic 22 stories Ready)
- ⏳ **Asset pipeline** : assets `swoosh.wav` / `clac.wav` / `blood.wav` / `dash.wav` / `wallrun_loop.wav` / `walljump.wav` / `death.wav` (60-80 ms validé) / `room_tone_chrome_zen.wav` (sub-bass synthwave 40-80 Hz) / `music_etage_NN.ogg` à produire pré-Sprint Audio par sound-designer (`/asset-spec system:audio-system` post art-bible). Story C1 implémentation peut démarrer sans assets via stub streams (`AudioStreamWAV.new()` test fixtures) ; assets réels intégrés en parallèle Sprint Audio.

## Solo Mode Notes

- **PR-EPIC skipped** (review mode `solo` — `production/review-mode.txt`)
- Aucune entrée TR-aud-* dans `tr-registry.yaml` au moment de la création epic — **R-AUD-1..17** servent de stable IDs jusqu'à rotation `/architecture-review` post-Sprint 1 (pattern précédent : Combat / Shop / Upgrade / Credit / Menu / Save/Load epics)
- Engine Risk **LOW** confirmé par ADR-0009 Engine Compatibility table — pas de breaking change Godot 4.4-4.6 sur APIs audio (cross-référencé `docs/engine-reference/godot/modules/audio.md` r3 + `breaking-changes.md` + `deprecated-apis.md`)
- 3 verifications empiriques pré-Sprint Audio déférées (AC-AUD-14 listener, AC-AUD-15-b waveform pop, pool latency hitch) — pattern précédent ADR-0006 Gaps 2/7/8 + ADR-0011 5 VC-LVL (verifications Sprint-time, pas blocker epic)

## Next Step

12/12 stories créées 2026-05-04 — fichiers `story-001-autoload-skeleton-bus-layout-pool-sidechain.md` … `story-012-sidechain-music-peak-meter-verification-headless-fallback.md`. Démarrage Sprint Audio :
1. `/story-readiness story-001` puis `/dev-story story-001` (autoload + bus layout + pool + sidechain idempotent — débloque toutes les autres)
2. Story-002 API verbes (architecturalement gated par story-001)
3. Stories 003-008 handlers consumer (parallélisables selon disponibilité Combat/Movement/Level/GSM/Secret signaux production)
4. Stories 009 (lints CI) + 010 (listener verification) + 011 (perf budget) + 012 (sidechain peak meter) — close-out epic

---

**Status** : Ready (Created 2026-05-04, ADR-0009 Accepted, GDD r2.3 APPROVED, MockAudioHandler référence canonique, engine-ref Phase D.5 RESOLVED, 12 stories décomposées).
