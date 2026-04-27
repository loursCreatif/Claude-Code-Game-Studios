# Architecture Review Report — 2026-04-23 r4

| Field | Value |
|-------|-------|
| **Date** | 2026-04-23 (r4 — fresh session, solo auto-approve) |
| **Mode** | `/architecture-review full` |
| **Engine** | Godot 4.6 (Jolt 4.6 default, D3D12 Windows, Forward+ renderer) |
| **GDDs Reviewed** | 7 (game-concept, input, movement, camera, combat, game-state-manager, level) |
| **ADRs Reviewed** | 9 (ADR-0001..0008 + ADR-0011) |
| **Trigger** | Promotion ADR-0008 Proposed → Accepted (fermeture Gap G-5) |
| **Verdict** | ✅ **PASS** (premier PASS depuis début projet) |

---

## Executive Summary

Cette revue r4 promeut **ADR-0008 Collision Layer Taxonomy & Mask Canonicalization** de Proposed à Accepted, fermant le dernier Gap majeur identifié (**G-5** Collision Layers). Après cette promotion :

- **Foundation layer gaps : 0** ✅
- **Core layer gaps : 0** ✅
- **Feature layer blockers MVP : 0** ✅
- **Coverage globale : 80/88 Covered = 91%** (↑ de 89% r3)
- **Gaps restants : 4 non-blockers MVP** (G-2a/G-2b Save/Load, G-4 Accessibility, G-7 Audio) tous documentés avec ADRs planifiés Polish/post-MVP

**L'architecture MVP est maintenant PASS.** Le gate Technical Setup → Pre-Production est satisfait sur la dimension traceability. Les stories Sprint 1 (Combat, Level Authoring, Enemy downstream) peuvent être découpées sans bloquage architectural.

---

## 1. Traceability Summary

| Status | Count | % |
|--------|-------|---|
| ✅ Covered | 80 | 91% |
| ⚠️ N/A intentional | 4 | 5% |
| ❌ Gap non-blocker MVP | 4 | 5% |
| ❌ Gap ADR requis | 0 | 0% |
| **Total** | **88** | **100%** |

### Delta r3 → r4

- **Nouvellement Covered (2)** : TR-cmb-012 (Combat Rule 12 taxonomie layers) + TR-lvl-008 (Interactive Area3D Layer 5).
- **Second coverage (1)** : TR-lvl-007 (ADR-0008 ajoute second coverage à ADR-0001 sur Static Environment Layer 4).
- **Gap G-5 fermé** : TRs `covered_by: []` → `covered_by: [ADR-0008]` dans `tr-registry.yaml`.

---

## 2. ADR-0008 Promotion Validation

### 2.1 Promotion Criteria — PASS

| Critère | Status | Evidence |
|---------|--------|----------|
| **Upstream dependencies Accepted** | ✅ PASS | ADR-0001 Physics Rate 60Hz + Jolt Accepted 2026-04-21 |
| **0 cross-ADR conflict (blocking)** | ✅ PASS | Cf. §3 ci-dessous |
| **Engine compatibility documented** | ✅ PASS | `docs/engine-reference/godot/modules/physics.md` vérifié — Knowledge Risk LOW |
| **0 post-cutoff API sans verification** | ✅ PASS | API `set_collision_layer_value` / `set_collision_mask_value` pré-cutoff Godot 4.0 stable |
| **0 deprecated API** | ✅ PASS | Grep `deprecated-apis.md` : aucune correspondance |
| **Specialist validation** | ✅ PASS | godot-specialist APPROVE r3 sans blocker (session state r3 extract) |
| **GDDs cohérents (0 revision flag)** | ✅ PASS | ADR-0008 ratifie Combat Rule 12 + Level §AC-LVL-12/13 existants |
| **Validation Criteria listés** | ✅ PASS | VC-1..VC-7 testables (grep, test GUT, project.godot diff) |

### 2.2 TRs nouvellement couverts

| TR-ID | GDD | Requirement | Coverage post-ADR-0008 |
|-------|-----|-------------|------------------------|
| TR-cmb-012 | combat | Collision layer taxonomy 5 layers + archetype contracts | `[ADR-0008]` (Covered) |
| TR-lvl-007 | level | Static geometry Layer 4 LAYER_ENVIRONMENT | `[ADR-0001, ADR-0008]` (Covered — second layer) |
| TR-lvl-008 | level | Interactive Area3D Layer 5 LAYER_INTERACTIVE | `[ADR-0008]` (Covered) |

---

## 3. Cross-ADR Conflict Detection

### 3.1 ADR-0008 vs autres ADRs

**0 conflit bloquant**.

| Pair | Type de relation | Résultat |
|------|------------------|----------|
| ADR-0008 ↔ ADR-0001 | Upstream dep (physics engine) | ✅ Cohérent — Jolt consomme même API layer/mask bits |
| ADR-0008 ↔ ADR-0005 | Independent (signals ≠ physics layers) | ✅ Pas de couplage |
| ADR-0008 ↔ ADR-0006 | Downstream consumer (Combat Rule 12) | ✅ Cohérent — ADR-0008 ratifie sans changer les valeurs AC-CMB-09 |
| ADR-0008 ↔ ADR-0007 | Independent (GSM ≠ physics) | ✅ Pas de couplage |
| ADR-0008 ↔ ADR-0011 | Downstream consumer (Level §LAYER_*) | ✅ Cohérent — ADR-0011 référence "ADR-0008 planifié" (à MAJ post-promotion) |

### 3.2 Notes de cohérence (non-blocking)

1. **ADR-0006 D-4a MockEnemy l.177** — snippet `collision_layer = 0b00010` dans `tests/unit/combat/mock_enemy.gd`.
   - **Scope lint D-6** : cible `src/**/*.gd` exclusivement. Tests hors scope → pas de violation CI.
   - **Spirit D-3** : enfreint "Forbidden dans tout code `.gd`" — à migrer vers `set_collision_layer_value(CollisionLayers.LAYER_ENEMY, true)` lors impl Sprint 1 Combat.
   - **Action** : étendre Migration Plan ADR-0008 l.341 pour inclure ce snippet + Combat GDD l.88 dans les items GDD sync Sprint 1.

2. **ADR-0011 l.433/484** — texte mentionne "ADR-0008 planifié G-5, non écrit".
   - **Action** : MAJ cosmétique post-promotion pour `ADR-0008 Accepted 2026-04-23 r4`. Non-blocking.

### 3.3 ADR Dependency Ordering

Ordre topologique (post-promotion ADR-0008) :

```
Foundation (no deps) :
  1. ADR-0001 Physics Rate 60 Hz + Jolt
  2. ADR-0003 Rendering Latency

Core (depends on Foundation) :
  3. ADR-0004 Input API & Focus Handling       (deps: ADR-0001)
  4. ADR-0002 Camera Scene Tree CameraArm      (deps: ADR-0001)
  5. ADR-0005 Movement Signals Architecture    (deps: ADR-0001, ADR-0004)
  6. ADR-0007 Game State Manager               (deps: ADR-0001, ADR-0004, ADR-0005)

Feature (depends on Foundation/Core) :
  7. ADR-0006 Combat Tick Model                (deps: ADR-0001, ADR-0004, ADR-0005)
  8. ADR-0008 Collision Layer Taxonomy         (deps: ADR-0001)
  9. ADR-0011 Level Scene Architecture         (deps: ADR-0001, ADR-0003, ADR-0005, ADR-0007, ADR-0008 *)

* ADR-0011 est Accepted r3 sans dépendance formelle sur ADR-0008 (référence textuelle only
  — les contrats layers 4/5 étaient déjà respectés). Post-r4 promotion, référence devient
  hard dependency documentée.
```

**0 cycle détecté**. **0 dépendance non résolue**.

---

## 4. Engine Compatibility Audit

### 4.1 Version Consistency

Tous les 9 ADRs référencent Godot 4.6 (post-cutoff du modèle LLM sur Jolt/D3D12/AccessKit).

### 4.2 Post-Cutoff APIs

| ADR | Post-Cutoff API | Verification Status |
|-----|-----------------|---------------------|
| ADR-0001 | Jolt default physics engine (4.6) | ✅ Vérifié `physics.md` |
| ADR-0002 | Camera3D hierarchy patterns | ✅ Stable 4.0+ |
| ADR-0003 | D3D12 default Windows (4.6), SMAA (4.5) | ✅ Vérifié `breaking-changes.md` |
| ADR-0004 | Input singleton main-thread + ring buffer | ✅ Pattern stable 4.0+ |
| ADR-0005 | `call_deferred` + signal patterns | ✅ Stable 4.0+ |
| ADR-0006 | ShapeCast3D swept query + Callable injection | ✅ Stable 4.0+ |
| ADR-0007 | Tree node swap + scene lifecycle | ✅ Stable 4.0+ |
| **ADR-0008** | **`set_collision_layer_value` / `set_collision_mask_value` / `[layer_names]` section** | ✅ **Stable Godot 4.0+ — 0 post-cutoff** |
| ADR-0011 | Shader Baker (4.5), Jolt authoring invariants | ✅ Vérifié |

### 4.3 Deprecated API Check

```bash
# Grep ADR-0008 vs deprecated-apis.md : 0 match
```

**0 deprecated API référencée dans aucun ADR**.

### 4.4 Missing Engine Compatibility Sections

| ADR | Section Present | Risk Level |
|-----|----------------|------------|
| ADR-0001..0007 | ✅ | LOW-MEDIUM |
| ADR-0008 | ✅ | **LOW** |
| ADR-0011 | ✅ | MEDIUM (D3D12/Shader Baker/Jolt) |

**0 ADR avec blind spot engine**.

### 4.5 Engine Specialist Consultation

**godot-specialist** validation (session r3, session state extract) :

> APPROVE sans blocker — API stable 4.0+, 0 post-cutoff, réciprocité unilatérale Player→Enemy valide Jolt (mask Enemy body exclut Layer 1 — collision résolue côté Player mask=30), NavigationAgent3D utilise `navigation_layers` séparé de `collision_layer` donc layers 6-32 libres pour extensions futures sans conflit avec nav mesh authoring.

**0 finding supplémentaire** en session r4 (pas de re-consultation requise — ADR inchangé).

---

## 5. Design Revision Flags (Architecture → GDD Feedback)

**Aucun flag.**

ADR-0008 **ratifie** la taxonomie pré-existante :
- Combat GDD r6 Rule 12 (layers 0b00001 / 0b00010 / 0b00100 / 0b01000 / 0b10000)
- Level GDD r2 §AC-LVL-12/13 (LAYER_ENVIRONMENT=4, LAYER_INTERACTIVE=5)
- Movement GDD (wall-ray mask Layer 4)

Aucune valeur modifiée. ADR-0008 formalise : (a) les noms canoniques, (b) la Decision Matrix 7 archetypes, (c) l'API 1-indexée obligatoire (D-3), (d) le pool réservé layers 6-32, (e) le lint CI pre-build.

**Sync cosmétique** recommandé Sprint 1 (non-blocking) :
- Combat GDD l.88 : snippet illustratif `query.collision_mask = 0b00010` → pointer vers `CollisionLayers.build_mask([LAYER_ENEMY])`
- ADR-0011 l.433/484 : texte "ADR-0008 planifié" → "ADR-0008 Accepted 2026-04-23 r4"

---

## 6. Coverage Gaps (Post-Promotion)

### Foundation layer : 0 gap ✅
### Core layer : 0 gap ✅
### Feature layer (4 gaps non-blockers MVP)

#### G-2a — TR-cam-006 Save/Load Camera Settings
- **Status** : Non-blocker MVP, post-MVP planned ADR-0014
- **Impact** : camera tuning persistence — Polish tier

#### G-2b — TR-inp-009 Save/Load Input Settings
- **Status** : Non-blocker MVP, mutualisé G-2a
- **Impact** : input remap persistence — Polish tier

#### G-4 — TR-mov-008 + TR-cmb-016 Accessibility
- **Status** : Advisory MVP (spec inline GDDs existe), ADR-0015 Polish/Full Vision
- **Impact** : reduce_motion / reduce_flash interfaces — Polish tier

#### G-7 — TR-lvl-042 Material tags Audio binding
- **Status** : Non-blocker Sprint 1 Combat/Level, blocker Sprint Audio
- **Impact** : surface_material tagging pour audio footstep — Core Audio ADR

**Aucun de ces gaps ne bloque Sprint 1** (Combat, Level Authoring, Enemy System).

---

## 7. Verdict

### ✅ PASS (premier PASS architecture depuis début projet)

**Critères PASS** :
- ✅ Tous GDDs requirements mappés à ADRs actifs (91% Covered, 0 Foundation/Core gap)
- ✅ 0 cross-ADR conflict bloquant
- ✅ Engine compatibility vérifiée 9/9 ADRs (LOW-MEDIUM risk, 0 deprecated, 0 blind spot)
- ✅ 0 GDD revision flag
- ✅ Dependency ordering valide (0 cycle, 0 unresolved)
- ✅ 0 Feature blocker MVP restant

**Coverage chains complètes** :
- Input (9/9 active MVP) : 100%
- Movement (7/7 active MVP) : 100%
- Camera (5/5 active MVP) : 100%
- Combat (16/16 active MVP) : 100%
- GSM : couvert par ADR-0007
- Level (44/45 active MVP, TR-lvl-042 Gap G-7) : 98%

### Gates Franchis

- ✅ **Technical Setup → Pre-Production** (dimension architecture traceability)
- ✅ **Stories Sprint 1 Combat** peuvent être rédigées (contrats Combat Rule 12 ratifiés)
- ✅ **Stories Sprint 1 Level Authoring** peuvent être rédigées (scenes .tscn peuvent passer lint pre-build)
- ✅ **Stories Enemy / Hazard / Boss / Secret** peuvent commencer à être rédigées (taxonomie layers stable)

### Non-Blocking Follow-Ups (Sprint 0 Technical Setup)

1. **Mettre à jour `project.godot`** avec `[layer_names]/3d_physics/layer_1..5` canonique (ADR-0008 D-4).
2. **Créer `src/core/collision_layers.gd`** (helper `CollisionLayers` + `build_mask` static).
3. **Ajouter CI job `lint-collision-layers`** à `.github/workflows/tests.yml` (ADR-0008 D-6).
4. **Créer `tests/unit/collision/layer_mask_contract_test.gd`** (smoke test 7 archetypes).
5. **Créer `.claude/rules/collision-layer-api-1-indexed.md`** (pattern D-3 pour code review).
6. **Cosmetic MAJ** : Combat GDD l.88, ADR-0011 l.433/484, ADR-0006 D-4a MockEnemy.

### Prochaines ADRs Recommandées (Priority Order)

| Priority | ADR Title | Gaps Closed | Tier |
|----------|-----------|-------------|------|
| P2 | ADR Audio System Architecture | G-7 | Core (avant Sprint Audio) |
| P3 | ADR Save/Load Settings Infrastructure | G-2a + G-2b | Polish |
| P3 | ADR Accessibility Interface Layer | G-4 | Polish / Full Vision |

---

## 8. Blocking Issues

**Aucun.**

---

## 9. Handoff

### Immediate Actions (priorité haute)

1. **Sprint 0 Technical Setup** — Exécuter les 6 follow-ups §7 (4-6 h estimé, parallélisable).
2. **`/create-stories level-system`** — épic Level Sprint 1 (cluster C1/C2/C3) peut démarrer.
3. **`/create-stories combat-system`** — épic Combat Sprint 1 avec référence ADR-0008.

### Gate Check

> **`/gate-check pre-production`** peut être exécuté — architecture dimension est PASS.

### Re-run Trigger

Prochaine `/architecture-review` déclenchée quand :
- Nouvelle ADR (P2 Audio dans 1-2 semaines)
- Nouveau GDD (Enemy System quand Sprint 1 complète)
- Nouveau TR ajouté à `tr-registry.yaml`

---

## 10. Files Modified (r4 Session)

| File | Change |
|------|--------|
| `docs/architecture/adr-0008-collision-layer-taxonomy.md` | Status Proposed → Accepted 2026-04-23 r4 |
| `docs/architecture/architecture-traceability.md` | v2.2 → v2.3 (coverage 78→80, G-5 closed §3.4, inverse index §4 ADR-0008, §5 P1→DONE) |
| `docs/architecture/tr-registry.yaml` | `last_updated` r3→r4 ; TR-cmb-012 `covered_by: []` → `[ADR-0008]` ; TR-lvl-007 `[ADR-0001]` → `[ADR-0001, ADR-0008]` ; TR-lvl-008 `[]` → `[ADR-0008]` |
| `docs/architecture/architecture-review-2026-04-23-r4.md` | **NEW** — ce rapport |

**Non modifiés cette session** :
- ADRs 0001-0007, 0011 (pas d'évolution)
- GDDs (0 revision flag)
- `architecture.md` (r1 existant, à réécrire r2 en session dédiée `/create-architecture`)
- `control-manifest.md` (à régénérer après Sprint 0 Technical Setup inclut ADR-0008 rules)

---

## 11. Session State Extract

Voir `production/session-state/active.md` r4 pour le bref.
