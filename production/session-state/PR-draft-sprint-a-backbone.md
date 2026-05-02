# PR Draft — Sprint A Backbone Integration

**Branch** : `chore/story-014-tech-debt-cleanup` → `main`
**État au 2026-04-27** : 26 commits ahead, 423 fichiers touchés, +78 861 / -459 lignes.
**Ne PAS firer tant que** les sessions parallèles n'ont pas committé les fichiers off-scope encore dans le working tree (upgrade r1.1 cosmetic + UX menus + shop-system epics + secret-system).

## Titre suggéré

```
Sprint A backbone — foundations + 9 GDDs Designed + Movement/Level/Combat/Camera Sprint 0 (story-014 included)
```

(Le scope a largement dépassé "story-014 tech-debt cleanup" — la branche est devenue le canal de livraison Sprint A.)

## Body

```markdown
## Summary

Cette PR consolide le backbone Sprint A : tech-debt Level System cleanup (scope original `story-014`), foundations ADRs, 9 systèmes en Designed (combat, movement, level, enemy, camera, credit, shop, upgrade, save/load, menu, secret, hud, checkpoint), et l'implémentation Sprint 0 de Movement (17/18 Complete), Level (23/23 Complete), Combat (12 stories Done), Camera (story 006/007 Complete).

## Scope par workstream

### Foundation
- `chore(level)` story-014 tech-debt cleanup + story-023 TR-lvl-039 auto gate (264b79c)
- `feat(level)` story-020 formula lints F3/F5/F6/F7 (af7a6a0)
- `chore(repo)` gitignore ephemeral state + Claude Code rules (d667d0d)
- `docs(arch)` foundation ADRs (-0001 à -0010) + GDDs + registries (a539c55, cb4e52f)
- `chore(prod)` epics + stories + gate-checks + tech-debt tracking (14237f9)

### Implémentation Sprint 0
- `feat(src+tests+tools)` Movement (17/18) + Level (23/23) + perf tools (778eb8d)
- `chore(movement)` officialise Movement story status Done → Complete (51b0626)
- `feat(combat)` marathon Sprint 0 — 12 stories Done (003-009 + 013-018) (c755054)
- `feat(camera+gdd)` story-006 polling→signal refactor + enemy-system r1+r2 reviews (7872547)
- `feat(camera)` story-007 shake additif + wall_jump kick — Complete 3/3 ACs (6afec6b)

### Designed GDDs (Sprint A backbone)
- enemy-system MVP r1+r2 (91457ba)
- checkpoint-respawn-system MVP (ec8f1d1)
- credit-economy-system r1 + r2 cosmetic + r2 full revision (d38af48, ee57883, 876a5b1)
- secret-system + hud-system r1 (624fa3a)
- shop-system r1 + r2 cosmetic (2542fd0, 2c349dd)
- upgrade-system r1 (a796379)
- save-load-system r1 + ADR-0010 (98f3a5b, cb4e52f)
- menu-system r1 + r2 cosmetic (127ffbd, 8f6594a)
- combat-system r7 amendment OQ-ENM-1 (fa251f2)
- secret-system review r1 NEEDS REVISION (5e109fa)

### Gate Checks
- pre-prod→prod gate checks r1+r2 FAIL + enemy-system GDD skeleton (e4d26b4)

## Test plan

- [ ] `godot --headless --script tests/gdunit4_runner.gd` — full suite passe
- [ ] Movement lint (TR-mov-006) : `tests/static/movement_lint_test.gd` clean
- [ ] Level lint aggregate (F3/F5/F6/F7) : `tools/lint/run_level_lint.gd` clean
- [ ] Camera story-007 integration test : `tests/integration/camera/story_007_shake_wall_jump_test.gd` 9/9 pass
- [ ] Combat Sprint 0 stories 003-009 + 013-018 régression
- [ ] CI lints : `lint-input-hot-paths`, `lint-level-signals-main-thread`, `lint-input-main-thread`
- [ ] Smoke playtest : boot scène test, dash, wall-run, wall-jump, combat melee, mort/respawn

## Risques connus

- **Scope inflation** : la branche `chore/story-014-tech-debt-cleanup` a accumulé 26 commits sur ~10 workstreams. Future organisation : créer une branche dédiée par workstream avant le premier commit.
- **GDDs en NEEDS REVISION** : secret-system r1, upgrade-system r1.1 — pas bloquant pour merge (Designed = OK), mais à raffiner avant `/create-epics` respectif.
- **Off-scope uncommitted au moment du draft** : upgrade-system reviews + UX main-menu/pause-menu + shop-system epics — à faire commit par les sessions parallèles avant fire de la PR.
```

## Pré-requis avant fire

1. Sessions parallèles committent leurs fichiers off-scope (upgrade r1.1, UX menus, shop epics, secret review)
2. `git status` clean sur la branche
3. `git push` final
4. `gh pr create --title "..." --body "..."`

## Source

- Multi-session integration branch reused as Sprint A delivery channel (2026-04-26 → 2026-04-27)
- Origin scope `story-014 Level System tech-debt cleanup` RÉSOLU dans commit 264b79c
- Lesson learned documenté dans `feedback_multi_session_git_reset_risk.md`
