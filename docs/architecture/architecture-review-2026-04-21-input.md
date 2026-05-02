# Architecture Review — single-gdd input (ADR-0004 validation)

> **Date** : 2026-04-21 (fresh session post-`/clear`)
> **Mode** : `/architecture-review single-gdd input` — validation indépendante d'ADR-0004 (dernier ADR Proposed parmi les 5)
> **Reviewer** : skill `architecture-review` en mode solo (TD-ADR gate + engine-specialist gate skipped)
> **Engine** : Godot 4.6 + GDScript
> **Verdict** : 🟢 **PASS** (avec 1 CONCERN cross-ADR résolu en séance)

---

## Scope

- **GDD** : `design/gdd/input-system.md` (r2, Designed, NEEDS REVISION r4 ADR-first path)
- **ADR principal** : `docs/architecture/adr-0004-input-api-focus-handling.md` (Proposed → **Accepted en séance**)
- **ADRs cross-référencés** : ADR-0001 (Physics Rate 60 Hz), ADR-0002 (Camera Scene Tree), ADR-0003 (Rendering Latency), ADR-0005 (Movement Signals)
- **TR Registry** : 9 TR-inp-* (001 à 009)

---

## Phase 1 — Load

| Artefact | Status |
|---|---|
| ADR-0001 Physics Rate 60 Hz | Accepted, read fully |
| ADR-0002 Camera Scene Tree | Accepted, cross-ref only |
| ADR-0003 Rendering Latency | Accepted, cross-ref only |
| ADR-0004 Input API & Focus Handling | **Proposed → Accepted ce review**, read fully |
| ADR-0005 Movement Signals | Proposed, cross-ref only (hors scope — /architecture-review dédié prévu) |
| GDD Input System | r2 Designed, lu intégralement |
| `docs/engine-reference/godot/modules/input.md` | Lu |
| `docs/engine-reference/godot/breaking-changes.md` | Lu (focus 4.5 SDL3 + 4.6 dual-focus) |
| `docs/engine-reference/godot/deprecated-apis.md` | Lu |
| `docs/architecture/tr-registry.yaml` | Lu (9 TR-inp-*) |
| `docs/registry/architecture.yaml` | Lu (interfaces + api_decisions + performance_budgets + forbidden_patterns) |

---

## Phase 2+3 — Traceability Matrix

| TR-ID | GDD anchor | ADR Coverage | Status |
|-------|-----------|--------------|--------|
| TR-inp-001 | règle 7 / AC-CS-1 | ADR-0004 D-1 + D-3 (swap pattern zero-alloc) ; ADR-0001 flag-via-signal authority | ✅ Covered |
| TR-inp-002 | règle 4 / architecture mouse flow | ADR-0004 Architecture Diagram + D-6 (fenêtre 50 ms) ; registry interface `mouse_motion_stream` | ✅ Covered |
| TR-inp-003 | règle 1 singleton autoload | ADR-0004 D-7 thread-safety Input.* main-only + ADR-0001 forbidden_pattern `is_action_just_pressed_direct_in_gameplay_physics_process` (couvre sous-cas) | ⚠️ Partial — la règle générale « interdiction de lire `Input.*` ailleurs que dans InputManager » n'est pas un forbidden_pattern registry ; seul le sous-cas `just_pressed` l'est. Advisory (coding standard). |
| TR-inp-004 | règle 8 StringName discipline | ADR-0004 utilise `StringName` dans toutes les signatures API | ⚠️ Partial — discipline rédigée GDD règle 8 mais non formalisée comme forbidden_pattern registry (« jamais de `is_action_just_pressed(some_string_var)` »). Advisory. |
| TR-inp-005 | règle 6 `enabled` gating | ADR-0004 D-4 refcount (30 lignes pseudo-code, auto-cleanup `tree_exited`) ; forbidden_pattern `set_enabled_bool_global_without_refcount` | ✅ Covered |
| TR-inp-006 | Edge Case l. 278 focus out | ADR-0004 D-5 signal découplage one-way ; registry interface `application_focus_events` | ✅ Covered |
| TR-inp-007 | Formulas latency l. 250 | ADR-0004 D-8 ring buffer `PackedFloat32Array`+`PackedInt64Array` ; forbidden_pattern `alloc_in_hot_path_via_literal_dict_or_pushback` | ✅ Covered |
| TR-inp-008 | Game Feel l. 383 p99 ≤ 16 ms intra-engine | ADR-0001 tick rate 60 Hz + ADR-0003 rendering budget + ADR-0004 input budget 0.2 ms/frame (registry) | ✅ Covered |
| TR-inp-009 | lifecycle save/load `input_settings.tres` | — | ❌ Gap G-2 (Input side) — Feature tier non-MVP-blocker. ADR save/load settings à créer (mutualisé avec TR-cam-006). |

**Totaux** : 9 TRs → **6 ✅ Covered** / **2 ⚠️ Partial (advisory)** / **1 ❌ Gap (Feature tier, non-MVP-blocker)**.

---

## Phase 4 — Cross-ADR Conflict Detection

### 🔴 CONFLICT C-1 — ADR-0001 vs ADR-0004 : timing reset flag `_pressed_this_tick`

**Type** : Integration contract conflict.

**ADR-0001 ligne 100 (avant edit)** :
> *« Le flag est **reset en fin de `_physics_process`** de l'InputManager »*

**ADR-0004 D-3** (lignes 123-166) aboutit explicitement après analyse interne au pattern **swap `_pressed ↔ _consumed` en ligne 1** de `_physics_process` (zero-alloc ref-swap). Le raisonnement montre que « reset en fin » casse AC-CS-1 : les consumers aval (Movement/Combat/Checkpoint) tournent **après** InputManager dans le même tick — lire le flag après reset retourne `false` systématiquement.

**Impact si non résolu** : un dev implémentant ADR-0001 littéralement produit du code où AC-CS-1 échoue à chaque tick. Bug silencieux sur hardware 144 Hz G-Sync — drop d'input one-shot.

**Résolution appliquée en séance (2026-04-21)** :
- **Edit 1** — ADR-0001 l. 100 : remplacé « reset en fin » par « consommé via swap `_pressed ↔ _consumed` en début — pattern canonique figé par ADR-0004 D-3 ».
- **Edit 2** — ADR-0001 l. 222 : remplacé référence stale `is_action_just_pressed(&"jump")` par `was_pressed_this_tick(&"jump")` + note « GDD à mettre à jour post-ADR-0004 Accepted, remplace méthode supprimée par ADR-0004 D-2 ».

**Statut post-résolution** : ✅ RÉSOLU. Cohérence cross-ADR restaurée. ADR-0004 reste la référence canonique pour le pattern input polling.

### Autres conflits

Aucun. Pairs analysées :
- ADR-0004 ↔ ADR-0002 : aucune interaction directe (Camera consomme `mouse_motion` signal — contrat stable).
- ADR-0004 ↔ ADR-0003 : complémentaires (intra-engine input vs display side) — additionnent pour Pillar 1 ≤ 50 ms E2E.
- ADR-0004 ↔ ADR-0005 : cohérence pattern (signals directs producer-to-consumer) — ADR-0005 D-1 réplique explicitement le pattern ADR-0004. `attacked` signal ADR-0005 = forward `was_pressed_this_tick(&"attack")` ADR-0004.

### ADR Dependency Order (topological)

```
Foundation:
  1. ADR-0001 Physics Rate 60 Hz (Accepted)

Core — dépendent uniquement d'ADR-0001 :
  2. ADR-0002 Camera Scene Tree      (Accepted)
  3. ADR-0003 Rendering Latency       (Accepted)
  4. ADR-0004 Input API & Focus        (Accepted ← ce review)
  5. ADR-0005 Movement Signals         (Proposed — /architecture-review dédié requis)
```

Aucun cycle. Aucune dépendance unresolved : ADR-0004 `Depends On` ADR-0001 Accepted → implémentable.

---

## Phase 5 — Engine Compatibility

| Point | Verdict | Note |
|---|---|---|
| `NOTIFICATION_APPLICATION_FOCUS_IN/OUT` Godot 4.6 | ✅ Stable | OS-level inchangées. Dual-focus 4.6 concerne widgets Control (mouse/touch vs keyboard/gamepad), **pas** les notifications OS-level de window focus. ADR-0004 VC-1 (validation runtime 3 OS) reste sage mais risque effectif LOW. Knowledge Risk HIGH flaggé par ADR-0004 = conservateur. |
| `Input.parse_input_event(InputEventAction)` | ✅ Stable | Confirmé seul path déclenchant `_unhandled_input` (godot-specialist authority r4). |
| `OS.has_feature("debug")` | ✅ Stable | Runtime check idiomatique Godot, existait pre-cutoff. Confirmé engine-reference. |
| `PackedFloat32Array` / `PackedInt64Array` + `.resize()` | ✅ Stable | API inchangée 4.x. Zero-alloc post-resize garanti. |
| `Input.mouse_mode` main-thread only | ✅ Cohérent | Singleton Input non documenté thread-safe — ADR-0004 D-7 pose la règle + forbidden_pattern `input_singleton_access_from_non_main_thread`. |
| Deprecated APIs référencées | ✅ Aucune | Grep ADR-0004 ∩ `deprecated-apis.md` = 0 match. |
| Dual-focus 4.6 impact | ℹ️ Hors scope | Concerne Controls (UI), pas InputManager qui opère au niveau OS. Pas de conflit. |
| SDL3 gamepad 4.5 | ℹ️ Hors scope MVP | Gamepad = Tier 2 post-MVP. API inchangée. |

**Engine Compatibility section d'ADR-0004** : présente, complète, Knowledge Risk HIGH correctement justifié par les 3 items `Verification Required` (focus 3 OS + dual-focus 4.6 semantic + zero-alloc bench).

---

## Phase 5b — GDD Revision Flags (Architecture → Design feedback)

Les 7 flags R-1..R-7 de la review r4 Input System sont **confirmés** par ce review :

| Flag | Action GDD post-Accepted |
|------|--------------------------|
| R-1 | Retirer `is_action_just_pressed` et `set_enabled(bool)` de la Published API (règle 7, lignes 76/97) |
| R-2 | Reset via swap `_pressed ↔ _consumed` en **début** de `_physics_process` (règle 10 — réécriture) |
| R-3 | Fenêtre 50 ms absolute time (règle 13 — remplace `_skip_next_mouse_delta: bool`) |
| R-4 | Ring buffer `PackedFloat32Array` + `PackedInt64Array` (Formulas Latency l. 249-253, remplace `Array[Dictionary]` + `push_back`) |
| R-5 | Signal `application_focus_lost` + GameStateManager consumer (Edge Case l. 278 — retirer appel direct `GameStateManager.request_pause()`) |
| R-6 | `OS.has_feature("debug")` + `parse_input_event(InputEventAction)` (règle 7 l. 111 — retirer `#if debug_build` ; AC-AG-1/2/3 → `parse_input_event`) |
| R-7 | AC-CS-1 tick N parity — déjà correcte GDD l. 493, maintenir |

Effort estimé application : **~2h15** (session dédiée post-Accepted ADR-0004).

---

## Phase 6 — Registry Updates

Aucune entrée registry à ajouter par ce review : les 4 interfaces (`input_polling_gameplay`, `application_focus_events`, `mouse_motion_stream`, `input_enable_gating`) + 7 api_decisions (`input_polling_api`, `input_enable_state`, `input_focus_burst_absorption`, `input_focus_event_coupling`, `latency_ring_buffer_format`, `debug_build_conditional`, `test_input_injection_api`) + 4 forbidden_patterns + 1 performance_budget (`input: 0.2 ms/frame`) sont **déjà** présents dans `docs/registry/architecture.yaml` r2 (append séance précédente 2026-04-21).

TR Registry (`docs/architecture/tr-registry.yaml`) : les 9 TR-inp-* sont présents. Aucun ajout ni renumérotation. TR-inp-009 reste `covered_by: []` (Gap G-2 Feature-tier délibéré).

---

## Phase 7 — Verdict

### 🟢 PASS

- **9/9 TRs** adressés (6 Covered + 2 Partial advisory + 1 Gap Feature-tier non-MVP-blocker).
- **1 CONFLICT cross-ADR (C-1) résolu en séance** par edits ADR-0001 l. 100 + l. 222 pointant vers ADR-0004 D-3.
- **Engine compatibility** : propre, aucun deprecated, aucun stale, Knowledge Risk HIGH conservateur avec Verification Required documenté.
- **ADR Dependency Order** : topologiquement sain, sans cycle.
- **Budgets performance cohérents** : input 0.2 + physics 4.0 + rendering 8.0 = 12.2 / 16.6 ms (marge 4.4 ms).
- **Pattern cohérent cross-ADR** : signals directs producer-to-consumer réplicable (ADR-0004 InputManager → ADR-0005 MovementController).

### Transition appliquée

**ADR-0004 `Proposed → Accepted`** (Date field updated : « 2026-04-21 (Proposed) → 2026-04-21 (Accepted via fresh-session /architecture-review single-gdd input — verdict PASS) »).

### Required follow-ups (non blockers pour Accepted)

1. **Application fixes GDD Input System** (~2h15, 7 flags R-1..R-7) — session dédiée, déjà tracée dans session state.
2. **ADR Save/Load Settings** (résout TR-inp-009 + TR-cam-006) — Feature tier, peut attendre phase Polish ou approche MVP+ settings menu.
3. **`/architecture-review single-gdd movement`** (ou autre variante ciblée ADR-0005) — valider indépendamment ADR-0005 Proposed → Accepted en fresh session.

---

## Phase 8 — Files written / updated

| File | Action |
|------|--------|
| `docs/architecture/adr-0001-physics-rate-60hz.md` | Edit l. 100 (reset → swap pattern) + l. 222 (stale `is_action_just_pressed` → `was_pressed_this_tick`) |
| `docs/architecture/adr-0004-input-api-focus-handling.md` | Status `Proposed → Accepted` + Date field update |
| `docs/architecture/architecture-review-2026-04-21-input.md` | **Ce rapport** (nouveau) |
| `production/session-state/active.md` | Session Extract append (section suivante) |
| `docs/architecture/tr-registry.yaml` | Non modifié (aucun nouveau TR à ce review) |
| `docs/registry/architecture.yaml` | Non modifié (toutes entrées ADR-0004 présentes depuis séance précédente) |

---

*Auteur : skill `/architecture-review` mode single-gdd input, 2026-04-21.*
*Mode review : solo — TD-ADR gate + engine-specialist gate skipped. Validation indépendante : ce review **EST** la fresh session post-`/clear` post-authoring ADR-0004 — contexte authoring écarté.*
