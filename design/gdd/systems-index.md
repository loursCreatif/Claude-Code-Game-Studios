# Systems Index: CHROME://ASCENT

> **Status**: Draft
> **Created**: 2026-04-21
> **Last Updated**: 2026-04-27 (Audio System **APPROVED r2.1** via `/design-review design/gdd/audio-system.md` fresh re-review session post Phase A+B — 4 specialists adversariaux parallèles (game-designer + audio-director + qa-lead + godot-specialist) — verdict NEEDS REVISION (14 BLOCKING surgicaux, 0 redesign architectural) → **14/14 fixes appliqués immédiatement** : (1) Header L22 + Cross-Refs L428 "≤ 40 ms" → "60-80 ms wall-clock" ; (2) Bus naming UPPER_SNAKE_CASE propagé (Rule 3 hierarchy + AC-AUD-01 + Mix hierarchy §1-5 + Visual/Audio table + Cross-Refs + Player Fantasy Couche 1 + Formulas) ; (3) Mix hierarchy §4 contradiction sidechain réécrite (auto-ducking via compressor) ; (4) Mix hierarchy §5 UI mute phrase auto-contradictoire nettoyée (OQ#6 mute total MASTER MVP) ; (5) Formula 3 pool_size 4/8 → 5/12 ; (6) Edge Cases pool 8 → 12 cohérence ; (7) Rule 11 clac slot exclusion explicite via `_active_clac_players` tracker (préserve Couche 1 invariance clac) + pitch_scale appliqué AVANT `play()` (zero latency 1 tick) ; (8) Rule 16 prose attack 5 ms perceptuelle correcte (peak ducking à t≈5 ms post-onset, pas instantané) + edge case swings 170 ms apart documenté + guard double-add_bus_effect Phase D ; (9) ADR-0009 D-6 amendé pour reconciliation ADR-0002 chain `... → Camera3D → AudioListener3D` (1 listener explicite, pas zéro) + Rule 9 GDD alignée + AC-AUD-14 (c) `size() == 1` ; (10) AC-AUD-01 (d) sidechain effect verification ajouté ; (11) AC-AUD-02 (e) `get_child_count() == 20` (déterministe vs OBJECT_COUNT delta) + AC-AUD-03 (c) cycle pool 5 ; (12) AC-AUD-05 cap 4e kill testé (pitch +4 max, pas +6 carry-over) ; (13) AC-AUD-07 ResourceLoader.exists precheck + (f) overlap evidence playtest non-automatisable ; (14) AC-AUD-15 (c) protocole anti-pop concret (AudioEffectRecord + FFT seuil 3 dB) + (e) sons démarrés slow-mo + AC-AUD-16 mesure `get_bus_peak_volume_left_db` post-effects + headless fallback. Scope **M** (~30 lignes éditées GDD + 1 amendment ADR-0009 D-6). Status `r2 Phase A+B applied (NEEDS RE-REVIEW)` → **`APPROVED r2.1`** — Phase A+B vision/spec figées, fixes surgicaux acceptés directement (skip re-review fresh — fixes scope-bounded et verified). **Débloque Story-020 Combat** (BLOCKED jusqu'à audio-system APPROVED) + Phase C (formules hardening) + Phase D (impl) adressables. Progress: 7/17 MVP designed, **4 APPROVED MVP** (Combat r6, Level r3, GSM r1, **Audio r2.1**), Movement r3 / Camera r2 / Input r4 pending re-review. Voir [audio-system.md](gdd/audio-system.md) + [review log r2.1](gdd/reviews/audio-system-review-log.md). Previous: NEEDS REVISION r1 (MAJOR) via `/design-review` 6 agents adversariaux + creative-director synthesis — verdict CD : 16 BLOCKING + 15 RECOMMENDED + 10 NICE-TO-HAVE. Scope **XL**. 4 BLOCKING vision (Couche 1 vs Couche 3 sidechain mix, multi_kill noop trou Fantasy, death.wav 40 ms perceptuellement impossible, D3 pitch invariance HLM-incompatible — Martin pending), 4 BLOCKING formules (F-01 div par zéro non gardée F1/F2/F4, F-02 lerp linéaire dB Formule 4 viole règle ligne 81, F-03 pool_2d_size min 3 insuffisant MVP, F-04 double atténuation player+bus non documentée), 2 BLOCKING impl Godot (pool 3D parented Node autoload spatial fragile, CONNECT_DEFERRED idle frame vs Rule 4 _physics_process timestamp race 53% relative error), 6 BLOCKING ACs (Open Question #9 Callable injection gate AC-04/06, tolerances dB non validées, AC-05 dedup mécanisme manquant, AC-08 state privé fragile, AC-09 untestable, AC-13 méthodologie absente) + AC-14/15 ADVISORY→BLOCKING promotion + 5 ACs manquants, 4 BLOCKING perf (AudioServer thread budget undefined, OBJECT_COUNT faux positifs CI, MEMORY_STATIC isolation, cold-cache non testé). 5 adjudications CD tranchées (death 60-80 ms+overlap, multi_kill pitch-shift +2 semi, sidechain Music, pools 2D 3→5 + 3D 8→12, naming UPPER_SNAKE_CASE). Ordre r2 imposé Phase A vision → B spec → C formules+ACs → D impl. Re-review uniquement après A+B. Voir [audio-system.md](gdd/audio-system.md) + [review log](gdd/reviews/audio-system-review-log.md). Story-020 Combat reste BLOCKED. Coordination Level r4 (signal `etage_loaded`) bloquante avant Sprint Audio. Progress: 7/17 MVP designed, 3 APPROVED MVP (Combat r6, Level r3, GSM r1), Audio NEEDS REVISION r1, Movement r3 / Camera r2 / Input r4 pending re-review. Previous: 2026-04-24 Game State Manager **APPROVED r1** via `/design-review` lean fresh session — verdict initial NEEDS REVISION (2 BLOCKING + 4 RECOMMENDED), **6 fixes éditoriaux appliqués immédiatement** + 1 fix réciproque ADR-0007 D-6 (RESPAWN_DELAY 0.3s→0.05s aligné registry entities.yaml l.220) : (1) Status ADR-0007 stale `Proposed`→`Accepted r2` ligne 9, (2) Header `## Detailed Design`→`## Detailed Rules` standard-conforme design/CLAUDE.md §3, (3) Refs stale `architecture.yaml l.125` remplacées par autorité ADR-0007 D-2 (3 occurrences : header, Rule 2, commentaire ENUM), (4) Refs `ADR-0011 à venir`→`ADR-0011 (Proposed)` (Rule 6 + Rule 8), (5) OQ-4 marquée RESOLVED (ADR-0007 promu Accepted r2 le 2026-04-23), (6) OQ-6 marquée RESOLVED — historical appendix (changelog réconciliations draft initial→ADR D-10). **12 alignements GDD↔ADR-0007 validés** : enum State, signal state_changed, 5 verbes API, autorité get_tree().paused, two-path scene transition, focus auto-pause, respawn observation pure, pattern pull boot, process_mode discipline, idempotence, CONNECT_DEFERRED died/respawned, BOSS_DEFEATED terminal. Scope **M**. Status `Designed r1 (pending fresh /design-review)` → `APPROVED r1`. Progress: **6/17 MVP designed → 1 APPROVED supplémentaire (Combat r6 + Level r3 + GSM r1 = 3 APPROVED MVP)**. Débloque `/architecture-review` consolidation (G-6 closed) + `/create-epics game-state-manager` Sprint 1. Previous: Game State Manager **Designed r1** via `/design-system game-state-manager` solo auto-approve — débloque Level system hard dependency G-6 Gap architecture. GDD 8 sections + Visual/Audio + UI + Open Questions. **API alignée strictement sur ADR-0007 D-10 (Proposed)** : enum `State` 5 values, 1 signal `state_changed(new_state)`, 5 verbes publics (`start_etage / request_pause / request_resume / request_scene_transition / request_new_run`), 1 getter. 18 ACs (Groupes A Boot × 3 + B Transitions × 5 + C Pause × 3 + D Respawn × 3 + E Scene × 2 + F Perf × 2), 6 Open Questions (OQ-4 promotion ADR-0007 Accepted, OQ-5 extensions post-MVP candidates, OQ-6 log des 8 réconciliations draft initial → ADR — divergences sur 9 verbes→5, signaux 10→1, pas de safety timeout, pattern pull boot, scene transition two-path). Registry : GSM ajouté en `referenced_by` sur `RESPAWN_DELAY` (Formula 2 GSM). Aucune nouvelle constante registry (draft RESPAWN_SAFETY_TIMEOUT_MS retiré au réalignement ADR-0007 D-7). Solo mode = skip CD-GDD-ALIGN. Status `Not Started` → `Designed r1 (pending fresh /design-review)`. Progress: 6/17 MVP designed. Previous: Level System **APPROVED r3** — `/design-review design/gdd/level-system.md` fresh full multi-specialist (3 agents game-designer + godot-specialist + qa-lead parallèles) post r2 CD 5 fixes : verdict NEEDS REVISION r2-fresh (4 BLOCKING éditoriaux, scope XS), **4/4 fixes r3 appliqués immédiatement**. **5/5 fixes CD ✅ RESOLVED CLEAN** (VerticalShaftRoom/F5 multi-rise ETAGE_HEIGHT_MAX=60m, hiérarchie 3D + archetypes TRAVERSAL/COMBAT/SHAFT/SECRET_HUB + 4 primitives PackedScene, R-2.U/R-2.A locaux, tuple Secret split 3 nœuds avec required_ability sur LureMarker, R-4 per-archetype + OnboardingAnchors Combat Rule 16). **4/4 r3 fixes ✅ APPLIED** : (1) AC-LVL-48 borne gate [15, 30]→[15, 60] m alignée F5 (cross-model 3× BLOCKING — un étage double-shaft 40m légal F5 était rejeté par CI), (2) AC-LVL-26 THEN reformulée pour tester comportement observable uniquement (`peer_ready_tick < active_received_tick`) avec raisonnement canonique EC-11 (ordre natif autoload Godot, pas propriété `call_deferred`), (3) AC-LVL-33 retiré (supersédé AC-LVL-55 per-archetype — double-gate avec Combat ≤32 incompatible avec uniforme ≤25), (4) Tuning Knob `SECRET_DENSITY_DIVISOR` default 2→3 aligné F7 nominal (5 secrets diluent Pillar 4, 3 rares > 5 faciles). 3 BLOCKING r2 lean antérieurs absorbés (Groupe G AC-LVL-46..50 + Groupe H AC-LVL-52..55 + AC-LVL-51 bonus, enum LevelState formelle lignes 181-186, PF/F5 cohérence via note F5 "puits 40m structurellement accommodable par double-shaft"). 0 BLOCKING, 9 RECOMMENDED optionnels absorbables Sprint 1 (ConcavePolygonShape3D garde Jolt, OQ-3 auto-tile 3D à vérifier, SHADER_BAKER_ENABLED garde @export, SecretLureMarker script conventions, Traversal min variance, `get_onboarding_anchors()` signature §Dependencies, F6 variance archetype, AC-LVL-34 phrasing alignement Combat, V-1/V-4/V-5 SMOKE ACs). Bidirectionalité Combat Rule 16 satisfaite. Rapport : [review fresh](gdd/reviews/level-system-review-r2-fresh-2026-04-23.md) + [log](gdd/reviews/level-system-review-log.md). Progress: 5/17 MVP designed (Combat APPROVED r6 / **Level APPROVED r3** / Movement r3, Camera r2, Input r4 pending re-review fresh). Next : `/create-epics level-system` pour backlog Sprint 1, OU paralléliser `/design-system` #6 Hazard / #8 Checkpoint, OU `/review-all-gdds` consistency sweep cross-GDD pré-epic.
> **Source Concept**: design/gdd/game-concept.md

---

## Overview

CHROME://ASCENT est un action-platformer FPS solo avec une boucle courte (30s moment-to-moment, 20-45 min par session) et quatre piliers : FLOW AVANT TOUT, LA PROGRESSION SE VOIT, UNE SECONDE CHANCE N'EST JAMAIS LOIN, LES SECRETS RÉCOMPENSENT LE MOUVEMENT. Les systèmes à concevoir reflètent cette identité : un moveset parkour extensible au cœur (risque #1), un combat katana one-shot, une économie de crédits gagnés par kill ou par secret, un shop de progression permanente entre étages, et une structure de niveaux verticale à checkpoints rapprochés. La narration, le multijoueur, et tout système d'inventaire/crafting/dialogue sont explicitement exclus par les anti-piliers. Le **boss final** est l'unique exception au one-shot mutuel : il dispose d'une barre de vie multi-hits tandis que le joueur reste one-shot. L'énumération privilégie un MVP serré (17 systèmes, 4-6 semaines) avec extensions progressives en Vertical Slice et Full Vision.

---

## Systems Enumeration

| # | System Name | Category | Priority | Status | Design Doc | Depends On |
|---|-------------|----------|----------|--------|------------|------------|
| 1 | Input System | Core | MVP | **NEEDS REVISION (r4 MAJOR — 4 BLOCKINGs convergents structurels + 3 bloquants testing, ADR-first path : ADR-0001 reopen + ADR-0002 Input API avant GDD fixes ; 2026-04-21, voir review log)** | [input-system.md](input-system.md) | (none — foundation) |
| 2 | Game State Manager | Core | MVP | **APPROVED r1** (2026-04-24 `/design-review` lean fresh session — verdict initial NEEDS REVISION 2 BLOCKING + 4 RECOMMENDED, **6 fixes éditoriaux appliqués + 1 fix réciproque ADR-0007 D-6** : status ADR Proposed→Accepted r2, header `Detailed Design`→`Detailed Rules` std-conforme, refs stale `architecture.yaml l.125` →ADR-0007 D-2 autorité, refs `ADR-0011 à venir`→`Proposed`, OQ-4/OQ-6 RESOLVED, ADR-0007 D-6 RESPAWN_DELAY 0.3s→0.05s registry-aligned. **12 alignements GDD↔ADR-0007 validés** structurellement. Scope **M**. GDD 8 sections + Visual/Audio + UI + Open Questions. **API alignée strictement ADR-0007 D-10 (Accepted r2)** : enum `State` 5 values, 1 signal `state_changed(new_state)`, 5 verbes publics (`start_etage / request_pause / request_resume / request_scene_transition / request_new_run`), 1 getter `get_current_state()`. 18 ACs Groupes A-F. Registry : GSM ajouté en `referenced_by` sur `RESPAWN_DELAY` (Formula 2). Voir [review log](reviews/game-state-manager-review-log.md). Débloque Level G-6 Gap architecture closed + `/create-epics game-state-manager` Sprint 1. | [game-state-manager.md](game-state-manager.md) | (none — foundation) |
| 3 | Save/Load System (inferred) | Persistence | MVP | Not Started | — | Game State Manager |
| 4 | Audio System | Audio | MVP | **APPROVED r2.1 (2026-04-27)** — `/design-review` re-review post A+B (4 specialists adversariaux parallèles) → 14/14 BLOCKING surgicaux appliqués (editorial UPPER_SNAKE_CASE propagation, Mix hierarchy §4 contradiction réécrite, Formula 3 pool_size 5/12, Rule 11 clac slot exclusion + pitch AVANT play, Rule 16 attack 5 ms prose perceptuelle, ADR-0009 D-6 amendé reconcile ADR-0002 chain AudioListener3D explicite, ACs testability `get_child_count()` + cap 4e kill + ResourceLoader precheck + AudioEffectRecord FFT anti-pop + `get_bus_peak_volume_left_db` post-effects + headless fallback). **Débloque Story-020 Combat**. Phase C (formules hardening) + Phase D (impl) adressables. Previous: r2 Phase A+B applied — `/design-system audio-system r2` solo auto-approve + Level r4 amend Option C + ADR-0009 D-1/D-3 r2 amendments. **Phase A vision** : Martin D3 REOPEN tranchée Option A (pitch shift bus allowlist `COMBAT_KILL`+`AMBIENCE` sous slow-mo, `MUSIC`+`SWING_ACTIVE` invariants), sidechain compressor `MUSIC`←`COMBAT_KILL` (résout Couche 1 vs Couche 3 par mécanisme), multi_kill pitch-shift +2/+4 semitones (comble trou Fantasy), death.wav 60-80 ms + overlap (perceptuel valide), Couche 4 HLM ajoutée Player Fantasy, 4 nouvelles Rules (Rule 11 réécrite, Rule 13 réécrite, Rule 14 réécrite, Rule 16 nouvelle sidechain). **Phase B spec** : pools 4→5 / 8→12 (CD reco), OQ#6 (UI mute MVP=mute total) RÉSOLU, OQ#7 (room tone Chrome Zen sub-bass `-12 dB` 40-80 Hz) RÉSOLU, OQ#9 (Callable injection `_set_time_provider` debug-guarded) RÉSOLU. **Phase C** (formules+ACs hardening : F-01 div par zéro guards, F-02 lerp dB perceptuel, AC observable reformulations, 5 ACs manquants) + **Phase D** (impl details : pool parenting `get_tree().root`, perf metric split GDScript vs AudioServer mixer thread, bus naming UPPER_SNAKE_CASE final propagation) RESTANTES. **NEEDS RE-REVIEW fresh post-A+B** (CD locked order) avant promotion APPROVED. Story-020 Combat reste BLOCKED jusqu'à audio-system APPROVED. Previous: NEEDS REVISION r1 (MAJOR — 16 BLOCKING + 15 RECOMMENDED + 10 NICE-TO-HAVE) (2026-04-27 `/design-review` fresh full multi-specialist — 6 agents adversariaux + creative-director synthesis. **Verdict CD : MAJOR REVISION NEEDED — 16 BLOCKING + 15 RECOMMENDED + 10 NICE-TO-HAVE**. Scope **XL**. **4 BLOCKING vision** : (1) Couche 1 "silence rythmique" vs Couche 3 "continuité musicale" se contredisent dans le mix (Music -3 dB jamais auto-ducked vs clac 0 dB) — fix CD : sidechain compressor sur bus Music feed depuis combat_kill, amende ADR-0009 D-1 ; (2) Multi-kill noop MVP = trou Fantasy au moment climax — fix CD : pitch-shift +2 semitones sur clac du 2e/3e kill (pas asset, pas Tier 2 deferral) ; (3) death.wav ≤ 40 ms asset-impossible perceptuellement (seuil reconnaissance timbre 60-100 ms) — fix CD : raise to 60-80 ms + overlap on first respawn frame, safe range `[40, 100]` ; (4) Decision Martin D3 pitch invariance vs identité HLM — **DÉCISION MARTIN PENDANTE**, reco CD = REOPEN D3 autoriser pitch-shift -2..-4 semitones sur combat_kill+Ambience sous slow-mo, Music protégé. **4 BLOCKING formules/spec** : F-01 division par zéro Formules 1/2/4 si knob hits 0 (silent failure), F-02 Formule 4 viole sa propre règle ligne 81 (lerp linéaire dB sur 500-2000 ms), F-03 pool_2d_size min 3 insuffisant MVP scenario (1 swoosh+1 dash+1 walljump+1 death+1 UI=5), F-04 double atténuation Formule 1+2 non documentée (player.volume_db -6 + bus.volume_db -12 = -18 dB effectif). **2 BLOCKING Godot impl** : AudioStreamPlayer3D pool parented à Node autoload (pas Node3D, spatial fragile), CONNECT_DEFERRED handler en idle frame vs Rule 4 fade en _physics_process (timestamp race 0-16 ms erreur sur fade 30 ms = 53% relative). **6 BLOCKING ACs (qa-lead)** : Open Question #9 Callable injection gate AC-AUD-04/06, dB tolerances ±1-2 non validées vs quantification AudioServer, AC-AUD-05 mécanisme assertion non spécifié (MockAudioHandler.play_3d_at_call_count), AC-AUD-08 atteint state interne privé (fragile), AC-AUD-09 resume offset untestable, AC-AUD-13 méthodologie mesure isolée audio CPU absente. **+ AC-AUD-14/15 ADVISORY→BLOCKING promotion** + 5 ACs manquants (null stream, invalid bus, pool saturation push_warning, Formule 4 boundaries, Master mute UI). **4 BLOCKING perf** : AudioServer mixer thread budget undefined, OBJECT_COUNT delta ≤+0 produira faux positifs CI, MEMORY_STATIC isolation manquante, cold-cache stream loading non testé. **5 adjudications CD vision** tranchées (death 60-80 ms+overlap, multi_kill pitch-shift, sidechain Music, pool 2D min 3→5 + 3D 8→12, naming UPPER_SNAKE_CASE) ; D3 pitch en attente Martin. **Ordre r2 imposé** : Phase A (vision : décision D3 + Fantasy rewrite + ADR-0009 amendment) → Phase B (spec : death/multi_kill/pools/OQ#6/#7/#9) → Phase C (formules+ACs : F-01/02/04 + AC observable + 5 ACs manquants + AC-14/15 BLOCKING) → Phase D (impl parallel C : pool parenting root, fade timing physics, perf metric split, bus naming). **Re-review uniquement après A+B**. Voir [review log](reviews/audio-system-review-log.md). Coordination Level GDD r4 (signal `etage_loaded`) bloquante avant Sprint Audio. Story-020 Combat reste BLOCKED jusqu'à audio-system APPROVED. Previous: Designed r1 via `/design-system audio-system` solo auto-approve 2026-04-27 — ADR-0009 Accepted 2026-04-27 binding (6 décisions D-1..D-6 + 8 VC absorbés). GDD 8 sections + Visual/Audio + UI + Cross-References + Open Questions. API canonique : autoload `AudioSystem` + helper static `AudioBuses`, 7 buses, pool 15 nodes, wall-clock fades, CONNECT_DEFERRED, 2D head-locked vs 3D positional matrix, AudioListener3D = Camera3D. 15 ACs (3 Boot/Pool + 3 Combat audio mirror + 1 Movement death + 2 Pause/resume + 4 Lint/Perf + 2 Empirical). | [audio-system.md](audio-system.md) | Game State Manager, Camera System, Level System, Player Combat, Player Movement |
| 5 | Player Movement System | Core | MVP | In Review (r3 appliqué 2026-04-21 — 5 clusters BLOCKING résolus, décisions Martin A/B/C/D propagées ; re-review fresh r4 attendue) | [player-movement-system.md](player-movement-system.md) | Input System |
| 6 | Camera System | Core | MVP | In Review (r2 — 5 BLOCKING + 6 RECOMMENDED résolus 2026-04-21, pending fresh re-review) | [camera-system.md](camera-system.md) | Player Movement System, Input System |
| 7 | Player Combat System | Gameplay | MVP | **APPROVED r6** (r5.1→r6 propagation Addendum r5.2 achevée inline 2026-04-23 solo mode : CONV-1 Basis fix via helper `_build_capsule_basis()` centralisé aux 4 occurrences, Invariant #9 duty cycle Section D.8, AC-CMB-17 clause 8, 3 décisions Martin D-r4-1/2/3 + 5 RECOMMENDED r5.2 propagées, 2 nouveaux ACs AC-CMB-47-Prelim + AC-CMB-51. 0 BLOCKING résiduel corps du GDD — voir [review log](reviews/player-combat-system-review-log.md) entries r5.2 + r6) | [player-combat-system.md](player-combat-system.md) | Player Movement, Camera |
| 8 | Checkpoint & Respawn System | Gameplay | MVP | Not Started | — | Player Combat, Level System |
| 9 | Enemy System | Gameplay | MVP | Not Started | — | Level System, Hazard System |
| 10 | Hazard System (inferred) | Gameplay | MVP | Not Started | — | Level System |
| 11 | Level System | Core | MVP | **APPROVED r3** (2026-04-23 fresh full multi-specialist review — 3 agents game-designer + godot-specialist + qa-lead parallèles — post r2 CD fixes. Verdict r2-fresh NEEDS REVISION 4 BLOCKING éditoriaux scope XS, **4/4 r3 fixes appliqués immédiatement** : AC-LVL-48 [15,30]→[15,60]m aligné F5 (cross-model 3× — double-shaft 40m Fantasy-légal débloqué), AC-LVL-26 THEN reformulée observable-only + raisonnement EC-11 (ordre natif autoload Godot, pas `call_deferred`), AC-LVL-33 retiré (supersédé AC-LVL-55 per-archetype), Tuning Knob `SECRET_DENSITY_DIVISOR` default 2→3 aligné F7 (Pillar 4 préservé). 5/5 fixes CD antérieurs ✅ RESOLVED CLEAN (VerticalShaftRoom/F5 multi-rise, archetypes + 4 primitives PackedScene, R-2.U/R-2.A locaux, Secret split 3 nœuds, R-4 per-archetype + OnboardingAnchors Combat Rule 16). 3 BLOCKING r2 lean antérieurs absorbés. 0 BLOCKING, 9 RECOMMENDED optionnels absorbables Sprint 1 (ConcavePolygonShape3D Jolt, OQ-3 auto-tile 3D, SHADER_BAKER_ENABLED @export garde, script conventions, API completeness). Bidirectionalité Combat Rule 16 satisfaite. Voir [review fresh](reviews/level-system-review-r2-fresh-2026-04-23.md) + [log](reviews/level-system-review-log.md). Ready pour `/create-epics level-system`. | [level-system.md](level-system.md) | Game State Manager |
| 12 | Credit Economy | Economy | MVP | Not Started | — | Enemy System, Secret System |
| 13 | Upgrade System | Progression | MVP | Not Started | — | Player Movement, Save/Load |
| 14 | Shop System | Economy | MVP | Not Started | — | Credit Economy, Upgrade System, Menu System |
| 15 | Secret System | Gameplay | MVP | Not Started | — | Level System, Credit Economy |
| 16 | Boss System | Gameplay | Full Vision | Not Started | — | Player Combat, Enemy System |
| 17 | HUD System (inferred) | UI | MVP | Not Started | — | Credit Economy, Player Combat |
| 18 | Menu System (inferred) | UI | MVP | Not Started | — | Game State Manager |
| 19 | VFX & Feedback System (inferred) | UI | MVP | Not Started | — | Player Combat, Enemy, Checkpoint |
| 20 | Accessibility System (inferred) | Meta | Full Vision | Not Started | — | Input, Menu, VFX |
| 21 | Tutorial / Onboarding System (inferred) | Meta | Vertical Slice | Not Started | — | Level, Player Movement, HUD |
| 22 | Speedrun & Leaderboards System | Meta | Full Vision | Not Started | — | Game State Manager, Save/Load |

**Systems explicitly excluded** (violated by anti-pillars or not relevant to solo action-platformer FPS) :
Narrative/Dialogue, Networking/Multiplayer, Crafting, Inventory (pas d'items — juste upgrades permanents), Procedural Generation (niveaux hand-crafted), Analytics/Telemetry (optionnel post-MVP seulement).

---

## Categories

| Category | Description | Systems in this project |
|----------|-------------|-------------------------|
| **Core** | Foundation systems everything depends on | Input, Game State Manager, Player Movement, Camera, Level |
| **Gameplay** | Systems that make the game fun | Player Combat, Checkpoint & Respawn, Enemy, Hazard, Secret, Boss |
| **Progression** | How the player grows over time | Upgrade System |
| **Economy** | Resource creation and consumption | Credit Economy, Shop |
| **Persistence** | Save state and continuity | Save/Load |
| **UI** | Player-facing information displays | HUD, Menu, VFX & Feedback |
| **Audio** | Sound and music systems | Audio System |
| **Meta** | Systems outside the core game loop | Accessibility, Tutorial, Speedrun & Leaderboards |

---

## Priority Tiers

| Tier | Definition | Target Milestone | Design Urgency |
|------|------------|------------------|----------------|
| **MVP** | Required for the core loop to function (tranche + bouge + achète) | Tier 1 — 4-6 semaines | Design FIRST |
| **Vertical Slice** | Required for one complete, polished area (3 étages, 3 ennemis, tuto intégré) | Tier 2 — 3 mois total | Design SECOND |
| **Alpha** | All features present in rough form (4-5 étages, 5 ennemis, pas de boss) | Tier 2.5 — 4 mois total | Design THIRD |
| **Full Vision** | Polish + meta (boss final, leaderboards, accessibility) | Tier 3 — 5-6 mois total | Design as needed |

---

## Dependency Map

### Foundation Layer (no dependencies)

1. **Input System** — toutes les actions du joueur passent par ici ; base des lectures clavier/souris
2. **Game State Manager** — orchestre scene loading, pause, run lifecycle — chaque système dépend de l'état du jeu

### Core Layer (depends on foundation)

1. **Save/Load System** — depends on: Game State Manager
2. **Audio System** — depends on: Game State Manager
3. **Level System** — depends on: Game State Manager
4. **Player Movement System** — depends on: Input System
5. **Camera System** — depends on: Player Movement System

### Feature Layer (depends on core)

1. **Player Combat System** — depends on: Player Movement, Camera
2. **Hazard System** — depends on: Level System
3. **Enemy System** — depends on: Level System, Hazard System
4. **Checkpoint & Respawn System** — depends on: Player Combat, Level System, Enemy System (reset state)
5. **Secret System** — depends on: Level System
6. **Credit Economy** — depends on: Enemy System, Secret System
7. **Upgrade System** — depends on: Player Movement, Save/Load
8. **Shop System** — depends on: Credit Economy, Upgrade System, Menu System
9. **Boss System** — depends on: Player Combat, Enemy System, Checkpoint & Respawn

### Presentation Layer (depends on features)

1. **HUD System** — depends on: Credit Economy, Player Combat
2. **Menu System** — depends on: Game State Manager, Input System
3. **VFX & Feedback System** — depends on: Player Combat, Enemy, Checkpoint & Respawn

### Polish Layer (depends on everything)

1. **Tutorial / Onboarding System** — depends on: Level, Player Movement, HUD
2. **Accessibility System** — depends on: Input, Menu, VFX, Audio
3. **Speedrun & Leaderboards System** — depends on: Game State Manager, Save/Load, Level

---

## Recommended Design Order

Dépendances d'abord, MVP avant Tier 2/3, le système à plus haut risque (Player Movement) est priorisé contre son rang strict de dépendance parce qu'un feel raté tue le projet — mieux vaut prototyper tôt quitte à itérer l'input system en parallèle.

| Order | System | Priority | Layer | Agent(s) | Est. Effort |
|-------|--------|----------|-------|----------|-------------|
| 1 | Player Movement System | MVP | Core | game-designer + systems-designer + godot-specialist | L |
| 2 | Input System | MVP | Foundation | gameplay-programmer + systems-designer | S |
| 3 | Camera System | MVP | Core | gameplay-programmer | S |
| 4 | Player Combat System | MVP | Gameplay | systems-designer + gameplay-programmer | M |
| 5 | Level System | MVP | Core | level-designer + game-designer | M |
| 6 | Hazard System | MVP | Gameplay | systems-designer | S |
| 7 | Enemy System | MVP | Gameplay | ai-programmer + systems-designer | M |
| 8 | Checkpoint & Respawn System | MVP | Gameplay | gameplay-programmer | S |
| 9 | Game State Manager | MVP | Foundation | gameplay-programmer | S |
| 10 | Save/Load System | MVP | Persistence | gameplay-programmer | S |
| 11 | Credit Economy | MVP | Economy | economy-designer | M |
| 12 | Upgrade System | MVP | Progression | game-designer + systems-designer | M |
| 13 | Shop System | MVP | Economy | economy-designer + ui-programmer | S |
| 14 | Secret System | MVP | Gameplay | level-designer + game-designer | S |
| 15 | Audio System | MVP | Audio | audio-director + sound-designer | S |
| 16 | HUD System | MVP | UI | ux-designer + ui-programmer | S |
| 17 | Menu System | MVP | UI | ux-designer + ui-programmer | S |
| 18 | VFX & Feedback System | MVP | UI | technical-artist | M |
| 19 | Tutorial / Onboarding | VS | Meta | level-designer + ux-designer | S |
| 20 | Boss System | Full Vision | Gameplay | systems-designer + ai-programmer | M |
| 21 | Accessibility System | Full Vision | Meta | accessibility-specialist | M |
| 22 | Speedrun & Leaderboards | Full Vision | Meta | game-designer + gameplay-programmer | M |

**Effort legend** : S = 1 session, M = 2-3 sessions, L = 4+ sessions.

**Design en parallèle possible** : #5-8 peuvent être conçus en parallèle après #4. #16-18 peuvent être conçus en parallèle après #15. #20-22 sont indépendants entre eux.

---

## Circular Dependencies

Aucune dépendance circulaire détectée.

Cas potentiellement ambigu résolu : **Upgrade System ↔ Player Movement System** est unidirectionnel — Upgrade modifie les capacités de Movement via une interface de capacités (addition de dash/double-jump/wall-run comme flags ou ability components), pas via un appel croisé. Player Movement ignore l'existence d'Upgrade System.

---

## High-Risk Systems

| System | Risk Type | Risk Description | Mitigation |
|--------|-----------|------------------|------------|
| **Player Movement System** | Design + Technique | Feel = seul différenciateur de FLOW. Input delay > 1 frame = jeu mort à 10 minutes. Hypothèse core du concept. | **Prototyper en premier** (dossier `prototypes/movement-katana/` déjà existant — documenter et itérer). Design-doc et prototype en parallèle. |
| **Player Combat System** | Technique | Tunneling hitbox à haute vitesse angulaire (dash + wall-run + katana court). | Continuous collision detection (Jolt supporte), tester à vitesse max pendant le prototype movement. |
| **Credit Economy** | Design | Trop rares = frustration, trop denses = progression trop rapide. Calibration par playtest uniquement. | Variables data-driven (tuning knobs dans GDD), itération systématique, 3 profils économiques à tester. |
| **Boss System** | Design | Barre de vie multi-hits risque de casser le rythme staccato. Asymétrie assumée mais fragile. | Prototyper tôt en Tier 3 (cf. concept Design Risks). Contraindre à 3-5 fenêtres d'exécution courtes, pas de DPS check. |
| **Upgrade System** | Design | Taille du moveset final (5 vs 8 upgrades) non tranchée — playtest dépendant. | Architecture extensible (data-driven) dès le départ. Valider le nombre à la fin du Vertical Slice. |

---

## Progress Tracker

| Metric | Count |
|--------|-------|
| Total systems identified | 22 |
| Design docs started | 7 |
| Design docs reviewed | 4 |
| Design docs approved | 3 |
| MVP systems designed | 7/17 |
| Vertical Slice systems designed | 0/1 |
| Full Vision systems designed | 0/4 |

---

## Next Steps

- [ ] Lancer `/design-system player-movement-system` en premier (risque #1)
- [ ] Prototyper en parallèle dans `prototypes/movement-katana/` (déjà amorcé)
- [ ] Run `/design-review design/gdd/player-movement-system.md` après rédaction
- [ ] Enchaîner #2-8 selon l'ordre recommandé
- [ ] Run `/review-all-gdds` après les 17 MVP systems
- [ ] Run `/gate-check pre-production` quand MVP systems approuvés
