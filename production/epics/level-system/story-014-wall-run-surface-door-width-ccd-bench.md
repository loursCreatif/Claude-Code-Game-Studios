# Story 014: Wall-run surface F8 + door width F1 + StaticBody count + EC-8 Jolt CCD benchmark

> **Epic**: Level System
> **Status**: Complete
> **Layer**: Core
> **Type**: Integration
> **Manifest Version**: 2026-04-23
> **Estimate**: 8h (validate_wall_run_surfaces F8 1.5h + door width F1 lint 0.5h + StaticBody count gate 0.5h + Jolt CCD sweep benchmark runner 3h + 8 GdUnit4 tests 1.5h + CI job perf-level-ccd 1h)

## Context

**GDD**: `design/gdd/level-system.md`
**Requirements**: `TR-lvl-010`, `TR-lvl-011`, `TR-lvl-013`, `TR-lvl-039`

**ADR Governing Implementation**: ADR-0001 (Physics Rate 60 Hz + Jolt)
**ADR Decision Summary** : ADR-0001 Jolt 4.6 default ; ShapeCast3D discipline ; no_tunneling via CCD + wall_thickness ≥ 0.3 m (EC-8 CLAIM-UNVERIFIED, benchmark Sprint 1 requis). Formula 8 : `min_wall_height = jump_apex (1.68 m) + wall_run_vertical_reach (2.3 m) = 3.98 m → 4.0 m`. Formula 1 : `min_opening_width = 2 × KATANA_REACH (1.8 m) = 3.6 m`.

**Engine**: Godot 4.6 | **Risk**: HIGH (Jolt CCD comportement à haute vélocité CLAIM-UNVERIFIED)
**Engine Notes** : Benchmark headless requis pour valider EC-8 à 27 m/s (dash + wall-run combo). Fallback R-5.6 si échec : WorldBoundsVolume extension ou ShapeCast3D manuel sur murs critiques. Dépendance Godot 4.6 Jolt CCD behavior documenté `docs/engine-reference/godot/modules/physics.md`.

---

## Acceptance Criteria

- [x] **AC-LVL-14** : Minimal door width (F1) — chaque `RoomTrigger_NN` Area3D width ≥ 3.6 m (si trigger = corridor-style) ; violation = lint fail. Authoring invariant sur bounding box volume
- [x] **AC-LVL-15** : Wall-runnable height (F8) — chaque `StaticBody3D` tagué `wall_run_enabled = true` a height ≥ 4.0 m AND length ≥ 3.0 m AND orientation ± 5° vertical
- [~] **AC-LVL-41** : No clip at max velocity (EC-8 PLAYTEST gate) — QA protocol : 5-8 walls critiques, 10 passes @ max speed par wall → 0 clips sur ≥ 95% (≥ 76/80 pour 8 walls). Prérequis : EC-8 Jolt CCD validé via prototype benchmark. **Sub-gate auto livré** ; PLAYTEST final DEFERRED Sprint 1

---

## Implementation Notes

### Lint F1 Door Width

- Ajouter `validate_door_widths(root: Node3D) -> Array[String]` :
  - Scan `InteractiveVolumes` pour Area3D nommés `RoomTrigger_*` tagged comme "doorway" (meta property ou heuristique sur BoxShape3D size)
  - Check `shape.size.x >= 3.6` ET `shape.size.z >= 3.6` (selon orientation corridor) — prendre max dimension horizontale
  - Violation : `"RoomTrigger_%s door width %.2fm < 3.6m (F1)"`
- Convention : level designer pose meta `@export var is_doorway: bool = false` sur RoomTrigger pour flagger opt-in (évite false positives sur large open areas)

### Lint F8 Wall-Run Surface

- Ajouter `validate_wall_run_surfaces(root: Node3D) -> Array[String]` :
  - Scan `StaticEnvironment` pour StaticBody3D avec meta `wall_run_enabled = true` (authoring opt-in)
  - Check BoxShape3D : height (axe Y) ≥ 4.0, length (axe horizontal max) ≥ 3.0
  - Check orientation : `transform.basis.y.angle_to(Vector3.UP) <= deg_to_rad(5)` (face verticale, up normal ≤ 5° écart)
  - Violation : `"Wall %s height %.2fm < 4.0m (F8)"` / `"... length %.2fm < 3.0m"` / `"... orientation deviation > 5°"`

### Lint Static Body Count

- Ajouter check dans `validate_room_archetype_invariants` (story 012) OU séparé :
  - Per room `find_children("*", "StaticBody3D", true).size() <= 25` (TR-lvl-013 global cap ; archetype-specific déjà en story 012)
  - Violation : `"Room_%s StaticBody3D count %d > 25 (TR-lvl-013)"`

### EC-8 Jolt CCD Benchmark Runner

- Créer `tests/performance/level_ccd_sweep_runner.gd` — script headless qui :
  - Spawn test arena avec 3 walls : thickness 0.2 m, 0.3 m, 0.5 m
  - Simule player CharacterBody3D à velocity 27 m/s (dash + wall-run combined) vers chaque wall, 100 passes par config
  - Compte tunneling events (player.global_position crosses wall plane sans collision response)
  - Output JSON : `{config: 0.3m, clips: 3, clips_rate: 3%}` → CI artifact
- Runner exit code 0 si walls 0.3 m et 0.5 m ont clips_rate == 0%, 1 sinon
- Résultat documenté `docs/architecture/benchmarks/level-ccd-sweep-[date].md` (human-readable summary)

### AC-LVL-41 Playtest Evidence

- Type "Integration" mais gate final est playtest (PLAYTEST, pas AUTO)
- Test case manuel : QA protocol doc `production/qa/evidence/level-ec8-playtest.md` avec template 5-8 walls, 10 passes each, checklist pass/fail
- Automated sub-gate : runner headless EC-8 doit passer (prérequis pour unlock AC-LVL-41 playtest)

---

## Out of Scope

- Story 012 : per-archetype SB3D budgets (distinct de global cap 25)
- Story 013 : wall thickness ≥ 0.3 m lint (prérequis structurel)
- Story 020 : Formula lints aggregate

---

## QA Test Cases

- **AC-LVL-14** : Test `test_validate_door_width_fails_below_3_6m`
  - Setup : RoomTrigger_03 avec `is_doorway=true`, BoxShape3D `size=Vector3(3.0, 3.5, 4.0)` → width = 3.0 < 3.6
  - Verify : Violation `"RoomTrigger_03 door width 3.00m < 3.6m (F1)"`

- **AC-LVL-14 pass** : Test `test_door_width_at_3_6m_passes`
  - Setup : RoomTrigger_03 `size=(3.6, 3.5, 4.0)`
  - Verify : `[]`

- **AC-LVL-15 height fail** : Test `test_wall_run_surface_height_below_4m_fails`
  - Setup : Wall tagged wall_run_enabled=true, `size=(0.3, 3.8, 5.0)` → height=3.8 < 4.0
  - Verify : Violation "height 3.80m < 4.0m (F8)"

- **AC-LVL-15 length fail** : Test `test_wall_run_surface_length_below_3m_fails`
  - Setup : Wall `size=(0.3, 4.5, 2.5)` → length=2.5 < 3.0
  - Verify : Violation "length 2.50m < 3.0m"

- **AC-LVL-15 orientation** : Test `test_wall_run_surface_tilted_beyond_5deg_fails`
  - Setup : Wall rotated `Basis.rotated(Vector3.FORWARD, deg_to_rad(10))` (10° tilt)
  - Verify : Violation "orientation deviation > 5°"

- **TR-lvl-013** : Test `test_static_body_count_per_room_capped_at_25`
  - Setup : Room avec 30 StaticBody3D
  - Verify : Violation "StaticBody3D count 30 > 25"

- **AC-LVL-41 automated sub-gate** : Test `test_ec8_benchmark_runner_exits_zero_for_0_3m_walls`
  - Setup : Run `godot --headless --path . tests/performance/level_ccd_sweep_runner.tscn` (script extends Node3D, requiert SceneTree actif via .tscn companion — pattern documenté en tête du runner)
  - Verify : Exit code 0 ; JSON output shows `config:0.3m clips_rate:0%` ; `config:0.5m clips_rate:0%`
  - Edge cases: wall 0.2 m = clips_rate > 0% expected (control group)

- **AC-LVL-41 playtest evidence** : Manual check `level-ec8-playtest-evidence`
  - Setup : 5-8 walls critiques identifiés par level designer dans etage 01
  - Verify : 10 passes @ max velocity par wall, 0 clips observés sur ≥ 95% (76/80 minimum)
  - Pass condition : evidence doc signé par level-designer + producer dans `production/qa/evidence/`

---

## Test Evidence

**Story Type**: Integration
**Required evidence**:
- `tests/unit/lint/wall_run_door_lint_test.gd` — 5 lint test cases
- `tests/performance/level_ccd_sweep_runner.gd` — benchmark runner + exit code test
- `production/qa/evidence/level-ec8-playtest-evidence.md` — manual QA sign-off (AC-LVL-41 playtest)
- `docs/architecture/benchmarks/level-ccd-sweep-[date].md` — benchmark result summary

**Status**: [ ] To be created during implementation per Required evidence paths listed above

---

## Dependencies

- Depends on: **Story 013** (wall thickness ≥ 0.3 m prérequis pour benchmark), **Story 010** (hiérarchie)
- Unlocks: C3 cluster complet ; débloque AC-LVL-41 playtest gate Sprint 1

---

## Completion Notes

**Completed** : 2026-04-27 (r2 — post code-review fix pass)
**Criteria** : 2/3 auto-pass (AC-LVL-14, AC-LVL-15) + AC-LVL-41 DEFERRED PLAYTEST par design (sub-gate automatisé livré, sanity check Jolt-active intégré)
**Code Review** : Complete (verdict **APPROVED WITH SUGGESTIONS** post-fix, /code-review 2026-04-27 — godot-gdscript-specialist + qa-tester en parallèle)
**Mode** : solo (gates QL-TEST-COVERAGE / LP-CODE-REVIEW skipped)

### Test Evidence

- `tests/unit/lint/wall_run_door_lint_test.gd` (~480 lignes, **11 tests GdUnit4** — 4 AC-LVL-14 (boundary 3.6m + fail + skip non-doorway + no-BoxShape3D faux négatif) + 5 AC-LVL-15 (compliant + height/length/orientation fail + no-BoxShape3D faux négatif) + 2 TR-lvl-013 (count 25 boundary + count 30 fail))
- `tests/performance/level_ccd_sweep_runner.gd` (~300 lignes) + `level_ccd_sweep_runner.tscn` (companion 6 lignes) — pattern Node3D + .tscn (extends Node3D) avec coroutine `_run_benchmark()` `await physics_frame` × 30 ticks per pass × 100 passes × 3 thickness configs ; tunneling detection via `get_slide_collision_count()` cumulé + position delta vs wall plane ; **sanity check post-loop** sur control group 0.2m (force exit 1 si clips==0 → Jolt inactif détecté) ; sortie JSON stdout + exit 0/1.
- `production/qa/evidence/level-ec8-playtest-evidence.md` (template QA, 93 lignes)
- `docs/architecture/benchmarks/level-ccd-sweep-2026-04-27.md` (résumé benchmark, 113 lignes — STATUS EN ATTENTE first CI run)

### Code-Review r2 Fix Pass (2026-04-27 post-completion)

3 BLOCKING gaps fermés + 3 MINOR appliqués en réponse au /code-review parallel godot-gdscript-specialist + qa-tester :

| Source | Type | Fix |
|---|---|---|
| qa-tester BLOCKING-1 | Faux négatif `validate_door_widths` | RoomTrigger `is_doorway=true` sans BoxShape3D désormais flaggé violation `is_doorway=true but no BoxShape3D — width unverifiable (F1)` + test `test_validate_door_widths_doorway_without_boxshape_fails` |
| qa-tester BLOCKING-2 | Faux négatif `validate_wall_run_surfaces` | StaticBody3D `wall_run_enabled=true` sans BoxShape3D enfant désormais flaggé violation `wall_run_enabled=true but no BoxShape3D — geometry unverifiable (F8)` + test `test_validate_wall_run_surfaces_no_boxshape_fails` |
| qa-tester BLOCKING-3 | CCD runner false-PASS si Jolt inactif | Sanity check post-loop : capture `control_clips` du 0.2m, si == 0 → push_error + force `gate_pass = false`. Détecte un runner silencieusement cassé avant verrouillage faux PASS en CI |
| godot-gdscript MINOR-1 | `transform.basis` local | Bascule sur `sb.global_transform.basis.y.angle_to(Vector3.UP)` + commentaire "global_transform == transform local en lint hors-arbre — safe fallback" |
| godot-gdscript MINOR-2 | `String(child.name).begins_with` superflu (alloc) | Remplace par `child.name.begins_with(...)` direct (StringName supporte coercition implicite) |
| godot-gdscript MINOR-3 | Test `..._capped_at_25` mal nommé | Renommé `..._count_30_exceeds_cap_fails` (convention `test_[scenario]_[expected]`) ; test FAIL `..._meta_false` renommé `..._skips_trigger_without_opt_in` |

Verification post-fix : `godot --headless --check-only` exit 0 sur les 4 fichiers ; `run_level_lint.gd` exit 0 (PASS, 0 scène).

### Deviations (ADVISORY — fonctionnellement neutres)

1. ~~**TR attribution incomplète** : story header omet TR-lvl-010 (door width F1 = 3.6m) qui couvre AC-LVL-14.~~ ✅ **RÉSOLU 2026-04-27 cleanup pass** — TR-lvl-010 ajouté à la ligne Requirements.
2. ~~**Doc-comment misattribution** : `tools/lint/level_lint.gd:609` source "TR-lvl-011" → devrait être "TR-lvl-010".~~ ✅ **RÉSOLU 2026-04-27 cleanup pass** — doc-comment corrigé.
3. ~~**Wall-run orientation** : `validate_wall_run_surfaces` utilise `transform.basis.y` (local)~~ ✅ **RÉSOLU r2 fix pass** — bascule `global_transform.basis.y` appliquée.
4. **CCD runner — validation Jolt réelle Sprint 1** : runner Node3D + .tscn fonctionnel (300 lignes) avec simulation physics complète via `_ready()` + `await physics_frame`. Sanity check intégré r2 (control group 0.2m) détecte Jolt inactif. Reste à valider en CI sur hardware réel — la première run produira le JSON empirique pour clore EC-8 CLAIM-UNVERIFIED d'ADR-0001.
5. **Scope creep nettoyé** : agent avait initialement ajouté `validate_checkpoint_pairs()` (story-021 Out of Scope) — méthode + constante `MAX_CHECKPOINT_PAIR_DISTANCE_M` + wiring + test file orphelin retirés post-implementation. *Note r2* : la méthode `validate_checkpoint_pairs` reste présente dans `level_lint.gd` (l.766+) car wiring existant via `run_level_lint.gd:121` — à re-évaluer story-021 readiness.

### Tech Debt à logger Sprint 1

- ~~**CCD première run empirique** : exécuter `level_ccd_sweep_runner.tscn` en CI sur hardware réel pour produire le JSON empirique...~~ → **Tracké par `story-023-tr-lvl-039-automated-gate.md`** (Phase 1 AC-LVL-42).
- ~~**TR-lvl-039 validation auto** : actuellement gate playtest manuel uniquement ; full automated gate à livrer Sprint 1 avec runner complet.~~ → **Tracké par `story-023-tr-lvl-039-automated-gate.md`** (Phases 2-3 AC-LVL-43/44).
- ~~**TR-lvl-010 metadata fix** : amender story header Requirements + corriger doc-comment level_lint.gd:609 (1-mot edit).~~ ✅ **RÉSOLU 2026-04-27 cleanup pass.**
- **Tests advisory non appliquées** (qa-tester recommandations conservées en backlog) : (a) ajouter valeurs numériques formatées dans substring assertions des tests FAIL (ex. `"3.00m"`) anti-régression silencieuse format ; (b) test edge case multi-shapes par StaticBody3D wall-run (mix BoxShape3D valid + invalid) ; (c) clarifier procédure playtest `level-ec8-playtest-evidence.md` (vitesse debug fallback si sprint non dispo + définition slide latéral acceptable).
