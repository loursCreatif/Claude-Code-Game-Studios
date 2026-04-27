# Epic: Level System

> **Layer**: Core
> **GDD**: design/gdd/level-system.md
> **Architecture Module**: LevelSystem (Node3D racine étage `res://scenes/levels/etage_NN.tscn` — voir architecture.md §4.3)
> **Status**: Ready
> **Stories**: 22 created — Sprint 1 priority C1 (001-008) + C5 (009) ; C2 (010-012) ; C3 (013-014, 021) ; C4 (015-016, 017) ; C6 (018) ; C7 (019) ; C8 (020) ; V-1/V-5 (022)
> **Manifest Version**: 2026-04-23
> **Engine Risk**: MEDIUM (Jolt CCD EC-8 CLAIM-UNVERIFIED — benchmark prototype Sprint 1 requis ; Forward+/Chrome Zen primitives LOW ; D3D12 indirect via Rendering layer déjà Camera-VR2)

## Stories

| # | Story | Type | ADR | Status |
|---|-------|------|-----|--------|
| 001 | Level scene root + LevelState enum + PlayerStart discovery | Logic | ADR-0001, ADR-0005 | Complete |
| 002 | load_etage() threaded + UNLOADED → LOADING → ACTIVE + level_active CONNECT_DEFERRED | Integration | ADR-0005, ADR-0007 | Complete |
| 003 | unload_current() + UNLOADING + level_unloading + concurrent-load reject | Integration | ADR-0005, ADR-0007 | Ready |
| 004 | level_load_failed (EC-3) + level_load_slow advisory (EC-10) | Integration | ADR-0005, ADR-0007 | Ready |
| 005 | EtageExitTrigger Area3D + etage_completed + ACTIVE → UNLOADING | Integration | ADR-0005 | Ready |
| 006 | Complete reset on reload (EC-12) + quit-to-menu | Integration | ADR-0007 | Ready |
| 007 | room_entered signal (RoomTrigger Area3D + tree order + NaN guard) | Integration | ADR-0005 | Ready |
| 008 | player_out_of_world signal + WorldBoundsVolume BoxShape3D | Integration | ADR-0001, ADR-0005 | Ready |
| 009 | Spatial lookups API (checkpoint/enemy/hazard/tutorial) | Logic | ADR-0005 | Ready |
| 010 | Canonical hierarchy + validate_scene_hierarchy() lint | Config/Data | — | Ready |
| 011 | RoomArchetype enum + @export + diversity lint (S-1..S-5) | Config/Data | — | Ready |
| 012 | 4 PackedScene primitives + per-archetype R-4 budgets + validate_room_archetype_invariants | Config/Data | — | Ready |
| 013 | Layers 4+5 discipline + validate_collision_layers + wall thickness ≥ 0.3m | Config/Data | ADR-0001 | Ready |
| 014 | Wall-run surface F8 + door width F1 + StaticBody count + EC-8 Jolt CCD benchmark | Integration | ADR-0001 | Ready |
| 015 | Draw call budget F2 ≤ 350/etage + sous-cap 170 peers + 500-frame gate | Logic | ADR-0003 | Ready |
| 016 | VRAM + RAM + combined ≤ 70 MB F6 + memory stability 60s | Logic | ADR-0003 | Ready |
| 017 | Load time F4 ≤ 1000 ms + frame-time intra-room + transition stutter | Logic | ADR-0001, ADR-0003 | Ready |
| 018 | Secret triplet + required_ability + validate_secret_lures + get_secret_slots | Logic | — | Ready |
| 019 | OnboardingAnchors étage 1 + validate_onboarding_anchors + get_onboarding_anchors | Config/Data | — | Ready |
| 020 | Formula lints aggregate (F3 checkpoint + F5 etage height + F7 secret density + room count) | Config/Data | — | Ready |
| 021 | validate_checkpoint_anchors (EC-7) + CheckpointVolume↔Anchor pair coherence | Logic | ADR-0001 | Ready |
| 022 | Chrome Zen shader + texture atlas + material tagging + level.yaml tuning + thread safety | Config/Data | ADR-0003, ADR-0005 | Ready |

**Totaux** : 22 stories (2 Complete + 20 Ready — ADR-0007 Accepted 2026-04-23 r2) | 10 Integration, 7 Logic, 5 Config/Data

**Sprint 1 priorité** : C1 complet (001-008 lifecycle) + C5 (009 spatial API) démarrables immédiatement. C2 (010-012 authoring) + C3 (013-014, 021) en parallèle. C4 (015-017), C6 (018), C7 (019), C8 (020), V-presentation (022) post C1+C2+C3 vert.

## Overview

LevelSystem est le **conteneur spatial** de la run : il héberge la géométrie
hand-crafted d'un étage de la tour Arasaka et publie aux peers (Checkpoint,
Enemy, Hazard, Secret, HUD, Tutorial, Audio, VFX) les ancres spatiales dont
ils dépendent (PlayerStart, CheckpointSlots, EnemySlots, HazardSlots,
SecretSlots split `lure`/`collect_volume`/`anchor`, OnboardingAnchors,
TutorialAnchors). Il **n'implémente aucun gameplay** de ses occupants —
séparation stricte producer/consumer. Le scope MVP est un **étage unique de
8-10 salles** assemblées en primitives Chrome Zen (cubes, plans, rampes,
shader flat unique ; zéro mesh importé), structurées par 4 archetypes typés
(`TRAVERSAL` / `COMBAT` / `SHAFT` / `SECRET_HUB`) et 4 primitives PackedScene
(`Mezzanine`, `Atrium`, `ShaftConnector`, `VerticalShaftRoom`). La machine
d'état Level (`UNLOADED → LOADING → ACTIVE → UNLOADING → UNLOADED`) est
pilotée par GameStateManager via `load_etage(id)` / `unload_current()` et
publie `level_active(etage_id, player_start)` en `call_deferred` pour
garantir l'ordre `_ready()` des peers avant binding (T-2). La géométrie
statique vit sur `LAYER_ENVIRONMENT = 4` (walk/run/wall-run), les triggers
non-solides sur `LAYER_INTERACTIVE = 5` (respawn volumes, secrets, portes).
Budgets : draw calls ≤ 350/étage (F2, sous-cap 170 dc peers), VRAM ≤ 50 MB
+ RAM ≤ 20 MB, load ≤ 1000 ms (F4), audio F5 hauteur étage ∈ [15, 30] m
(multi-rise Shaft `ETAGE_HEIGHT_MAX = 60 m`). Aucun ADR dédié Level n'est
nécessaire au MVP — les contraintes temps-réel sont absorbées par
ADR-0001 (physics 60 Hz Jolt) et ADR-0003 (rendering latency).

## Governing ADRs

| ADR | Decision Summary | Engine Risk |
|-----|------------------|-------------|
| ADR-0001 : Physics Rate 60 Hz + Jolt | `_physics_process` 60 Hz autorité gameplay ; Jolt default 4.6 ; collision layers 4 (environment) et 5 (interactive) ; ShapeCast3D/Area3D discipline. Level consume : `PhysicsServer3D.is_body_excluded_from_physics` pour `Unloading` atomicité. | HIGH (Jolt default 4.6 — CCD EC-8 CLAIM-UNVERIFIED) |
| ADR-0003 : Rendering & Display Latency | Forward+ renderer ; Shader Baker 4.6 export ; budget 8 ms render / 16.6 ms frame ; D3D12 Windows default 4.6 (VR-2 advisory). Level contrainte : F2 draw calls ≤ 350 Level + 150 peers = 500 hard cap ; primitives statiques précuites Shader Baker. | HIGH (VR-2 D3D12, VR-1 Shader Baker — advisory Sprint 1 couverte par Camera epic, pas blocker Level) |
| ADR-0005 : Movement Signals Architecture | `CONNECT_DEFERRED` critères a-d (ADR-0005 D-5) ; typed signals outbound-only ; pas d'EventBus autoload. Level applique D-5 sur `level_active` (call_deferred car : peers doivent être `_ready()` avant binding ; payload Vector3 ; potentiel re-entry si peer appelle back-lookup). `player_out_of_world`, `room_entered(int, int)`, `level_unloading`, `etage_completed`, `level_load_failed`, `level_load_slow` = signals typés Level → peers. | LOW (consumer pattern Foundation, pas de changement 4.4/4.5/4.6 sur signaux) |
| ADR-0007 : Game State Manager & Scene Transition Pattern (**Accepted 2026-04-23 r2**) | Autoload GSM orchestrant Level lifecycle : `request_scene_transition()` → `LevelSystem.load_etage(id)` ; `process_mode` discipline pause ; ordre `_ready()` autoloads (InputManager → GSM → SaveLoad → Audio). Couvre TR-lvl-001/028/029/033/034 (gsm_level_orchestration contract). | LOW (pattern autoload + ResourceLoader stable 4.0-4.6) |

## GDD Requirements

### Coverage Summary

- **Total TRs**: 45 (TR-lvl-001 … TR-lvl-045)
- **Covered by Accepted ADRs**: 19 TRs (via ADR-0001, ADR-0002, ADR-0003, ADR-0005)
- **Covered by ADR-0007 (Proposed)**: 5 TRs (TR-lvl-001 partiel, 028, 029, 033, 034) — **Story status = Blocked jusqu'à ADR-0007 Accepted**
- **Untraced (authoring invariants, non-structurels)**: 22 TRs — implémentables depuis GDD directement sans ADR requis (voir §Known Gaps)

### TR Clusters (for story breakdown)

| Cluster | TR-IDs | Scope | ADR Coverage |
|---------|--------|-------|--------------|
| **C1. Lifecycle + State Machine** | TR-lvl-001, 002, 021, 023, 026, 028, 029, 031, 033, 034, 044 | `load_etage` / `unload_current`, enum `LevelState`, T-1..T-4 transitions, `level_active` call_deferred, `level_unloading`, `etage_completed`, `level_load_failed`, `level_load_slow`, `room_entered` | ADR-0005 ✅ (signals) + ADR-0007 ⏸ (Proposed, 5 TRs blocked) |
| **C2. Scene Structure + Archetypes** | TR-lvl-006, 016, 019 | Hierarchy `StaticEnvironment` / `InteractiveVolumes` / `SpawnMarkers` / `EtageExitTrigger` ; 4 archetypes `{TRAVERSAL, COMBAT, SHAFT, SECRET_HUB}` ; 4 primitives PackedScene ; lint pre-build | ADR-0002 ✅ (scene tree discipline) + ADR-0001 ✅ (physics bodies) |
| **C3. Collision Layers + Physics** | TR-lvl-007, 008, 011, 013, 038, 039 | LAYER_ENVIRONMENT=4 (walk/wall-run), LAYER_INTERACTIVE=5 (triggers signal-only), bitmask API `set_collision_layer_value(N)`, Jolt CCD EC-8 benchmark, WorldBoundsVolume BoxShape3D | ADR-0001 ✅ |
| **C4. Budgets Rendering + Load** | TR-lvl-003, 005, 024, 035, 036 | Draw calls ≤ 350 (F2) + sous-cap 170 dc peers, VRAM ≤ 50 MB / RAM ≤ 20 MB, Load ≤ 1000 ms (F4), physics p50 ≤ 12 ms / p99 ≤ 14 ms intra-Level | ADR-0003 ✅ + ADR-0001 ✅ |
| **C5. Spatial Lookups API** | TR-lvl-022, 025, 027, 030, 032 | `get_checkpoint_slots()`, `get_enemy_slots()`, `get_hazard_slots()`, `get_secret_slots()`, `get_tutorial_anchor()`, `get_onboarding_anchors()` | No direct ADR — GDD R-3 spec (non-structurel) |
| **C6. Secret Split Contract (r2 fix #4)** | TR-lvl-017, 018, 020, 040 | SecretLureMarker / SecretCollectVolume / SecretAnchor tuple split ; `required_ability: StringName` enum {none, dash, double_jump, wall_run, wall_run_long} ; lint orphelin ; contrainte économique ≥ 1 secret wall_run | No direct ADR — GDD R-3 + CO contract spec |
| **C7. Onboarding Contract (r2 fix #5)** | TR-lvl-042, 043, 045 | OnboardingAnchors salle 3 étage 1 : `first_enemy_sightline` + `safe_zone_center` ; bridge Combat Rule 16 ; existence-check side peer | No direct ADR — Combat/Level cross-GDD contract |
| **C8. Formulas + Invariants** | TR-lvl-004, 009, 010, 012, 014, 015, 037, 041 | F1 KATANA_REACH 1.8 m, F2 draw budget, F3 checkpoint spacing, F5 étage height multi-rise, F6 bounding volume 5000 m³, F7 secret density, F8 wall-run reach derived | No direct ADR — formulas computed from constants |

## Known Gaps

### 1. ADR-0007 Proposed — 5 TRs Blocked

5 TRs couvertes par ADR-0007 (Game State Manager) dont le status reste
**Proposed** au 2026-04-23 : TR-lvl-001 (contrat GSM → Level), TR-lvl-028
(ordre autoload `_ready()`), TR-lvl-029 (process_mode discipline pause),
TR-lvl-033 (`request_scene_transition`), TR-lvl-034 (`state_changed` reçu
avant 1er frame PLAYING).

**Impact** : stories correspondantes au cluster C1 Lifecycle qui consomment
directement l'API GSM seront marquées **Blocked** jusqu'à promotion
ADR-0007 Proposed → Accepted via `/architecture-decision` ou re-run
`/architecture-review`. Les stories C1 portant uniquement sur la machine
d'état Level interne (enum LevelState, T-1..T-4) et les signaux outbound
(`level_active`, `level_unloading`, `room_entered`) ne sont pas bloquées —
elles dépendent d'ADR-0005 (Accepted) pour la discipline CONNECT_DEFERRED.

**Unblock path** : le GDD game-state-manager.md est Not Started (systems-index
ligne 21). ADR-0007 écrit préalablement au GDD est inhabituel mais légal
en solo mode ; il reste à l'Accepter formellement (re-run /architecture-review
ou décision explicite user pour transition Proposed → Accepted).

### 2. Jolt CCD EC-8 CLAIM-UNVERIFIED (benchmark Sprint 1)

EC-8 du GDD documente le comportement attendu *clip through wall* à
haute vélocité (dash + wall-run, ~27 m/s) avec Jolt CCD sweep. Claim
empirique **non-vérifié** au moment du GDD APPROVED r2 — nécessite
benchmark prototype Sprint 1 par lead-programmer/godot-specialist.

**Impact** : les stories C3 (collision layers) et C4 (physics budgets)
sont **Ready** — la machinerie d'encodage collision n'est pas bloquée.
Mais le story "valider EC-8 sweep Jolt CCD ne tunnel pas à 27 m/s"
reste conditionnel au benchmark. Si le benchmark échoue : amendement
R-5.6 GDD requis (WorldBoundsVolume fallback ou ShapeCast3D manuel
sur murs critiques), pas de blocker epic breakdown.

**Empirical follow-up**: aligné avec les 3 gaps ADR-0006 déjà résolus
(Gaps 2/7/8 ShapeCast3D + CapsuleShape3D basis, 2026-04-23) — même pattern
empirique runner headless `tests/performance/level_ccd_sweep_runner.gd` à
écrire Sprint 1.

### 3. 22 Authoring Invariants sans ADR (non-blocker)

22 TR-lvl sans ADR couvert sont des **invariants d'authoring** testables
directement depuis le GDD sans décision structurelle architecturale :
hiérarchie de scène obligatoire (TR-006), zéro-pad naming (TR-020),
bitmask collision layers (TR-007/008/011), SecretSlot split (TR-017/018/020),
formules F1-F8 (TR-004/009/010/012/014/015/037), OnboardingAnchors
(TR-042/043/045), Marker3D sub-budgets (TR-025/027/030/032), mesures
runtime (TR-040/041).

**Aucun blocker** — ces TRs deviennent des acceptance criteria directs
dans les stories (lint pre-build, AUTO tests, PLAYTEST evidence selon
classification Groupe A..H du GDD).

## Validation Requirements (Sprint 1)

### Blocking Sprint 1 (stories AC)

- **AC-LVL-51** — Lint checkpoint spacing `floor(N_rooms/K) ∈ [2, 3]`
  strict + cas limites K=0/K=1/K=N documentés, CI job `lint-level-invariants`
  (exécute `tools/lint/level_lint.gd`).
- **AC-LVL-52..55** — r2 CD 5 fixes : primitive `VerticalShaftRoom` authoring
  contract, hiérarchie 3D + archetypes enum, invariants locaux R-2.U/R-2.A,
  Secret tuple split lure/volume/anchor, R-4 per-archetype budget.
- **AC-LVL-46..50** — Coverage formules F3/F5/F6/F7 + diversité typologique.
- **AC-LVL-34** — Perf physics aligné Combat p50 ≤ 12 ms / p99 ≤ 14 ms
  intra-Level.
- **AC-LVL-37** — Combined memory ≤ 70 MB (20 RAM + 50 VRAM).
- **T-1..T-4** — Atomicité state machine transitions (integration tests
  GUT assert `load_etage()` rejet hors UNLOADED, etc.).
- **Signal ordering** : `level_active` via `call_deferred` publie dans la
  même tick que `add_child()` tree (ADR-0005 D-5, verification : peer
  `_ready()` → await → connect → reçoit signal).
- **Lint suite** : `validate_level_shapes()`, `validate_secret_lures()`,
  `validate_scene_hierarchy()`, `validate_collision_layers()`, `validate_checkpoint_pairs()`,
  `validate_onboarding_anchors()` — tous CI-gated.

### Advisory Sprint 1 (non-blocker Accept)

- **EC-8 Jolt CCD benchmark** (voir Known Gaps §2) — runner headless
  `tests/performance/level_ccd_sweep_runner.gd` à écrire ; amendement R-5.6
  conditionnel si échec.
- **Budget cross-cap F2 vs R-4 per-archetype** (MINOR observation review
  r2) — sous distributions S-compliant extrêmes (ex: 4 COMBAT = 356 DC
  vs cap 350), AC-LVL-55 détecte au lint. Pas d'amendement GDD requis.
- **F4 Load time** — mesure empirique `load_threaded_request` → `load_threaded_get_status`
  sur target laptop (même testbed que VR-2 D3D12). Advisory ; fallback
  sous-scene-split si > 1000 ms (OQ-1 réouverture conditionnelle).

## Definition of Done

Cet epic est complet quand :
- Toutes les stories sont implémentées, reviewées, et closed via `/story-done`
- Tous les acceptance criteria du GDD (`design/gdd/level-system.md` AC-LVL-1..55,
  Groupes A..H) sont vérifiés
- Toutes les stories Logic (lifecycle state machine, lints, formulas) ont
  passing test files dans `tests/unit/level/` + `tests/unit/lint/`
- Toutes les stories Integration (signal binding peers, spawn markers lookup,
  transitions scène) ont passing tests dans `tests/integration/level/`
- Toutes les stories Visual/Feel (Chrome Zen primitives render, room entered
  feedback audio-swap éventuel) ont evidence docs avec sign-off dans
  `production/qa/evidence/`
- Toutes les stories Config/Data (level_tuning.tres si créé, scene
  authoring invariants) ont smoke check pass
- Control Manifest v2026-04-23 Core layer rules respectés (scene tree
  ADR-0002, `_physics_process` autorité ADR-0001, signal CONNECT_DEFERRED
  ADR-0005 D-5)
- Benchmark EC-8 Jolt CCD exécuté et documenté dans
  `docs/architecture/benchmarks/level-ccd-sweep-[date].md`
- Lint CI job `lint-level-invariants` vert (tools/lint/level_lint.gd)
- Story bloquée TR-lvl-001/028/029/033/034 débloquée par ADR-0007 Accepted
  (ou justification amendement Level si ADR-0007 mute matériellement)

## Cross-References

- GDD : `design/gdd/level-system.md`
- Reviews : `design/gdd/reviews/level-system-review-r2-fresh-2026-04-23.md`, `design/gdd/reviews/level-system-review-log.md`
- ADRs Accepted : `docs/architecture/adr-0001-physics-rate-60hz.md`, `docs/architecture/adr-0002-camera-scene-tree-cameraarm.md`, `docs/architecture/adr-0003-rendering-latency.md`, `docs/architecture/adr-0005-movement-signals-architecture.md`
- ADR Proposed (unblock required) : `docs/architecture/adr-0007-game-state-manager.md`
- Architecture module : `docs/architecture/architecture.md` §4.3 Feature Layer (Level listé §4.3 LevelSystem ownership)
- Control Manifest : `docs/architecture/control-manifest.md` (Core Layer section, Manifest Version 2026-04-23)
- TR Registry : `docs/architecture/tr-registry.yaml` (TR-lvl-001..045)
- Architecture review : `docs/architecture/architecture-review-2026-04-23.md`
- Registry : `design/registry/entities.yaml` (constants KATANA_REACH, RESPAWN_DELAY, LAYER_ENVIRONMENT, LAYER_INTERACTIVE, ETAGE_HEIGHT_MAX)
- Upstream epics : — (aucune Core/Foundation complete préalable requise au boot : Level charge une scène indépendante ; GSM epic attend GDD + ADR-0007 Accepted)
- Downstream epics (futurs) : Checkpoint, Hazard, Enemy, Secret, HUD, Tutorial, Audio, VFX (tous attendent leurs GDDs respectifs)

## Stories

| # | Story | Cluster | Type | Status |
|---|-------|---------|------|--------|
| 001 | Level scene root + LevelState enum + PlayerStart discovery | C1 | Logic | Complete |
| 002 | load_etage threaded + UNLOADED→LOADING→ACTIVE + level_active | C1 | Integration | Complete |
| 003 | unload_current + UNLOADING + level_unloading + concurrent reject | C1 | Integration | Ready |
| 004 | level_load_failed + level_load_slow advisory | C1 | Integration | Ready |
| 005 | EtageExitTrigger + etage_completed + ACTIVE→UNLOADING | C1 | Integration | Ready |
| 006 | Complete reset on reload (EC-12) + quit-to-menu | C1 | Integration | Ready |
| 007 | room_entered signal (RoomTrigger + tree order + NaN guard) | C1 | Integration | Ready |
| 008 | player_out_of_world + WorldBoundsVolume BoxShape3D | C1 | Integration | Ready |
| 009 | Spatial lookups API (checkpoint/enemy/hazard/tutorial) | C5 | Logic | Ready |
| 010 | Canonical hierarchy + validate_scene_hierarchy lint | C2 | Logic | Ready |
| 011 | RoomArchetype enum + @export + diversity lint | C2 | Logic | Ready |
| 012 | 4 PackedScene primitives + R-4 archetype budgets + validator | C2 | Logic | Ready |
| 013 | Layers 4+5 discipline + validate_collision_layers + wall thickness | C3 | Logic | Ready |
| 014 | Wall-run F8 + door F1 + StaticBody count + EC-8 Jolt CCD bench | C3 | Integration | Ready |
| 015 | Draw call budget F2 ≤ 350 + sous-cap 170 peers | C4 | Logic | Ready |
| 016 | VRAM + RAM + combined ≤ 70 MB + 60s stability | C4 | Logic | Ready |
| 017 | Load time F4 ≤ 1000 ms + frame time p99 gate | C4 | Logic | Ready |
| 018 | Secret split (Lure/Volume/Anchor) + required_ability lint | C6 | Logic | Ready |
| 019 | Onboarding anchors lint (FirstEnemySightline + SafeZone) | C7 | Logic | Ready |
| 020 | Formula lints aggregate (F1..F8) | C8 | Logic | Ready |
| 021 | validate_checkpoint_anchors (EC-7 inside static geometry) | C3 | Logic | Ready |
| 022 | Chrome Zen shader + texture atlas tuning (V-1/V-5) | V-presentation | Config/Data | Ready |
| 023 | TR-lvl-039 full automated CCD gate (gameplay scenario + baseline lock) | C3 | Integration | Ready |

## Next Step

Sprint 1 priorité : C1 (stories 001-008) + C2 (010-012) + C3 (013-014, 021) —
fondations dont dépendent C4..C8. Stories 015-017 (C4 budgets) et 018-020
(C6-C8) parallélisables après C1-C3 vert.

ADR-0007 GSM **Accepted** (promu 2026-04-23 r2) : les 5 TRs autrefois
Blocked (TR-lvl-001/028/029/033/034) sont maintenant Ready. ADR-0011 Level
Scene **Proposed** : les stories C2 (010-012) embarquent les invariants
GDD R-1 r2 directement sans attendre promotion — si ADR-0011 mute
matériellement lors de son Accept, les stories seront amendées.

Lead-programmer/godot-specialist exécute le benchmark EC-8 Jolt CCD en
marge de Sprint 1 (intégré à story-014). Runner headless
`tests/performance/level_ccd_sweep_runner.gd` — follow-up empirique,
non-blocker.

Run `/story-readiness production/epics/level-system/story-001-level-scene-root-state-machine.md`
puis `/dev-story` pour démarrer l'implémentation.
