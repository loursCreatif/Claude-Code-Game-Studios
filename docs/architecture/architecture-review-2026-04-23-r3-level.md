# Architecture Review — 2026-04-23 (r3, ADR-0011 Level Scene Architecture promotion)

## Document Status

| Field | Value |
|-------|-------|
| **Mode** | `/architecture-review single-gdd level-system.md` — focused ADR-0011 promotion |
| **Date** | 2026-04-23 r3 |
| **Engine** | Godot 4.6 (pinned 2026-02-12) |
| **GDD Scope** | `design/gdd/level-system.md` r2 (APPROVED 2026-04-23) + `player-combat-system.md` Rule 16 onboarding |
| **ADR Focus** | **ADR-0011 Level Scene Architecture & Lint-Gated Authoring Invariants** (Proposed) |
| **ADRs Referenced** | ADR-0001/0003/0005/0007 (Accepted) + ADR-0006 (Accepted) |
| **Predecessor Review** | `architecture-review-2026-04-23-r2.md` (ADR-0007 promotion, verdict PASS) |

---

## 1. Executive Summary

Cette revue focused valide l'**éligibilité d'ADR-0011 Level Scene Architecture** (Proposed 2026-04-23, 490 lignes, 13 décisions D-1..D-13) à la promotion `Proposed → Accepted`. Les 3 upstream deps (ADR-0001/0003/0005) sont Accepted depuis 2026-04-21 ; ADR-0007 (GSM) Accepted ce jour en r2 confirme le contrat `LevelSystem.load_etage()` additif référencé par D-1/D-8.

**Verdict ADR-0011** : ✅ **PROMOTE Proposed → Accepted** en tant que **design-contract ADR** (pattern ADR-0005 / ADR-0007). Les 8 VC-LVL + 5 Verification Required §Engine Compatibility sont des **gates implémentation Sprint 1**, pas des gates pré-Accepted. Cela diffère intentionnellement du pattern ADR-0006 (où Gaps 2/7/8 étaient des unknowns empiriques sur comportements Jolt non-documentés).

**Verdict architecture globale** : ⚠️ **CONCERNS** (progression mais G-5 Collision Layers + G-7 Audio System restants)

---

## 2. Coverage — Impact ADR-0011 sur Gap G-8

### 2.1 21 TRs Level résolus

Les 21 TRs G-8 identifiés dans `/architecture-review` 2026-04-23 initial (cf. `architecture-traceability.md` §3.7) passent `Gap → ✅ Covered` :

| TR-ID | Requirement | Coverage via ADR-0011 |
|-------|-------------|----------------------|
| TR-lvl-004 | Draw call budget ≤ 350 | D-7 invariant #10 + D-13 (AC-LVL-31, AC-LVL-55) |
| TR-lvl-006 | Scene hierarchy mandatoire (5 groupes) | D-2 canonique + `_validate_scene_hierarchy()` (AC-LVL-11) |
| TR-lvl-009 | PlayerStart Marker3D unique | D-2 + D-7 invariant #4 (AC-LVL-18) |
| TR-lvl-010 | Min door width = 3.6 m | D-7 invariant #1 (AC-LVL-14) |
| TR-lvl-012 | Room count 8-10 per etage | D-7 invariant #6 (AC-LVL-20) |
| TR-lvl-014 | Checkpoint spacing 2-3 rooms | D-7 invariant #11 (AC-LVL-51) |
| TR-lvl-015 | Secret density ≥ 3 + divisor ∈ [2,3] | D-7 invariant #8 + D-2 tuple Secret separate (AC-LVL-46, AC-LVL-53) |
| TR-lvl-017 | Etage bounding volume ≈ 5000 m³ | D-9 `validate_level_shapes()` (AC-LVL-49) |
| TR-lvl-018 | Static geometry Y ≥ -2.0 m | D-7 invariant #3 (AC-LVL-16) |
| TR-lvl-020 | CheckpointVolume_NN ↔ CheckpointAnchor_NN naming | D-2 conventions + D-7 invariant #5 (AC-LVL-19) |
| TR-lvl-022 | Signal `room_entered` fire-once per entry | D-5 contrat signal + émission sync `RoomTrigger.body_entered` (AC-LVL-22) |
| TR-lvl-025 | Signal `level_unloading` avant `queue_free()` | D-4 T-3 + D-5 ordre (AC-LVL-25) |
| TR-lvl-027 | Signal `level_load_slow(elapsed_ms)` ≥ 600 ms | D-5 + D-8 polling `_process` advisory (AC-LVL-27) |
| TR-lvl-030 | Assert si PlayerStart missing | D-2 `_validate_scene_hierarchy` runtime + D-7 invariant #4 (AC-LVL-8, AC-LVL-18) |
| TR-lvl-032 | Ignore NaN/Inf body position | D-5 `player_out_of_world` avec `last_valid_position` filtré |
| TR-lvl-037 | No major alloc post-`level_active` | D-6 arrays pré-construites + `make_read_only()` + D-13 budget (AC-LVL-36) |
| TR-lvl-040 | Render Chrome Zen primitives + flat shader | D-10 Shader Baker + précompilation boot (VR-LVL-1) |
| TR-lvl-041 | Texture atlas 1024×1024, pas > 512×512 | D-13 budgets verrouillés (note: enforcement par lint successeur ADR si nécessaire) |
| TR-lvl-043 | Tuning knobs authoring + runtime | D-7 lint pré-build + D-13 runtime budgets |

### 2.2 5 TRs additionnellement co-covered (déjà ✅ via autres ADRs)

| TR-ID | Original coverage | ADR-0011 addition |
|-------|-------------------|-------------------|
| TR-lvl-011 | ADR-0001 | D-7 invariant #2 wall-run geometry (AC-LVL-15) |
| TR-lvl-013 | ADR-0001 | D-13 budget StaticBody3D ≤ 25 (AC-LVL-33) |
| TR-lvl-019 | ADR-0001 | D-9 BoxShape3D + `validate_level_shapes` |
| TR-lvl-035 | ADR-0001 | D-13 frame time p99 ≤ 14 ms (AC-LVL-34) |
| TR-lvl-038 | ADR-0001 | D-9 + lint `validate_level_shapes()` (AC-LVL-38) |
| TR-lvl-039 | ADR-0001 | D-4 T-1 atomicité anti-race |

### 2.3 TRs restants Gap après ADR-0011

| TR-ID | Gap | Raison |
|-------|-----|--------|
| TR-lvl-008 | G-5 Collision Layer Taxonomy | Layers 4/5 utilisés mais taxonomie formelle hors scope ADR-0011 — ADR-0008 planifié |
| TR-lvl-042 | G-7 Audio System Binding | `surface_material` tagging requiert ADR Audio dédié |

### 2.4 Coverage Summary après ADR-0011 Accepted

| Status | Count | % | Delta vs r2 |
|--------|-------|---|-------|
| ✅ Covered | 78 | 89% | +19 (G-8 19 TRs closed) |
| ⚠️ N/A intentional | 4 | 5% | — |
| ❌ Gap non-blocker MVP | 6 | 7% | — |
| ❌ Gap ADR requis | 0 | 0% | −19 |
| **Foundation layer gaps** | **0** | **0%** | — |
| **Core layer gaps** | **0** | **0%** | — |

Feature layer : reste 2 Gaps (G-5 collision layers, G-7 audio binding) — bloquants stories Enemy/Hazard/Audio mais **pas** Level stories Sprint 1.

---

## 3. Cross-ADR Consistency — ADR-0011 vs upstream/parallel

### 3.1 ADR-0011 D-1/D-8 vs ADR-0007 D-5 (GSM scene transition policy)

- **ADR-0007 D-5** : `change_scene_to_file()` EXCLUSIVEMENT pour scenes menu ; étages via `LevelSystem.load_etage(id)` additive instanciée sous root.
- **ADR-0011 D-1** : single `.tscn` par étage, `ResourceLoader.load_threaded_request` + `add_child(_current_etage_root)` sous `get_tree().root` (D-3).
- **ADR-0011 D-8** : séquence `load_etage(id)` avec polling `_process` + émission `level_active` après `_validate_scene_hierarchy()` PASS — exactement ce que ADR-0007 D-7 `_on_level_active` consomme pour transitionner PLAYING.
- **Conflit** : aucun. Patterns alignés par construction (ADR-0007 a été écrit avec ADR-0011 déjà draft en parallèle, références croisées explicites).

### 3.2 ADR-0011 D-5 vs ADR-0005 D-5 (signals connection mode policy)

- **ADR-0005 D-5** : CONNECT_DEFERRED par défaut, SYNC autorisé sous 4 critères explicites (a-d : work léger, read-only, idempotent, pas de trigger chain).
- **ADR-0011 D-5** : table explicite par signal (level_active CONNECT_DEFERRED ; level_unloading/level_load_failed/level_load_slow/player_out_of_world SYNC ; etage_completed CONNECT_DEFERRED ; room_entered mixed selon consumer). Justifications conformes critères a-d.
- **Conflit** : aucun. Application directe du pattern.

### 3.3 ADR-0011 D-12 vs ADR-0005 REQ-5/6 (outbound-only + forbidden EventBus)

- **ADR-0005** : `event_bus_autoload_for_movement_intra_gameplay_events` forbidden ; outbound-only.
- **ADR-0011 D-12** : généralisation directe — `level_system_direct_reference_to_peers` + `mutate_level_state_from_peer_signal_handler` forbidden. Pas d'EventBus pour Level.
- **Conflit** : aucun. Cohérence architecturale renforcée.

### 3.4 ADR-0011 D-8 polling `_process` vs ADR-0001 D-1 autorité `_physics_process`

- **ADR-0001 D-1** : mutation d'état gameplay uniquement dans `_physics_process`.
- **ADR-0011 D-8** : polling `ResourceLoader.load_threaded_get_status()` dans `_process` — exception explicite documentée (ne mute pas d'état gameplay, orchestre state machine Level non-gameplay). `set_process(false)` dès `_state != LOADING`.
- **Conflit** : aucun. Exception documentée conforme au pattern exemption ADR-0001 (rendu, UI, streaming orchestration).

### 3.5 ADR-0011 D-9 BoxShape3D vs ADR-0001 (Jolt physics)

- **ADR-0001** : Jolt physics default 4.6.
- **ADR-0011 D-9** : `WorldBoundsVolume` obligatoirement `BoxShape3D` (Jolt broad-phase O(1) vs O(N) concave). Mesure attendue : ~5 μs vs ~1.5 ms / tick.
- **Conflit** : aucun. Décision engine-informée cohérente avec Jolt characteristics documentées.

### 3.6 ADR-0011 D-10 Shader Baker vs ADR-0003 (Rendering)

- **ADR-0003** : Forward+ + SMAA 1x + Compositor ; Shader Baker 4.5+ advisory.
- **ADR-0011 D-10** : Shader Baker + précompilation boot OBLIGATOIRE (promu d'advisory à obligatoire par ADR-0011). CI gate `lint-project-settings`.
- **Conflit** : aucun — ADR-0011 renforce une recommandation ADR-0003 sans la contredire. ADR-0003 reste source de vérité Forward+/SMAA ; ADR-0011 ajoute le contrat Shader Baker.

### 3.7 ADR-0011 D-2 OnboardingAnchors vs ADR-0006 Combat Rule 16

- **ADR-0006** / `player-combat-system.md` Rule 16 : combat onboarding contract sightline + safe zone étage 1.
- **ADR-0011 D-2** : sous-arbre optionnel `OnboardingAnchors` (FirstEnemySightline + SafeZoneCenter) étage 1 uniquement + D-6 `get_onboarding_anchors()` + D-7 invariant #9 (AC-LVL-54).
- **Conflit** : aucun. Contrat bilatéral Level → Combat figé.

### 3.8 Autorité `_state` Level

- ADR-0011 D-3 + D-12 : write access `_state` exclusif à LevelSystem + GSM orchestrateur (via `load_etage`/`unload_current`).
- Aucun autre ADR ne revendique cette autorité.
- **Conflit** : aucun.

**Conclusion consistency** : 0 conflit cross-ADR détecté entre ADR-0011 et ADR-0001/0003/0005/0006/0007.

---

## 4. ADR Dependency Ordering (après promotions r2 + r3)

```
Foundation layer (Accepted):
  ADR-0001 Physics Rate 60Hz + Jolt        [Accepted 2026-04-21]
  ADR-0003 Rendering & Display Latency     [Accepted 2026-04-21]
  ADR-0004 Input API & Focus               [Accepted 2026-04-21]

Core layer (Accepted):
  ADR-0002 Camera Scene Tree  (←0001)                 [Accepted 2026-04-21]
  ADR-0005 Movement Signals   (←0001/0002)            [Accepted 2026-04-21]
  ADR-0007 GSM               (←0001/0004/0005)        [Accepted 2026-04-23 r2]

Feature layer:
  ADR-0006 Combat Tick Model  (←0001/0002/0005)       [Accepted 2026-04-23]
  ADR-0011 Level Scene Arch.  (←0001/0003/0005,
                               parallel to 0007)      [Proposed → Accepted ici r3]
```

- **ADR-0011 Depends On** : ADR-0001 ✅, ADR-0003 ✅, ADR-0005 ✅ — tous Accepted.
- **Parallel** : ADR-0007 promu ce jour en r2, indépendamment figeable (ADR-0011 §Ordering Note ligne 27 confirme).
- **Cycles** : 0.
- **Unresolved deps** : 0.

---

## 5. Engine Compatibility — ADR-0011

### 5.1 Audit §Engine Compatibility

| Dimension | Result |
|-----------|--------|
| Engine version | ✅ Godot 4.6 consistent |
| Post-cutoff APIs | 🟡 MEDIUM risk noté : `ResourceLoader.load_threaded_request` (stable pré-4.3), Shader Baker 4.5+, D3D12 default 4.6, NavigationRegion3D baked 4.6 — tous documentés engine-reference |
| Deprecated API references | ✅ 0 match (Node3D/Area3D/StaticBody3D/Marker3D stables pré-4.0) |
| Engine Compatibility section | ✅ Présente et complète avec References Consulted détaillées |
| Verification Required | ✅ 5 items listés (1)-(5) — gates Sprint 1 implémentation (pas pré-Accepted) |

### 5.2 Post-Cutoff API Consistency

ADR-0011 utilise 4 APIs post-cutoff, tous documentés engine-reference :

| API | ADR | Status |
|-----|-----|--------|
| `ResourceLoader.load_threaded_request()` / `load_threaded_get_status()` | ADR-0011 D-8 | ✅ Stable pré-4.3, confirmé 4.6 (rendering.md) |
| Shader Baker Project Settings (`rendering/shader_compiler/enable_shader_baker`) | ADR-0011 D-10, ADR-0003 | ✅ 4.5+ (rendering.md), renforcé obligatoire par ADR-0011 |
| D3D12 rendering backend default Windows | ADR-0011 D-10 (Shader Baker prerequisite), ADR-0003 | ✅ 4.6 default (rendering.md) |
| NavigationRegion3D `bake_navigation_mesh()` authoring-time | ADR-0011 D-11 | ✅ 4.6 stable (navigation.md) ; forbidden runtime explicite |

Cohérence cross-ADR : ADR-0003 et ADR-0011 alignés sur Shader Baker + D3D12. Pas de contradiction.

### 5.3 Deprecated API Check

Grep `adr-0011-level-scene-architecture.md` contre `deprecated-apis.md` — 0 match.

### 5.4 Pattern `_process` exemption (cohérence ADR-0001)

ADR-0011 D-8 utilise `_process` pour polling `ResourceLoader.load_threaded_get_status()`. Exception documentée explicite :
- Pas de mutation d'état gameplay (ADR-0001 D-1 respecté)
- `set_process(false)` dès `_state != LOADING` (pas de drain silencieux)
- Alternative synchrone rejetée (bloque main thread 300-1000 ms → casse Pillar 1)

Pattern conforme à l'exemption ADR-0001 pour orchestration non-gameplay (rendu, UI, streaming).

### 5.5 godot-specialist re-consultation requise ?

Les 5 Verification Required items sont des gates empiriques Sprint 1 impl :
1. `ResourceLoader.load_threaded_request` timing — mesurable seulement post-impl scène réelle
2. Shader Baker élimine freeze D3D12 — mesurable post-impl
3. BoxShape3D Jolt broad-phase O(1) — mesurable post-impl ou standalone runner
4. Draw calls p99 ≤ 350 — post-impl
5. Zero major alloc 60 s — post-impl

Ces items ne sont **pas** des unknowns sur le comportement moteur (comme ADR-0006 Gaps 2/7/8 étaient) — ce sont des **budgets à vérifier empiriquement sur l'implémentation**. Le GDD addendum godot-specialist (2026-04-23) a déjà validé engine-level (OQ-1 + OQ-5 CLOSED, Tech-Risk-1/2/3 résolus).

**Décision** : pas de re-consultation godot-specialist requise pour cette promotion. Les 5 VR sont gates Sprint 1 implementation-time, pas pré-Accepted. Cohérent avec pattern ADR-0005/0007 (ADR = design contract, impl validation via stories).

---

## 6. GDD Revision Flags

Aucun conflit GDD ↔ engine reality détecté :
- `level-system.md` r2 APPROVED 2026-04-23 avec addendum godot-specialist IMPLEMENTABLE WITH RISK résolu
- Hiérarchie R-1 GDD = D-2 ADR-0011 (mapping 1:1)
- F1-F8 formules GDD = D-7 invariants lint + D-13 budgets ADR-0011
- Tuning Knobs GDD = D-10 Shader Baker + D-13 budgets
- Signals GDD = D-5 ADR-0011 (mapping 1:1, 7 signaux)
- Lookups GDD = D-6 ADR-0011 (mapping 1:1, 6 APIs)
- States UNLOADED/LOADING/ACTIVE/UNLOADING + T-1..T-4 GDD = D-4 ADR-0011

**Aucun GDD à flager en "Needs Revision"**.

---

## 7. Verdict

### 7.1 Pour ADR-0011 spécifiquement

| Critère | Result |
|---------|--------|
| Coverage (GDD addressed) | ✅ 19 TRs G-8 + 6 co-covered + Combat Rule 16 + `architecture.md` §8.3 |
| Consistency upstream/parallel | ✅ 0 conflit ADR-0001/0003/0005/0006/0007 |
| Dependency order | ✅ Tous upstream deps Accepted ; parallèle ADR-0007 aligné |
| Engine compatibility | ✅ MEDIUM risk (D3D12/Shader Baker/Jolt) mais APIs toutes documentées engine-reference ; 5 VR = gates Sprint 1 |
| GDD revision flags | ✅ 0 flag (GDD r2 APPROVED, addendum godot-specialist intégré) |
| Pattern cohérence architecturale | ✅ Suit ADR-0005 (direct signals, CONNECT_DEFERRED par critères, outbound-only, forbidden EventBus) |

**Verdict ADR-0011** : ✅ **PROMOTE Proposed → Accepted** (design-contract pattern ADR-0005/ADR-0007)

### 7.2 Pour l'architecture globale

⚠️ **CONCERNS** (progression r2 → r3 : 67% → 89% Covered) — Gaps restants :

| Gap | TRs | Impact | Plan |
|-----|-----|--------|------|
| G-5 Collision Layer Taxonomy | TR-cmb-012, TR-lvl-008 | Bloque stories Enemy/Hazard/Boss/Secret | ADR-0008 dédié |
| G-7 Audio System Binding | TR-lvl-042, TR-cmb-013 (part.) | Non-blocker Sprint 1-2 Level ; blocker Sprint Audio | ADR Audio System dédié |
| G-2a/G-2b Save/Load Settings | TR-cam-006, TR-inp-009 | Non-blocker MVP | ADR-0014 post-MVP |
| G-4 Accessibility | TR-mov-008, TR-cmb-016 | Advisory MVP | ADR-0015 Polish |

### 7.3 Blocking issues pour verdict PASS architecture globale

- **G-5 Collision Layer Taxonomy** (ADR-0008 à créer — peut être rapide, inventaire des 5 layers déjà implicite ADR-0001 + GDD Combat/Level)
- G-7 Audio non-blocker Sprint 1-2 (Sprint 3+ pour Audio Director)
- Gaps G-2/G-4 post-MVP

**Après ADR-0008 (G-5) Accepted** : verdict architecture globale pourrait atteindre **PASS** (89% → ~91% Covered, 0 blocking gaps MVP Sprint 1-2).

---

## 8. Actions

### 8.1 Immédiat (cette session r3)

1. ✅ **Promouvoir ADR-0011 Status Proposed → Accepted 2026-04-23 r3** (file: `docs/architecture/adr-0011-level-scene-architecture.md`)
2. ✅ Mettre à jour `docs/architecture/architecture-traceability.md` v2.1 → v2.2 : G-8 19 TRs Covered, inverse index +ADR-0011, section §3.7 G-8 closed
3. ✅ Mettre à jour `docs/architecture/tr-registry.yaml` : `covered_by` pour 19+6 TRs
4. ✅ Append session extract à `production/session-state/active.md`

### 8.2 Prochains ADRs prioritaires

| Priority | ADR | Gaps Closed | Unblocks |
|----------|-----|-------------|----------|
| **P1** | **ADR-0008 Collision Layer Taxonomy** | G-5 | Stories Enemy/Hazard/Boss/Secret + Combat layer lint |
| P2 | ADR Audio System Architecture | G-7 | Sprint Audio |
| — | `/create-stories level-system` cluster C1 (Lifecycle+State Machine) | — | Sprint 1 backlog débloqué |
| — | `/create-epics menu-system` | — | Sprint 2 backlog |

### 8.3 Gate guidance

Quand ADR-0008 (G-5) Accepted : re-run `/architecture-review full` pour verdict potentiellement **PASS**. À ce stade `/gate-check pre-production` devient éligible.

---

## 9. Files Modified This Review

1. `docs/architecture/architecture-review-2026-04-23-r3-level.md` (NEW — ce document)
2. `docs/architecture/adr-0011-level-scene-architecture.md` (Status Proposed → Accepted)
3. `docs/architecture/architecture-traceability.md` (v2.1 → v2.2 : G-8 19 TRs closed)
4. `docs/architecture/tr-registry.yaml` (19 TRs covered_by [ADR-0011] + 6 co-covered)
5. `production/session-state/active.md` (session extract)

---

## 10. Reflexion Log

Aucun 🔴 CONFLICT détecté (0 conflit cross-ADR cross-domain). `docs/consistency-failures.md` n'existe pas — pas d'append.
