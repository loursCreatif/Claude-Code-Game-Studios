# Architecture Traceability Matrix

## Document Status

| Field | Value |
|-------|-------|
| **Version** | 2.3 |
| **Last Updated** | 2026-04-23 (r4 — G-5 Collision Layer Taxonomy closed via ADR-0008 Accepted ; architecture globale PASS) |
| **Source Registry** | `docs/architecture/tr-registry.yaml` (88 TRs) |
| **Source ADRs** | ADR-0001..ADR-0008 + ADR-0011 (tous Accepted — 9/9) |
| **Companion Doc** | `docs/architecture/architecture.md` (r1 du 2026-04-21, à réécrire r2) |
| **Companion Review** | `docs/architecture/architecture-review-2026-04-23-r4.md` |

---

## 1. Coverage Summary

| Status | Count | Percentage |
|--------|-------|------------|
| ✅ **Covered** | 80 | 91% |
| ⚠️ **N/A intentional** | 4 | 5% |
| ❌ **Gap non-blocker MVP** | 4 | 5% |
| ❌ **Gap ADR requis** | 0 | 0% |
| **Total** | **88** | **100%** |
| **Foundation layer gaps** | **0** | **0% ✅** |
| **Core layer gaps** | **0** | **0% ✅** |
| **Feature layer blockers MVP** | **0** | **0% ✅** |

**Gate outcome** : Foundation + Core layers 0 gap ; 0 Feature blocker MVP — **architecture PASS** (premier PASS depuis début projet). **G-6 GSM Interface RÉSOLU** 2026-04-23 r2 via ADR-0007 Accepted (+5 TRs). **G-8 Level Scene Anchors RÉSOLU** 2026-04-23 r3 via ADR-0011 Accepted (+19 TRs + 6 co-covered). **G-5 Collision Layer Taxonomy RÉSOLU** 2026-04-23 r4 via ADR-0008 Accepted (+2 TRs : TR-cmb-012, TR-lvl-008 ; second coverage TR-lvl-007). Gaps restants Feature layer non-blockers MVP : G-7 Audio System (ADR Audio dédié — non-blocker Sprint 1-2), G-2a/G-2b Save/Load Settings (post-MVP), G-4 Accessibility (Polish/Full Vision).

---

## 2. Matrix — Full TR × ADR

### 2.1 Input System (9 TRs)

| TR-ID | Requirement (summary) | ADR(s) | Status |
|-------|-----------------------|--------|--------|
| TR-inp-001 | `was_pressed_this_tick(action)` polling tick N parity | ADR-0004, ADR-0001 | ✅ Covered |
| TR-inp-002 | `mouse_motion(delta)` signal via `_unhandled_input` | ADR-0004 | ✅ Covered |
| TR-inp-003 | InputManager singleton autoload unique Input access | ADR-0004 | ✅ Covered |
| TR-inp-004 | StringName discipline actions préallouées const | ADR-0004 | ✅ Covered |
| TR-inp-005 | Refcount `request_disable/release_enable_request(owner)` | ADR-0004 | ✅ Covered |
| TR-inp-006 | Signal `application_focus_lost` découplage GameState | ADR-0004 (emitter), ADR-0007 (consumer) | ✅ Covered |
| TR-inp-007 | Zero-alloc ring buffer PackedFloat32Array latence | ADR-0004 | ✅ Covered |
| TR-inp-008 | Cible latence p99 ≤ 16 ms intra-engine | ADR-0001, ADR-0003 | ✅ Covered |
| TR-inp-009 | Lifecycle save/load `input_settings.tres` | — | ❌ Gap G-2b (post-MVP, planned ADR Save/Load Settings) |

### 2.2 Player Movement (8 TRs)

| TR-ID | Requirement (summary) | ADR(s) | Status |
|-------|-----------------------|--------|--------|
| TR-mov-001 | Physics tick 60 Hz, PHYSICS_TICK_RATE paramétré | ADR-0001 | ✅ Covered |
| TR-mov-002 | CharacterBody3D + Jolt + ShapeCast3D + WallRay unique-name | ADR-0001 | ✅ Covered |
| TR-mov-003 | Autorité `_physics_process` unique mutation | ADR-0001 | ✅ Covered |
| TR-mov-004 | Camera hiérarchie 3 étages | ADR-0002 | ✅ Covered |
| TR-mov-005 | Jump buffer post-MVP (retiré r3) | — | ⚠️ N/A intentional |
| TR-mov-006 | Movement signals 8 MVP + outbound-only | ADR-0005 | ✅ Covered |
| TR-mov-007 | Project Setting `physics/3d/default_gravity=0.0` | ADR-0001 | ✅ Covered (amendé 2026-04-21) |
| TR-mov-008 | Accessibility `reduce_flash`/`reduce_motion` MVP interface | — | ❌ Gap G-4 (post-MVP, planned ADR Accessibility) |

### 2.3 Camera System (6 TRs)

| TR-ID | Requirement (summary) | ADR(s) | Status |
|-------|-----------------------|--------|--------|
| TR-cam-001 | Ownership par étage scene tree | ADR-0002 | ✅ Covered |
| TR-cam-002 | `aim_forward` close-form trigo ignore tilt | ADR-0002 | ✅ Covered |
| TR-cam-003 | Logique caméra `_process`, mouse_motion event-driven | ADR-0001, ADR-0003 | ✅ Covered |
| TR-cam-004 | Tilt wall-run 95% ≤ 200 ms tuning | — | ⚠️ N/A tuning |
| TR-cam-005 | Performance budget caméra ≤ 0.5 ms/frame p99 | ADR-0002 | ✅ Covered |
| TR-cam-006 | Lifecycle save/load `camera_settings.tres` | — | ❌ Gap G-2a (post-MVP) |

### 2.4 Game Concept / Pillars (3 TRs)

| TR-ID | Requirement (summary) | ADR(s) | Status |
|-------|-----------------------|--------|--------|
| TR-gc-001 | Pillar 1 FLOW latence ≤ 1 frame perçue | ADR-0001, ADR-0003, ADR-0004 | ✅ Covered |
| TR-gc-002 | Pillar 4 PERFORMANCE 60+ fps vsync locked | ADR-0001, ADR-0003 | ✅ Covered |
| TR-gc-003 | Forward+ + Jolt + D3D12 4.6 stack | ADR-0001, ADR-0003 | ✅ Covered |

### 2.5 Player Combat System (17 TRs — nouveaux 2026-04-23)

| TR-ID | Requirement (summary) | ADR(s) | Status |
|-------|-----------------------|--------|--------|
| TR-cmb-001 | CombatSystem = direct child Player (DFS preorder) | ADR-0006 | ✅ Covered |
| TR-cmb-002 | `physics_process_priority == 0` invariant | ADR-0006 | ✅ Covered |
| TR-cmb-003 | `_prev_position` owned Combat, update end-of-tick | ADR-0006 | ✅ Covered |
| TR-cmb-004 | ShapeCast3D sweep N_SUBSTEPS=3 anti-tunneling | ADR-0001, ADR-0006 | ✅ Covered (Gap 8 empirique) |
| TR-cmb-005 | `_build_capsule_basis()` helper centralisé | ADR-0006 | ✅ Covered |
| TR-cmb-006 | Hitbox reach 1.8m, radius 0.45m | — | ⚠️ N/A (tuning Combat-local) |
| TR-cmb-007 | `aim_forward` read-only consumer Camera | ADR-0002, ADR-0006 | ✅ Covered |
| TR-cmb-008 | Trigger swing via `Player.attacked()` signal | ADR-0004, ADR-0005 | ✅ Covered |
| TR-cmb-009 | Attack buffer 80 ms unconditional single-slot | ADR-0005, ADR-0006 | ✅ Covered |
| TR-cmb-010 | Timing constants + invariants 4/6/7 | ADR-0001, ADR-0006 | ✅ Covered |
| TR-cmb-011 | Multi-hit MAX=3 sorted by distance | ADR-0006 | ✅ Covered |
| TR-cmb-012 | **Collision layer taxonomy (layers 1-5)** | **ADR-0008** | ✅ Covered (G-5 closed 2026-04-23 r4) |
| TR-cmb-013 | Slow-mo timing wall-clock via `_get_time_msec` | ADR-0001, ADR-0006 | ✅ Covered |
| TR-cmb-014 | Mutual kill Hybrid M1 via `_death_pending` | ADR-0005 amendment r2, ADR-0006 | ✅ Covered |
| TR-cmb-015 | Idempotence `_hit_this_swing` via instance_ids | ADR-0006 | ✅ Covered |
| TR-cmb-016 | Accessibility `reduce_motion` Combat impact | — | ❌ Gap G-4 (extension cmb) |
| TR-cmb-017 | `_get_time_msec` Callable injection CI | ADR-0006 | ✅ Covered |

### 2.6 Level System (45 TRs — nouveaux 2026-04-23)

**Note** : Level System GDD status = "In Design r1 — Draft Complete" (pas encore /design-review approuvé). TRs extraits en state `active` sous réserve d'ajustements post-design-review.

| TR-ID | Requirement (summary) | ADR(s) | Status |
|-------|-----------------------|--------|--------|
| TR-lvl-001 | Scene loading via single `.tscn` (no streaming MVP) | ADR-0005, **ADR-0007** | ✅ Covered (G-6 closed 2026-04-23 r2) |
| TR-lvl-002 | State machine `Unloaded→Loading→Active→Unloading` | ADR-0005 D-5 | ✅ Covered |
| TR-lvl-003 | Load time budget ≤ 1000 ms | ADR-0003 | ✅ Covered |
| TR-lvl-004 | Draw call budget per etage ≤ 350 | **ADR-0011** (D-7+D-13) | ✅ Covered (G-8 closed 2026-04-23 r3) |
| TR-lvl-005 | VRAM per etage ≤ 50 MB | ADR-0003, ADR-0011 | ✅ Covered |
| TR-lvl-006 | Scene hierarchy mandatoire | **ADR-0011** (D-2) | ✅ Covered (G-8 closed 2026-04-23 r3) |
| TR-lvl-007 | Static geometry Layer 4 LAYER_ENVIRONMENT | ADR-0001, **ADR-0008** | ✅ Covered (G-5 closed 2026-04-23 r4) |
| TR-lvl-008 | Interactive triggers Area3D Layer 5 LAYER_INTERACTIVE | **ADR-0008** | ✅ Covered (G-5 closed 2026-04-23 r4) |
| TR-lvl-009 | PlayerStart Marker3D unique mandatoire | **ADR-0011** (D-2+D-7) | ✅ Covered (G-8 closed 2026-04-23 r3) |
| TR-lvl-010 | Min door width = 3.6 m (2 × KATANA_REACH) | **ADR-0011** (D-7 #1) | ✅ Covered (G-8 closed 2026-04-23 r3) |
| TR-lvl-011 | Wall-run min height 4m / length 3m / slope ±5° | ADR-0001, **ADR-0011** (D-7 #2) | ✅ Covered |
| TR-lvl-012 | Room count per etage 8-10 | **ADR-0011** (D-7 #6) | ✅ Covered (G-8 closed 2026-04-23 r3) |
| TR-lvl-013 | StaticBody3D count ≤ 25 par room | ADR-0001, **ADR-0011** (D-13) | ✅ Covered |
| TR-lvl-014 | Checkpoint spacing 2-3 rooms | **ADR-0011** (D-7 #11) | ✅ Covered (G-8 closed 2026-04-23 r3) |
| TR-lvl-015 | Secret density min ≥ 3, divisor ∈ [2,3] | **ADR-0011** (D-7 #8+D-2) | ✅ Covered (G-8 closed 2026-04-23 r3) |
| TR-lvl-016 | Altitude change +1..+4m average 2.5m | ADR-0002 | ✅ Covered |
| TR-lvl-017 | Etage bounding volume ≈ 5000 m³ | **ADR-0011** (D-9) | ✅ Covered (G-8 closed 2026-04-23 r3) |
| TR-lvl-018 | Static geometry Y ≥ -2.0m | **ADR-0011** (D-7 #3) | ✅ Covered (G-8 closed 2026-04-23 r3) |
| TR-lvl-019 | Wall thickness ≥ 0.3m (tunneling prevention) | ADR-0001, **ADR-0011** (D-9) | ✅ Covered |
| TR-lvl-020 | CheckpointVolume_NN ↔ CheckpointAnchor_NN pair naming | **ADR-0011** (D-2+D-7 #5) | ✅ Covered (G-8 closed 2026-04-23 r3) |
| TR-lvl-021 | Signal `level_active` via call_deferred | ADR-0005 D-5, **ADR-0011** (D-5) | ✅ Covered |
| TR-lvl-022 | Signal `room_entered` fire-once per entry | **ADR-0011** (D-5) | ✅ Covered (G-8 closed 2026-04-23 r3) |
| TR-lvl-023 | Signal `etage_completed` fire-once | ADR-0005, **ADR-0011** (D-5) | ✅ Covered |
| TR-lvl-024 | Signal `player_out_of_world` WorldBounds exit | ADR-0003, **ADR-0011** (D-5+D-9) | ✅ Covered |
| TR-lvl-025 | Signal `level_unloading` before queue_free() | **ADR-0011** (D-4 T-3+D-5) | ✅ Covered (G-8 closed 2026-04-23 r3) |
| TR-lvl-026 | Signal `level_load_failed(etage_id, reason)` | ADR-0005, **ADR-0011** (D-5+D-8) | ✅ Covered |
| TR-lvl-027 | Advisory signal `level_load_slow(elapsed_ms)` >600ms | **ADR-0011** (D-5+D-8) | ✅ Covered (G-8 closed 2026-04-23 r3) |
| TR-lvl-028 | Reject concurrent `load_etage(id2)` when Active | **ADR-0007** (D-2+D-5) | ✅ Covered (G-6 closed 2026-04-23 r2) |
| TR-lvl-029 | Reject `load_etage()` if scene missing/corrupted | **ADR-0007** (D-7), ADR-0011 (impl) | ✅ Covered (G-6 closed 2026-04-23 r2) |
| TR-lvl-030 | Assert if PlayerStart missing | **ADR-0011** (D-2+D-7 #4) | ✅ Covered (G-8 closed 2026-04-23 r3) |
| TR-lvl-031 | Deterministic room trigger ordering | ADR-0005, **ADR-0011** (D-5) | ✅ Covered |
| TR-lvl-032 | Ignore NaN/Inf in body position | **ADR-0011** (D-5) | ✅ Covered (G-8 closed 2026-04-23 r3) |
| TR-lvl-033 | Safe idempotence `unload_current()` | **ADR-0007** (D-5) | ✅ Covered (G-6 closed 2026-04-23 r2) |
| TR-lvl-034 | Reset on reload (complete state) | **ADR-0007** (D-8) | ✅ Covered (G-6 closed 2026-04-23 r2) |
| TR-lvl-035 | Frame time p99 ≤ 16.6 ms intra-room | ADR-0001, **ADR-0011** (D-13) | ✅ Covered |
| TR-lvl-036 | No perceptible stutter on room transitions | ADR-0003, **ADR-0011** (D-13) | ✅ Covered |
| TR-lvl-037 | No major allocation post-`level_active` | **ADR-0011** (D-6+D-13) | ✅ Covered (G-8 closed 2026-04-23 r3) |
| TR-lvl-038 | Validate CheckpointAnchor not inside static geometry | ADR-0001, **ADR-0011** (D-9) | ✅ Covered |
| TR-lvl-039 | No collision clip-through at high velocity | ADR-0001 | ✅ Covered |
| TR-lvl-040 | Render via Chrome Zen primitives + flat shader | **ADR-0011** (D-10) | ✅ Covered (G-8 closed 2026-04-23 r3) |
| TR-lvl-041 | Texture atlas 1024×1024, no >512×512 | **ADR-0011** (D-13) | ✅ Covered (G-8 closed 2026-04-23 r3) |
| TR-lvl-042 | Material tagging `surface_material` | — | ❌ Gap G-7 (Audio consumption) |
| TR-lvl-043 | Tuning knobs authoring + runtime | **ADR-0011** (D-7+D-13) | ✅ Covered (G-8 closed 2026-04-23 r3) |
| TR-lvl-044 | All signals emit from main thread | ADR-0005 | ✅ Covered |
| TR-lvl-045 | Reciprocity forward (Checkpoint/Enemy/Secret/HUD Deps) | — | ⚠️ Forward-looking (peers Not Started) |

---

## 3. Gap Analysis

### 3.1 ❌ Gap G-2a — TR-cam-006 (Save/Load Camera Settings)

- Non-blocker MVP ; résolution planifiée ADR-0014 post-MVP (mutualisé G-2b).

### 3.2 ❌ Gap G-2b — TR-inp-009 (Save/Load Input Settings)

- Non-blocker MVP ; mutualisé avec G-2a.

### 3.3 ❌ Gap G-4 — TR-mov-008 + TR-cmb-016 (Accessibility)

- Advisory MVP (spec inline GDD existe). ADR-0015 Polish/Full Vision.

### 3.4 ✅ Gap G-5 — Collision Layer Taxonomy — CLOSED 2026-04-23 r4

- **TRs couvertes (2)** : TR-cmb-012 (freeze inline Combat GDD Rule 12 ratifiée), TR-lvl-008 (Interactive Area3D Layer 5)
- **TRs co-covered (1)** : TR-lvl-007 (ADR-0008 ajoute second coverage Static Environment Layer 4)
- **Résolution** : **ADR-0008 Collision Layer Taxonomy & Mask Canonicalization** Accepted 2026-04-23 r4 (6 décisions D-1..D-6 : taxonomie 5-layer ratifiée, Decision Matrix 7 archetypes, API 1-indexée obligatoire, `project.godot` layer names canoniques, layers 6-32 réservées + protocole amendement, lint pre-build CI `lint-collision-layers`)
- **Validation** : `/architecture-review full` r4 verdict PASS pour promotion — 0 cross-ADR conflict, upstream dep ADR-0001 Accepted, Engine LOW risk, godot-specialist APPROVE r3
- **Tier** : Feature (Combat/Level) — débloque stories Enemy/Hazard/Boss/Secret avec taxonomie canonique pour leurs `(collision_layer, collision_mask)` contracts

### 3.5 ✅ Gap G-6 — Game State Manager Interface — CLOSED 2026-04-23 r2

- **TRs couvertes** : TR-lvl-001, TR-lvl-028, TR-lvl-029, TR-lvl-033, TR-lvl-034
- **Résolution** : **ADR-0007 Game State Manager + Scene Transition Pattern** Accepted 2026-04-23 r2
- **Validation** : `/architecture-review full` r2 verdict PASS pour promotion — 0 cross-ADR conflict, upstream deps satisfaits, Engine LOW risk
- **Tier** : Core (layer 3/3 Core ADRs Accepted : ADR-0002 + ADR-0005 + ADR-0007)

### 3.6 ❌ Gap G-7 — Audio System Binding (NEW)

- **TRs** : TR-lvl-042 (material tags)
- **Impact** : non-blocker Sprint Combat ; blocker Sprint Audio
- **Plan** : **ADR Audio System Architecture**
- **Tier** : Core

### 3.7 ✅ Gap G-8 — Level Scene + Anchors + LevelKit — CLOSED 2026-04-23 r3

- **TRs couvertes (19)** : TR-lvl-004, 006, 009, 010, 012, 014, 015, 017, 018, 020, 022, 025, 027, 030, 032, 037, 040, 041, 043
- **TRs co-covered (6)** : TR-lvl-011, 013, 019, 021, 023, 031 (ADR-0011 ajoute coverage complémentaire aux ADRs originales)
- **Résolution** : **ADR-0011 Level Scene Architecture & Lint-Gated Authoring Invariants** Accepted 2026-04-23 r3 (490 lignes, 13 décisions D-1..D-13)
- **Validation** : `/architecture-review single-gdd level-system.md` r3 verdict PASS pour promotion comme design-contract ADR — 0 cross-ADR conflict, upstream deps Accepted, Engine MEDIUM risk (D3D12/Shader Baker/Jolt) avec tous APIs documentés engine-reference, 5 VR §Engine Compatibility + 8 VC-LVL = gates Sprint 1 impl (pattern ADR-0005/0007)
- **Tier** : Feature (Level) — débloque epic `level-system` + 5 epics downstream (Checkpoint/Enemy/Hazard/Secret/HUD) sur contrats signals/lookups
- **Note** : TR-lvl-008 (layers 5 LAYER_INTERACTIVE) reste Gap G-5 — hors scope ADR-0011, adressé par ADR-0008 futur

### 3.8 ⚠️ N/A Intentionnels

- TR-mov-005 Jump buffer post-MVP (Martin r2)
- TR-cam-004 Tilt tuning (playtest calibré, hors archi)
- TR-cmb-006 Hitbox reach/radius (tuning Combat-local)
- TR-lvl-045 Reciprocity forward (peers Not Started ; review via `/consistency-check` quand peer GDDs démarrent)

---

## 4. Inverse Index — ADR → TRs Covered

| ADR | TRs covered | Count |
|-----|-------------|-------|
| ADR-0001 Physics Rate 60Hz + Jolt | TR-inp-001/008, TR-mov-001/002/003/007, TR-cam-003, TR-gc-001/002/003, TR-cmb-004/010/013, TR-lvl-007/011/013/019/035/038/039 | 18 |
| ADR-0002 Camera Scene Tree | TR-mov-004, TR-cam-001/002/005, TR-cmb-007, TR-lvl-016 | 6 |
| ADR-0003 Rendering & Latency | TR-inp-008, TR-cam-003, TR-gc-001/002/003, TR-lvl-003/005/024/035/036 | 10 |
| ADR-0004 Input API | TR-inp-001..007, TR-gc-001, TR-cmb-008 | 9 |
| ADR-0005 Movement Signals | TR-mov-006, TR-cmb-008/009/014, TR-lvl-001/002/021/023/026/031/044 | 11 |
| ADR-0006 Combat Tick Model | TR-cmb-001..005/007..015/017 | 14 |
| ADR-0007 Game State Manager | TR-inp-006 (consumer), TR-lvl-001/028/029/033/034, TR-gc-001 | 7 |
| ADR-0008 Collision Layer Taxonomy | TR-cmb-012, TR-lvl-007, TR-lvl-008 | 3 |
| ADR-0011 Level Scene Architecture | TR-lvl-004/005/006/009/010/011/012/013/014/015/017/018/019/020/021/022/023/024/025/026/027/030/031/032/035/036/037/038/040/041/043 | 31 |

**Note** : totaux > TRs actives car plusieurs TRs multi-covered (couches complémentaires).

---

## 5. ADRs Required to Close Gaps

| Priority | ADR Title (proposed) | Gaps Closed | Unblocks |
|----------|---------------------|-------------|----------|
| ✅ DONE | ADR-0006 Combat Tick Model | n/a | Epic player-combat (Accepted 2026-04-23) |
| ✅ DONE | ADR-0007 Game State Manager + Scene Transition | **G-6 closed** | Stories Level C1 + Menu + Pause (Accepted 2026-04-23 r2) |
| ✅ DONE | ADR-0011 Level Scene Architecture & Lint Invariants | **G-8 closed** | Stories Level complètes + 5 epics downstream (Checkpoint/Enemy/Hazard/Secret/HUD) — contrats signals/lookups (Accepted 2026-04-23 r3) |
| ✅ DONE | ADR-0008 Collision Layer Taxonomy & Mask Canonicalization | **G-5 closed** | Stories Enemy / Hazard / Boss / Secret / Combat layer lint (Accepted 2026-04-23 r4) |
| P2 | **ADR Audio System Architecture** | G-7 | Sprint Audio |
| P3 | ADR Save/Load Settings Infrastructure | G-2a + G-2b | Polish tier |
| P3 | ADR Accessibility Interface Layer | G-4 (mov + cmb) | Polish / Full Vision |

---

## 6. Maintenance

- Ce document est régénéré par `/architecture-review` Phase 8.
- Ajout d'un nouvel ADR → append ligne §4 Inverse Index + mise à jour cellules §2.
- Ajout d'un nouveau TR → append `tr-registry.yaml` puis §2 + §4.
- Résolution d'un Gap → déplacer §3 → §2 statut ✅ Covered + référence ADR.
- Verdict review : voir `architecture-review-2026-04-23.md`.
