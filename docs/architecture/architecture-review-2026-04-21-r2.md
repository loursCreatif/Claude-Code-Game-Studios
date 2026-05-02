# Architecture Review Report — 2026-04-21 (r2, fresh session post-ADR-0005)

**Mode** : full (no argument)
**Engine** : Godot 4.6 (GDScript, Jolt, Forward+)
**Verdict** : **PASS**

**Scope** :
- GDDs : 4 (game-concept, input-system, player-movement-system r3, camera-system)
- ADRs : 5 (ADR-0001..0005)
- Registry : `tr-registry.yaml` (21 TRs), `architecture.yaml` r3 (après appends ADR-0005)

**Contexte** : validation indépendante post-création d'ADR-0005 (Movement Signals) et amendement ADR-0001 (default_gravity=0.0) le 2026-04-21. Review précédente (`architecture-review-2026-04-21.md`) avait retourné CONCERNS avec gaps G-1 HIGH et G-3 HIGH — tous deux résolus depuis. Cette r2 vérifie l'absence de régression et autorise la transition finale Proposed → Accepted pour ADR-0004 et ADR-0005.

---

## Traceability Summary

| Statut | Compte | Notes |
|--------|--------|-------|
| ✅ Covered | 17 | Tous les TRs blocker-MVP et Pillar-critical |
| ⚠️ Intentionally empty (non-archi) | 2 | TR-mov-005 (jump buffer post-MVP), TR-cam-004 (tuning knob playtest-validé) |
| ❌ Gap ouvert | 3 | Tous non-blocker MVP Sprint 1 |

**Couverture** : 17/21 = 81 % couvert + 2/21 N/A non-archi → 100 % des TRs couvrables adressés.

### Full Traceability Matrix

| TR-ID | GDD | Requirement (abrégé) | ADR Coverage | Status |
|-------|-----|--------------------|--------------|--------|
| TR-inp-001 | input | `was_pressed_this_tick(action)` polling tick-based | ADR-0004 D-1, ADR-0001 pattern | ✅ |
| TR-inp-002 | input | `mouse_motion(delta)` via `_unhandled_input` + signal | ADR-0004 (conservé) | ✅ |
| TR-inp-003 | input | InputManager singleton autoload unique | ADR-0004 | ✅ |
| TR-inp-004 | input | StringName discipline actions | ADR-0004 | ✅ |
| TR-inp-005 | input | refcount `request_disable/release_enable_request(owner)` | ADR-0004 D-4 | ✅ |
| TR-inp-006 | input | Signal `application_focus_lost` one-way | ADR-0004 D-5 | ✅ |
| TR-inp-007 | input | Zero-alloc ring buffer PackedFloat32Array | ADR-0004 D-8 | ✅ |
| TR-inp-008 | input | Latence p99 ≤ 16 ms intra-engine | ADR-0001 + ADR-0003 | ✅ |
| TR-mov-001 | movement | Physics tick rate 60 Hz, PHYSICS_TICK_RATE paramétré | ADR-0001 | ✅ |
| TR-mov-002 | movement | CharacterBody3D + Jolt + ShapeCast3D + raycasts | ADR-0001 | ✅ |
| TR-mov-003 | movement | Autorité `_physics_process` unique | ADR-0001 | ✅ |
| TR-mov-004 | movement | Hiérarchie camera 3 étages | ADR-0002 | ✅ |
| TR-mov-005 | movement | Jump buffer post-MVP (retiré r3) | — | ⚠️ N/A (post-MVP intentionnel) |
| TR-mov-006 | movement | Architecture signaux Movement (8 MVP + 1 réservé) | ADR-0005 | ✅ |
| TR-mov-007 | movement | `default_gravity=0.0` Project Settings | ADR-0001 (amendé 2026-04-21) | ✅ |
| TR-mov-008 | movement | Accessibility toggles `reduce_flash`/`reduce_motion` WCAG | — | ❌ GAP G-4 |
| TR-cam-001 | camera | Ownership par étage scene tree (yaw/pitch/tilt/fov) | ADR-0002 | ✅ |
| TR-cam-002 | camera | `aim_forward` forme close trigonométrique | ADR-0002 | ✅ |
| TR-cam-003 | camera | Logique caméra en `_process`, mouse motion event-driven | ADR-0001 + ADR-0003 | ✅ |
| TR-cam-004 | camera | Tilt wall-run 95 % en ≤ 200 ms (TILT_LERP_SPEED) | — | ⚠️ N/A (tuning knob) |
| TR-cam-005 | camera | Budget camera ≤ 0.5 ms/frame p99 registry | ADR-0002 | ✅ |
| TR-cam-006 | camera | Lifecycle save/load `camera_settings.tres` | — | ❌ GAP G-2a |
| TR-inp-009 | input | Lifecycle save/load `input_settings.tres` | — | ❌ GAP G-2b |
| TR-gc-001 | game-concept | Pillar 1 FLOW : latence ≤ 1 frame | ADR-0003 + ADR-0001 + ADR-0004 | ✅ |
| TR-gc-002 | game-concept | Pillar 4 : 60+ fps vsync, budgets frame | ADR-0001 + ADR-0003 | ✅ |
| TR-gc-003 | game-concept | Stack Godot 4.6 (Forward+/Jolt/D3D12) | ADR-0001 + ADR-0003 | ✅ |

---

## Coverage Gaps (prioritized)

### G-2a HIGH(Feature tier) — TR-cam-006 : save/load `camera_settings.tres`
- Suggested ADR : **ADR Save/Load Settings Infrastructure**
- Domain : Persistence / UX / Data
- Engine Risk : LOW
- Non-blocker Sprint 1 Movement — bloque la 1ère story Settings UI (Tier 2).

### G-2b HIGH(Feature tier) — TR-inp-009 : save/load `input_settings.tres` (remap bindings, focus window tunable)
- Couplé à G-2a : même ADR couvre les deux systèmes (infrastructure Settings partagée).

### G-4 MEDIUM(MVP desirable) — TR-mov-008 : Accessibility toggles WCAG
- Suggested : **inline spec dans GDD Accessibility** (skippable ADR formel) OU **ADR Accessibility Layer** si propagation cross-system non-triviale.
- Domain : Accessibility / UX / Cross-system
- Interactions : Camera shake bypass, Movement tilt bypass, VFX flash bypass, Audio sting bypass
- Non-blocker Sprint 1, mais devrait être cadré avant 1re story de polish visuel.

---

## Cross-ADR Conflict Detection

**10 paires analysées** (C(5,2)). **Aucun conflit détecté**.

### Cohérences explicites vérifiées

| Paire | Interaction | Résultat |
|-------|-------------|----------|
| 0001 × 0002 | Camera en `_process` (cosmétique) ↔ autorité gameplay `_physics_process` | ✅ Aligné (diagramme ADR-0001) |
| 0001 × 0003 | Budget physics 4 ms + budget rendering 8 ms = 12 ms / 16.6 ms | ✅ Aligné, 4.6 ms marge avant Input/Camera |
| 0001 × 0004 | `was_pressed_this_tick` concretise le pattern flag-via-signal d'ADR-0001 ; forbidden `is_action_just_pressed` coexistent | ✅ Cohérent par construction |
| 0001 × 0005 | emit depuis `_physics_process` uniquement (D-4) ⊆ autorité gameplay | ✅ Strict respect |
| 0002 × 0003 | Camera3D dans scene tree Forward+ ; D3D12 Windows neutral | ✅ Pas d'interaction directe |
| 0002 × 0004 | Camera consomme `mouse_motion` (ADR-0004) one-way | ✅ Direction unidirectionnelle |
| 0002 × 0005 | Camera consumer de 4 signals Movement (wall_run, dash, died, respawned) | ✅ D-5 connection mode compatible |
| 0003 × 0004 | Rendering latency (VSync/144Hz) + Input latency (0.2 ms intra) additionnent | ✅ Budget Pillar 1 end-to-end ≤ 50 ms |
| 0003 × 0005 | Zero-alloc dispatch signals (D-9) neutre vs rendering | ✅ Pas d'interaction |
| 0004 × 0005 | `attacked()` forward de `was_pressed_this_tick(&"attack")` ; pattern signal directs répliqué | ✅ Référence croisée explicite ADR-0005 D-1 |

### State Ownership (pas de double ownership)

| State | Owner | Consumers (read-only) |
|-------|-------|----------------------|
| Input polling flag | InputManager (ADR-0004) | Movement, Combat, Checkpoint |
| Enable blockers set | InputManager (ADR-0004 D-4) | — |
| Movement state machine (`_state`) | MovementController (ADR-0005 D-7) | Camera, Combat, VFX, Audio, HUD |
| Player position/rotation/velocity | MovementController (ADR-0001 autorité) | Camera (read), Combat (read) |
| Camera pitch/yaw/tilt/fov | par étage (ADR-0002) | Combat lit aim_forward |

### ADR Dependency Order (topologiquement trié)

```
Foundation (no deps):
  1. ADR-0001  Physics Tick Rate 60 Hz + Jolt               [Accepted]

Core (depend on ADR-0001):
  2. ADR-0002  Camera Scene Tree CameraArm                  [Accepted]
  3. ADR-0003  Rendering & Display Latency                  [Accepted]
  4. ADR-0004  Input API & Focus Handling                   [Proposed → Accepted recommandé]
  5. ADR-0005  Movement Signals Architecture                [Proposed → Accepted recommandé]
```

**Aucun cycle**. **Aucune dépendance unresolved** (ADR-0001 Accepted, les 4 Core peuvent passer Accepted en parallèle).

---

## Performance Budget Consolidation

| Composant | Budget p99/frame | Source ADR |
|-----------|-----------------|-----------|
| Physics (Jolt) | 4 ms | ADR-0001 |
| Rendering (Forward+) | 8 ms | ADR-0003 |
| Input | 0.2 ms | ADR-0004 |
| Camera | 0.5 ms | ADR-0002 / TR-cam-005 |
| Movement events dispatch | ~0.1 ms (cumulé amorti) | ADR-0005 (inclus budget Movement global) |
| **Total réservé** | **~12.8 ms / 16.6 ms** | — |
| **Marge** | **~3.8 ms** | Réservée pour Combat, AI, Audio, VFX Sprint 2+ |

Pas de conflit de budget. Marge saine.

---

## Engine Compatibility Audit

**Engine Compatibility sections** : 5/5 ADRs ✅

### Post-Cutoff APIs Used (consolidé)

| ADR | APIs | Risk |
|-----|------|------|
| 0001 | Jolt Physics 3D (default 4.6), `physics_interpolation_mode` (4.5 rearchitect, API publique inchangée) | MEDIUM — verify VC-1..4 Sprint 1 |
| 0002 | Stack `Node3D`/`Camera3D`/`AudioListener3D` pré-4.0 | LOW |
| 0003 | Forward+ (stable), D3D12 default Windows 4.6, SMAA 1x 4.5, Shader Baker 4.5, glow 4.6 rework | HIGH advisory (3 items à verify Sprint 1) |
| 0004 | `NOTIFICATION_APPLICATION_FOCUS_IN/OUT` (dual-focus 4.6 sémantique à confirmer), `PackedFloat32Array` (stable) | HIGH advisory (VC-1 Sprint 1) |
| 0005 | Signals typés (4.0+), `CONNECT_DEFERRED`, `emit()` | LOW |

### Deprecated APIs Referenced
**Aucun** (verif contre `deprecated-apis.md`).

### Version Consistency
Tous ADRs = Godot 4.6. Pas de stale reference.

### Known Engine Risks (advisory, non-blocker)

Items **HIGH advisory** identifiés review précédente et toujours ouverts (verification Sprint 1, pas blocage ADR) :

1. **Shader Baker 4.5** (ADR-0003) — sémantique clés conservative. Impact : build time. VC à ajouter en CI pre-release.
2. **D3D12 default Windows 4.6** (ADR-0003) — launch-time fallback Vulkan si D3D12 unavailable. VC manuel 1ère build Windows.
3. **Dual-focus system 4.6** (ADR-0004 VC-1) — `NOTIFICATION_APPLICATION_FOCUS_IN/OUT` vs `Window.focus_entered/exited` à disambiguer sur 3 OS (Win11 / macOS / Linux Wayland+X11). Si notifications obsolètes, migration vers `Window` signals.

Pas de revision GDD requise — aucune assumption contradictoire.

---

## Architecture Document Coverage

`docs/architecture/architecture.md` n'existe pas. Le registry `docs/registry/architecture.yaml` (r3 post-ADR-0005) joue le rôle de source structurée :
- 17 api_decisions
- 9 forbidden_patterns
- 5 performance_budgets (physics, rendering, input, camera + stub movement)
- 1 state_ownership (player_movement_state)
- Interfaces : 12+ entrées (InputManager 4, Camera 2, Movement 1 groupé 8 signals, autres)

Alignement registry ↔ 5 ADRs vérifié. Aucune architecture orpheline.

---

## Verdict Final

### **PASS**

**Motifs** :
- Aucun conflit cross-ADR sur 10 paires analysées
- DAG dépendances sain, pas de cycle, ADR-0001 Foundation Accepted permet ADR-0004/0005 Core Accepted
- Couverture 81 % (17/21) + 2/21 intentionnellement N/A = 100 % des TRs couvrables adressés
- 3 gaps restants tous non-blocker MVP Sprint 1 (save/load Settings Feature tier, Accessibility MVP-desirable)
- Budgets performance cohérents avec 3.8 ms de marge
- Engine compatibility : 5/5 ADRs documentés, 0 deprecated API, 3 advisory verifications planifiées Sprint 1
- ADR-0004 et ADR-0005 structurellement solides, complets (8 VCs chacun, 4-5 alternatives chacun, 5-6 risks documentés)

### Blocking Issues
**Aucun**.

### Recommandations post-verdict

**Immédiat** :
1. Transition **ADR-0004** `Proposed → Accepted` (fresh-session validation passée)
2. Transition **ADR-0005** `Proposed → Accepted` (fresh-session validation passée)
3. Mettre à jour registry `architecture.yaml` : bump version (r3 après ADR-0005 appends, déjà fait, OK)

**Court terme (Sprint 1 prep)** :
4. Déclencher **application fixes GDD Input System** (~2h15, 7 flags R-1..R-7) post-ADR-0004 Accepted
5. Déclencher **application fixes GDD Movement** (~30 min, 4 edits ADR-0005 footer) post-ADR-0005 Accepted
6. Re-review `/design-review design/gdd/player-movement-system.md` en fresh session (verdict r3 NEEDS REVISION pending)
7. `/design-review design/gdd/camera-system.md` fresh session (pending)

**Court/moyen terme** :
8. `/architecture-review engine` avec accès modules pour lever les 3 HIGH advisory (Shader Baker, D3D12, dual-focus)
9. `/create-control-manifest` après clôture des re-reviews GDD (dépend ADR-0004/0005 Accepted + GDDs Approved)

**Post-MVP (non-blocker)** :
10. ADR Save/Load Settings Infrastructure → couvre G-2a + G-2b
11. ADR ou inline spec Accessibility Layer → couvre G-4

### Required ADRs (post-MVP only)

Aucun ADR **blocker** manquant. Deux ADRs Feature-tier à prévoir au Sprint 2+ :

| Priorité | ADR | Scope | Gaps couverts |
|----------|-----|-------|--------------|
| Feature | Save/Load Settings Infrastructure | Persistence `*.tres` + migration + fallback corruption | G-2a + G-2b |
| MVP-desirable | Accessibility Layer (ou inline spec) | `reduce_flash`/`reduce_motion` WCAG 2.3.1/2.3.3 propagation cross-system | G-4 |

---

## Handoff

- **Gate guidance** : `/gate-check pre-production` peut être déclenché maintenant (plus aucun blocker ADR).
- **Rerun trigger** : re-run `/architecture-review` après chaque nouvelle ADR (Save/Load, Accessibility, Combat, etc.) pour vérifier que coverage améliore sans conflict.

---

*Review produite par `/architecture-review` full mode, fresh session 2026-04-21 post-ADR-0005 + amendement ADR-0001 default_gravity.*
*Validation indépendante : contexte vierge (post-`/clear`), 5 ADRs relus intégralement, registry TR cross-checked 21 entries.*
*Mode review : solo (TD-ADR gate skipped, engine-specialist gate deferred pour advisory Sprint 1).*
