# Architecture Review — 2026-04-23

## Document Status

| Field | Value |
|-------|-------|
| **Review Date** | 2026-04-23 |
| **Mode** | `/architecture-review full` (solo, auto-approve) |
| **Engine** | Godot 4.6 (pinned 2026-02-12) |
| **GDDs Reviewed** | 6 — game-concept, systems-index, input-system, player-movement-system, camera-system, **player-combat-system r6 APPROVED**, **level-system r1 Draft** |
| **ADRs Reviewed** | 6 — ADR-0001..ADR-0005 Accepted, **ADR-0006 Proposed** |
| **Prior Review** | 2026-04-21 (5 rapports distincts : camera, input, movement, r2, r2-consolidation) |
| **Verdict** | **CONCERNS** |

---

## 1. Executive Summary

Depuis le batch `/architecture-review` du 2026-04-21, le projet a livré deux artefacts de design majeurs :

- **Player Combat System GDD r6 APPROVED** (2026-04-23) — 17 nouvelles technical requirements (TR-cmb-*)
- **Level System GDD r1 Draft Complete** (2026-04-23) — 45 nouvelles technical requirements (TR-lvl-*)

Et un nouvel ADR :

- **ADR-0006 Combat Tick Model** (Proposed 2026-04-23) — dépend de ADR-0001 + 0002 + 0005 (tous Accepted)

**Verdict CONCERNS** (non FAIL) :

- Foundation layer reste **0 gap** (gate Core → Feature toujours satisfait) ✅
- ADR-0006 encore `Proposed` → **bloque l'epic player-combat** (convention ADR deps)
- **G-5 Nouveau Gap** : taxonomie collision layers (Combat a gelé inline layers 1-5, Level les utilise, mais aucun ADR canonique)
- **G-6 Nouveau Gap** : Game State Manager interface provisoire dans Level GDD → ADR-0007 requis avant stories Level
- **G-8 Nouveau Gap** : Level Scene + Anchors + LevelKit → ADR-0011 requis avant stories Level
- Gaps persistants 2026-04-21 (G-2a, G-2b, G-4) restent post-MVP, non-blocker
- **62 nouvelles TRs à enregistrer** (17 Combat + 45 Level)

Aucun conflit cross-ADR détecté. Aucun GDD Revision Flag (hypothèses GDD alignées avec engine).

---

## 2. Phase Summary Table

| Phase | Résultat | Détails |
|-------|---------|---------|
| **1. Load Everything** | ✅ | 6 GDDs (7910 lignes total) + 6 ADRs + tr-registry.yaml + architecture-traceability.md + engine reference (VERSION + breaking-changes + deprecated-apis + current-best-practices + 4 modules) |
| **2. Extract TRs** | ✅ | 26 TRs existantes validées (ancien compte §1 matrix 2026-04-21 reportait 21 — erreur de synthèse, le §2 listait bien 26) ; **62 nouvelles TRs extraites** (17 Combat + 45 Level) ; nouveau total **88 TRs** |
| **3. Traceability Matrix** | ✅ | Matrice complète TR × ADR re-synthétisée ; voir §5 + `architecture-traceability.md` |
| **4. Cross-ADR Conflict Detection** | ✅ PASS | Aucun conflit entre ADR-0001..ADR-0006. DAG topologique stable. Aucun cycle. |
| **5. Engine Compatibility** | ✅ + ⚠️ | Version 4.6 cohérente 6/6 ADRs. 3 VRs héritées (VR-1/2/3). 3 Gaps empiriques ADR-0006 (Gap 2/7/8 pré-Sprint 1). Zéro API deprecated. |
| **5b. Design Revision Flags** | ✅ | Aucun — toutes hypothèses GDD alignées avec engine reality |
| **6. Architecture Doc Coverage** | ⚠️ | `architecture.md` daté 2026-04-21, ne couvre pas encore Combat + Level. Section 4.3 Feature layer liste PlayerCombat + LevelSystem en "to create ADR" — cohérent avec état actuel. **Re-écrire `architecture.md` r2 après ADR-0007/0011 Accepted.** |

---

## 3. Requirements Extraction — Nouveautés

### 3.1 Combat System (17 TRs — TR-cmb-001..017)

Catégories prédominantes : **Data structures** (6), **Cross-system communication** (4), **State persistence** (4), **Engine capability** (2), **Game tuning** (1).

| TR | Descripteur | ADR(s) | Status |
|----|-------------|--------|--------|
| TR-cmb-001 | CombatSystem = direct child Player (DFS preorder) | ADR-0006 D-1 | ✅ Covered |
| TR-cmb-002 | `physics_process_priority == 0` invariant | ADR-0006 D-2 | ✅ Covered |
| TR-cmb-003 | `_prev_position` owned Combat, update end-of-tick | ADR-0006 D-3 | ✅ Covered |
| TR-cmb-004 | ShapeCast3D sweep N_SUBSTEPS=3 anti-tunneling | ADR-0001 + ADR-0006 | ✅ Covered (Gap 8 empirique pré-Sprint 1) |
| TR-cmb-005 | `_build_capsule_basis(forward)` helper centralisé | ADR-0006 D-7 | ✅ Covered |
| TR-cmb-006 | Hitbox reach 1.8m, radius 0.45m | — | ⚠️ N/A (tuning Combat-local) |
| TR-cmb-007 | `aim_forward` read-only consumer de Camera | ADR-0002 | ✅ Covered |
| TR-cmb-008 | Trigger swing via `Player.attacked()` signal | ADR-0004 + ADR-0005 | ✅ Covered |
| TR-cmb-009 | Attack buffer 80 ms unconditional single-slot | ADR-0005 + ADR-0006 | ✅ Covered |
| TR-cmb-010 | Timing constants (120ms/400ms/50ms) + invariants | ADR-0001 + ADR-0006 | ✅ Covered |
| TR-cmb-011 | Multi-hit MAX=3 sorted by distance | ADR-0006 D-4a | ✅ Covered |
| TR-cmb-012 | **Collision layer taxonomy (layers 1-5)** | — | ❌ **Gap G-5 (new)** |
| TR-cmb-013 | Slow-mo timing wall-clock via `_get_time_msec` | ADR-0001 + ADR-0006 D-5 | ✅ Covered |
| TR-cmb-014 | Mutual kill Hybrid M1 via `_death_pending` flag | ADR-0005 amendment r2 + ADR-0006 | ✅ Covered |
| TR-cmb-015 | Idempotence `_hit_this_swing` via instance_ids | ADR-0006 implicit | ✅ Covered |
| TR-cmb-016 | Accessibility `reduce_motion` Combat impact | — | ❌ Gap G-4 (extension) |
| TR-cmb-017 | `_get_time_msec` Callable injection CI | ADR-0006 D-5 | ✅ Covered |

**Bilan Combat** : 14 ✅ Covered, 1 ⚠️ N/A tuning, 2 ❌ Gap (layers + accessibility extension)

### 3.2 Level System (45 TRs — TR-lvl-001..045)

Catégories prédominantes : **Cross-system communication** (14), **Performance constraints** (11), **Data structures** (10), **Engine capability** (6), **State persistence** (4), **Threading/timing** (4).

Coverage réduit par tier :

| Tier | Count | Principales ADRs |
|------|-------|-----------------|
| ✅ Covered | 11 | ADR-0001 (physics/collision), ADR-0003 (rendering/latency), ADR-0005 (signals) |
| ❌ Gap non-blocker MVP | 9 | scene hierarchy lint, material tagging, triggers Area3D |
| ❌ Gap ADR requis Core | 12 | Game State Manager interface (G-6), Level Scene + Anchors (G-8) |
| ❌ Gap ADR requis Feature | 8 | Audio layer swap (G-7), layers (G-5), VFX signals |
| ⚠️ Forward-looking | 5 | Reciprocity Checkpoint/Enemy/Secret/HUD (GDDs Not Started) |

**TRs les plus critiques** (blocker avant 1ère story Level) :

- TR-lvl-001 + TR-lvl-028 : interface Game State Manager → **G-6 ADR-0007**
- TR-lvl-006 + TR-lvl-009 + TR-lvl-020 : scene hierarchy + PlayerStart + Checkpoint naming → **G-8 ADR-0011**
- TR-lvl-007 + TR-lvl-008 : collision layers (4 Environment, 5 Interactive) → **G-5 ADR Collision Layers**
- TR-lvl-042 : material tagging pour Audio consumption → **G-7 ADR Audio System**

**TRs couvertes par ADR existants** :

- TR-lvl-003, 005, 035, 036 (frame/load budgets) → ADR-0003
- TR-lvl-007, 011, 019, 039 (physics layer + wall-run geometry + tunneling) → ADR-0001
- TR-lvl-016 (altitude change camera context) → ADR-0002
- TR-lvl-021, 023, 026, 031, 044 (signal pattern CONNECT_DEFERRED + main thread) → ADR-0005

---

## 4. Cross-ADR Conflict Detection — Phase 4

**Résultat** : **Aucun conflit détecté** entre ADR-0001..ADR-0006.

### 4.1 ADR Dependency DAG

```
ADR-0001 Physics Rate 60Hz + Jolt  [Accepted, Foundation]
     │
     ├──> ADR-0002 Camera Scene Tree         [Accepted]
     ├──> ADR-0003 Rendering Latency         [Accepted]
     ├──> ADR-0004 Input API                  [Accepted]
     └──> ADR-0005 Movement Signals           [Accepted]
                │
                └──> ADR-0006 Combat Tick Model  [PROPOSED]
                     (depends on 0001 + 0002 + 0005)
```

**Aucun cycle**. Ordre topologique stable. 0 unresolved deps (ADR-0006 → tous deps Accepted).

### 4.2 Implementation Order (topologically sorted)

**Foundation layer (no deps)** :
1. ADR-0001 Physics Rate 60Hz + Jolt

**Depends on Foundation** :
2. ADR-0002 Camera Scene Tree CameraArm (req ADR-0001)
3. ADR-0003 Rendering & Display Latency (req ADR-0001)
4. ADR-0004 Input API & Focus Handling (req ADR-0001)
5. ADR-0005 Movement Signals Architecture (req ADR-0001)

**Depends on Core** :
6. **ADR-0006 Combat Tick Model** (req ADR-0001 + ADR-0002 + ADR-0005) — PROPOSED, bloque stories Combat

### 4.3 Conflict Matrix Inspectée

| Dimension | ADR-0006 vs autres | Résolution |
|-----------|--------------------|-------------| 
| Data ownership | `_prev_position` owned Combat ; Player owne `position` | ✅ Aligné (Combat is downstream read) |
| Integration contract | `aim_forward` getter Camera | ✅ Consistent avec ADR-0002 |
| Performance budget | +0.001 ms/frame signal dispatch Combat | ✅ Absorbé dans budget physics 4.0 ms (ADR-0001 stub) |
| Dependency | ADR-0006 → 0001 + 0002 + 0005 | ✅ Aucun cycle |
| Architecture pattern | Combat signals DEFERRED par défaut + 1 SYNC exemption VFX flash | ✅ Extend ADR-0005 D-5 hiérarchiquement |
| State management | `_death_pending` Combat-local ; Movement state intouché | ✅ Respecte ADR-0005 D-7 consumer contract |

---

## 5. Traceability Matrix Consolidée — Phase 3

### 5.1 Coverage Summary (nouveau total 88 TRs)

| Status | Count | % |
|--------|-------|---|
| ✅ Covered | 54 | 61% |
| ⚠️ N/A intentional | 4 | 5% |
| ❌ Gap non-blocker MVP | 6 | 7% |
| ❌ Gap ADR requis pré-Feature | 24 | 27% |
| **Total** | **88** | **100%** |
| **Foundation layer gaps** | **0** | **0% ✅** |

Détail complet par TR : voir `architecture-traceability.md` (mis à jour par cette review).

### 5.2 Inverse Index ADR → TRs

| ADR | Count TRs covered | Principaux TRs |
|-----|-------------------|----------------|
| ADR-0001 | 14 | TR-inp-001/008, TR-mov-001/002/003/007, TR-cam-003, TR-gc-001/002/003, TR-cmb-004/010/013, TR-lvl-007/011/019/035/039 |
| ADR-0002 | 6 | TR-mov-004, TR-cam-001/002/005, TR-cmb-007, TR-lvl-016 |
| ADR-0003 | 9 | TR-inp-008, TR-cam-003, TR-gc-001/002/003, TR-lvl-003/005/035/036 |
| ADR-0004 | 9 | TR-inp-001..007, TR-gc-001, TR-cmb-008 |
| ADR-0005 | 9 | TR-mov-006, TR-cmb-008/009/014, TR-lvl-021/023/026/031/044 |
| ADR-0006 | 14 | TR-cmb-001..005/009..015/017 |

---

## 6. Engine Compatibility — Phase 5

### 6.1 Version Consistency ✅

6/6 ADRs pinned Godot 4.6. Zéro drift.

### 6.2 Post-Cutoff APIs inventaire consolidé

- **Jolt Physics default 4.6** (ADR-0001, ADR-0003, ADR-0006) — sémantique cohérente
- **D3D12 default Windows 4.6** (ADR-0003) — verification VR-2 pré-Sprint 1
- **SMAA 1x + Shader Baker 4.5** (ADR-0003) — verification VR-1 pré-Sprint 1
- **Glow pre-tonemapping 4.6** (ADR-0003) — visual-only, no latency impact
- **NOTIFICATION_APPLICATION_FOCUS_IN/OUT dual-focus 4.6** (ADR-0004) — verification VR-3 pré-Sprint 1
- **`Engine.is_in_physics_frame()` assertion pattern** (ADR-0006) — stable API, nouveau usage
- **ShapeCast3D.margin Jolt** (ADR-0006) — Gap 8 empirique pré-Sprint 1

Aucune contradiction cross-ADR.

### 6.3 Deprecated API Check

Zéro API deprecated référencée dans les 6 ADRs.

### 6.4 ADR-0006 Verification Gates

3 gaps empiriques pré-Sprint 1 (non-défauts, points de vérification intentionnels) — lead-programmer :

- **Gap 2** ShapeCast3D overlap at origin Godot 4.6 + Jolt → détermine variante AC-CMB-47 A/B
- **Gap 7** CapsuleShape3D basis pattern doc manquante dans engine-reference
- **Gap 8** ShapeCast3D.margin behavior Jolt vs GodotPhysics3D

Tant que ces gaps ne sont pas résolus, ADR-0006 reste `Proposed`, ce qui bloque l'epic player-combat.

### 6.5 Engine Hazards Non-Addressed (deferred appropriately)

| Hazard | Tier | ADR Plan |
|--------|------|----------|
| IK system restored (SkeletonModifier3D 4.6) | Tier 2 | Post-MVP |
| SDL3 gamepad + Wayland subwindow | Tier 2 | Post-MVP (gamepad stretch goal) |
| Accessibility (AccessKit 4.5) | Tier 3 | **ADR-0015 (planifié §8.4 architecture.md)** |

---

## 7. Design Revision Flags — Phase 5b

**Aucun GDD Revision Flag détecté** — toutes hypothèses GDD alignées avec la réalité engine vérifiée par engine-reference.

---

## 8. Architecture Doc Coverage — Phase 6

`architecture.md` (468 lignes, daté 2026-04-21) :

- ✅ Couvre layers Foundation + Core avec ADR mapping
- ✅ Liste §8 "Required New ADRs" complète (ADR-0006 Audio, ADR-0007 GSM, ADR-0008 Combat — ce dernier résolu par ADR-0006 en cours)
- ⚠️ Ne couvre pas encore les 45 TRs Level System ni les 17 TRs Combat
- ⚠️ §4.3 Feature Layer liste PlayerCombat + LevelSystem comme "to create ADR" — cohérent avec état actuel, mais à mettre à jour une fois ADR-0006 Accepted + ADR-0011 écrit

**Action recommandée** : réécrire `architecture.md` r2 après promotion ADR-0006 Accepted et création ADR-0007 (Game State Manager) + ADR-0011 (Level Scene + Secret Anchors).

---

## 9. New Gaps Identified — Phase 7

### 9.1 Gap G-5 — Collision Layer Taxonomy

- **TRs concernés** : TR-cmb-012 (Combat freeze inline), TR-lvl-007 + TR-lvl-008 (Level consume Layer 4 + 5)
- **Impact** : Combat est la **1ère GDD à geler la taxonomie 5 layers**. Level reprend Layer 4 (Environment) + Layer 5 (Interactive) — cohérent sémantiquement. Mais avant Enemy / Hazard / Boss GDDs, il faut canoniser cette taxonomie dans un ADR.
- **Suggested ADR** : **"ADR-0007a Collision Layer Taxonomy & Mask Canonicalization"** (ou ADR-0011 combiné scène+layers)
- **Tier** : Feature (blocker avant Enemy GDD)
- **Engine Risk** : LOW

### 9.2 Gap G-6 — Game State Manager Interface

- **TRs concernés** : TR-lvl-001 + TR-lvl-002 + TR-lvl-028 (interface provisoire Level → GSM)
- **Impact** : Level System GDD définit son interface vers GSM (pas réciproque). Sans ADR-0007, stories Level bloquées sur `load_etage()` / `unload_current()` atomicity.
- **Suggested ADR** : **ADR-0007 Game State Manager + Scene Transition Pattern** (déjà planifié `architecture.md` §8.2)
- **Tier** : Core (blocker avant 1ère story Level)
- **Engine Risk** : LOW

### 9.3 Gap G-7 — Audio System Binding

- **TRs concernés** : TR-lvl-042 (material tags Audio routing), TR-cmb-013 (slow-mo pitch behavior)
- **Impact** : Level prévoit `room_entered` signal pour Audio layer swap (knob disabled MVP). Combat confirme `Engine.time_scale` n'affecte pas `AudioStreamPlayer` pitch. Sans ADR Audio, contrat de consommation non formalisé.
- **Suggested ADR** : **"ADR-0008 Audio System Architecture"** (déjà planifié §8.2, mais renumérotation requise car ADR-0006 pris)
- **Tier** : Core (non-blocker Sprint 1 Combat, blocker Sprint Audio)
- **Engine Risk** : LOW

### 9.4 Gap G-8 — Level Scene + Secret Anchors

- **TRs concernés** : TR-lvl-006, TR-lvl-009, TR-lvl-015, TR-lvl-017, TR-lvl-020, TR-lvl-038, TR-lvl-040, TR-lvl-041
- **Impact** : Level GDD spécifie scene hierarchy mandatoire (StaticEnvironment / InteractiveVolumes / SpawnMarkers / EtageExitTrigger), naming zero-pad CheckpointVolume_NN ↔ CheckpointAnchor_NN, WorldBoundsVolume, single texture atlas 1024×1024, shader partagé `shader_chrome_zen_flat.gdshader`. Besoin de canoniser en ADR pour lint pre-build.
- **Suggested ADR** : **"ADR-0011 Level System Scene Architecture + Secret Anchors"** (déjà planifié §8.3)
- **Tier** : Feature (blocker avant 1ère story Level)
- **Engine Risk** : LOW

### 9.5 Gaps Persistants 2026-04-21 (non-blockers MVP)

- **G-2a TR-cam-006** Save/Load Camera Settings → ADR-0014 post-MVP
- **G-2b TR-inp-009** Save/Load Input Settings → ADR-0014 post-MVP mutualisé
- **G-4 TR-mov-008** Accessibility toggles → ADR-0015 Polish/Full Vision
- **G-4 ext. TR-cmb-016** Accessibility Combat (`reduce_motion` slow-mo mult, flash mult) → ADR-0015 mutualisé

---

## 10. Required New ADRs (Prioritized)

### 10.1 Must-have avant Sprint Combat

**Aucun** — ADR-0006 suffit **une fois promu à `Accepted`** (Gaps 2/7/8 empiriques résolus pré-Sprint 1).

### 10.2 Must-have avant Sprint Level

1. **ADR-0007 Game State Manager + Scene Transition Pattern** — résout G-6
2. **ADR-0011 Level System Scene Architecture + Secret Anchors** — résout G-8 (+ optionnellement G-5 si taxonomie fusionnée)

### 10.3 Must-have avant Sprint Enemy / Hazard / Boss

3. **ADR Collision Layer Taxonomy** — résout G-5 (indépendant ou fusionné avec ADR-0011)

### 10.4 Should-have avant Sprint Audio

4. **ADR Audio System Architecture** — résout G-7

### 10.5 Can defer to Polish

5. **ADR Save/Load Settings Infrastructure** — résout G-2a + G-2b
6. **ADR Accessibility Interface Layer** — résout G-4 (mov + cmb)

### 10.6 Post-MVP / Full Vision

7. **ADR Checkpoint & Respawn Pattern**
8. **ADR Upgrade Capabilities Interface**
9. **ADR Enemy State Machine + Hazard**
10. **ADR HUD + Menu UI Framework**
11. **ADR VFX & Feedback Architecture**
12. **ADR Boss System Asymmetric Combat**
13. **ADR Speedrun & Leaderboards**

---

## 11. Verdict Final

### **CONCERNS**

**Justification synthétique** :

- Foundation layer **toujours 0 gap** → gate Technical Setup → Pre-Production reste franchissable sur la dimension traceability
- ADR-0006 `Proposed` + Gaps empiriques 2/7/8 pré-Sprint 1 → **bloque epic player-combat** jusqu'à validation
- 3 nouveaux Gaps Core-layer (G-5, G-6, G-8) → **bloquent epic player-combat** (G-5), stories Level (G-6 + G-8), stories Enemy/Hazard/Boss (G-5)
- 1 Gap Audio (G-7) non-blocker Sprint Combat mais blocker Sprint Audio
- 62 nouvelles TRs à enregistrer dans registry

### Blocking Issues (doivent être résolus avant re-verdict PASS)

| Issue | Owner | Sprint | Action |
|-------|-------|--------|--------|
| ADR-0006 Proposed → Accepted | lead-programmer + godot-specialist | Pré-Sprint 1 | Résoudre Gaps 2/7/8 empiriquement + `/architecture-review single-gdd combat` fresh session |
| G-5 Collision Layer Taxonomy | technical-director | Avant Sprint Enemy | `/architecture-decision collision-layers` |
| G-6 Game State Manager | technical-director | Avant Sprint Level | `/architecture-decision game-state-manager` |
| G-8 Level Scene Architecture | technical-director | Avant Sprint Level | `/architecture-decision level-scene-architecture` |

### Non-Blocking (advisory)

- VR-1 Shader Baker semantique 4.6 (ADR-0003) — Sprint 1 advisory
- VR-2 D3D12 launch-time Windows 4.6 (ADR-0003) — Sprint 1 advisory
- VR-3 Dual-focus Godot 4.6 (ADR-0004) — Sprint 1 advisory

---

## 12. Handoff & Next Actions

1. **Register new TRs** : append TR-cmb-001..017 + TR-lvl-001..045 dans `tr-registry.yaml` (fait par cette review)
2. **Update traceability matrix** : `architecture-traceability.md` régénéré (fait par cette review)
3. **Resolve Gaps 2/7/8 ADR-0006** : lead-programmer test empirique pré-Sprint 1, puis re-run `/architecture-review single-gdd player-combat-system.md` et promouvoir ADR-0006 → Accepted
4. **Create ADR-0007 Game State Manager** : `/architecture-decision game-state-manager` fresh session
5. **Create ADR-0011 Level Scene + Anchors** : `/architecture-decision level-scene-architecture` fresh session
6. **Create ADR Collision Layers** : `/architecture-decision collision-layer-taxonomy` fresh session (peut être fusionné avec ADR-0011)
7. **Re-run `/architecture-review full`** après 4/5/6 pour verdict PASS potentiel
8. **Update `architecture.md` r2** après ADR-0006 Accepted et nouveaux ADRs écrits

---

## 13. Cross-References

- TR registry mis à jour : `docs/architecture/tr-registry.yaml`
- Matrice traceability mise à jour : `docs/architecture/architecture-traceability.md`
- Architecture master doc : `docs/architecture/architecture.md` (à réécrire r2 post-ADR-0007/0011)
- Reviews antérieures :
  - `docs/architecture/architecture-review-2026-04-21.md` (batch camera/input/movement consolidé)
  - `docs/architecture/architecture-review-2026-04-21-r2.md` (r2 input-system)
  - `docs/architecture/architecture-review-2026-04-21-camera.md`
  - `docs/architecture/architecture-review-2026-04-21-input.md`
  - `docs/architecture/architecture-review-2026-04-21-movement.md`
- GDDs reviewed :
  - `design/gdd/player-combat-system.md` (r6 APPROVED 2026-04-23, 1200 lignes)
  - `design/gdd/level-system.md` (r1 Draft 2026-04-23, 923 lignes)
- Engine reference : `docs/engine-reference/godot/VERSION.md` + breaking-changes + deprecated-apis + current-best-practices + 4 modules
