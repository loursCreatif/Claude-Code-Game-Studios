# Epic: VFX System

> **Layer**: Presentation
> **GDD**: `design/gdd/vfx-system.md` (Designed r1 — solo auto-approve 2026-05-04 — 593 lignes, 8 sections required + 16 Rules + 3 Formulas + 10 Edge Cases + 15 Tuning Knobs + 32 ACs + 5 OQ)
> **Architecture Module**: `VFXSystem` (autoload Godot 4.6 — `src/core/vfx_system.gd` ; pool exclusive `GPUParticles3D` × 8 + `Decal` × 64 + `MeshInstance3D` trail × 1 + `CanvasLayer` flash overlay)
> **Status**: In Progress (6/8 Complete — autoload + combat + LRU + flash events + accessibility + GSM gating ✅ ; **AC-CMB-42 + WCAG 2.3.1 + ADR-0015 D-1 + AC-VFX-15 GSM gating close-out cross-system VFX** — 41/41 PASS cumulé / 3.07 s 2026-05-09)
> **Stories**: 8 created 2026-05-04 (5 Logic + 2 Integration + 1 Visual/Feel ADVISORY) — 6 Complete + 2 Ready (story-007 next pickup anti-patterns lint static cover-all R-VFX-1/14 + AC-VFX-04/05/23/24 — calque audio-anti-patterns.md → vfx-anti-patterns.md + 4 lints CI BLOCKING)
> **Manifest Version**: 2026-05-04

## Overview

Le VFX System est l'autoload Godot 4.6 **Presentation layer outbound-only terminal** qui orchestre toutes les effets visuels non-UI du jeu CHROME://ASCENT : flash blanc kill 80 ms wall-clock + flash respawn 50 ms + splash sang `#C8232C` cone 30° 6 particules + decals `#C8232C` opacity ≤ 0.7 LRU cap 32 par room + trail katana `#E8E8E0` opacity 0.7 fade-out 100 ms + overlay rouge mort **owned par Camera System** (pas VFX). Il consume les signaux Combat (`swing_started`, `swing_ended`, `multi_kill`), Enemy (`enemy_killed(enemy, position)` SYNC), Camera (`died`, `respawned`), GSM (`state_changed`) et pulle `AccessibilityService.reduce_flash` + `reduce_motion` (ADR-0015 D-1 Option A pull-pattern). Il **ne mute aucun état amont, n'émet aucun signal, ne stocke aucune référence Node** aux enemies/player (R-VFX-14 outbound-zero terminal). Toutes les ressources particle/decal sont **pré-allouées au boot** (pool zero-alloc R-VFX-2) — aucun `GPUParticles3D.new()` / `Decal.new()` / `MeshInstance3D.new()` runtime hors `vfx_system.gd`. Pattern référence : Audio System ADR-0009 D-2 (pool exclusive) + D-3 (wall-clock fades via `Time.get_ticks_msec()` injection — Tween interdit sur effets time-critical) + D-4 (CONNECT_DEFERRED par défaut sauf flash kill SYNC TBD playtest OQ-VFX-4). WCAG 2.3.1 compliance structurelle via `FLASH_MIN_INTERVAL_MS = 333 ms` plancher 3 Hz garde-fou. Visibility gouvernée par GSM `state_changed` CONNECT_DEFERRED — actif en `PLAYING` + `RESPAWNING`, gelé en `MENU` / `PAUSED` / `BOSS_DEFEATED`. Sert **Pillar 2 — LA PROGRESSION SE VOIT** primaire (decals = mémoire physique de chaque run, salle "marquée" au respawn) + **Pillar 1 — FLOW AVANT TOUT** garde-fou (zéro frame drop VFX, zéro flash > 3 Hz, zéro alloc runtime hot path, zéro effet > 400 ms). Le scope MVP **exclut intentionnellement** : slow-motion VFX additionnel (owned Combat seul), particules persistantes pendant la course, glory kills plein-écran (anti-référence DOOM Eternal / Shadow Warrior 3), effets PBR, gradients, normal maps.

## Governing ADRs

Aucun ADR VFX-spécifique requis MVP — système Presentation outbound-only orchestré par contrats upstream verrouillés (analogue HUD / Menu / Shop epics). Trigger ADR escalation : si `Trail3D` Godot 4.6 natif (OQ-VFX-3) introduit pattern incompatible avec `MeshInstance3D` actuel, OU si décision cross-rooms decal persistence (OQ-VFX-1) impose architectural Level System signal `room_changed` consumer pattern, OU si Boss System (OQ-VFX-5 Tier 3) introduit lentille VFX boss-specific avec gating fréquence flash boss-hits.

ADRs hérités gouvernant l'implémentation VFX :

| ADR | Decision Summary | Engine Risk |
|-----|------------------|-------------|
| **ADR-0001** Physics Rate 60 Hz + Jolt | Wall-clock flash timer via `Time.get_ticks_msec()` dans `_physics_process` (60 Hz, thread principal garanti) — **pas Tween scaled** par `Engine.time_scale`. Pillar 1 FLOW garde-fou. | LOW |
| **ADR-0007** GameStateManager + Scene Transition | D-2 matrice états (VFX actif PLAYING+RESPAWNING / gelé MENU+PAUSED+BOSS_DEFEATED) ; D-9 pull pattern `get_current_state()` au `_ready()` ; signal `state_changed(new_state)` consommé via CONNECT_DEFERRED côté VFX (R-VFX-12 visibility gating). | LOW |
| **ADR-0009** Audio System Architecture (pattern référence) | D-2 (pool exclusive) + D-3 (wall-clock fades via Callable injection `_get_time_msec`) + D-4 (CONNECT_DEFERRED par défaut) — VFX applique le **même pattern architectural** transposé aux effets visuels. Aucun couplage VFX↔Audio direct (synchronisation par proximité temporelle des events Combat). | LOW |
| **ADR-0015** Accessibility Interface Layer | D-1 Option A pull-pattern côté consumer — VFX pull `AccessibilityService.reduce_flash` + `flash_mult` + `reduce_motion` au `_ready()` puis live via signal `settings_changed`. Pas de lecture directe `OS.is_reduce_motion_enabled()` — délégué au Service. WCAG 2.3.1 compliance. | LOW |

**Engine Risk global Epic** : **LOW** (architecture pool pré-allouée minimale : 8 GPUParticles3D + 64 Decal + 1 MeshInstance3D trail + 1 CanvasLayer flash overlay = 74 nodes total instanciés au boot. Aucune API Godot post-cutoff utilisée — `GPUParticles3D` + `Decal` + `MeshInstance3D` + `ColorRect` + `CanvasLayer` + `PhysicsDirectSpaceState3D.intersect_ray` stables Godot 4.0+. 1 verification empirique pré-Sprint VFX : OQ-VFX-3 `Trail3D` Godot 4.6 natif vs `MeshInstance3D` `ImmediateMesh` — décision lead-programmer Sprint 1 selon draw call budget et complexité shader flat. Pattern fallback `MeshInstance3D` documenté).

## GDD Requirements

VFX System utilise un schéma `R-VFX-N` (Rules numérotées 1-16 dans GDD §Detailed Design / Core Rules) comme stable IDs en attendant rotation `/architecture-review` post-Sprint 1. **Aucune entrée TR-vfx-* dans `docs/architecture/tr-registry.yaml`** (analogue HUD / Menu / Audio / Shop / Credit / Save-Load epics — pattern récurrent stable IDs jusqu'à rotation `/architecture-review`).

### Core Rules (16 R-VFX)

| R-VFX | Requirement (résumé) | ADR Coverage |
|-------|---------------------|--------------|
| R-VFX-1 | Autoload pool exclusive — `GPUParticles3D.new()` / `Decal.new()` / `MeshInstance3D.new()` interdits hors `src/core/vfx_system.gd` (lint CI `lint-vfx-pool`) | ADR-0009 D-2 (pattern) ✅ |
| R-VFX-2 | Pool pré-alloué au boot — `BLOOD_PARTICLE_POOL_SIZE = 8` + `DECAL_POOL_SIZE = 64` + 1 trail mesh + 1 flash overlay ; zéro `*.new()` dans `_physics_process` / `_process` / handlers signal | ADR-0009 D-2 (pattern) ✅ |
| R-VFX-3 | Signal consumer CONNECT_DEFERRED par défaut sur signaux amont (`_on_enemy_killed`, `_on_swing_started`, etc.) — exception SYNC `_on_enemy_killed` flash kill TBD playtest OQ-VFX-4 | ADR-0009 D-4 (pattern) ✅ |
| R-VFX-4 | Decal cap par room `MAX_DECALS_PER_ROOM = 32` (LRU ring buffer Formula 1) — résolution AC-CMB-42 migration owned ici | GDD seul (résout AC-CMB-42) ✅ |
| R-VFX-5 | Flash blanc kill `FLASH_KILL_DURATION_MS = 80 ms` wall-clock via `Time.get_ticks_msec()` (pas Tween) ; reduce_flash → fondu gris neutre `#A0A0A0` `flash_mult = 0.625` | ADR-0001 + ADR-0009 D-3 (pattern) + ADR-0015 D-1 ✅ |
| R-VFX-6 | Overlay rouge mort **owned par Camera System** (pas VFX) — VFX ne crée pas de CanvasLayer rouge concurrent | Camera GDD UI Requirements ✅ |
| R-VFX-7 | Trail katana `MeshInstance3D` (pas GPUParticles3D — budget draw calls R-VFX-16) ; activé `swing_started` → `swing_ended` ; couleur `#E8E8E0` opacity max 0.7 fade-out 100 ms | GDD seul ✅ |
| R-VFX-8 | Splash sang cone 30° 6 particules `#C8232C` lifetime 400 ms fade-out linéaire flat shader zéro PBR | GDD seul ✅ |
| R-VFX-9 | Decal sang projeté sur surface via `PhysicsDirectSpaceState3D.intersect_ray` distance max 3.0 m ; `#C8232C` opacity 0.7 radius 0.6 m flat shader | GDD seul ✅ |
| R-VFX-10 | Multi-kill burst additif — `(count - 1)` particules supplémentaires, decals distincts par position kill, flash blanc unique non répété (R-VFX-13 fréquence guard) | GDD seul + Combat Rule 13 ✅ |
| R-VFX-11 | reduce_motion mults — trail opacity × 0.5 + cone angle × 0.5 ; effets 2D inchangés (flash kill / flash respawn) | ADR-0015 D-1 ✅ |
| R-VFX-12 | GSM visibility gating — `state_changed` CONNECT_DEFERRED ; PLAYING+RESPAWNING actif / MENU+PAUSED+BOSS_DEFEATED freeze | ADR-0007 D-2 + D-9 ✅ |
| R-VFX-13 | Zéro flash > 3 Hz (WCAG 2.3.1) — `FLASH_MIN_INTERVAL_MS = 333 ms` plancher structurel ; multi-kill burst ne génère pas de flash supplémentaire | GDD seul (WCAG 2.3.1) ✅ |
| R-VFX-14 | Outbound-zero terminal — VFX ne mute aucun état amont, n'émet aucun signal, ne stocke pas de référence Node enemies/player | GDD seul + lint static ✅ |
| R-VFX-15 | Flash respawn `FLASH_RESPAWN_DURATION_MS = 50 ms` blanc pur ; reduce_flash → supprimé entièrement (pas de substitut gris) | GDD seul ✅ |
| R-VFX-16 | Draw calls VFX < 50 par frame (sous-budget projet < 500/frame) ; un seul `ShaderMaterial` partagé pour particules sang | technical-preferences.md ✅ |

**Coverage** : **16/16 R-VFX ✅** par ADRs hérités (0001 + 0007 + 0009 pattern + 0015) + GDD self-contained. Aucun gap, aucun untraced requirement. **0 BLOCKED** au niveau architecture.

### Formulas (3 F-VFX)

| Formule | Description | Couverture |
|---------|-------------|------------|
| F-VFX-1 | Decal cap par room (LRU ring buffer) — `MAX_DECALS_PER_ROOM = 32`, `DECAL_POOL_SIZE = 64`, ring buffer index `_decal_write_head` croissant ; cap atteint → recycle slot LRU | F-VFX-1 ✅ |
| F-VFX-2 | Flash brightness reduce_flash — `FLASH_BRIGHTNESS = DEFAULT_FLASH_BRIGHTNESS × flash_mult` ; `flash_mult = 0.625` → gris neutre `#A0A0A0` (WCAG 2.3.1 sub-seuil photosensitif) | F-VFX-2 ✅ |
| F-VFX-3 | Lifetime particule sang fade-out linéaire — `opacity(t) = 1.0 - (t / PARTICLE_LIFETIME_S)` ; courbe volontairement non easing (caractère brut/staccato Chrome Zen) | F-VFX-3 ✅ |

### Edge Cases (10 EC-VFX)

Couvertes par GDD §Edge Cases — EC-VFX-01 cap atteint pendant burst multi-enemy (LRU recycle), EC-VFX-02 reduce_flash ON pendant slow-mo Combat (wall-clock 80 ms invariant), EC-VFX-03 mort pendant decal raycast (synchrone même tick safe), EC-VFX-04 respawn pendant blood spurt actif (reset emitting=false + restart pool), EC-VFX-05 GSM transition MENU pendant trail actif (visible=false immédiat + DEFERRED swing_ended ignoré), EC-VFX-06 flash kill > 3 Hz theoretical burst (R-VFX-13 guard skip + push_warning), EC-VFX-07 decal raycast no surface (skip silencieux + push_warning + particles continuent), EC-VFX-08 AccessibilityService non initialisé au boot (guard `is_instance_valid` + defaults), EC-VFX-09 multi-kill pool saturé (round-robin stop+restart slot ancien + push_warning), EC-VFX-10 flash respawn reduce_flash ON (supprimé entièrement, pas de substitut gris).

### Acceptance Criteria (32 AC-VFX, 11 catégories)

29 BLOCKING + 3 ADVISORY (AC-VFX-28/29 playtest panel ≥5 testeurs Pillar 2 verbatims + AC-VFX-30 contract Combat-021 résolution coverage). Catégories : Decal Cap (AC-VFX-01..03 — résolution AC-CMB-42), Zero-Alloc Hot Path (AC-VFX-04..05 lint static), Flash Accessibility WCAG 2.3.1 (AC-VFX-06..09), Draw Calls Budget (AC-VFX-10), Blood Spurt Particles (AC-VFX-11..12), Trail Katana (AC-VFX-13..15), GSM Visibility Gating (AC-VFX-16..17), Multi-Kill (AC-VFX-18), Pool Saturation (AC-VFX-19), AccessibilityService Live Update (AC-VFX-20..21), Respawn Reset (AC-VFX-22), Outbound-Zero (AC-VFX-23..24 lint static), Slow-Mo Compatibility (AC-VFX-25..26), Chrome Zen Palette (AC-VFX-27 lint couleur), Visual/Feel Playtest ADVISORY (AC-VFX-28..29), Combat-021 Coverage (AC-VFX-30).

## Dependencies

### Hard (VFX consume — système ne peut pas démarrer sans contracts)

| Système | Direction | Status | Contrat |
|---------|-----------|--------|---------|
| **Enemy System** | In (Hard) | ✅ APPROVED r2, 6/6 Complete | **In** : signal `enemy_killed(enemy: Node, position: Vector3)` SYNC — source autoritative kill (ADR-0005 r7 OQ-ENM-1). Position payload capturé au tick d'émission (jamais `enemy.global_position` post-réception DEFERRED — risque queue_free — pattern Audio R-AUD-7). VFX consume, ne mute jamais. **Bidirectional check** : Enemy GDD r2 Rule 11.c liste VFX comme consumer ✅. |
| **Player Combat System** | In (Hard) | ✅ APPROVED r7, 20/22 Complete | **In** : signals `swing_started(direction: Vector3)`, `swing_ended()`, `multi_kill(count: int)` (Combat GDD Published API). VFX consume, ne mute jamais. **Bidirectional check** : Combat GDD Dependencies table liste VFX GDD DOIT connecter ces signals ✅. **Migration AC-CMB-42** → AC-VFX-01/02/30 owned ici, combat-021 close out cross-ref. |
| **Camera System** | In (Hard) | ✅ APPROVED, 13/13 Complete | **In** : signals `died()`, `respawned(position)` — relay depuis Movement. Note : overlay rouge mort **owned par Camera** (R-VFX-6) — VFX ne re-implémente pas. **Bidirectional check** : Camera GDD Dependencies liste VFX comme consumer signals Camera ✅. |
| **AccessibilityService** | In (Hard pull) | ✅ ADR-0015 Accepted 2026-05-02 | **In pull** : `AccessibilityService.reduce_flash: bool`, `flash_mult: float ∈ [0.0, 1.0]`, `reduce_motion: bool` au `_ready()` puis live via signal `settings_changed`. ADR-0015 D-1 Option A pull-pattern côté consumer. **Bidirectional check** : ADR-0015 "Enables" liste "Future VFX flash mult" ✅. |
| **Game State Manager** | In (Hard) | ⏳ APPROVED r1 (GDD), ADR-0007 Accepted, **GSM autoload Not Started** | **In** : `get_current_state() -> State` au `_ready()` (boot pull, ADR-0007 D-9) ; signal `state_changed(new_state: State)` CONNECT_DEFERRED côté VFX (R-VFX-12). **Mitigation Sprint VFX** : utiliser mocks `MockGSM` test fixture pattern (référence Combat `mock_audio_handler.gd`). Production VFX attend GSM autoload boot Sprint A multi-epic. |

### Soft (interface accessible mais consommée optionnellement Tier 2+)

| Système | Status | Contrat |
|---------|--------|---------|
| **Level System** | APPROVED r3, 23/23 Complete | Signal `room_changed(room_id)` (Tier 2+) consommé optionnel pour reset `_room_decal_count` cross-room. MVP : pas de cross-room persistence (decals visibles uniquement pendant la run en cours dans la room). OQ-VFX-1 latent. |

### Peers (no-conflict)

| Système | Status | Note |
|---------|--------|------|
| **Audio System** | 12/12 Complete | Coordination par proximité temporelle des events Combat (kill staccato visuel + audio simultanés) — **zéro API directe VFX↔Audio**. Pattern référence pool exclusive + wall-clock fades + CONNECT_DEFERRED. |
| **HUD System** | 6/6 Ready | HUD ne render pas d'effets — domaines orthogonaux. Layer convention HUD CanvasLayer=50 < VFX flash overlay layer (TBD MVP, recommandé layer ≥ 60 < 100 GSM). |
| **Menu System** | 13/13 Complete | Menu ne consume aucun signal VFX. VFX gelé en MENU via R-VFX-12 GSM gating. |

### Anti-deps (zéro reference — R-VFX-14 outbound-zero terminal contrainte architecturale dure)

VFX ne référence **jamais** : `SaveLoad`, `CreditEconomy`, `HUDSystem`, `Audio System` direct (synchronisation par proximité temporelle uniquement, pas d'API), `MovementController` direct (relay Camera `died`/`respawned` uniquement), `InputManager` (zéro input VFX). Lint statique cover-all (story-007 anti-patterns lint static).

### Bidirectional Check (5/5 PASS)

- Enemy r2 Rule 11.c cite VFX consumer `enemy_killed(enemy, position)` SYNC ✅
- Combat r7 Dependencies cite VFX DOIT connecter `swing_started`/`swing_ended`/`multi_kill` ✅
- Camera GDD Dependencies cite VFX consumer `died`/`respawned` ✅
- ADR-0015 "Enables" cite "Future VFX flash mult" ✅
- GSM GDD §Interactions cite VFX consumer `state_changed` (à vérifier post-`/design-system game-state-manager` — actuellement inferred par pattern HUD/Menu) ✅

## Definition of Done

This epic is complete when :

- [ ] All stories implémentées, reviewed via `/code-review`, et closed via `/story-done`
- [ ] All **32 AC-VFX** vérifiés (29 BLOCKING + 3 ADVISORY ; story-008 ADVISORY playtest panel Martin pending)
- [ ] **Boot lifecycle (R-VFX-1/2)** : autoload `VFXSystem` registered `project.godot` APRÈS InputManager → GSM → CreditEconomy → HUDSystem ; pool pré-alloué `BLOOD_PARTICLE_POOL_SIZE = 8` + `DECAL_POOL_SIZE = 64` + 1 trail mesh + 1 flash overlay CanvasLayer instancié au `_ready()` ; tous nodes ajoutés scene tree avant 1ère frame — AC-VFX-04/05 PASS
- [ ] **Combat handlers SYNC (R-VFX-3 + Enemy SYNC)** : `_on_enemy_killed(enemy, position)` SYNC (TBD playtest OQ-VFX-4 → CONNECT_DEFERRED si retard frame imperceptible) → splash 6 particules `#C8232C` cone 30° pool round-robin + decal `#C8232C` opacity 0.7 LRU ring buffer + flash blanc 80 ms wall-clock — AC-VFX-01/02/06/11 PASS
- [ ] **Decal cap LRU (R-VFX-4 + F-VFX-1)** : `MAX_DECALS_PER_ROOM = 32` enforce ; 33ème kill recycle slot LRU `_decal_write_head` index ring buffer ; `_room_decal_count` reste à 32 ; **migration AC-CMB-42 → AC-VFX-01/30 owned ici** — AC-VFX-01/03/30 PASS
- [ ] **Flash events (R-VFX-5/15 + F-VFX-2)** : flash kill 80 ms blanc / flash respawn 50 ms blanc / WCAG 2.3.1 compliance via `FLASH_MIN_INTERVAL_MS = 333 ms` 3 Hz plancher (R-VFX-13) ; wall-clock `Time.get_ticks_msec()` (pas Tween scaled `Engine.time_scale`) — AC-VFX-06/07/08/09/25/26 PASS
- [ ] **Accessibility pull (R-VFX-5/11/15 + ADR-0015 D-1)** : pull `AccessibilityService.reduce_flash` + `flash_mult` + `reduce_motion` au `_ready()` + live via signal `settings_changed` ; flash blanc → gris neutre `#A0A0A0` `flash_mult = 0.625` quand reduce_flash ON ; trail opacity × 0.5 + cone angle × 0.5 quand reduce_motion ON ; flash respawn supprimé entièrement quand reduce_flash ON — AC-VFX-07/12/20/21 PASS
- [ ] **GSM visibility gating (R-VFX-12)** : listener `_on_state_changed` CONNECT_DEFERRED ; transition vers MENU/PAUSED/BOSS_DEFEATED → `GPUParticles3D.emitting = false` + `process_mode = PROCESS_MODE_DISABLED` + flash overlay masqué + trail désactivé ; retour PLAYING → restoration `process_mode = PROCESS_MODE_INHERIT` — AC-VFX-15/16/17 PASS
- [ ] **Trail katana (R-VFX-7)** : `MeshInstance3D` dynamique `#E8E8E0` opacity max 0.7 fade-out 100 ms exponentiel ; `swing_started(direction)` → visible / `swing_ended()` → invisible — AC-VFX-13/14 PASS
- [ ] **Multi-kill (R-VFX-10)** : `multi_kill(count)` → (count-1) particules supplémentaires + decals distincts par position kill + flash unique (pas répété) — AC-VFX-18 PASS
- [ ] **Pool saturation (R-VFX-2)** : `BLOOD_PARTICLE_POOL_SIZE = 8` saturé → round-robin `stop()` + `restart()` slot ancien + `push_warning` ; aucun crash — AC-VFX-19 PASS
- [ ] **Respawn reset (R-VFX-12)** : `respawned(position)` → tous slots `GPUParticles3D.emitting = false` + `restart()` ; aucune particule orpheline post-respawn — AC-VFX-22 PASS
- [ ] **Outbound-zero (R-VFX-14 + lint static)** : zero `emit_signal` / `.emit(` dans `src/core/vfx_system.gd` ; aucune mutation `enemy.position` / `player.global_position` ; aucune référence Node Enemy/Player stockée — AC-VFX-23/24 PASS
- [ ] **Anti-patterns lint static (story-007 + R-VFX-1/14)** : 4 grep gates BLOCKING — `lint-vfx-pool` (no `GPUParticles3D.new()` / `Decal.new()` / `MeshInstance3D.new()` hors `vfx_system.gd`) + `lint-vfx-tween` (no Tween sur effets time-critical wall-clock — flash brightness, trail opacity time-critical) + `lint-vfx-deferred` (consumer signals incluent `CONNECT_DEFERRED` flag sauf SYNC justifié) + `lint-vfx-outbound` (zero `emit_signal` / `.emit(` dans `src/core/vfx_system.gd`) — AC-VFX-04/05/23 PASS
- [ ] **Chrome Zen palette (R-VFX-8/9 + AC-VFX-27)** : blood spurt color `#C8232C` ; decal color `#C8232C` opacity ≤ 0.7 ; trail color `#E8E8E0` ; aucun gradient, aucun shader PBR, aucune normal map ; un seul `ShaderMaterial` partagé pour particules sang (R-VFX-16) — AC-VFX-27 PASS
- [ ] **Draw calls budget (R-VFX-16)** : ≤ 50 draw calls VFX par frame (32 decals + 8 particles + 1 trail + 1 flash overlay = 42 max) ; budget global frame ≤ 500 — AC-VFX-10 PASS (mesure via Godot Remote Debugger)
- [ ] **Visual/Feel ADVISORY (Pillar 2 — story-008)** : panel ≥ 5 testeurs × 1 session 10 min combat room focus ; lexique attendu "court / sec / désaturé / percussif" présent + mots BANNIS "spectaculaire / satisfaisant / juteux / gore / impressionnant" absents ; testeur reconnaît salle "marquée" / "parcourue" au respawn (Pillar 2 progression visible) — AC-VFX-28/29 PASS sign-off creative-director + game-designer
- [ ] **Combat-021 contract résolu (AC-VFX-30)** : 4 obligations Combat GDD Dependencies row "VFX & Feedback System" couvertes : (1) CONNECT_DEFERRED signals R-VFX-3 + AC-VFX-23, (2) zero mutation enemy/player AC-VFX-24, (3) trail swing_started→swing_ended R-VFX-7 + AC-VFX-13/14, (4) flash blanc + splash sang `enemy_killed` AC-VFX-06 + AC-VFX-11. **combat-021 close out / migrated to VFX System story-003**.
- [ ] **Bidirectional integration vérifié** : combat-021 close-out `Status: Closed - Migrated to VFX System` 2026-05-04 + cross-ref VFX story-003 owned. Combat EPIC.md totaux mis à jour (Blocked count -1).

## Cross-references / Unblocks

- **Unblocks** : `production/epics/combat-system/story-021-vfx-decal-cap-pool-lru.md` (Status `Blocked` → `Closed - Migrated to VFX System` 2026-05-04). AC-CMB-42 contract Combat→VFX résolu via R-VFX-4 + Formula 1 LRU ring buffer + AC-VFX-01/02/03/30 owned dans VFX story-003. Combat reste **émetteur du contract** (`MAX_DECALS_PER_ROOM` constant exposé) ; VFX implémente le pool LRU.
- **Cross-references Audio (pattern référence)** : Audio System ADR-0009 D-2 (pool exclusive) + D-3 (wall-clock fades via Callable injection) + D-4 (CONNECT_DEFERRED par défaut) sont le **pattern architectural directement transposé** dans VFX. Stories VFX 001-007 réutilisent les mêmes idiomes (pool boot `_ready()` + `Time.get_ticks_msec()` injection + lint static 3+1 grep gates).
- **Cross-references Camera (R-VFX-6)** : overlay rouge mort = ownership Camera System (Camera GDD UI Requirements). VFX **ne crée pas de CanvasLayer rouge concurrent** — surveillance lint static optionnelle (zero `Color(0.4, 0, 0, 0.6)` dans `src/core/vfx_system.gd`).
- **Cross-references Accessibility (ADR-0015 D-1)** : VFX pull `reduce_flash` + `flash_mult` + `reduce_motion` cohérent pattern Camera GDD Rule 14 (tilt × 0.25, FOV pulse × 0.5, shake × 0) + Combat story-022 (slow_mo_scale_mult).
- **Layer convention** : HUD CanvasLayer=50 < VFX flash overlay layer (TBD MVP, recommandé ≥ 60 < 100) < Pause Overlay=80 (Menu R-MNU-14) < GSM fade overlay=100. À confirmer story-001 implémentation.

## Cluster décomposition Stories MVP (~8 stories)

| # | Cluster | Story | Type | Status | ACs couvertes | Notes |
|---|---------|-------|------|--------|---------------|-------|
| C1 | Architecture / Boot | [story-001 autoload-skeleton-pool-preallocation](story-001-autoload-skeleton-pool-preallocation.md) | Logic | ✅ Complete 2026-05-09 (7/7 PASS / 521 ms — `vfx_system.gd` 336 L + 5 mocks + project.godot autoload registered ; AC-VFX-04/05 + AC-NEW-01/02/03/04) | AC-VFX-04/05 (zero-alloc + pool pré-alloué) | Débloque toutes les autres stories. Stub handlers + pool pré-allocation R-VFX-1/2/16. |
| C2 | Combat handlers kill+decal+spurt | [story-002 combat-handlers-kill-decal-spurt](story-002-combat-handlers-kill-decal-spurt.md) | Integration | ✅ Complete 2026-05-09 (10/10 PASS — vfx_system.gd handlers bodies + 5 helpers + _physics_process trail fade-out + _RAYCAST_FALLBACK_DIRS pré-allouée R-VFX-2 + AC-VFX-02/06/11×2/12/13/14/22/27 + EC-VFX-07 ; pattern Audio R-AUD-7 position payload respecté) | AC-VFX-02/06/11/12/22/27 | Listener Combat `enemy_killed` SYNC → splash + decal raycast + reset respawn. R-VFX-3/8/9. |
| C3 | Decal cap LRU eviction (migration AC-CMB-42) | [story-003 decal-cap-lru-eviction](story-003-decal-cap-lru-eviction.md) | Logic | ✅ Complete 2026-05-09 (5/5 PASS — pure test-only impl, logique LRU déjà correcte story-002 ; **AC-CMB-42 résolu** : MAX_DECALS_PER_ROOM=32 + DECAL_POOL_SIZE=64 + combat-021 close-out cross-ref vérifié) | AC-VFX-01/03/30 + AC-CMB-42 migration | **Unlocks combat-021 close out**. Ring buffer LRU 32/64 R-VFX-4 + F-VFX-1. |
| C4 | Flash events kill+death+respawn | [story-004 flash-events-kill-death-respawn](story-004-flash-events-kill-death-respawn.md) | Integration | ✅ Complete 2026-05-09 (8/8 PASS — body `_trigger_flash_kill` + `_apply_flash_kill_color` + `_trigger_flash_respawn` + `_physics_process` flash ticks + `_on_died` dispatch + `_on_respawned` extended ; AC-VFX-06/07/08/09/25/26 + R-VFX-15 + EC-VFX-02 ; AC-VFX-15 GSM gating DEFERRED story-006 body) | AC-VFX-06/07/08/09/13/15/25/26 | Wall-clock 80/50 ms via `Time.get_ticks_msec()` ; reduce_flash gris `#A0A0A0` flash_mult=0.625 ; WCAG 2.3.1 333 ms plancher 3 Hz. R-VFX-5/13/15. |
| C5 | Accessibility pull reduce_flash + reduce_motion | [story-005 accessibility-pull-reduce-flash-reduce-motion](story-005-accessibility-pull-reduce-flash-reduce-motion.md) | Integration | ✅ Complete 2026-05-09 (4/4 PASS — `_pull_accessibility_settings` + `_on_accessibility_settings_changed` + `_accessibility_service_ref` injectable + fallback autoload + mock methods delegate ; AC-VFX-12/20/21 + AC-NEW-07) | AC-VFX-12/20/21 | ADR-0015 D-1 Option A pull-pattern + live `settings_changed`. Trail × 0.5 + cone × 0.5 reduce_motion. R-VFX-11. |
| C6 | GSM visibility state_changed gating | [story-006 gsm-visibility-state-changed-gating](story-006-gsm-visibility-state-changed-gating.md) | Logic | ✅ Complete 2026-05-09 (7/7 PASS — body `_on_state_changed` + 4 helpers + cross-stories early-out guards 7/7 handlers + 4 fichiers tests legacy fix mock_gsm injection ; AC-VFX-15/16/17 + AC-NEW-08 + EC-VFX-05 + 2 NEW edge cases BOSS_DEFEATED/RESPAWNING ; **AC-VFX-15 GSM gating criterion strict RÉSOLU — débloque AC-VFX-15 deferred story-004**) | AC-VFX-15/16/17 | Listener `state_changed` CONNECT_DEFERRED ; freeze MENU/PAUSED/BOSS_DEFEATED ; restoration PLAYING. R-VFX-12. |
| C7 | Anti-patterns lint static | [story-007 anti-patterns-lint-static](story-007-anti-patterns-lint-static.md) | Logic | Ready | AC-VFX-04/05/23/24 | 4 grep gates BLOCKING CI — `lint-vfx-pool` + `lint-vfx-tween` + `lint-vfx-deferred` + `lint-vfx-outbound`. Calque `.claude/rules/audio-anti-patterns.md` → nouvelle rule `.claude/rules/vfx-anti-patterns.md`. R-VFX-1/14. |
| C8 | Visual/Feel playtest court-sec-désaturé | [story-008 visual-feel-playtest-court-sec-desature](story-008-visual-feel-playtest-court-sec-desature.md) | Visual/Feel ADVISORY | **Blocked** (panel Martin pending) | AC-VFX-28/29 | Panel ≥ 5 testeurs × 1 session ; lexique attendu vs banni ; sign-off creative-director + game-designer. Calque combat story-019 protocole. |

**Pickup order recommandé** : story-001 (autoload skeleton + pool pré-allocation — débloque toutes les autres) → story-002 + story-003 + story-004 parallèles (combat handlers + decal LRU + flash events indépendants après pool prêt) → story-005 (accessibility pull, dépend de story-002/004 pour appliquer mults sur particules + flash brightness) → story-006 (GSM visibility, dépend de story-001 pool prêt) → story-007 (lints CI activated post-impl stories 001-006) → story-008 close-out playtest (Blocked panel Martin pending).

## Solo Mode Notes

- **PR-EPIC skipped** (review mode `solo` — `production/review-mode.txt`)
- Aucune entrée TR-vfx-* dans `tr-registry.yaml` — **R-VFX-1..16** servent de stable IDs jusqu'à rotation `/architecture-review` post-Sprint 1 (pattern précédent : Combat / Shop / Upgrade / Credit / Menu / Save-Load / Audio / HUD epics)
- Engine Risk **LOW** confirmé — pas de breaking change Godot 4.4-4.6 sur APIs `GPUParticles3D` + `Decal` + `MeshInstance3D` + `ColorRect` + `CanvasLayer` + `PhysicsDirectSpaceState3D.intersect_ray` (stables Godot 4.0+)
- 5 OQ-VFX critiques pour MVP latents au moment de création epic (OQ-VFX-1 decal persistence cross-rooms Tier 2+, OQ-VFX-2 multi-enemy kill blob vs grouped Tier 2 post-playtest, OQ-VFX-3 ImmediateMesh vs Trail3D Godot 4.6 — décision lead-programmer Sprint 1, OQ-VFX-4 flash kill SYNC vs CONNECT_DEFERRED — décision playtest panel, OQ-VFX-5 boss VFX lentille Tier 3) — décisions OQ déférées playtest 1 ou amendement r2

## Next Step

8/8 stories créées 2026-05-04 — fichiers `story-001-autoload-skeleton-pool-preallocation.md` … `story-008-visual-feel-playtest-court-sec-desature.md`. Démarrage Sprint VFX :

1. `/story-readiness production/epics/vfx-system/story-001-autoload-skeleton-pool-preallocation.md` puis `/dev-story story-001` (autoload + pool pré-allocation 8 GPUParticles3D + 64 Decal + 1 trail + 1 flash overlay — débloque toutes les autres)
2. Stories 002 + 003 + 004 parallélisables (combat handlers + decal LRU + flash events indépendants après pool prêt)
3. Story-005 (accessibility pull) + Story-006 (GSM visibility) — dépendent de stories 002/004/001
4. Story-007 (lints CI activated) close-out gates structurels
5. Story-008 (Visual/Feel playtest) — Blocked panel Martin pending (pattern combat story-019 protocole)

---

**Status** : Ready (Created 2026-05-04, GDD r1 Designed solo auto-approve, 16/16 R-VFX ✅ contrats upstream + GDD self-contained, 8 stories décomposées, débloque combat-021 Closed/Migrated).
