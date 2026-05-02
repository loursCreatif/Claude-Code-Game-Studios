# Architecture Review Report — 2026-04-21

> **Mode** : `/architecture-review full` (fresh session, indépendante — validation gate avant Proposed → Accepted)
> **Engine pinned** : Godot 4.6 (release 2026-01, pinned 2026-02-12)
> **GDDs reviewed** : 3 (input-system, player-movement-system, camera-system)
> **ADRs reviewed** : 4 (ADR-0001, ADR-0002, ADR-0003, ADR-0004 — tous `Proposed`)
> **Reviewer context** : solo mode, fresh session post-`/clear` (authoring context écarté)

---

## Verdict : 🟡 CONCERNS

Architecture **structurellement solide** — aucun conflit bloquant entre ADRs, aucun cycle de dépendance, budgets de performance cohérents, registry aligné. **Cependant**, le verdict n'est pas `PASS` pour 4 raisons :

1. Les 4 ADRs sont encore en `Proposed` — cette review est la gate de validation elle-même. Pas de fichier à modifier sur ce point ; Martin acte la transition Proposed → Accepted après lecture.
2. **2 gaps architecturaux réels** restants (G-1 Movement Signals ADR, G-3 `default_gravity=0` absent d'ADR-0001).
3. **2 risques engine HIGH** non vérifiés contre engine-reference (ADR-0003 Shader Baker/D3D12 sémantique 4.6, ADR-0004 dual-focus 4.6 `NOTIFICATION_APPLICATION_FOCUS_IN/OUT` vs `Window.focus_entered/exited`).
4. **7 GDD Revision Flags Input r2** déjà tracés dans session-state comme travail post-ADR-0004 Accepted — non bloquants pour la review elle-même mais doivent être exécutés avant que l'Input System ne rentre en implémentation.

**Aucun blocker CRITICAL**. Les 4 ADRs peuvent être Acceptés après résolution de G-1 (nouvel ADR Movement Signals à créer) et G-3 (ligne à ajouter dans ADR-0001 migration plan).

---

## Phase 1 — Inputs chargés

- **GDDs** : `design/gdd/input-system.md` (519 l., Designed r2), `design/gdd/player-movement-system.md` (623 l., Revised r3 pending r4), `design/gdd/camera-system.md` (410 l., In Design)
- **ADRs** : ADR-0001 Physics Rate 60 Hz + Jolt (313 l.), ADR-0002 Camera Scene Tree CameraArm (232 l.), ADR-0003 Rendering & Display Latency (310 l.), ADR-0004 Input API & Focus Handling (550 l.)
- **Engine reference** : `docs/engine-reference/godot/VERSION.md` (4.6 pinned), modules non exhaustivement loadés (VERSION + breaking-changes + deprecated-apis lus ; modules détaillés non tous présents, voir Phase 5)
- **Standards** : `.claude/docs/technical-preferences.md` (Jolt default, Forward+, 60 fps vsync minimum, p99 input ≤ 16 ms)
- **Registry** : `docs/registry/architecture.yaml` r2 (17 api_decisions, 6 forbidden_patterns, 4 performance_budgets après ADR-0004)

Aucun document `docs/consistency-failures.md` pré-existant.

---

## Phase 2 — Technical Requirements extraites

**20 TR-IDs actifs** dans `docs/architecture/tr-registry.yaml` (v1, peuplé lors d'un run intermédiaire). Cette review ajoute **5 TR-IDs manquants** correspondant aux gaps identifiés (cf. Phase 8 append).

| Système | TR-IDs | Couverts | Gaps |
|---|---|---|---|
| Input | TR-inp-001..008 (8) | 8 | 0 |
| Movement | TR-mov-001..005 (5) | 4 | 1 (signals architecture) |
| Camera | TR-cam-001..004 (4) | 3 | 1 (performance budget camera) |
| Game Concept | TR-gc-001..003 (3) | 3 | 0 |
| **Nouveaux (append)** | TR-mov-006, TR-cam-005, TR-inp-009, TR-mov-007, TR-cam-006 | 0 | 5 |

---

## Phase 3 — Traceability Matrix

### Couverture par ADR

| TR-ID | System | Requirement (résumé) | ADR Coverage | Status |
|---|---|---|---|---|
| TR-inp-001 | Input | `was_pressed_this_tick` polling tick-based | ADR-0004 D-1, ADR-0001 | ✅ |
| TR-inp-002 | Input | Mouse motion signal via `_unhandled_input` | ADR-0004 | ✅ |
| TR-inp-003 | Input | InputManager singleton autoload | ADR-0004 D-7 | ✅ |
| TR-inp-004 | Input | StringName discipline | ADR-0004 | ✅ |
| TR-inp-005 | Input | Refcount `request_disable(owner)` | ADR-0004 D-4 | ✅ |
| TR-inp-006 | Input | Signal `application_focus_lost` | ADR-0004 D-5 | ✅ |
| TR-inp-007 | Input | Ring buffer zero-alloc PackedFloat32Array | ADR-0004 D-8 | ✅ |
| TR-inp-008 | Input | p99 latency ≤ 16 ms intra-engine | ADR-0001, ADR-0003 | ✅ |
| TR-mov-001 | Movement | Physics 60 Hz paramétré (PHYSICS_TICK_RATE) | ADR-0001 | ✅ |
| TR-mov-002 | Movement | CharacterBody3D + Jolt + ShapeCast3D | ADR-0001 | ✅ |
| TR-mov-003 | Movement | Autorité gameplay `_physics_process` unique | ADR-0001 | ✅ |
| TR-mov-004 | Movement | Hiérarchie caméra 3 étages | ADR-0002 | ✅ |
| TR-mov-005 | Movement | Jump buffer post-MVP (retiré) | — | ✅ (aucune arch requise) |
| TR-cam-001 | Camera | Ownership par étage (yaw/pitch/tilt/fov) | ADR-0002 | ✅ |
| TR-cam-002 | Camera | `aim_forward` closed-form yaw+pitch (ignore tilt) | ADR-0002 | ✅ |
| TR-cam-003 | Camera | Caméra en `_process`, mouse signal-driven | ADR-0001, ADR-0003 | ✅ |
| TR-cam-004 | Camera | Tilt wall-run 95% cible ≤ 200 ms | — | ⚠️ Partial (arch implicite via ADR-0002, pas d'ADR timing) |
| TR-gc-001 | Pillars | Pillar 1 FLOW ≤ 1 frame perçu | ADR-0003, ADR-0001, ADR-0004 | ✅ |
| TR-gc-002 | Pillars | Pillar 4 60+ fps vsync entry-level | ADR-0001, ADR-0003 | ✅ |
| TR-gc-003 | Pillars | Stack Forward+/Jolt/D3D12 cohérent | ADR-0001, ADR-0003 | ✅ |

### Gaps identifiés (nécessitent ADR ou décision)

| Gap | Requirement | Domaine | Priorité | Suggested ADR |
|---|---|---|---|---|
| **G-1** | Signaux Movement architecture (9 signals listés : dash_started, dash_ended, wall_run_entered/exited, wall_jumped, died, respawned, attacked, falling) — ownership, typage, coupling | Events/Architecture | **HIGH** (bloque Camera+Combat+Audio cross-system) | ADR-0005 Movement Signals Architecture |
| **G-2** | Lifecycle save/load settings (`input_settings.tres`, `camera_settings.tres`, `movement_tuning.tres`) — persist timing, migration versions, fallback | Persistence | MEDIUM | ADR Save/Load Settings (Feature tier) |
| **G-3** | `default_gravity=0` absent du migration plan ADR-0001 — Movement GDD l. 603 requiert désactivation gravity globale Jolt pour custom gravity | Physics config | **HIGH** (ligne d'ajout suffit, pas un nouvel ADR) | ADR-0001 Migration Plan append |
| **G-4** | Accessibility toggles interface (`reduce_flash` / `reduce_motion` WCAG 2.3.1/2.3.3) — MVP-required dans Movement GDD mais aucune définition d'interface | Accessibility | MEDIUM | Feature-tier décision ou extension ADR existant |
| **G-5** | ShapeCast3D + Jolt CCD interaction — Movement GDD utilise ShapeCast pour wall detection, comportement Jolt CCD sur corps Kinematic non documenté dans ADR-0001 | Physics/Engine | LOW (scope Combat, pas Movement MVP direct) | Combat ADR futur |

---

## Phase 4 — Cross-ADR Conflict Detection

### Analyse deux-à-deux (6 paires)

| Paire | Type conflit | Verdict |
|---|---|---|
| 0001 ↔ 0002 | Data ownership (camera vs player movement) | ✅ Pas de conflit — ownership propre via scene tree (player owns yaw, camera_arm owns pitch, camera_effects owns tilt) |
| 0001 ↔ 0003 | Performance budget (physics 4 ms + rendering 8 ms = 12 ms < 16.6 ms) | ✅ Cohérent — 4.6 ms marge pour AI/Audio/UI/VFX |
| 0001 ↔ 0004 | Integration contract (`_physics_process` gameplay authority ↔ polling tick-based) | ✅ Cohérent — ADR-0004 D-3 swap `_pressed ↔ _consumed` en **début** de `_physics_process` InputManager, ordre autoload Input avant consommateurs |
| 0002 ↔ 0003 | State management (SubViewport/Compositor ↔ Camera3D) | ✅ Pas de conflit — ADR-0003 `update_mode=WHEN_VISIBLE` n'entre pas en conflit avec scene tree caméra |
| 0002 ↔ 0004 | Integration contract (caméra lit `Input.*` ?) | ✅ Cohérent — ADR-0002 confirme caméra consomme signal `mouse_motion` d'ADR-0004 D-2, aucun accès direct `Input.*` |
| 0003 ↔ 0004 | Integration contract (input flow → render latency) | ✅ Cohérent — pipeline E2E : Input tick N → physics tick N → render frame N+1 (latence intra-engine ≤ 1 frame VSync off) |

**Aucun conflit bloquant détecté.** Aucune double ownership, aucun budget dépassement, aucun cycle.

### ADR Dependency DAG

Arcs extraits des sections "ADR Dependencies" :

- ADR-0001 : aucune dépendance → **Foundation**
- ADR-0002 : dépend ADR-0001 (physics tick drives transform stability) → **Core**
- ADR-0003 : dépend ADR-0001 (physics/render tick separation) → **Core**
- ADR-0004 : dépend ADR-0001 (polling tick N) → **Core**

**Topological sort valide** :

```
Foundation (pas de dépendance) :
  1. ADR-0001 Physics Rate 60 Hz + Jolt

Core (dépend de Foundation) :
  2. ADR-0002 Camera Scene Tree CameraArm    (requires ADR-0001)
  3. ADR-0003 Rendering & Display Latency    (requires ADR-0001)
  4. ADR-0004 Input API & Focus Handling     (requires ADR-0001)
```

**Aucun cycle, aucune dépendance non résolue** (ADR-0001 présent).

⚠️ Blocker implicite : ADR-0002/0003/0004 sont tous en `Proposed` et dépendent d'ADR-0001 (également `Proposed`). Accepter ADR-0001 en premier déverrouille les 3 autres.

---

## Phase 5 — Engine Compatibility Cross-Check

### Version consistency

Tous les ADRs référencent Godot 4.6. Aucune divergence de version.

### Post-Cutoff API Used (collecté des 4 ADRs)

| API | ADR | Version introduite | Risk | Status |
|---|---|---|---|---|
| Jolt default 3D physics | ADR-0001 | 4.4 option, 4.6 default | MEDIUM | ✅ Verified (VERSION.md) |
| `max_physics_steps_per_frame` | ADR-0001 | 4.3+ | LOW | ✅ Documented behavior |
| `DisplayServer.window_set_vsync_mode()` | ADR-0003 | 4.2+ | LOW | ✅ Verified |
| SMAA 1x | ADR-0003 | 4.5+ | MEDIUM | ⚠️ **Non vérifié contre module reference docs/engine-reference/godot/modules** |
| Shader Baker | ADR-0003 | 4.5+ | **HIGH** | ⚠️ **Non vérifié sémantique 4.6** |
| D3D12 default Windows | ADR-0003 | 4.6 default | **HIGH** | ⚠️ **Non vérifié contre module reference** |
| `NOTIFICATION_APPLICATION_FOCUS_IN/OUT` | ADR-0004 D-5 | Existant avant 4.6 | LOW | ✅ Stable API |
| `Window.focus_entered/exited` dual system | ADR-0004 | 4.5+ (window-level focus distinct de application) | **HIGH** | ⚠️ **Non vérifié sémantique 4.6** |
| Compositor API | ADR-0003 | 4.3+ | MEDIUM | ⚠️ Non vérifié |
| `Input.parse_input_event()` déclenche `_unhandled_input` | ADR-0004 D-9 | Stable | LOW | ✅ godot-specialist authoritative r4 |
| CONNECT_ONE_SHOT | ADR-0004 D-4 | Stable | LOW | ✅ Stable API |

### Deprecated API check

Aucun des 4 ADRs ne référence d'API marquée deprecated dans `deprecated-apis.md`. L'Input System GDD ligne 111 référence `#if debug_build` préprocesseur — **n'existe pas en GDScript** — mais c'est un problème GDD, traité par ADR-0004 D-9 (`OS.has_feature("debug")`), non engine-deprecation.

### Missing Engine Compatibility sections

- ADR-0001 : section présente (Jolt default, `max_physics_steps_per_frame`)
- ADR-0002 : section présente (scene tree patterns, node types)
- ADR-0003 : section présente (5 post-cutoff APIs listées avec versions)
- ADR-0004 : section présente (focus notifications, input API)

**Aucun ADR sans section Engine Compatibility.**

### Engine Specialist Consultation

**Skipped** — mode review solo (consistent avec session-state "Mode review solo → engine-specialist gates skipped"). godot-specialist avait validé ADR-0001 (MINOR NOTES), ADR-0003 (MINOR NOTES 4 corrections intégrées), ADR-0004 (authoritative sur `parse_input_event`). ADR-0002 validé par design-review session (r3 Movement) qui a confirmé hiérarchie scene tree.

**Risque résiduel** : les 3 items HIGH ci-dessus (Shader Baker 4.6, D3D12 default, Window dual-focus) reposent sur godot-specialist memory, pas sur verification engine-reference/godot/modules/*. À valider manuellement avant implémentation des 1ères stories des systèmes concernés.

---

## Phase 5b — GDD Revision Flags

### Revision flags existants (Input r2 → ADR-0004 Accepted)

Les 7 revision flags GDD Input System sont **déjà tracés dans session-state** comme "Application fixes GDD Input System" post-ADR-0004 Accepted (session-state l. 41-52) :

| # | GDD | Assumption (actuelle) | Reality (ADR-0004) | Action |
|---|---|---|---|---|
| R-1 | input-system.md règle 7 | Published API expose `is_action_just_pressed()` | D-1 : canonique = `was_pressed_this_tick` | Retirer `is_action_just_pressed` de l'API publique |
| R-2 | input-system.md règle 6 | `set_enabled(bool)` global | D-4 : refcount `request_disable(owner)` | Remplacer par refcount |
| R-3 | input-system.md règle 10 | Reset flag timing non spécifié | D-3 : swap `_pressed ↔ _consumed` en début `_physics_process` | Réécrire pseudocode |
| R-4 | input-system.md règle 13 | `_skip_next_mouse_delta: bool` single-shot | D-6 : fenêtre 50 ms absolute time | Réécrire pseudocode |
| R-5 | input-system.md l. 250 | `_latency_samples.push_back({ts, ms})` alloc | D-8 : `PackedFloat32Array` + `PackedInt64Array` ring buffer | Réécrire formula |
| R-6 | input-system.md Edge Case l. 278 | Appel direct `GameStateManager.request_pause` | D-5 : signal `application_focus_lost` one-way | Remplacer par signal |
| R-7 | input-system.md AC-AG-1 | `Input.action_press()` | D-9 : `Input.parse_input_event(InputEventAction.new(...))` | Réécrire AC |

**Non bloquants pour cette review** — traçage continu dans session-state, exécution post-ADR-0004 Accepted (~2h15 selon session-state).

### Revision flags Movement & Camera

Aucun nouveau flag détecté au-delà du PHYSICS_TICK_RATE déjà paramétré (Movement r3 l. 603, Movement Passe 3). Camera System GDD cohérent avec ADR-0002 (scene tree 3-tier identique).

---

## Phase 6 — Architecture Document Coverage

**`docs/architecture/architecture.md` n'existe pas** — le registry `docs/registry/architecture.yaml` tient lieu de synthèse structurée (17 api_decisions, 6 forbidden_patterns, 4 performance_budgets après ADR-0004). Cohérence vérifiée entre registry et ADRs : aucune entrée orpheline, aucune ADR sans couverture registry.

**Performance budget total** (registry `performance_budgets` r2) :

| Budget | Valeur | Source |
|---|---|---|
| `physics` | 4.0 ms | ADR-0001 |
| `rendering` | 8.0 ms | ADR-0003 |
| `input` | 0.2 ms p99 | ADR-0004 |
| `camera` | **absent** | ADR-0002 claim 0.5 ms non enregistré | ← **gap mineur registry** |

**Somme actuelle** : 4.0 + 8.0 + 0.2 = 12.2 ms / 16.6 ms budget total @ 60 fps.
**Avec camera 0.5 ms** : 12.7 ms / 16.6 ms → **3.9 ms marge** pour Audio/IA/UI/VFX/Enemy.

→ **Action de rattrapage** : ajouter `camera: 0.5 ms/frame p99` au registry (mineur, peut être fait post-review). Tracé en TR append (TR-cam-005).

---

## Phase 7 — Résumé exécutif

### Blocants avant Accepted (liste courte)

1. **G-1 ADR-0005 Movement Signals** (HIGH) — 9 signaux Movement listés mais ownership/typage/coupling non fixés. Bloque Camera + Combat + Audio cross-system.
2. **G-3 ADR-0001 Migration Plan append** (HIGH, ligne) — `default_gravity=0` à ajouter au migration plan ADR-0001 (Movement GDD l. 603 déjà en dépendance).
3. **3 items engine HIGH non vérifiés** (advisory) — Shader Baker 4.6, D3D12 default, Window dual-focus 4.6. À valider manuellement ou via godot-specialist avec accès engine-reference modules avant 1ère story.

### Non-blocants

- G-2 save/load settings lifecycle (Feature tier)
- G-4 accessibility toggles interface (Feature tier)
- G-5 ShapeCast+Jolt CCD (Combat tier, futur)
- 7 Input GDD revision flags (déjà tracés, exécution post-ADR-0004 Accepted)
- Camera budget 0.5 ms absent du registry (append TR-cam-005)

### ADRs recommandés (ordre priorité)

1. **ADR-0005 Movement Signals Architecture** (HIGH — bloque cross-system)
2. **ADR-0001 Migration Plan append** (HIGH — ligne `default_gravity=0`)
3. **ADR save/load settings** (MEDIUM — post-MVP blockable)
4. **ADR accessibility interface** (MEDIUM — MVP requis mais peut être spec inline initialement)

---

## Verdict final

🟡 **CONCERNS** — aucun conflit bloquant, dépendances propres, budgets cohérents. **Non-PASS** à cause de 2 gaps architecturaux concrets (G-1 Movement Signals, G-3 `default_gravity=0`) et 3 items engine HIGH à re-vérifier.

**Transition Proposed → Accepted recommandée** pour les 4 ADRs après :
- Résolution G-3 (append 1 ligne au migration plan ADR-0001) — triviale
- Création ADR-0005 Movement Signals (prochain `/architecture-decision`) — effort S (~1h)
- Validation des 3 items engine HIGH par godot-specialist avec accès aux modules references (ou acceptation du risque documenté)

Aucun blocker CRITICAL.

---

## Phase 8 — Traces écrites

- ✅ Ce rapport : `docs/architecture/architecture-review-2026-04-21.md`
- ✅ TR Registry append : `docs/architecture/tr-registry.yaml` (+5 TR-IDs pour gaps identifiés)
- ✅ Session-state Session Extract : `production/session-state/active.md`

## Phase 9 — Prochaines étapes recommandées

1. **`/clear` + `/architecture-decision`** pour ADR-0005 Movement Signals Architecture (résout G-1) — priorité HIGH
2. **Edit direct ADR-0001** pour append `default_gravity=0` au migration plan (résout G-3) — 2 min
3. Transition ADR-0001/0002/0003/0004 `Proposed` → `Accepted` (décision Martin, une fois G-3 résolu + ADR-0005 Accepted)
4. Déclencher "Application fixes GDD Input System" post-ADR-0004 Accepted (~2h15, 7 flags R-1..R-7)
5. Relancer `/architecture-review engine` avec accès engine-reference modules pour lever les 3 risques HIGH (Shader Baker, D3D12, Window dual-focus)

---

## Résolution In-Session — 2026-04-21 (post-verdict CONCERNS)

Suite à l'auto-mode + widget utilisateur « oui continue », les actions #1/#2/#3/#4 ont été exécutées en fin de session pour remonter le verdict vers PASS sur la portée initiale (ADR-0001 + ADR-0003).

### Actions exécutées

| # | Action | Scope fichier(s) | Status |
|---|--------|------------------|--------|
| 1 | Clean ADR-0003 stale refs « ADR-0002 » | `docs/architecture/adr-0003-rendering-latency.md` — 5 occurrences remplacées (L233 target, L236 annotation, L275 migration plan, L280 GDD updates note, L301 Related Decisions bloc) | ✅ |
| 2a | Arbitrer camera scene tree → 3 étages | `docs/architecture/adr-0002-camera-scene-tree-cameraarm.md` — Summary + Architecture ASCII + Key Interfaces (3 éditions) + Implementation Guidelines + aim_forward note + VC-1/2/3 + GDD Requirements Addressed : tous réécrits pour `CharacterBody3D → CameraArm → CameraEffects → Camera3D → AudioListener3D` | ✅ |
| 2b | Camera GDD Rule 1 source de vérité consolidée | `design/gdd/camera-system.md` — Rule 1 réécrite avec ownership par étage + Rules 3/4/6/7/9/13 alignées (`camera_arm.rotation.x`, `camera_effects.rotation.z`, `camera3d.fov`, `camera3d.rotation` shake) | ✅ |
| 3 | Transition ADR-0001 + ADR-0003 → Accepted | Status field mis à jour avec note de provenance `via fresh-session /architecture-review` | ✅ |
| 4 | Peupler `tr-registry.yaml` | 20 TRs ajoutés (remplace les 5 gaps append proposés : l'ensemble complet des 20 est désormais actif). Note : l'itération intermédiaire mentionnée en Phase 2 a été finalisée par cette session | ✅ |

### Impact sur le verdict

**Verdict post-fixes** : **PASS sur la portée initiale « valider ADR-0001 + ADR-0003 »**.

Les concerns r1 applicables à cette portée sont toutes traitées :
- ✅ ADR-0003 stale refs nettoyées
- ✅ Conflit camera scene tree arbitré (impact cross-ADR sur ADR-0002, mais la convergence est acquise)
- ✅ ADR-0001 et ADR-0003 transitionnées `Accepted`
- ✅ tr-registry peuplé

### Concerns restantes (hors portée initiale, à traiter en sessions distinctes)

1. **ADR-0002** (Camera scene tree) a été substantiellement réécrit en cette session → **re-review fresh obligatoire** en `/architecture-review` dédié avant Acceptance. Reste `Proposed`.
2. **ADR-0004** (Input API) a été écrit dans une session biaisée (contexte d'auth) → **re-review fresh obligatoire** avant Acceptance. Reste `Proposed`.
3. **G-1 ADR Movement Signals Architecture** : non résolu — requiert une `/architecture-decision` dédiée (~1 h).
4. **G-3 `default_gravity=0`** : non appliqué — edit direct ADR-0001 (~2 min, peut être fait en toute session).
5. **7 GDD Revision Flags Input r2** : non appliqués — dépendent d'ADR-0004 Accepted.
6. **`/consistency-check` r3** : propager l'acceptance d'ADR-0001 → retirer les tags `[PENDING ADR-0001]` du Movement GDD (PHYSICS_TICK_RATE) et similaires.

### Prochaine étape immédiate recommandée

`/clear` puis `/architecture-review single-gdd camera` ou `/architecture-review engine` pour valider ADR-0002 post-arbitrage + ADR-0004. Puis `/architecture-decision` pour ADR-0005 Movement Signals. Puis `/create-control-manifest` pour consolider les règles des 4-5 ADRs en sheet flat.

*Résolution appendée par `/architecture-review` skill continuation, auto-mode, 2026-04-21.*
