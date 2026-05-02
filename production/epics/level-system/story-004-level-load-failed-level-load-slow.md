# Story 004: level_load_failed (EC-3) + level_load_slow advisory (EC-10)

> **Epic**: Level System
> **Status**: Complete
> **Layer**: Core
> **Type**: Integration
> **Estimate**: 5h (signals declarations 0.5h + load_etage error path + ResourceLoader.exists pré-check 1h + polling THREAD_LOAD_FAILED + slow timer 1.5h + 2 integration tests 2h)
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/level-system.md`
**Requirements**: `TR-lvl-026`, `TR-lvl-027`, `TR-lvl-029`

**ADR Governing Implementation**: ADR-0005, ADR-0007 (Accepted 2026-04-23 r2)
**ADR Decision Summary** : ADR-0005 D-3 payload `String` interdit pour hot-path mais autorisé sur error paths rares (1× par load failure). ADR-0007 D-7 : GSM consomme `level_load_failed` sync, transitionne MENU + affiche error screen.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes** : `ResourceLoader.load_threaded_get_status(path, progress)` retourne `THREAD_LOAD_FAILED` sur scene corrompue/inexistante. `ResourceLoader.exists(path)` pour pré-check missing file (optionnel — async load détecte aussi). `Time.get_ticks_msec()` pour mesure écoulé `level_load_slow`.

**Control Manifest Rules (Core Layer)**: signals typés (ADR-0005 D-1) ; String payload accepté uniquement car error path non hot (docs Rule 9 + exception error paths).

---

## Acceptance Criteria

- [x] **AC-LVL-6** : `level_load_failed` on missing scene — `load_etage(999)` (id inexistant) → signal `level_load_failed(999, reason)` reçu ; `reason` non vide ; state reste `UNLOADED`
- [x] **AC-LVL-7** : `level_load_slow` advisory (EC-10) — émis si load > 600 ms (seuil advisory, gate = 1000 ms story 017) ; load continue ; `level_active` toujours émis quand prêt

---

## Implementation Notes

- Signals declarations : `signal level_load_failed(etage_id: int, reason: String)` + `signal level_load_slow(elapsed_ms: int)` typed
- `load_etage()` pré-check optional : `var path := "res://scenes/levels/etage_%02d.tscn" % etage_id` ; `if not ResourceLoader.exists(path): _assert_main_thread() ; level_load_failed.emit(etage_id, "scene file not found: " + path) ; _state = LevelState.UNLOADED ; return`
- Polling `_process` : capturer `_load_started_msec := Time.get_ticks_msec()` au début de load ; chaque frame si status == `THREAD_LOAD_IN_PROGRESS` et `(Time.get_ticks_msec() - _load_started_msec) > 600` ET flag `_load_slow_emitted == false` : set flag, emit `level_load_slow(elapsed)` en `_physics_process` tick suivant
- Polling détecte `THREAD_LOAD_FAILED` : `level_load_failed.emit(etage_id, "ResourceLoader returned THREAD_LOAD_FAILED")` ; `_state = LevelState.UNLOADED` ; `_current_etage_id = -1`
- Reset flag `_load_slow_emitted = false` à chaque nouveau `load_etage()`
- Les signals error paths acceptent `String` (exemption documentée ADR-0005 D-3 — pas hot path)

---

## Out of Scope

- Story 002 : load path nominal
- Story 006 : reset complet EC-12 (re-load après quit menu)
- Story 017 : gate F4 mesure ≤ 1000 ms (budget hard gate, distinct de advisory 600 ms)

---

## QA Test Cases

- **AC-LVL-6** : Test `test_load_etage_999_emits_level_load_failed`
  - Given: Level UNLOADED, `res://scenes/levels/etage_999.tscn` inexistant
  - When: `load_etage(999)` + `await level.level_load_failed`
  - Then: Signal reçu avec args `(999, reason: String)` où `reason.length() > 0` ET `level.get_state() == UNLOADED` ET `level.get_current_etage_id() == -1`
  - Edge cases: path corrompu (binary garbage .tscn) — même signal émis avec reason distinct (THREAD_LOAD_FAILED)

- **AC-LVL-7** : Test `test_level_load_slow_emitted_after_600ms`
  - Given: Test scene synthétique `slow_etage.tscn` avec `@tool` script qui sleep 800 ms au parse (helper test only)
  - When: `load_etage(slow_id)` puis monitor signals pendant 1500 ms
  - Then: `level_load_slow(elapsed_ms)` reçu 1× avec `elapsed_ms >= 600` ET plus tard `level_active` reçu quand load terminé ; state passe bien à ACTIVE
  - Edge cases: load rapide < 600 ms → `level_load_slow` jamais émis ; re-load après slow → flag reset, re-emission possible

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/level/level_load_failures_test.gd` — 2 test cases

**Status**: [x] Created — 5 test functions (dépasse spec 2 minimum)

---

## Dependencies

- Depends on: **Story 002** (load path nominal)
- Unlocks: Story 017 (gate F4 mesure)

---

## Completion Notes

**Completed** : 2026-04-27 (r7 — verification re-entry après implémentation r6)

**Criteria** : 2/2 passing (AC-LVL-6 ✓ AC-LVL-7 ✓), 0 deferred

**Test coverage** : 5 test functions (dépasse spec 2 minimum)
- `test_load_etage_999_emits_level_load_failed` (AC-LVL-6 main)
- `test_load_etage_999_reason_contains_path` (AC-LVL-6 diagnostic)
- `test_level_load_slow_emitted_after_600ms` (AC-LVL-7 main)
- `test_level_load_slow_emitted_only_once_per_load` (AC-LVL-7 idempotence)
- `test_level_load_slow_flag_reset_on_reload` (AC-LVL-7 reset)

**Test Evidence** : `tests/integration/level/level_load_failures_test.gd` (262 lignes) + fixture `tests/fixtures/levels/test_etage_42.tscn`

**Files modifiés** :
- `src/gameplay/level/level_system.gd` (372 lignes — ajout 2 signals typés, polling THREAD_LOAD_FAILED, advisory slow load, emit deferred via `_physics_process`, helper test-only `_simulate_load_elapsed_ms`)

**Deviations** :
- ADVISORY : test count 5 vs 2 demandés — couverture renforcée des edge cases AC-LVL-7 (idempotence + reset flag), pas une régression
- ADVISORY : estimate `5h` ajouté retroactivement au header (gap /story-readiness fix r7)
- ADVISORY r8 : `THREAD_LOAD_FAILED` (scène corrompue) listé QA Test Cases AC-LVL-6 mais non testé — branche `_process` L.108-118 + constante `REASON_THREAD_LOAD_FAILED` non exercées (GAP-1 MEDIUM, qa-tester r8)
- ADVISORY r8 : `load_slow_threshold_ms = 0` off-switch documenté L.76 non testé (GAP-2 MEDIUM, qa-tester r8)
- ADVISORY r8 : branche `packed == null` post-`THREAD_LOAD_LOADED` (L.162) ne déclenche pas `level_load_failed` — état UNLOADED silencieux, inconsistant avec ADR-0007 D-7 (cas défensif rare en pratique)

**ADR compliance** : ADR-0005 D-3 (String exception error path) ✓ ; D-4 (emit `_physics_process` only via flags pending) ✓ ; D-8 (mutation état avant emit) ✓ ; ADR-0007 D-7 (GSM consumer compatible) ✓ ; ADR-0011 D-4 T-3 + D-5 ✓ ; zero-alloc hot path (reason String construite 1× hors poll) ✓

**Code Review** : Complete — passé en r6 (verdict initial CHANGES REQUIRED → 3 fixes appliqués RC-1/RC-2/RC-3 → final COMPLETE WITH NOTES). Re-review r8 via `/code-review` (godot-gdscript-specialist MINOR ISSUES + qa-tester GAPS) → verdict APPROVED WITH SUGGESTIONS, 4 advisories non-bloquantes. Solo mode : LP-CODE-REVIEW + QL-TEST-COVERAGE gates skip.

**Manifest staleness** : story 2026-04-23 = control-manifest 2026-04-23 — pas de drift

**Suggestions follow-up** (non-bloquant, à adresser avant story-017) :
1. Ajouter test `THREAD_LOAD_FAILED` (fixture .tscn corrompue) — comble GAP-1
2. Ajouter test `load_slow_threshold_ms = 0` désactivation — comble GAP-2
3. (nit) Émettre `level_load_failed` aussi dans branche `packed == null` (L.162)
4. (nit) `find_children(..., true, false)` pour robustesse fixtures programmatiques
5. (nit) Annoter `var status: ResourceLoader.ThreadLoadStatus` (L.104)
