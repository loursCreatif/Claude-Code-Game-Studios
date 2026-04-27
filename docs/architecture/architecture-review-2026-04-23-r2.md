# Architecture Review — 2026-04-23 (r2, ADR-0007 promotion)

## Document Status

| Field | Value |
|-------|-------|
| **Mode** | `/architecture-review full` — focused on ADR-0007 promotion |
| **Date** | 2026-04-23 |
| **Engine** | Godot 4.6 (pinned 2026-02-12) |
| **GDDs Reviewed** | 7 (game-concept, input, movement, camera, combat, level, game-state-manager) |
| **ADRs Reviewed** | 8 (ADR-0001..0007 + ADR-0011) |
| **Registry Source** | `docs/architecture/tr-registry.yaml` v2 (88 TRs) |
| **Predecessor Review** | `architecture-review-2026-04-23.md` (verdict CONCERNS, 4 Gaps G-5..G-8) |
| **Consistency Failures Log** | `docs/consistency-failures.md` absent — skipped |

---

## 1. Executive Summary

Cette revue ciblée évalue l'**éligibilité de ADR-0007 Game State Manager** (Proposed 2026-04-23) à la promotion `Proposed → Accepted`. Les 3 upstream deps (ADR-0001/0004/0005) sont `Accepted` depuis 2026-04-21 ; ADR-0007 passe tous les critères (coverage, consistency, engine, dependency ordering) et est éligible à promotion immédiate.

L'état global de l'architecture reste **CONCERNS** en raison des gaps G-5 (Collision Layers), G-7 (Audio System), G-8 (Level Scene Anchors — partiellement adressé par ADR-0011 Proposed) et de ADR-0011 lui-même en statut Proposed. Ces gaps sont **non bloquants pour la promotion de ADR-0007**.

**Verdict ADR-0007** : ✅ **PROMOTE Proposed → Accepted**
**Verdict architecture globale** : ⚠️ **CONCERNS** (inchangé depuis 2026-04-23 review initial)

---

## 2. Coverage — ADR-0007 Impact

### 2.1 Gap G-6 RÉSOLU

5 TRs du Level System passent `Gap/Partiel → ✅ Covered` grâce à ADR-0007 :

| TR-ID | Requirement | Coverage avant | Coverage après |
|-------|-------------|----------------|----------------|
| TR-lvl-001 | Scene loading via GSM `load_etage()/unload_current()` atomique | ⚠️ Partiel ADR-0005 | ✅ ADR-0005 + **ADR-0007** (D-5 + D-10) |
| TR-lvl-028 | Reject concurrent `load_etage(id2)` quand state=Active | ❌ Gap G-6 | ✅ **ADR-0007** (D-2 + D-5 — GSM permet start_etage() uniquement en MENU) |
| TR-lvl-029 | Reject `load_etage()` si scene missing/corrupted → route error | ❌ Gap G-6 | ✅ **ADR-0007** (D-7 + contract gsm_level_orchestration, impl exacte via ADR-0011) |
| TR-lvl-033 | Safe idempotence `unload_current()` quand déjà unloaded | ❌ Gap G-6 | ✅ **ADR-0007** (D-5 — GSM appelle unload uniquement en * → MENU) |
| TR-lvl-034 | Complete reset on reload (quit-to-menu puis reload = fresh state) | ❌ Gap G-6 | ✅ **ADR-0007** (D-8 — transition BOSS_DEFEATED → MENU via request_new_run) |

### 2.2 TR-inp-006 — Consumer side now formalized

| TR-ID | Emitter ADR | Consumer ADR |
|-------|-------------|--------------|
| TR-inp-006 (`application_focus_lost` signal) | ADR-0004 D-5 (déjà Accepted) | **ADR-0007 D-6** (nouveau, formalise auto-pause conditionnel) |

### 2.3 Coverage Summary après ADR-0007 Accepted

| Status | Count | % | Delta |
|--------|-------|---|-------|
| ✅ Covered | 59 | 67% | +5 |
| ⚠️ N/A intentional | 4 | 5% | — |
| ❌ Gap non-blocker MVP | 6 | 7% | — |
| ❌ Gap ADR requis | 19 | 22% | −5 (G-6 closed) |
| **Foundation layer gaps** | **0** | **0%** | — |

Gate Technical Setup → Pre-Production reste satisfait (Foundation 0 gap).

---

## 3. Cross-ADR Consistency — ADR-0007 vs upstream

### 3.1 ADR-0007 D-6 vs ADR-0004 D-5 (focus signal)

- **ADR-0004 D-5** : InputManager emits `application_focus_lost()` one-way ; GameStateManager (aval) connecte dans son `_ready()` et appelle `request_pause("focus_lost")`.
- **ADR-0007 D-6** : GSM consomme `InputManager.application_focus_lost` SYNC dans `_ready()`, auto-pause conditionnel si `state == PLAYING`.
- **Conflit** : aucun. ADR-0007 est l'implémentation concrète de ce qu'ADR-0004 D-5 prescrivait côté aval. Les exemples de code s'alignent.

### 3.2 ADR-0007 D-7 vs ADR-0005 D-5 (Movement signals policy)

- **ADR-0005 D-5** : signals Movement consommés via `CONNECT_DEFERRED` par défaut, SYNC uniquement si besoin explicite.
- **ADR-0007 D-7** : GSM consomme `died`/`respawned` via `CONNECT_DEFERRED` — conforme policy par défaut.
- **Conflit** : aucun.

### 3.3 ADR-0007 D-7 vs ADR-0006 D-6 (Combat SYNC exemption on `died`)

- **ADR-0006 D-6** : CombatSystem consomme `died` SYNC (exemption documentée zero-alloc post-hit).
- **ADR-0007 D-7** : GSM consomme `died` DEFERRED (state tracker seulement).
- **Mix SYNC + DEFERRED sur même signal** : ordre tick déterministe garanti par Godot 4.6 — Combat résout tick N (SYNC) → GSM transitionne RESPAWNING tick N+1 (DEFERRED). Rationale explicite dans ADR-0007 D-7 §connection mode.
- **Conflit** : aucun. Séquencement documenté.

### 3.4 Autorité `get_tree().paused`

- **ADR-0007 D-4** : GSM seul autorité pour mutation `get_tree().paused`. Forbidden pattern `scene_tree_paused_set_outside_gsm` enregistré registry.
- **Autre ADR revendiquant cette autorité** : aucun. ADR-0001/0002/0003/0004/0005/0006/0011 ne touchent pas `get_tree().paused`.
- **Conflit** : aucun.

### 3.5 Autorité `change_scene_to_file`

- **ADR-0007 D-5** : GSM seul appelant autorisé de `change_scene_to_file` pour scenes menu ; étages gameplay via `LevelSystem.load_etage()` (ADR-0011).
- **ADR-0011 (Proposed)** : hors scope cette revue, mais préliminairement aligné (load_etage additive via ResourceLoader.load_threaded_request, pas via change_scene_to_file).
- **Conflit** : aucun.

### 3.6 Authority RESPAWN_DELAY / player state reset

- **ADR-0005 D-3** : RESPAWN_DELAY owned par MovementController ; GSM ne pilote pas le timing.
- **ADR-0007 D-7** : GSM est **tracker d'état uniquement** — ne mute pas `player.velocity`, n'appelle pas `die()/respawn()`. Confirme séparation des responsabilités.
- **Conflit** : aucun.

### 3.7 Process_mode discipline

- **ADR-0007 D-4** : table exhaustive process_mode par système (autoloads ALWAYS, gameplay PAUSABLE, menu WHEN_PAUSED).
- **Autre ADR définissant un process_mode divergent** : aucun.
- **Conflit** : aucun.

**Conclusion consistency** : 0 conflit cross-ADR détecté entre ADR-0007 et ADR-0001..0006 + ADR-0011.

---

## 4. ADR Dependency Ordering

### 4.1 Graph actuel (statuts)

```
Foundation layer (no deps):
  ADR-0001 Physics Rate 60Hz + Jolt    [Accepted 2026-04-21]
  ADR-0003 Rendering & Display Latency [Accepted 2026-04-21]
  ADR-0004 Input API & Focus           [Accepted 2026-04-21]

Core layer:
  ADR-0002 Camera Scene Tree  (depends ADR-0001)     [Accepted 2026-04-21]
  ADR-0005 Movement Signals   (depends ADR-0001/0002) [Accepted 2026-04-21]
  ADR-0007 GSM                (depends ADR-0001/0004/0005) [Proposed → Accepted ici]

Feature layer:
  ADR-0006 Combat Tick Model     (depends ADR-0001/0002/0005) [Accepted 2026-04-23]
  ADR-0011 Level Scene Arch.     (depends ADR-0001/0003/0005/0007) [Proposed — out of scope]
```

### 4.2 Unresolved dependencies — ADR-0007 spécifique

- ADR-0007 depends on : ADR-0001 ✅ Accepted, ADR-0004 ✅ Accepted, ADR-0005 ✅ Accepted
- **Tous les upstream deps satisfaits** — ADR-0007 éligible à promotion Accepted.

### 4.3 Cycles

- Aucun cycle détecté.
- ADR-0007 n'apparaît dans aucun `Depends On` upstream de ADR-0001/0004/0005.
- ADR-0011 (Proposed) dépend de ADR-0007 — une fois ADR-0007 Accepted, ADR-0011 lui-même devient éligible (après résolution de ses propres validations).

### 4.4 Implementation order recommandé (après cette revue)

1. Foundation : ADR-0001, ADR-0003, ADR-0004 (déjà Accepted)
2. Core : ADR-0002, ADR-0005, **ADR-0007 (promu Accepted ici)**
3. Feature : ADR-0006 (Accepted), ADR-0011 (Proposed — revue séparée requise)

---

## 5. Engine Compatibility — ADR-0007

### 5.1 Audit

| Dimension | Result |
|-----------|--------|
| Engine version consistency | ✅ Tous ADRs alignés Godot 4.6 |
| Post-cutoff API usage | ✅ ADR-0007 n'utilise aucun API post-4.3 |
| Deprecated API references | ✅ 0 match (autoload + SceneTree.paused + change_scene_to_file + process_mode tous stables 4.0+) |
| Engine Compatibility section présente | ✅ ADR-0007 §Engine Compatibility complète (Knowledge Risk LOW) |

### 5.2 R-6 gotcha — `change_scene_to_file` 1 frame defer

ADR-0007 §Risks R-6 documente le comportement stable Godot 4.0→4.6 : `get_tree().change_scene_to_file(path)` est processé en **fin de frame** par SceneTree, pas synchrone. Mitigation (consumers `state_changed(MENU)` await 1 frame ou CONNECT_DEFERRED) est conforme au comportement vérifié du moteur.

### 5.3 godot-specialist pre-review (depuis session 2026-04-23)

La session précédente a déjà consulté godot-specialist pour l'écriture d'ADR-0007 — verdict `VALIDATE` (autoload pattern OK, pause discipline idiomatique, CONNECT_DEFERRED/SYNC mixed handlers corrects Godot 4.6). Les 2 fixes mineurs ont été intégrés :
- R-6 documenté
- Suppression emit state_changed(MENU) au boot → pattern pull via get_current_state()

**Re-consultation spécialiste** : non requise pour cette revue promotion (même ADR, pas de modification depuis validation).

---

## 6. GDD Revision Flags

Aucune hypothèse GDD ne contredit l'engine reality pour le domaine GSM :
- `level-system.md` §Dependencies ligne 605+ : décrit déjà un Game State Manager appelant `load_etage()` → aligné avec D-5.
- `input-system.md` D-5 : décrit déjà consumer `GameStateManager._on_focus_lost` → aligné avec D-6.
- `architecture.md` §6.4 : pose l'API provisoire GSM (enum State 5 valeurs, signal state_changed, request_pause/resume/scene_transition, get_current_state) → D-10 correspond **exactement** à cette spec avec extensions documentées (start_etage, request_new_run).

**Aucun GDD à flager en "Needs Revision"**.

---

## 7. Verdict

### 7.1 Pour ADR-0007 spécifiquement

| Critère | Result |
|---------|--------|
| Coverage (GDDs addressed) | ✅ 5 TRs Level + 1 TR Input (consumer) |
| Consistency upstream | ✅ 0 conflit ADR-0001/0003/0004/0005/0006/0011 |
| Dependency order | ✅ Tous upstream deps Accepted |
| Engine compatibility | ✅ LOW risk, APIs stables 4.0+, 0 deprecated |
| godot-specialist sign-off | ✅ VALIDATE verdict pré-promotion |
| GDD revision flags | ✅ 0 flag |

**Verdict ADR-0007** : ✅ **PROMOTE Proposed → Accepted**

### 7.2 Pour l'architecture globale

⚠️ **CONCERNS** (inchangé depuis 2026-04-23 initial) — Gaps restants :

| Gap | TRs | Impact | Plan |
|-----|-----|--------|------|
| G-5 Collision Layer Taxonomy | TR-cmb-012, TR-lvl-008 | Bloque stories Enemy/Hazard/Boss/Secret | ADR Collision Layers (ou fusionné ADR-0011) |
| G-7 Audio System Binding | TR-lvl-042, TR-cmb-013 (part.) | Non-blocker Sprint Combat ; blocker Sprint Audio | ADR Audio System Architecture |
| G-8 Level Scene + Anchors | 21 TRs Level | Bloque stories Level | **ADR-0011 Proposed** — revue dédiée requise |
| G-2a/G-2b Save/Load Settings | TR-cam-006, TR-inp-009 | Non-blocker MVP | ADR-0014 post-MVP |
| G-4 Accessibility | TR-mov-008, TR-cmb-016 | Advisory MVP | ADR-0015 Polish |

### 7.3 Blocking issues pour verdict PASS architecture globale

- ADR-0011 encore Proposed → promouvoir via `/architecture-review single-gdd level-system.md` ou revue dédiée
- G-5 Collision Layers à adresser (peut être fusionné ADR-0011)
- G-7 Audio System Binding (non-blocker Sprint 1-2, à traiter Sprint 3+)

---

## 8. Actions

### 8.1 Immédiat (cette session)

1. ✅ **Promouvoir ADR-0007 Status Proposed → Accepted 2026-04-23 r2** (file: `docs/architecture/adr-0007-game-state-manager.md`)
2. ✅ Mettre à jour `docs/architecture/architecture-traceability.md` (v2.1 : G-6 closed, 5 TRs Covered, inverse index +ADR-0007)
3. ✅ tr-registry.yaml — déjà à jour (last_updated mentionne G-6 RÉSOLU)
4. ✅ Append session extract à `production/session-state/active.md`

### 8.2 Prochains ADRs prioritaires

| Priority | ADR | Gaps Closed | Unblocks |
|----------|-----|-------------|----------|
| P1 | **ADR-0011 promotion Proposed → Accepted** (single-gdd level-system review) | G-8 (partiel) | Stories Level complètes |
| P1 | **ADR Collision Layer Taxonomy** (fusion ADR-0011 recommandée) | G-5 | Stories Enemy/Hazard/Boss/Secret |
| P2 | **ADR Audio System Architecture** | G-7 | Sprint Audio |
| P3 | ADR Save/Load Settings | G-2 | Polish tier |
| P3 | ADR Accessibility Layer | G-4 | Polish tier |

### 8.3 Gate guidance

Quand ADR-0011 Accepted + G-5 résolu : re-run `/architecture-review full` pour verdict potentiellement PASS.
Quand verdict PASS obtenu : `/gate-check pre-production` pour advancement.

---

## 9. Files Modified This Review

1. `docs/architecture/architecture-review-2026-04-23-r2.md` (NEW — ce document)
2. `docs/architecture/adr-0007-game-state-manager.md` (Status Proposed → Accepted)
3. `docs/architecture/architecture-traceability.md` (v2.0 → v2.1 : G-6 closed)
4. `production/session-state/active.md` (session extract)
5. `docs/architecture/tr-registry.yaml` (pas de modif additionnelle — déjà à jour v2 pré-review)

---

## 10. Reflexion Log

Aucun 🔴 CONFLICT détecté cette revue (0 conflit cross-ADR cross-domain). `docs/consistency-failures.md` n'existe pas — pas d'append.
