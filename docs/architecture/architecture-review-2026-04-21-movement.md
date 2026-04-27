# Architecture Review — Single-GDD Movement (ADR-0005 validation)

**Date** : 2026-04-21
**Mode** : `/architecture-review single-gdd movement` (fresh session post-`/clear`)
**Review mode projet** : solo (TD-ADR gate + engine-specialist secondaire skipped — cette review indépendante fresh-session EST la validation)
**Engine** : Godot 4.6 + GDScript + Jolt 3D + Forward+
**Scope** : `design/gdd/player-movement-system.md` (r3 révisé, 622 lignes) × ADR-0005 Movement Signals Architecture, cross-ref ADR-0001/0002/0004.
**GDDs revus** : 1 (Movement)
**ADRs revus** : 4 (ADR-0001 Physics, ADR-0002 Camera Scene Tree, ADR-0004 Input API, ADR-0005 Movement Signals)

---

## Verdict : 🟢 PASS

ADR-0005 couvre intégralement TR-mov-006 (architecture des 8 signaux Movement MVP). Cohérence cross-ADR confirmée sur les 4 paires analysées (0005 × 0001/0002/0004). Aucun conflit détecté, aucun deprecated API référencé, aucun blocker identifié. ADR-0005 **reste Accepted** (confirmation indépendante de la transition faite en session r2 full).

---

## Contexte

Cette review est une validation ciblée **indépendante** de la review full r2 du 2026-04-21 qui avait transité ADR-0005 `Proposed → Accepted`. Elle se focalise sur le couple GDD Movement × ADR-0005 pour :

1. Confirmer la couverture des TR Movement par les ADRs cités.
2. Détecter toute incohérence cross-ADR résiduelle spécifique au périmètre Movement (principalement 0005 × {0001, 0002, 0004}).
3. Valider indépendamment les 10 décisions canoniques D-1..D-10 d'ADR-0005 contre la Published API du GDD (l. 82–91).
4. Signaler d'éventuelles GDD revision flags post-Accepted non encore appliquées.

---

## Phase 1 — Inputs chargés

- `design/gdd/player-movement-system.md` (622 lignes, r3, status « Revised pending r4 fresh re-review »)
- `docs/architecture/adr-0001-physics-rate-60hz.md` (318 lignes, Accepted + amendé `default_gravity=0.0`)
- `docs/architecture/adr-0002-camera-scene-tree-cameraarm.md` (231 lignes, Accepted)
- `docs/architecture/adr-0004-input-api-focus-handling.md` (549 lignes, Accepted)
- `docs/architecture/adr-0005-movement-signals-architecture.md` (431 lignes, Accepted)
- `docs/architecture/tr-registry.yaml` (21 TRs)
- `docs/engine-reference/godot/VERSION.md` (4.6 pinned 2026-02-12)
- `docs/engine-reference/godot/breaking-changes.md` + `deprecated-apis.md`
- `production/session-state/active.md` (session précédente r2 PASS)

---

## Phase 2 — Technical Requirements Movement (8 TRs)

Extraits depuis le TR registry, vérifiés contre le GDD Movement :

| TR-ID | Requirement (résumé) | GDD ref | Domain |
|-------|----------------------|---------|--------|
| TR-mov-001 | Physics tick rate 60 Hz paramétré | l. 18, 156, 460, 600 | Physics |
| TR-mov-002 | CharacterBody3D + Jolt + ShapeCast3D + `%WallRayLeft`/`%WallRayRight` unique-name | l. 46, 602 | Physics |
| TR-mov-003 | Autorité gameplay `_physics_process` unique | Rule 9, l. 406 | Physics/Core |
| TR-mov-004 | Hiérarchie camera trois étages (CameraArm → CameraEffects → Camera3D → AudioListener3D) | l. 70, 420, 424–430 | Scene Composition |
| TR-mov-005 | Jump buffer post-MVP (0 impl MVP) | Rule 5, AC-MV-15 [POST-MVP] | Feature-tier |
| TR-mov-006 | Architecture signaux Movement (8 signals MVP + 1 réservé, direct typed, `_physics_process` only, CONNECT_DEFERRED critères, ordre déterministe, idempotence, zero-alloc, outbound-only) | l. 82–91, Published API | Events/Architecture |
| TR-mov-007 | `default_gravity=0.0` (évite double-cumul Jolt vs `GRAVITY=24` custom) | l. 603, 611 | Physics |
| TR-mov-008 | Accessibility toggles `reduce_flash` / `reduce_motion` (WCAG 2.3.1/2.3.3) | l. 382–388 | A11y/Interface |

---

## Phase 3 — Traceability Matrix

| TR-ID | ADR Coverage | Statut | Notes |
|-------|--------------|--------|-------|
| TR-mov-001 | ADR-0001 | ✅ Covered | `physics_ticks_per_second = 60` explicite (l. 62), GDD paramétré `PHYSICS_TICK_RATE` résolu |
| TR-mov-002 | ADR-0001 | ✅ Covered | Jolt default 4.6 + CharacterBody3D pattern ; `%WallRayLeft` unique-name `@onready` (godot-specialist F11) couvert par Published API pattern |
| TR-mov-003 | ADR-0001 | ✅ Covered | Règle d'autorité (l. 75–91 ADR-0001) explicite, forbidden_pattern `mutate_gameplay_state_in_process` registry |
| TR-mov-004 | ADR-0002 | ✅ Covered | 3 étages figés (l. 82–92 ADR-0002) ; VC-1 assert scene tree, VC-2/3 grep lint pitch/tilt sur mauvais nœuds |
| TR-mov-005 | — | ⚠️ N/A intentionnel | Jump buffer explicitement POST-MVP (decision Martin r2, AC-MV-15 tagué `[POST-MVP]`). `covered_by: []` volontaire. Non-blocker MVP. |
| **TR-mov-006** | **ADR-0005** | ✅ **Covered (sous review)** | **10 décisions canoniques D-1..D-10 couvrent tous les points REQ-1..REQ-8 listés dans ADR-0005 Context** |
| TR-mov-007 | ADR-0001 (amendé) | ✅ Covered | Project Settings section + Migration Plan ligne dédiée (G-3 résolu 2026-04-21) |
| TR-mov-008 | — | ❌ Gap G-4 | Accessibility interface à spécifier (ADR dédié OU inline spec). **Non-blocker MVP** — A11y toggles MVP-required par Steam release mais spec implémentable à partir de la description actuelle du GDD (l. 382–388). Trace existant session state. |

**Résultat couverture TR Movement** :
- ✅ Covered : 6/8
- ⚠️ N/A intentionnel : 1/8 (TR-mov-005)
- ❌ Gap : 1/8 (TR-mov-008, non-blocker MVP, pre-existing)

**Couvrables (hors N/A et post-MVP) : 6/7 = 86 %. Gap G-4 pre-existing documenté.**

---

## Phase 3 bis — Validation TR-mov-006 : 10 décisions D-1..D-10 × Published API GDD

Cross-vérification exhaustive des décisions ADR-0005 contre la liste GDD Movement l. 82–91 et les règles associées :

| Décision ADR-0005 | GDD Movement confirme ? | Notes de validation |
|--------------------|-------------------------|----------------------|
| **D-1** Direct typed signals depuis MovementController | ✅ Oui (l. 82 « émis depuis le Player node, avec payload typé ») | Aligned. Pattern identique ADR-0004 (InputManager) — cohérence cross-ADR parfaite. |
| **D-2** 8 signals MVP figés + `falling` réservé post-MVP | ✅ Oui (l. 83–91 liste identique mot-à-mot) | Les 8 signatures GDD match exactement D-2 (`dash_started(dash_dir: Vector3, dash_speed: float)` etc.). `attacked()` bien décrit en GDD l. 91 et cohérent avec « forward from Input `attack` action ». |
| **D-3** Typage strict payloads Vector3/float, pas Dictionary/Array/Node/Resource | ✅ Oui (l. 93–94 note typed signals Godot 4.x debug-only) | GDD note explicitement le gap debug-only → D-3 impose test GUT contrat qui adresse ce gap (godot-specialist F5). |
| **D-4** Emit depuis `_physics_process` uniquement | ✅ Oui (cohérent règle d'autorité ADR-0001 + GDD Game Feel l. 406 « Polling dans `_physics_process` à 60 Hz ») | Aligned. `attacked` forward explicitement « depuis `_physics_process` » (ADR-0005 Key Interfaces l. 267). |
| **D-5** CONNECT_DEFERRED pour consumers lourds (critères a-d), sync pour light | ✅ Oui (l. 95–96 note godot-specialist F4 nuancé r3) | GDD description « lourd vs light » verbale, ADR-0005 D-5 formalise en 4 critères objectifs. Reference table MVP dans Migration Plan (VFX=DEF, Audio=DEF, Camera=sync, HUD=sync). |
| **D-6** Ordre intra-tick déterministe : sortie-avant-entrée, `died` terminal | ✅ Oui (AC-MV-41 idempotence `died`, AC-MV-24 Dashing → Dead transition) | GDD couvre partiellement : idempotence `died` OK, ordre intra-tick `dash_ended → died` pas explicitement testé en AC. **ACs symétriques à ajouter post-Accepted** (ADR-0005 Migration Plan l. 388) — non-blocker, tracé. |
| **D-7** Consumer contract interdisant mutation état Movement depuis signal handler | ✅ Oui (GDD Published API read-only pattern `get:` backing var, godot-specialist F7) | Aligned via godot-specialist F7 pattern (`_state` private, `state` read-only getter). |
| **D-8** Idempotence par transition (1× emit par entrée d'état) | ✅ Oui pour `died` (AC-MV-41 early return), **symétrie à étendre** aux autres entry signals | GDD couvre `died` via early return. ACs symétriques dash/wall_run à ajouter post-Accepted (Migration Plan ADR-0005). |
| **D-9** Zero-alloc signal dispatch | ✅ Oui (cohérent Pillar 1 GDD + forbidden_pattern `alloc_in_hot_path_via_literal_dict_or_pushback` ADR-0004) | GDD implicite via Pillar 1. ADR-0005 formalise + test GUT `MEMORY_STATIC delta < 64 KB`. |
| **D-10** MovementController outbound-only, zero knowledge of consumers | ✅ Oui (GDD l. 72–75 Interactions table descriptive scene-tree, pas de refs code) | **Pas de violation détectée**. La mention « Hiérarchie recommandée » l. 70 est descriptive pour guider la composition scene-tree, pas une référence code interdite par D-10. Lint VC-5 couvre enforcement. |

**Conclusion TR-mov-006 : 10/10 décisions ADR-0005 validées contre GDD Movement**. Les 3 ACs symétriques (D-6 ordre, D-8 idempotence généralisée) restent à ajouter post-Accepted au GDD (non-blocker pour Accept ADR, tracé Migration Plan).

---

## Phase 4 — Cross-ADR Conflict Detection

4 paires ADR-impactant-Movement analysées :

### 4.1 ADR-0005 × ADR-0001 (Physics Foundation)

| Point | ADR-0001 | ADR-0005 | Cohérence |
|-------|----------|----------|-----------|
| Autorité gameplay | `_physics_process` unique | D-4 emit depuis `_physics_process` exclusivement | ✅ Hérite et confirme |
| Budget physics | 4 ms / 16.6 ms (stub Sprint 1) | Signal dispatch cumulé ≤ 0.1 ms/frame amorti (VC-8) | ✅ Compatible (0.6 % du budget) |
| Timing tick-based | `Engine.get_physics_frames()` déterministe | Signals émis par tick déterministe | ✅ Cohérent |
| Dépendance déclarée | Foundation, no deps | Depends On : ADR-0001 | ✅ Ordre topologique respecté |

**Verdict** : ✅ Aucun conflit. ADR-0005 est une extension consistante d'ADR-0001.

### 4.2 ADR-0005 × ADR-0002 (Camera Scene Tree)

| Point | ADR-0002 | ADR-0005 | Cohérence |
|-------|----------|----------|-----------|
| Scene tree | 3 étages CameraArm/CameraEffects/Camera3D | Camera = consumer de signals Movement, connection mode D-5 | ✅ Orthogonaux |
| Camera mutations | `camera_arm.rotation.x` (pitch), `camera_effects.rotation.z` (tilt), `camera3d.fov` (FOV), `camera3d.rotation` (shake) | Camera = consumer sync (lerp target var, bool toggle) — D-5 critère light | ✅ Camera tilt wall-run lerp target = sync compatible avec D-5 |
| Ownership inversé | Camera lit `player.wall_normal`, `player.state`, `player.velocity` read-only | D-7 consumers read-only (interdit mutate Movement) | ✅ Parfaitement aligné |
| `aim_forward` closed-form | Camera expose `aim_forward` pour Combat (Rule 14 Camera GDD) | Orthogonal — ADR-0005 ne touche pas à `aim_forward` | ✅ No interaction |

**Verdict** : ✅ Aucun conflit. Camera = consumer correctement scopé par D-10 (inbound-to-Camera, outbound-from-Movement).

### 4.3 ADR-0005 × ADR-0004 (Input API)

| Point | ADR-0004 | ADR-0005 | Cohérence |
|-------|----------|----------|-----------|
| Pattern signals directs | InputManager émet `mouse_motion`, `application_focus_lost/gained` directement | D-1 MovementController émet 8 signals directement (pattern identique) | ✅ **Cohérence cross-ADR parfaite** — pattern réplicable futurs ADRs Combat/Audio/VFX |
| `attacked` forward | `was_pressed_this_tick(&"attack")` API canonique (D-1 ADR-0004) | D-2 `attacked()` signal = forward de `was_pressed_this_tick(&"attack")` | ✅ Aligned. Pattern explicite dans Key Interfaces ADR-0005 l. 267 |
| `_physics_process` discipline | InputManager swap `_pressed ↔ _consumed` en début `_physics_process` (D-3) | MovementController emit depuis `_physics_process` (D-4) | ✅ Ordre autoload : Input Foundation (1er) → Movement Core → Consumers |
| Ban `Input.is_action_just_pressed` | D-2 ADR-0004 forbidden | D-4 ADR-0005 implicite via ADR-0001 registry | ✅ Aligned |

**Verdict** : ✅ Aucun conflit. **Cohérence pattern cross-ADR remarquable** — le même pattern (direct typed signals sur le node source, consumer connecte via scene tree ou injection) est appliqué uniformément Input/Movement.

### 4.4 ADR-0005 D-10 × GDD Movement Interactions table

- **Point d'attention analysé** : GDD Movement Interactions table l. 70 mentionne « Hiérarchie recommandée : `CharacterBody3D → CameraArm → Camera3D` » dans la description du consumer Camera.
- **Analyse** : D-10 interdit à `movement_controller.gd` de contenir des références code aux consumers (`preload()`, `get_node()`, class name). La mention en GDD est **descriptive au niveau scene-tree composition**, pas une référence code. L'enforcement VC-5 (grep lint sur `src/core/movement_controller.gd`) cible bien les refs code, pas la documentation.
- **Verdict** : ✅ **Pas un conflit**. La Interactions table reste légitimement informative pour les devs Camera qui lisent le GDD Movement avant d'implémenter leur consumer.

### Synthèse Phase 4

**0 conflit cross-ADR détecté** sur les 4 paires analysées. ADR-0005 s'intègre proprement dans le réseau Foundation (ADR-0001) → Core (ADR-0002/0003/0004/0005).

---

## Phase 4b — DAG des dépendances ADRs

```
ADR-0001 (Physics — Foundation)
  │
  ├── ADR-0002 (Camera scene tree — Core)
  ├── ADR-0003 (Rendering & Display latency — Core)
  ├── ADR-0004 (Input API & Focus — Core)
  └── ADR-0005 (Movement Signals — Core)
```

- **Topologie** : DAG propre, 0 cycle, ADR-0001 Foundation unique, 4 ADRs Core parallélisables.
- **Status** : 5/5 Accepted.
- **ADR-0005 dépendances** : `Depends On: ADR-0001` déclaré dans le header ADR-0005 (l. 24). ADR-0001 Accepted → ADR-0005 Accepted possible. ✅ Satisfait.
- **ADR-0005 enables** : Camera Sprint 1 (tilt wall-run), Combat (hitbox `attacked`), Audio/VFX/HUD consumers — tous non encore écrits mais leur blocage est justifié par la stabilité API.

---

## Phase 5 — Engine Compatibility Audit

### 5.1 Version consistency

- Tous les ADRs targettent Godot 4.6 (pin 2026-02-12) ✓
- Aucun ADR stale version

### 5.2 Post-cutoff APIs (ADR-0005)

- **ADR-0005 Knowledge Risk** : LOW (déclaré).
- **Post-Cutoff APIs Used** : Aucune. Typed signals + `CONNECT_DEFERRED` + `emit_signal()` stables pré-4.0.
- **Vérification** : `breaking-changes.md` (Godot 4.4 → 4.5 → 4.6) ne liste aucun changement signal-related. ✅ Confirmé.

### 5.3 Deprecated APIs check

Recherche dans ADR-0005 des patterns listés dans `deprecated-apis.md` :
- `connect("signal", obj, "method")` string-based : **ZÉRO occurrence** — ADR-0005 utilise exclusivement `signal.connect(callable)` typed (D-10 exemple l. 204).
- `yield()` : 0 occurrence (tous les consumers lisent `player.state` read-only, pas d'await).
- `instance()` / `PackedScene.instance()` : 0 occurrence.
- `$NodePath` en `_process()` : 0 (D-4 impose `_physics_process`, et le pattern `@onready var` cached reference est la règle via godot-specialist F11).

**Verdict** : ✅ Aucun deprecated API référencé dans ADR-0005.

### 5.4 Verification Required (VC-1/2/3) — à valider Sprint 1

- **VR-1** Typed signal strictness debug build (mismatch connexion déclenche `push_error`) — couvert par VC-1 test GUT.
- **VR-2** Benchmark signal dispatch 8 signals × 3-6 consumers × 60 fps ≤ 0.05 ms/frame cumulé — couvert par VC-8.
- **VR-3** `emit_signal` depuis `_physics_process` avec `CONNECT_DEFERRED` exécute callback avant fin process_frame suivant — couvert par VC-3 (test ordre intra-tick).

**3 VRs à lever Sprint 1 post-impl. Non-blocker pour Accept.**

### 5.5 Engine specialist consultation

**Skipped** (mode solo review projet). Cohérent avec `production/review-mode.txt` et protocole ADR-0001..0005. Cette review indépendante (fresh session post-`/clear`) joue le rôle de la validation TD-ADR absente du mode solo.

---

## Phase 5b — GDD Revision Flags (Architecture → Design Feedback)

**Aucun nouveau flag identifié** par cette single-gdd review.

**Rappel des flags pre-existing tracés dans session state** (à appliquer post-Accepted avant first story Movement, ~30 min, **non-blockers pour le verdict PASS**) :

| # | Edit GDD Movement | Ligne | Raison |
|---|-------------------|-------|--------|
| 1 | Ajouter commentaire header canonical list | l. 82 Published API | `# Canonical list per ADR-0005 (D-2). Ajout d'un signal = amendement ADR-0005.` |
| 2 | Transformer « Connexions recommandées CONNECT_DEFERRED » en référence formelle | l. 74–75 | « Connection mode per ADR-0005 D-5 — see table » (critères a-d) |
| 3 | Marquer RÉSOLU le PENDING ADR signals | l. 619 (Progress) | « **ADR — Architecture signaux Movement** → **RÉSOLU par ADR-0005** » |
| 4 | Ajouter 3 ACs symétriques | Section Acceptance Criteria | AC-MV-XX (`dash_started` 1× par `* → Dashing`), AC-MV-YY (`wall_run_entered` 1× par `Airborne → WallRunning`), AC-MV-ZZ (`dash_ended` précède `died` si `die()` pendant Dashing) |

Ces 4 edits couvrent les requirements D-6/D-8 non encore testés à l'AC niveau. Une fois appliqués, le GDD Movement sera 100 % aligné ADR-0005.

---

## Phase 6 — Architecture Document Coverage

`docs/architecture/architecture.md` n'existe pas (pré-Production). Non applicable à ce stade.

---

## Phase 7 — Synthèse

### Traceability Summary

- **Total TR Movement** : 8
- ✅ **Covered** : 6 (TR-mov-001/002/003/004/006/007)
- ⚠️ **N/A intentionnel** : 1 (TR-mov-005 post-MVP)
- ❌ **Gap** : 1 (TR-mov-008 G-4 accessibility, non-blocker MVP, pre-existing)

### Coverage Gaps (hors scope ADR-0005)

| Gap | TR-ID | Criticité | Suggested ADR | Engine risk | Blocker MVP ? |
|-----|-------|-----------|---------------|-------------|---------------|
| G-4 | TR-mov-008 | MEDIUM | ADR ou inline spec « Accessibility Layer » (reduce_flash / reduce_motion ownership, defaults, propagation cross-system Camera/Movement/VFX) | LOW | Non (A11y MVP-required par Steam mais spec implémentable depuis GDD l. 382–388) |

### Cross-ADR Conflicts

**0 conflit détecté.**

### ADR Dependency Order

```
Foundation : ADR-0001 ✅ Accepted
Core       : ADR-0002 ✅ Accepted (CameraArm scene tree)
             ADR-0003 ✅ Accepted (Rendering latency)
             ADR-0004 ✅ Accepted (Input API & Focus)
             ADR-0005 ✅ Accepted (Movement Signals) ← confirmé par cette review
```

**5/5 Accepted, 0 cycle, ordre topologique respecté.**

### Engine Compatibility Issues

- ADRs avec section Engine Compatibility : 5/5 ✅
- Deprecated API references : 0
- Stale version references : 0
- Post-cutoff API conflicts ADR-0005 : 0
- **3 HIGH engine advisory** pre-existing (Shader Baker 4.5, D3D12 default 4.6, dual-focus 4.6) — hors scope ADR-0005, à lever via `/architecture-review engine` dédié avec accès modules reference.

---

## Verdict : 🟢 PASS

### Critères de passage

- ✅ Couverture TR Movement couvrables complète (6/7, hors 1 intentional N/A et 1 pre-existing non-blocker gap)
- ✅ TR-mov-006 (architecture signals Movement) couverte par ADR-0005 — 10/10 décisions D-1..D-10 validées contre Published API GDD
- ✅ Zéro conflit cross-ADR sur les 4 paires analysées
- ✅ Dépendance ADR-0005 → ADR-0001 satisfaite (Accepted)
- ✅ Engine Godot 4.6 clean (LOW risk, aucun deprecated API, aucun post-cutoff conflict)
- ✅ GDD Movement revision flags pre-existing tracés, non-blockers, ~30 min d'edits post-Accepted

### ADR-0005 status confirmé

**Accepted** (transitionné en session r2 full 2026-04-21, confirmé indépendamment par cette single-gdd review fresh-session).

### Non-blocker items (informatifs, pour suivi)

1. **4 edits GDD Movement post-Accepted** (~30 min) — voir tableau Phase 5b ci-dessus. À appliquer avant first story Movement Sprint 1.
2. **Gap G-4 TR-mov-008** (accessibility toggles) — à adresser avant release Steam (WCAG compliance). Spec implémentable à partir du GDD actuel, ADR ou inline spec dédié à écrire en phase Polish.
3. **3 HIGH engine advisory** pre-existing hors scope ADR-0005 — à lever via `/architecture-review engine` dédié.

---

## Recommandations immédiates (par priorité)

1. **Application fixes GDD Movement post-Accepted** (~30 min) — 4 edits listés Phase 5b.
2. **Application fixes GDD Input System post-ADR-0004 Accepted** (~2h15, 7 flags R-1..R-7 pending).
3. **Re-review `/design-review design/gdd/player-movement-system.md`** fresh session (statut r3 « pending r4 re-review » inchangé par cette review architecturale).
4. **`/design-review design/gdd/camera-system.md`** fresh session (toujours pending).
5. **`/gate-check pre-production`** — **éligible maintenant** (5/5 ADRs Accepted, pas de blocker architectural).
6. **`/architecture-review engine`** avec accès modules pour lever les 3 HIGH advisory engine pre-existing.
7. **Post-MVP / Feature tier** : ADR Save/Load Settings (G-2a/b), ADR ou inline spec Accessibility Layer (G-4).

---

## Required ADRs

**Aucun ADR supplémentaire blocker MVP.** Les 2 ADRs pending post-MVP (Save/Load Settings, Accessibility Layer) ne bloquent pas l'avance vers `/gate-check pre-production`.

---

*Auteur : /architecture-review single-gdd movement skill — fresh session post-`/clear` (2026-04-21)*
*Mode projet : solo (TD-ADR + engine-specialist secondaire skipped — cette review indépendante EST la validation)*
*Review précédente full r2 (2026-04-21) : verdict PASS, 5/5 ADRs Accepted. Cette single-gdd confirme indépendamment le périmètre Movement × ADR-0005.*
