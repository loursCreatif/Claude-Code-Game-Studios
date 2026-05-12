# Story W-4 — Test Infra Autoload Reset Between Suites

**Status** : DIAGNOSTIC COMPLETE — DEFER FIX
**Sprint** : Pre-Production 2026-05-05 (tech-debt #1)
**Type** : Tech-debt — Test Infrastructure
**Created** : 2026-05-09 (chore tech-debt cleanup post story-014)
**Source** : `production/sprints/sprint-pre-production-2026-05-05.md` ligne 85
**Trigger** : Smoke W-4 verdict FAIL 2026-05-05 (`production/qa/smoke-2026-05-05.md`)

## Hypothèse initiale (smoke 2026-05-05)

> Autoloads (`InputManager`, `GameStateManager`, `LevelSystem`, `AudioSystem`, `SaveLoadSystem`,
> `AccessibilityService`) ne sont pas réinitialisés entre suites. State accumulé d'une suite à
> l'autre fait crasher le `before_test()` des suites suivantes.
> Pattern observé : tous les tests non-Combat échouent avec erreurs ligne 0 (setup discovery)
> uniquement quand exécutés dans la même invocation cmdtool.

→ Verdict : autoload reuse pollution **dominante**.

## Diagnostic actualisé 2026-05-09

**Hypothèse infirmée**. Mesure cross-suite 2026-05-09 : 36 suites failing dans le sweep complet,
**32 / 36 (89 %) sont des régressions intrinsèques** (la suite échoue pareil isolée).
Seules **4 / 36 (11 %)** sont des vraies pollutions cross-suite.

Voir matrice complète : `production/qa/evidence/cross-suite-pollution-analysis-2026-05-09.md`.

### Évolution du paysage 2026-05-05 → 2026-05-09

Entre le smoke W-4 et 2026-05-09, plusieurs sprints ont stabilisé les test suites :

- Sprint VFX 7/8 stories complete (refactor visibility, GSM gating, lint anti-patterns)
- Sprint HUD complete (visibility consumer pattern aligné)
- Sprint Audio complete (R-AUD-* pool exclusive)
- Sprint Menu story-014 cleanup (281 dupes Mac Finder + lints anti-patterns)

Conséquence : la pollution autoload (qui semblait massive) a en grande partie disparu —
remplacée par les régressions per-epic qui restaient noyées sous le bruit de pollution.

### 4 vraies pollutions identifiées

| Suite | Sweep | Iso | Hypothèse cause |
|---|---:|---:|---|
| `main_menu_boot_test` | 1 fail | 0 fail | GSM `_current_state` muté par suite précédente sans restore |
| `no_alloc_play_2d_test` | 1 fail | 0 fail | AudioSystem pool / `MEMORY_STATIC` delta biaisé par voisins |
| `story_009_respawn_fade_flash_test` | 1 fail | 0 fail | VFX `_flash_active` ou pool decals état résiduel |
| `test_movement_signals_typed_contract` | 1 fail | 0 fail | Signal connection refcount accumulé |

**Total impact** : 4 fails sur 1117 tests = **0.36 % du volume total**.

## Décision : DEFER FIX

**Rationale** :

- ROI fix infra `AutoloadResetTestSuite` : 4 fails sur 1117 tests
- ROI fix régressions per-epic : 32 fails sur 1117 tests (8× plus impactant)
- Risque infra : ajouter une base test class touche **toutes** les suites (potentiel régression)
- Workaround disponible : CI split par-epic via jobs séparés (déjà partiel)

**Action** : prioriser stories régression per-epic, re-évaluer pollution infra post-cleanup.

## Stories régression à créer (recommandation)

Décomposition par epic des 32 régressions intrinsèques :

| Epic | Suites failing | Fails | Story tech-debt suggérée |
|---|---:|---:|---|
| Level | 13 | 30 | `tech-debt-level-test-regression-cleanup` |
| Camera | 3 | 10 | `tech-debt-camera-story_001-003-regression` |
| Input | 7 | 11 | `tech-debt-input-test-regression-cluster` |
| Movement | 5 | 6 | `tech-debt-movement-canonical-fails-physics_interp` (référencé sprint plan #2) |
| Lint | 5 | 5 | `tech-debt-lint-drift-cluster` |
| Misc | 3 | 3 | absorber dans stories ci-dessus |

**Note Movement** : tech-debt #2 sprint plan déjà documenté (`b60d809 fix(player): physics_interpolation_mode=2 (OFF) Godot 4.6` → 4 fails canonical attendus). Cette story W-4 confirme empiriquement.

## Acceptance Criteria (si fix re-priorisé futur)

Si ROI change (par exemple : régressions résolues mais 4 pollutions persistent ou s'amplifient) :

- AC-W4-1 : `tests/helpers/autoload_test_suite.gd` (NEW) extends `GdUnitTestSuite`, override
  `before_test()` snapshot autoloads canonicals, `after_test()` restore.
- AC-W4-2 : Snapshot autoloads inclut au minimum : `GSM._current_state` + `InputManager._pressed_*` +
  `AudioSystem.music_paused` + `LevelSystem._current_etage`.
- AC-W4-3 : 4 suites pollution opt-in `extends AutoloadResetTestSuite` → diff sweep == iso.
- AC-W4-4 : Zéro régression sur 32 régressions intrinsèques (orthogonal).

## Out of Scope

- Régressions per-epic (32 suites) : story dédiée par epic.
- CI split par-epic : déjà en place partiellement (lint jobs).
- Smoke W-4 re-run : à exécuter après cleanup régressions, pas avant.

## Source

- Smoke W-4 verdict 2026-05-05 (obsolete) : `production/qa/smoke-2026-05-05.md`
- Diagnostic actualisé 2026-05-09 : `production/qa/evidence/cross-suite-pollution-analysis-2026-05-09.md`
- Sprint plan tech-debt #1 : `production/sprints/sprint-pre-production-2026-05-05.md` ligne 85
- Sprint plan tech-debt #2 (Movement canonical fails) : ligne 86
- Sprint plan tech-debt #3 (Camera 8 fails story_001 isolé) : ligne 87
