# Story 005: Pause / state lifecycle integration (GameStateManager)

> **Epic**: Enemy System
> **Status**: Complete
> **Layer**: Integration
> **Type**: Integration
> **Manifest Version**: 2026-04-23
> **Completed**: 2026-05-02 (auto-mode, solo)

## Context

**GDD Source**: `design/gdd/enemy-system.md` r2 APPROVED 2026-04-27 (Rule 11.d + EC-ENM-9 + AC-ENM-19/20)
**ADRs Governing**: ADR-0007 GameStateManager (D-4 unique authority `get_tree().paused`), ADR-0006 Combat Tick Model
**Depends on**: story-001 (Grunt state machine + tween wall-clock), story-002 (Grunt.tscn + LaserCone)

**Scope** : valider que la séparation API `Tween.set_ignore_time_scale(true)` + default
`set_pause_mode(TWEEN_PAUSE_BOUND)` produit le comportement attendu :
- Pause GSM → `tree.paused = true` → tween Enemy figé.
- Resume GSM → `tree.paused = false` → tween reprend.
- Wall-clock total = 150 ms hors temps de pause (EC-ENM-9).
- LaserCone.monitoring reste `true` pendant pause (AC-ENM-20) — le no-fire body_entered
  est garanti par Godot natif (physics frozen quand tree.paused).

**Engine**: Godot 4.6 | **Risk**: LOW (test pur — aucune modification src/, valide
contrat existant story-001/002 sous transition state machine GSM)

**Control Manifest Rules (Integration layer)** :
- Required : `Tween.set_pause_mode` reste au default (TWEEN_PAUSE_BOUND) → `set_ignore_time_scale(true)`
  ne casse pas la séparation pause vs slow-mo (ADR-0007 D-4 vs ADR-0006).
- Forbidden : modifier `set_pause_mode(TWEEN_PAUSE_PROCESS)` qui violerait EC-ENM-9.
- Guardrail : pas d'override `process_mode = ALWAYS` sur Grunt — sinon le tween
  continuerait pendant la pause (test régression couvre).

---

## Acceptance Criteria

- [x] **AC-ENM-19 [Integration]** : GIVEN un Grunt en `DYING` (tween 75 ms wall-clock écoulés),
      WHEN `get_tree().paused = true` (autorité GSM D-4) puis attente wall-clock 100 ms,
      puis `get_tree().paused = false`, THEN le tween reprend son cours, completion à
      wall-clock 150 ms hors temps de pause (EC-ENM-9). `_state == DEAD`,
      `mesh.scale ≈ Vector3(EPSILON, EPSILON, EPSILON)`.
- [x] **AC-ENM-20 [Logic]** : GIVEN un Grunt en `ALIVE` ET `tree.paused == true`,
      WHEN inspect, THEN `LaserCone.monitoring` reste `true` (no-fire `body_entered`
      pendant la pause est Godot natif, pas testable hermétiquement sans physics frame).

**Bonus ACs covered** :
- **Régression EC-ENM-9** : pendant la pause, `mesh.scale` ne progresse pas (tween figé via TWEEN_PAUSE_BOUND).
- **Régression Rule 11.b** : pause sur Grunt en DYING n'affecte pas `LaserCone.monitoring` (déjà false post-die()).
- **Idempotence pause** : pause appliquée 2× ou resume 2× → comportement stable (couvert via GSM tests).

---

## Implementation Notes

**Files** (NEW tests) :
- `tests/integration/enemy/grunt_pause_lifecycle_test.gd` — 4 tests AC-ENM-19/20 + 2 bonus.

**Files** (NO src/ change) :
- Aucun changement Grunt.gd / Grunt.tscn / GSM. Le contrat est déjà respecté en story-001 :
  - `Tween.set_ignore_time_scale(true)` (ignore Engine.time_scale) — story-001.
  - `Tween.set_pause_mode` left default = `TWEEN_PAUSE_BOUND` (gèle pendant pause) — story-001.
  - Grunt sans process_mode override (default INHERIT) — Grunt.tscn story-002.

**Test driver pattern** :
- `get_tree().create_timer(t, true, false, true)` — `process_always=true` (fire même pendant
  pause tree, sert de wall-clock) + `ignore_time_scale=true` (insensible à Engine.time_scale).
- Direct `get_tree().paused = true/false` simule l'effet GSM sans dépendance autoload state
  (GSM ne peut pause que depuis PLAYING ; le test driver bypasse cette contrainte pour isoler
  le contrat tween↔pause). GSM mute lui-même `get_tree().paused` en production (D-4).

---

## Test Plan

| AC | Test file | Test function | Status |
|----|-----------|---------------|--------|
| AC-ENM-19 | `grunt_pause_lifecycle_test.gd` | `test_pause_during_dying_freezes_tween_resume_completes_at_150ms_wall_clock_excluding_pause` | ✅ PASS |
| AC-ENM-20 | `grunt_pause_lifecycle_test.gd` | `test_paused_alive_grunt_keeps_laser_cone_monitoring_enabled` | ✅ PASS |
| Régression EC-ENM-9 | `grunt_pause_lifecycle_test.gd` | `test_tween_scale_does_not_progress_during_pause` | ✅ PASS |
| Régression Rule 11.b | `grunt_pause_lifecycle_test.gd` | `test_pause_during_dying_keeps_laser_cone_monitoring_disabled` | ✅ PASS |

**Test report** : `reports/report_<N>` — 34/34 PASSED enemy suite (story-001 + 002 + 003 + 005).

---

## Definition of Done

- [x] All 2 ACs (AC-ENM-19/20) PASS in automated tests.
- [x] Bonus régression tests EC-ENM-9 + Rule 11.b PASS.
- [x] Zero régression on enemy suite (story-001/002/003 — 30/30 still PASS).
- [x] Lint clean : pas de `process_mode = ALWAYS` ni `set_pause_mode(TWEEN_PAUSE_PROCESS)` ajoutés.
- [x] Status switched `Ready` → `Complete` (auto-mode solo).

---

## Completion Notes

- **GSM intégration directe non requise** : le contrat EC-ENM-9 est sur l'effet `tree.paused`
  (mécanisme bas niveau Godot), pas sur l'API GSM. GSM est testé en propre suite (`tests/unit/core/`)
  et mute exclusivement `get_tree().paused` (ADR-0007 D-4). Tester via `get_tree().paused`
  directement = isoler le contrat tween↔pause sans coupler à l'état autoload GSM (qui peut être
  MENU/PLAYING/PAUSED selon ordre des tests).
- **AC-ENM-20 limite hermétique** : « no `body_entered` pendant pause » est garanti par Godot
  natif (physics paused ⇒ pas de collision queries). Reproduire ça hermétiquement nécessiterait
  une physics frame complète — coût test disproportionné. Le test BLOCKING couvre `monitoring == true`,
  le no-fire est documenté comme Godot guarantee (ADR-0008 + Godot 4.6 docs).
- **Wall-clock test driver** : `create_timer(0.10, true, false, true)` — `process_always=true`
  pour fire pendant pause (sinon le test deadlock), `ignore_time_scale=true` pour
  insensibilité slow-mo Combat (cohérence avec Rule 11.d).
- **Test fragility** : la phase 3 (resume + 100 ms) attend `~85 ms restants + buffer`. Marge
  confortable pour CI lent. Si flaky futur, augmenter à 150 ms.

## Next Stories

- **story-004** : Combat sweep + Player laser cross-system tests (Blocked — Combat sweep impl).
- **story-006** : Authoring lints `validate_enemy_slot_*` triplet (Ready — story-003 base).
- **story-007** : Performance benchmark 30 grunts (Ready — story-003 base).
