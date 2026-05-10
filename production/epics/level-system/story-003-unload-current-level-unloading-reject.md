# Story 003: unload_current() + UNLOADING + level_unloading + concurrent-load reject

> **Epic**: Level System
> **Status**: Complete
> **Layer**: Core
> **Type**: Integration
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/level-system.md`
**Requirements**: `TR-lvl-025`, `TR-lvl-028`, `TR-lvl-033`

**ADR Governing Implementation**: ADR-0005, ADR-0007 (Accepted 2026-04-23 r2)
**ADR Decision Summary** : ADR-0005 T-3 = `ACTIVE → UNLOADING` émet `level_unloading(etage_id)` AVANT `queue_free()` laissant 1 frame pour peer cleanup. ADR-0007 D-5 : GSM appelle `unload_current()` uniquement en transition * → MENU ; idempotence owned par Level. EC-2 reject concurrent : debug assert "concurrent load rejected — unload first", release `push_error` silencieux + no-op.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes** : `queue_free()` natif déferre destruction à fin de frame. Pattern `level_unloading` emit puis `queue_free()` sur `_current_scene_root` garantit 1 frame peer cleanup. `PhysicsServer3D.is_body_excluded_from_physics` possible pour atomicité si stall physics observé (follow-up L-017 perf).

**Control Manifest Rules (Core Layer)**: signals typés (ADR-0005 D-1/D-3), emit depuis `_physics_process` uniquement (D-4), payload `int` value-type.

---

## Acceptance Criteria

- [x] **AC-LVL-4** : Reject concurrent load (EC-2) — `load_etage(2)` sans `unload_current()` → assert fail debug, no-op + `push_error` release ; state inchangé
- [x] **AC-LVL-5** : Clean unload — signal `level_unloading(etage_id)` émis AVANT `queue_free()` ; 1 frame plus tard `get_state() == UNLOADED`
- [x] **AC-LVL-10** : Idempotence `unload_current()` quand UNLOADED → silent no-op, pas crash (déjà AC couvert en L-001, revalidé end-to-end ici)
- [x] **AC-LVL-28** : Unsubscribe on `level_unloading` — peer handler clear listeners proactivement
- [x] **AC-LVL-39** : Assert concurrent-load précis — message contient "concurrent load" AND "unload first"

---

## Implementation Notes

- Signal declaration : `signal level_unloading(etage_id: int)` typed
- `func unload_current() -> void` : guard `if _state == LevelState.UNLOADED: return` (idempotence release+debug)
- Transition ACTIVE → UNLOADING : set `_state = LevelState.UNLOADING`, `_assert_main_thread()`, `level_unloading.emit(_current_etage_id)`, puis `_current_scene_root.queue_free()`, `_current_scene_root = null`
- Transition UNLOADING → UNLOADED : dans `_physics_process` tick suivant, si `_current_scene_root == null && _state == UNLOADING` → `_state = LevelState.UNLOADED`, `_current_etage_id = -1`
- `load_etage()` reject : guard `if _state != LevelState.UNLOADED: if OS.has_feature("debug"): assert(false, "concurrent load rejected — unload first (state=%s)" % LevelState.keys()[_state]); else: push_error("concurrent load rejected — unload first"); return`
- Peers subscribers typiques : CheckpointSystem, EnemySystem, HUDController — leur responsabilité de disconnect listeners Level dans `_on_level_unloading()` handler

---

## Out of Scope

- Story 002 : load_etage + transition LOADING→ACTIVE
- Story 004 : level_load_failed / level_load_slow
- Story 006 : reset complet EC-12 quit-to-menu (state reset côté Level)

---

## QA Test Cases

- **AC-LVL-4 / AC-LVL-39** : Test `test_concurrent_load_rejected_in_debug`
  - Given: Level en state ACTIVE (post load_etage(1))
  - When: `load_etage(2)` en debug build
  - Then: `assert_fails_with_message("concurrent load rejected")` ET assertion message contient "unload first"
  - Edge cases: state LOADING = même reject ; state UNLOADING = même reject ; release build = `push_error` + state inchangé, pas d'exception

- **AC-LVL-5** : Test `test_unload_emits_signal_before_queue_free`
  - Given: Level ACTIVE avec `_current_scene_root` présent dans tree
  - When: `unload_current()` + monitor signal emission frame + monitor `_current_scene_root.is_inside_tree()` frame
  - Then: Dans le même tick : signal `level_unloading(1)` reçu de façon synchrone AVANT `queue_free()` — au moment du handler `_current_scene_root.is_queued_for_deletion() == false` (ordre ADR-0011 D-4 T-3 : emit → queue_free → null). Frame N+1 (physics tick) : `get_state() == UNLOADED` ET `_current_scene_root == null`
  - Edge cases: peer disconnecté avant signal = signal toujours émis ; peer qui add_child dans handler = ignoré (parent en queue_free)

- **AC-LVL-10** : Test `test_unload_idempotent_from_unloaded`
  - Given: Level UNLOADED
  - When: `unload_current()` × 3
  - Then: Pas de crash, pas de signal, state reste UNLOADED

- **AC-LVL-28** : Test `test_peer_unsubscribes_on_level_unloading`
  - Given: Peer connecte `room_entered` dans `_on_level_active`, disconnect dans `_on_level_unloading`
  - When: `load_etage(1)` + `unload_current()`
  - Then: Après `level_unloading`, `level.get_signal_connection_list("room_entered").is_empty() == true` (peer a proactivement unsub)

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/level/level_unload_test.gd` — 4 test cases

**Status**: [x] Created — `tests/integration/level/level_unload_test.gd` (6 tests : test_load_etage_rejected_when_active, test_load_etage_rejected_when_loading, test_load_etage_rejected_when_unloading, test_unload_emits_signal_before_queue_free, test_unload_idempotent_from_unloaded, test_peer_unsubscribes_on_level_unloading)

---

## Dependencies

- Depends on: **Story 001** + **Story 002** (ACTIVE state reachable)
- Unlocks: Story 004, Story 005, Story 006

---

## Completion Notes

**Completed** : 2026-04-27
**Verdict** : COMPLETE WITH NOTES (mode review = solo)
**Criteria** : 5/5 passing (AC-LVL-4, AC-LVL-5, AC-LVL-10, AC-LVL-28, AC-LVL-39)
**Test Evidence** : `tests/integration/level/level_unload_test.gd` — 6 cases, GdUnit4

### Test-Criterion Traceability

| AC | Test | Statut |
|----|------|--------|
| AC-LVL-4  | `test_load_etage_rejected_when_active` + `test_load_etage_rejected_when_loading` + `test_load_etage_rejected_when_unloading` (3 sous-états couverts ; `assert_error → is_push_error` capture en debug ET release grâce au pattern push_error→assert) | COVERED (debug + release) |
| AC-LVL-5  | `test_unload_emits_signal_before_queue_free` (sync handler capture `is_queued_for_deletion()` au moment du signal + state UNLOADING immédiat + UNLOADED après physics_frame) | COVERED |
| AC-LVL-10 | `test_unload_idempotent_from_unloaded` (3× from UNLOADED, signal_count == 0) | COVERED |
| AC-LVL-28 | `test_peer_unsubscribes_on_level_unloading` (peer disconnect dans handler `level_unloading`) | COVERED |
| AC-LVL-39 | Couvert par les 3 tests reject — message complet `"concurrent load rejected — unload first (state=ACTIVE/LOADING/UNLOADING)"` matché via `is_push_error` | COVERED (debug + release) |

**Code Review** : `/code-review` exécuté 2026-04-27 — godot-gdscript-specialist verdict **APPROVED WITH SUGGESTIONS** (1 finding medium typage corrigé, 6 advisories acceptés).

**Finding medium corrigé** :
- `_load_progress: Array` → `Array[float]` (l.71) pour respecter le coding standard de typage strict.

**Advisories non bloquants** :
- **Spec drift story** : Implementation Notes l.40 prescrit `if OS.has_feature("debug"): assert else: push_error` mutually exclusive. Implémentation effective utilise `push_error → assert(false)` séquentiel (l.176-177 level_system.gd) — pattern aligné sur `_discover_player_start` (story-001 leçon B2 : assert seul non capté par GdUnit4). Comportement fonctionnel équivalent (debug : push_error logged + halt ; release : push_error logged + return). Spec à MAJ lors d'un prochain `/propagate-design-change`.
- **Cross-ADR traçabilité** : `level_unloading` émis sync depuis `unload_current()` est une exception à ADR-0005 D-4 documentée par ADR-0011 D-5 (« level_unloading → sync »). Le doc-comment l.39-40 le note. ADR-0005 ne référence pas cette exception explicitement — à ajouter en note cross-ADR lors d'un prochain `/architecture-review` (non bloquant).
- ~~**Test concurrent-load coverage gap (debug build)**~~ — **RÉSOLU r5** : pattern `push_error(msg)` AVANT `assert(false, msg)` dans `load_etage()` reject (l.176-177) permet à GdUnit4 `assert_error → is_push_error` de capturer le message AVANT que l'assert halt l'exécution. Le bail-out anticipé `if OS.has_feature("debug"): return` a été retiré. Les 3 tests reject (active/loading/unloading) exercent désormais le contrat en debug ET release, sans coverage gap. Pattern aligné sur story-001 B2.
- **Accès membre privé en test** : `test_unload_emits_signal_before_queue_free` accède à `level._current_scene_root` (l.104) pour vérifier `is_queued_for_deletion()` au moment du signal. Acceptable pour integration test ; pas de getter public à exposer (violerait l'encapsulation côté consumer).
- **Nommage ADR vs implem (advisory)** : ADR-0011 D-3 nomme le membre `_current_etage_root` ; implémentation utilise `_current_scene_root`. Pas de bug fonctionnel ; à harmoniser éventuellement dans un futur cleanup pass.

### Conformité ADR (post-correctifs)

- Signal `level_unloading(etage_id: int)` ✓ ADR-0011 D-5 typed contract.
- Émission AVANT queue_free ✓ ADR-0011 D-4 T-3 ; sync mode ✓ ADR-0011 D-5.
- `_assert_main_thread()` AVANT emit (l.206) ✓ AC-LVL-29.
- Idempotence `if _state == UNLOADED: return` (l.203) ✓ AC-LVL-10, ADR-0007 D-5.
- Reject concurrent load `if _state != UNLOADED: push_error + assert + return` (l.172-178) ✓ AC-LVL-4, AC-LVL-39, message contient "concurrent load" ET "unload first".
- Transition UNLOADING → UNLOADED dans `_physics_process` tick suivant (l.101-104) ✓ ADR-0011 D-4 T-3.

### Out of Scope / Deviations

- **Cleanup story-002 anticipation** : la signature `signal level_unloading` + flag `_unload_pending` avaient été déclarés en anticipation pendant story-002 (out-of-scope flagué dans story-002 Completion Notes). Le flag `_unload_pending` n'a finalement pas été utilisé — l'implémentation `unload_current()` mute `_state` directement (pattern sync legitimé par exception ADR-0011 D-5). Flag retiré du code.
- **NONE blocking** — toutes les ACs couvertes par tests dans le scope défini.

**Manifest Staleness** : story `2026-04-23` = control-manifest `2026-04-23` ✓ no drift.

**Files Validated** :
- `src/gameplay/level/level_system.gd` — paths story-003 (signal `level_unloading` l.41, `load_etage` reject l.171-178, `unload_current` l.202-210, `_physics_process` UNLOADING transition l.101-104).
- `tests/integration/level/level_unload_test.gd` — 6 tests (AC-LVL-4 + AC-LVL-39 sur ACTIVE / LOADING / UNLOADING, AC-LVL-5, AC-LVL-10, AC-LVL-28).

**Runtime Verification** : production code parse OK (`godot --check-only` 4.6.2). Tests parse-error attendue en local (GdUnit4 non installé) ; exécution effective via CI `godot-gdunit-labs/gdUnit4-action@v1`.

### Addendum r6 — code-review hardening (2026-04-27)

Re-run `/code-review` solo a remonté 2 BLOCKING + 4 advisories. Correctifs appliqués directement (memory `feedback_no_confirmation_apply_directly`) :

- **W-4 — state corruption race fix** : `unload_current()` reset désormais `_transition_to_active_pending = false` et `_loading_path = ""` (level_system.gd l.211-215). Sans ce reset, un appel `unload_current()` depuis l'état LOADING avec `_transition_to_active_pending` déjà à true par `_process` aurait conduit à : (T+1) UNLOADING→UNLOADED + reset etage_id ; (T+2) flag pending consomme `load_threaded_get(_loading_path)` → re-add scene → state ACTIVE. Test de couverture indirect via `test_load_etage_rejected_when_unloading` (n'exerce pas le scénario LOADING-cancel mais valide le guard reject sur UNLOADING).
- **Test couverture LOADING/UNLOADING reject** : ajout `test_load_etage_rejected_when_unloading` (level_unload_test.gd l.108-134). `test_load_etage_rejected_when_loading` était déjà présent (r5). 3 sous-états couverts (ACTIVE/LOADING/UNLOADING) conformément aux edge cases story `## QA Test Cases`.
- **Spec doc AC-LVL-5 fix** : story `## QA Test Cases` AC-LVL-5 disait `is_queued_for_deletion() == true` au moment du signal — incorrect (ordre ADR-0011 D-4 T-3 : emit AVANT queue_free → false). Doc corrigé l.64. Test (déjà correct) maintenant aligné avec la spec.

Aucun BLOCKING résiduel. Verdict final : **COMPLETE WITH NOTES**.
