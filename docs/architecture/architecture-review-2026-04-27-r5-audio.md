# Architecture Review Report — ADR-0009 Audio Promotion

Date : 2026-04-27
Engine : Godot 4.6
Mode : `/architecture-review` fresh session **focused on ADR-0009** (promotion Proposed → Accepted)
ADRs Reviewed : ADR-0009 (subject) + cross-check vs ADR-0001/0002/0003/0005/0006/0007/0008/0011 (all Accepted)
GDDs Cross-checked : `player-combat-system.md`, `player-movement-system.md`, `camera-system.md`, `level-system.md`, `game-state-manager.md`, `game-concept.md`

---

## Scope

Cette review est **focalisée** (vs `full`) — objectif unique : valider la promotion d'ADR-0009 Audio System Architecture de `Proposed` à `Accepted` afin de débloquer :
- Audio System GDD (`/design-system audio-system`)
- Story-020 Combat (BLOCKED sur swoosh fade-out + multi-kill clac + ducking)
- Audio epic + cluster Sprint Audio post-MVP

Pas de re-traversal complet de l'architecture (déjà PASS r4 globalement post-ADR-0008).

## Phase 1 — Inputs Loaded

- ADR-0009 (full read)
- `docs/engine-reference/godot/modules/audio.md` (référence engine pinned 2026-02-12)
- `docs/architecture/tr-registry.yaml` v2 r4 (45 TRs Level + 17 TRs Combat + autres)
- ADR-0002 §AudioListener3D chain (cross-ref D-6)
- ADR-0006 D-4c/D-4d/D-5 (MockAudioHandler/MockAudioBus + `_get_time_msec` injection)
- ADR-0005 D-5 (CONNECT_DEFERRED heavy consumers)
- `production/session-state/active.md` (état post story-003 + Combat 22 stories)
- `docs/CLAUDE.md` (standards ADR — Status lifecycle Proposed → Accepted obligatoire)

## Phase 2 — Technical Requirements Coverage

ADR-0009 adresse les requirements suivants :

| GDD | Requirement | Couvert par |
|---|---|---|
| Combat §Audio Requirements + Mix hierarchy | 4 ducking rules + AC-CMB-51 wall-clock + AC-CMB-audio-01/02 | D-1 (bus `swing_active` + `combat_kill`) + D-3 (wall-clock fade) + D-4 (DEFERRED) + D-5 (spatialisation 2D/3D) |
| Combat AC-CMB-audio-01 (multi-kill dedup) | flag `_kill_sound_played_this_swing` | D-2 (pool dedup intra-swing) + D-4 |
| Combat AC-CMB-audio-02 (ducking ordering) | bus dédié + release 30 ms wall-clock | D-1 + D-3 |
| Movement signals (dash/wall-run/jump/died/respawned) | DEFERRED + 2D head-locked proprioceptif | D-4 + D-5 |
| Camera AudioListener3D | enfant Camera3D auto-current single-listener | D-6 (no dedicated listener) |
| Level music/ambience swap | par etage load_etage / unload_current | D-1 (bus Music/Ambience) + D-2 (1× Music + 2× Ambience pool) |
| GSM mute/restore on pause/resume | API `set_paused(bool)` | Key Interface `set_paused(bool)` |
| Game-concept Pillar 1 FLOW | pas de hitching audio en slow-mo | D-3 (wall-clock fades) + D-4 (DEFERRED) + D-2 (pre-alloc pool) |

**TR-lvl-042** (material tagging `surface_material` → footstep SFX routing) : ADR-0009 fournit l'**infrastructure bus + spatialisation** mais le mapping material → stream reste **Audio GDD scope** (TR-aud-* à créer post `/design-system`). `covered_by` mis à jour avec ADR-0009 partial + note.

## Phase 4 — Cross-ADR Conflict Detection

| Pair | Verdict | Détails |
|---|---|---|
| ADR-0009 D-6 ↔ ADR-0002 §REQ-5 | ✅ CONSISTENT | Même conclusion (Camera3D actif = listener auto-current). ADR-0009 explicite "no dedicated listener" → confirme la chain ADR-0002 sans la dupliquer. |
| ADR-0009 D-3 ↔ ADR-0006 D-5 | ✅ CONSISTENT (réutilise) | `_get_time_msec: Callable = Time.get_ticks_msec` même pattern, partagé Combat ↔ Audio. Tests CI déterministes communs (mocks réutilisables). |
| ADR-0009 D-4 ↔ ADR-0005 D-5 | ✅ CONSISTENT | DEFERRED par défaut pour heavy consumers. ADR-0009 explicite "aucune exemption SYNC pour Audio MVP" — verrouille le contract Combat GDD r5 BLOCK-r5-B fix. |
| ADR-0009 D-2 (mocks) ↔ ADR-0006 D-4c/D-4d | ✅ CONSISTENT | ADR-0006 fige déjà MockAudioHandler + MockAudioBus contracts. ADR-0009 référence sans redéfinir — single source of truth. |
| ADR-0009 D-3 (wall-clock) ↔ ADR-0001 (physics rate authority) | ✅ CONSISTENT | Fades dans `_physics_process` (ADR-0001 autorité simulation), pas `_process` ni `Tween` scaled. Forbidden pattern lint CI documenté. |
| ADR-0009 ↔ ADR-0011 (Level scene) | ✅ CONSISTENT | Music/Ambience swap par etage cohérent avec Level lifecycle ADR-0011 D-4/D-5 (level_active → music swap, level_unloading → ambience fade). |

**Verdict Phase 4 : 0 cross-ADR conflict détecté.**

## ADR Dependency Order

ADR-0009 dépend de : ADR-0001, ADR-0002, ADR-0005, ADR-0006, ADR-0007, ADR-0011. **Tous Accepted**. Pas de cycle. Foundation/Core upstream complète.

## Phase 5 — Engine Compatibility Audit

| Check | Verdict |
|---|---|
| Engine version cohérence | ✅ Godot 4.6 unanime |
| Post-cutoff APIs used | ✅ None (audio APIs stables 4.0+) |
| Deprecated APIs | ✅ 0 référence (cross-check `deprecated-apis.md`) |
| Breaking changes 4.4-4.6 | ✅ 0 (audio.md "No audio-specific breaking changes" en 4.4/4.5/4.6) |
| Engine Compatibility section présente | ✅ ADR-0009 §l.9-18 conforme template |

**Verifications Required différées Sprint Audio** (pattern précédent ADR-0006/ADR-0011) :
1. R-2 — `AudioListener3D = Camera3D actif` comportement Godot 4.6 (edge case SubViewport)
2. R-3 — `AudioStreamPlayer.pitch_scale` non-affecté par `Engine.time_scale`
3. Pool latency — `play()` sur pool pré-instancié sans hitch ≥ 1 frame

### Engine Specialist Findings (godot-specialist consultation)

**VERDICT : APPROVE WITH SUGGESTIONS** (4 LOW findings, 0 blocker — tous appliqués) :

| Finding | Sévérité | Application |
|---|---|---|
| **D-1 collision identifiant `class_name AudioBuses` ↔ autoload** | LOW | ✅ Reformulé classe statique pure (PAS autoload), per mémoire projet `feedback_godot_class_name_autoload_collision.md`. Seul `AudioSystem` reste autoload. |
| **D-2 click audible si pool 4× saturé** | LOW | ✅ Ajout `push_warning` sur `is_playing()` détection saturation + note R-1 (mitigation : pool 6× post-MVP si combo Tier 2+). |
| **D-3 `lerpf` linéaire sur dB log** | LOW | ✅ Note ajoutée : OK pour swoosh ≤ 30 ms (perceptuel non audible) ; `db_to_linear`/`linear_to_db` switch obligatoire pour music crossfade ≥ 1 s (futur Music ADR). |
| **`AudioSystem` autoload `class_name` + `process_priority` non spécifiés** | LOW | ✅ Key Interface retire `class_name` (collision autoload) + documente `process_priority = 0 (default)`. |

**Empirical verifications validées par specialist** :
- ✅ `AudioStreamPlayer*`, `AudioServer.set_bus_volume_db()`, `AudioServer.get_bus_index()` stables 4.0+
- ✅ Pooling pattern conforme audio.md
- ✅ R-3 `pitch_scale` invariance vs `Engine.time_scale` cohérent comportement Godot
- ✅ R-2 D-6 Camera3D listener auto-current cohérent ADR-0002 VC-5 (vérification empirique SubViewport reste requise)
- DIVERGE MINEUR — audio.md exemple Tween music fade contredit D-3 ; ADR-0009 a raison (exemple engine-reference simplifié, pas conscient slow-mo project context)

## Phase 5b — GDD Revision Flags

**None** — ADR-0009 ratifie des contracts déjà figés par Combat GDD §Audio (ducking rules + AC-CMB-51 + AC-CMB-audio-01/02) sans contradiction. Aucun GDD ne fait d'assumption sur audio qui contredit ADR-0009 ou audio.md.

## Phase 6 — Architecture Document Coverage

`docs/architecture/architecture.md` r1 (2026-04-21) ne reflète pas encore ADR-0006/0007/0008/0009/0011. Re-génération r2 recommandée non-bloquante (déjà flagué dans gate-check 2026-04-27 recommendation #3).

## Verdict : ✅ PASS pour promotion ADR-0009 → Accepted

**Justifications** :
- 0 cross-ADR conflict (vs 8 ADRs upstream Accepted)
- Upstream deps Accepted (ADR-0001/0002/0003/0005/0006/0007/0011)
- Engine LOW risk (APIs stables 4.0+, 0 post-cutoff, 0 deprecated, 0 breaking 4.4-4.6)
- godot-specialist APPROVE WITH SUGGESTIONS (4 LOW, 0 blocker — tous appliqués)
- 3 Verification Required différées Sprint Audio (pattern précédent ADR-0006/0011)
- Couverture intégrale Combat GDD §Audio + AC-CMB-51 + AC-CMB-audio-01/02 + signals Movement consume
- Pattern testabilité (`MockAudioHandler` + `MockAudioBus` + `_get_time_msec` Callable) déjà figé ADR-0006

**Gap G-7 RÉSOLU** — Audio System architecture verrouillée. Story-020 Combat débloquée. Audio System GDD authoring débloqué.

## Required ADRs (suite)

| Priorité | ADR suggéré | Gap |
|---|---|---|
| MEDIUM | ADR Save/Load Settings (`master_volume_db`, `mouse_sensitivity`, `mouse_y_inverted`, `fov_user_offset`, `input_settings.tres`) | G-2a/G-2b (Feature, post-MVP) |
| MEDIUM | ADR Accessibility Interface Layer (`reduce_flash`, `reduce_motion`, `reduce_motion_slow_mo_scale_mult`, `reduce_motion_disable_slow_mo`, `reduce_motion_flash_mult`) | G-4 mutualisé TR-mov-008 + TR-cmb-016 (post-MVP Tier 3) |
| LOW | Future Music ADR (transitions musicales contextuelles, dynamic mixing, perceptual crossfade) | Tier 2 post-MVP |
| LOW | Future Voice/VO ADR (narrative voice acting + accessibility subtitles) | Tier 3 post-MVP |

Tous **non-blockers MVP**.

## Next Steps

1. **`/design-system audio-system`** — écrire le GDD Audio System aligné sur ADR-0009 Accepted (D-1 buses + D-2 pool + D-3 wall-clock + D-4 DEFERRED + D-5 spatialization + D-6 listener)
2. **`/architecture-review` fresh session post-GDD Audio** — extraire TRs `TR-aud-*`, vérifier `TR-lvl-042` covered_by ajusté avec TR-aud-* footstep routing
3. **Story-020 Combat** — passer de Blocked à Ready une fois GDD Audio écrit
4. **Sprint 0 Technical Setup follow-ups Audio** (Migration Plan §1) :
   - Créer `default_bus_layout.tres` (7 buses)
   - Configurer `project.godot audio/buses/default_bus_layout`
   - Créer autoload `AudioSystem` (`src/core/audio_system.gd` — pas de `class_name`)
   - Créer `src/core/audio_buses.gd` (`class_name AudioBuses` static helper)
   - Lint CI `lint-audio-tween` (regex `Tween.*volume_db|tween_property.*volume_db` dans `src/gameplay/audio/` + `src/core/audio_system.gd`)
5. **`/create-epics audio-system`** post Audio GDD Approved
